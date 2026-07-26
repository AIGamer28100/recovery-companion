import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../../platform/audio/energy_vad.dart';
import '../../../platform/audio/mic_capture.dart';
import '../data/spike_gemma_service.dart';
import '../data/wav_encoder.dart';
import '../domain/spike_latency.dart';

/// Coarse state machine for the spike UI. Not meant to model every edge
/// case a production feature would need -- just enough to demo the cascaded
/// pipeline (mic -> Gemma 4 text -> TTS, with simple barge-in).
enum SpikeState {
  idle,
  downloadingModel,
  loadingModel,
  recording,
  thinking,
  speaking,
  capturingFrame,
  describingFrame,
  error,
}

/// Orchestrates the isolated on-device spike pipeline:
///  1. `MicCapture` (reused as-is from `lib/platform/audio/`) records one
///     push-to-talk utterance as 16kHz mono PCM16.
///  2. The PCM is wrapped in a WAV header and sent to Gemma 4 E2B via
///     `SpikeGemmaService.sendAudio`.
///  3. The text reply is spoken with `flutter_tts`.
///  4. While speaking, a second `MicCapture` instance feeds
///     `EnergyVad` (also reused as-is) purely to detect barge-in; on
///     detection, TTS is stopped and the app returns to idle so the user can
///     press-and-hold to speak again. This is a simple stop-and-restart, not
///     the production barge-in path in `lib/features/live_session/`.
///  5. A single camera frame can be captured and described via
///     `SpikeGemmaService.sendImage`, then spoken the same way.
///
/// This controller is intentionally standalone: it does not read or write
/// any state from `lib/features/live_session/`.
class OnDeviceSpikeController extends ChangeNotifier {
  OnDeviceSpikeController({
    SpikeGemmaService? gemmaService,
    FlutterTts? tts,
  })  : _gemma = gemmaService ?? SpikeGemmaService(),
        _tts = tts ?? FlutterTts();

  final SpikeGemmaService _gemma;
  final FlutterTts _tts;

  MicCapture? _utteranceMic;
  StreamSubscription<Uint8List>? _utteranceSub;
  final BytesBuilder _utteranceBuffer = BytesBuilder(copy: false);

  MicCapture? _bargeInMic;
  StreamSubscription<Uint8List>? _bargeInSub;
  final EnergyVad _vad = EnergyVad();

  CameraController? _cameraController;

  SpikeState state = SpikeState.idle;
  int downloadProgress = 0;
  String lastUserTranscriptNote = '';
  String lastModelResponse = '';
  String? lastError;
  SpikeLatency? lastLatency;

  Completer<void>? _speakingCompleter;

  void _setState(SpikeState next) {
    state = next;
    notifyListeners();
  }

  Future<void> initializeModel() async {
    try {
      _setState(SpikeState.downloadingModel);
      await _gemma.installModelIfNeeded(
        onProgress: (percent) {
          downloadProgress = percent;
          notifyListeners();
        },
      );
      _setState(SpikeState.loadingModel);
      await _gemma.ensureChatReady();
      _setState(SpikeState.idle);
    } catch (e) {
      lastError = 'Model setup failed: $e';
      _setState(SpikeState.error);
    }
  }

  /// Begins recording one push-to-talk utterance.
  Future<void> startRecording() async {
    if (state != SpikeState.idle) return;
    _utteranceBuffer.clear();
    final mic = MicCapture();
    _utteranceMic = mic;
    final batched = await mic.start();
    _utteranceSub = batched.listen(_utteranceBuffer.add);
    _setState(SpikeState.recording);
  }

