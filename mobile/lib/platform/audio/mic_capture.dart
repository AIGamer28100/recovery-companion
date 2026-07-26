import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import 'chunk_batcher.dart';

/// The only file that imports `record`. Wraps mic capture per DESIGN.md
/// §3.2: 16kHz mono PCM16 via the `voiceCommunication` audio source (the
/// load-bearing choice that pairs with the playback side's
/// `USAGE_VOICE_COMMUNICATION` attributes for OEM-level AEC/NS — see §3.4),
/// batched into ~100-200ms chunks before being handed upstream.
class MicCapture {
  MicCapture({AudioRecorder? recorder, ChunkBatcher? batcher})
      : _recorder = recorder ?? AudioRecorder(),
        _batcher = batcher ?? ChunkBatcher();

  final AudioRecorder _recorder;
  final ChunkBatcher _batcher;
  StreamSubscription<Uint8List>? _rawSub;
  final StreamController<Uint8List> _rawMirror =
      StreamController<Uint8List>.broadcast();

  // `echoCancel: true` matters beyond the symmetric-attributes trick in
  // DESIGN.md §3.4: the `record` plugin's Android implementation
  // (`record_android`'s `PCMReader.enableEchoSuppressor`) checks
  // `AcousticEchoCanceler.isAvailable()` itself and, when true, creates and
  // enables one bound to its OWN `AudioRecord.audioSessionId` — which is
  // exactly the "explicitly instantiate and enable it bound to the active
  // AudioRecord session ID" §3.4 calls for, and something a separate
  // platform channel could not do without `record` exposing that session
  // id (it doesn't). The *availability* boolean surfaced to the UI still
  // comes from the dedicated native-audio channel's own
  // `AcousticEchoCanceler.isAvailable()` check (see `native_audio_channel.dart`)
  // since `record` only logs, and doesn't report, the unavailable case.
  static const _config = RecordConfig(
    encoder: AudioEncoder.pcm16bits,
    sampleRate: 16000,
    numChannels: 1,
    echoCancel: true,
    androidConfig: AndroidRecordConfig(
      audioSource: AndroidAudioSource.voiceCommunication,
      audioManagerMode: AudioManagerMode.modeInCommunication,
    ),
  );

  /// Raw (unbatched) PCM16 fragments, mirrored for the local energy VAD
  /// (DESIGN.md §3.5), which wants the freshest possible samples rather than
  /// waiting for a full outbound chunk.
  Stream<Uint8List> get rawFragments => _rawMirror.stream;

  /// True if the OS has granted mic access. Does not prompt.
  Future<bool> hasPermission() => _recorder.hasPermission(request: false);

  /// Starts capture and returns the batched outbound chunk stream. Throws a
  /// [MicPermissionDenied] if permission isn't (and can't be) granted.
  Future<Stream<Uint8List>> start() async {
    final granted = await _recorder.hasPermission();
    if (!granted) {
      throw const MicPermissionDenied();
    }
    final raw = await _recorder.startStream(_config);
    _rawSub = raw.listen(_rawMirror.add, onError: _rawMirror.addError);
    return _batcher.batch(_rawMirror.stream);
  }

  Future<void> stop() async {
    await _rawSub?.cancel();
    _rawSub = null;
    await _recorder.stop();
  }

  Future<void> dispose() async {
    await stop();
    await _rawMirror.close();
    await _recorder.dispose();
  }
}

/// Thrown by [MicCapture.start] when the microphone permission is denied.
/// Mirrors the UI-safe-failure contract of `AppException`, but lives at the
/// platform layer (§2.3: `platform/` is deliberately isolated from
/// `core/errors`) so callers translate it into the copy from DESIGN.md §1.6
/// ("I need your microphone to talk with you...") themselves.
class MicPermissionDenied implements Exception {
  const MicPermissionDenied();
}