  /// Stops recording, runs the audio through Gemma 4, then speaks the reply.
  Future<void> stopRecordingAndRespond() async {
    if (state != SpikeState.recording) return;
    await _utteranceSub?.cancel();
    await _utteranceMic?.dispose();
    _utteranceSub = null;
    _utteranceMic = null;
    final micStoppedAt = DateTime.now();

    final pcm = _utteranceBuffer.takeBytes();
    if (pcm.isEmpty) {
      _setState(SpikeState.idle);
      return;
    }

    _setState(SpikeState.thinking);
    try {
      final wav = pcm16ToWav(pcm);
      final responseText = await _gemma.sendAudio(wav);
      final modelRespondedAt = DateTime.now();
      lastUserTranscriptNote =
          '(${(pcm.lengthInBytes / 32000).toStringAsFixed(1)}s of audio sent -- '
          'Gemma 4 has no ASR transcript to show, only its reply)';
      lastModelResponse = responseText;
      await _speak(
        text: responseText,
        micStoppedAt: micStoppedAt,
        modelRespondedAt: modelRespondedAt,
      );
    } catch (e) {
      lastError = 'Inference failed: $e';
      _setState(SpikeState.error);
    }
  }

  Future<void> _speak({
    required String text,
    required DateTime micStoppedAt,
    required DateTime modelRespondedAt,
  }) async {
    if (text.trim().isEmpty) {
      _setState(SpikeState.idle);
      return;
    }
    _speakingCompleter = Completer<void>();

    await _tts.awaitSpeakCompletion(true);
    _tts.setCompletionHandler(() {
      if (!(_speakingCompleter?.isCompleted ?? true)) {
        _speakingCompleter!.complete();
      }
    });
    _tts.setErrorHandler((msg) {
      if (!(_speakingCompleter?.isCompleted ?? true)) {
        _speakingCompleter!.complete();
      }
    });

    await _startBargeInMonitor();
    final ttsStartedAt = DateTime.now();
    lastLatency = SpikeLatency(
      micStoppedAt: micStoppedAt,
      modelRespondedAt: modelRespondedAt,
      ttsStartedAt: ttsStartedAt,
    );
    _setState(SpikeState.speaking);

    unawaited(_tts.speak(text));
    await _speakingCompleter!.future;
    await _stopBargeInMonitor();

    if (state == SpikeState.speaking) {
      _setState(SpikeState.idle);
    }
  }

  Future<void> _startBargeInMonitor() async {
    _vad.reset();
    final mic = MicCapture();
    _bargeInMic = mic;
    await mic.start();
    _bargeInSub = mic.rawFragments.listen((chunk) {
      if (_vad.addChunk(chunk)) {
        _onBargeIn();
      }
    });
  }

  Future<void> _stopBargeInMonitor() async {
    await _bargeInSub?.cancel();
    _bargeInSub = null;
    await _bargeInMic?.dispose();
    _bargeInMic = null;
  }

  void _onBargeIn() {
    if (state != SpikeState.speaking) return;
    unawaited(_tts.stop());
    if (!(_speakingCompleter?.isCompleted ?? true)) {
      _speakingCompleter!.complete();
    }
  }

  // --- Camera / vision round trip -----------------------------------------

  Future<void> captureFrameAndDescribe() async {
    if (state != SpikeState.idle) return;
    _setState(SpikeState.capturingFrame);
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        lastError = 'No cameras available on this device.';
        _setState(SpikeState.error);
        return;
      }
      final controller = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      _cameraController = controller;
      await controller.initialize();
      final file = await controller.takePicture();
      final bytes = await file.readAsBytes();
      await controller.dispose();
      _cameraController = null;

      _setState(SpikeState.describingFrame);
      final micStoppedAt = DateTime.now(); // "capture" stands in for "mic stop" here
      final description = await _gemma.sendImage(bytes);
      final modelRespondedAt = DateTime.now();
      lastModelResponse = description;
      await _speak(
        text: description,
        micStoppedAt: micStoppedAt,
        modelRespondedAt: modelRespondedAt,
      );
    } catch (e) {
      lastError = 'Frame capture/description failed: $e';
      _setState(SpikeState.error);
    }
  }

  @override
  void dispose() {
    unawaited(_utteranceSub?.cancel());
    unawaited(_utteranceMic?.dispose());
    unawaited(_bargeInSub?.cancel());
    unawaited(_bargeInMic?.dispose());
    unawaited(_cameraController?.dispose());
    unawaited(_gemma.dispose());
    unawaited(_tts.stop());
    super.dispose();
  }
}
