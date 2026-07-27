import 'dart:async';
import 'dart:typed_data';

import 'package:permission_handler/permission_handler.dart';

import '../foreground_service/foreground_service_channel.dart';
import 'audio_focus_handler.dart';
import 'energy_vad.dart';
import 'mic_capture.dart';
import 'native_audio_channel.dart';

/// The public, package-shaped facade for the whole audio pipeline described
/// in DESIGN.md §3 — composes mic capture, native playback, echo
/// cancellation, audio focus, and the foreground service behind one narrow
/// API. Deliberately has no Riverpod or Firestore imports (§2.2): the
/// `application/` layer (Riverpod) owns lifecycle decisions, this class only
/// owns audio mechanics.
class AudioPipeline {
  AudioPipeline({
    MicCapture? mic,
    NativeAudioChannel? native,
    AudioFocusHandler? focus,
    ForegroundServiceChannel? foregroundService,
    EnergyVad? vad,
  })  : _mic = mic ?? MicCapture(),
        _native = native ?? NativeAudioChannel(),
        _focus = focus ?? AudioFocusHandler(),
        _foregroundService = foregroundService ?? const ForegroundServiceChannel(),
        _vad = vad ?? EnergyVad();

  final MicCapture _mic;
  final NativeAudioChannel _native;
  final AudioFocusHandler _focus;
  final ForegroundServiceChannel _foregroundService;
  final EnergyVad _vad;

  /// Playback volume while ducked on a local VAD hint. Not silence — this is
  /// a hint, not the authoritative barge-in — see DESIGN.md §3.5.
  static const _duckVolume = 0.25;

  final StreamController<AudioPipelineEvent> _events =
      StreamController<AudioPipelineEvent>.broadcast();
  StreamSubscription<Uint8List>? _rawVadSub;
  StreamSubscription<FocusSignal>? _focusSub;
  StreamSubscription<NativeAudioEvent>? _nativeEventsSub;
  Timer? _focusGraceTimer;

  bool _modelSpeaking = false;
  bool _micMutedForAec = false;
  bool _echoCancellationAvailable = false;

  Stream<AudioPipelineEvent> get events => _events.stream;
  bool get echoCancellationAvailable => _echoCancellationAvailable;

  /// Starts mic capture, native playback, focus handling, and the
  /// foreground service. Returns the batched outbound PCM16 chunk stream
  /// (16kHz mono) ready to hand to the Live session.
  Future<Stream<Uint8List>> start() async {
    _echoCancellationAvailable = await _native.init();
    await _focus.start();
    _focusSub = _focus.signals.listen(_onFocusSignal);

    // Mic capture MUST succeed (and RECORD_AUDIO must already be granted)
    // before the foreground service starts. Android 14+ rejects
    // startForeground(type=microphone) with a SecurityException unless the
    // app already holds RECORD_AUDIO at that exact moment -- confirmed on a
    // real device (Pixel 9a, targetSDK 36): the service crashed on every
    // attempt because this used to run in the opposite order, so
    // RECORD_AUDIO was still ungranted when startForeground() fired. If
    // _mic.start() throws MicPermissionDenied, we never reach the
    // foreground-service call at all -- that's the correct behavior.
    final outbound = await _mic.start();
    _rawVadSub = _mic.rawFragments.listen(_onRawMicFragment);

    // Best-effort: POST_NOTIFICATIONS (Android 13+) governs whether the
    // foreground service's persistent notification can actually show, but
    // unlike RECORD_AUDIO its absence doesn't crash startForeground() -- the
    // call still works, just without the notification. Request it, but
    // don't block the call on the result.
    try {
      await Permission.notification.request();
    } catch (_) {
      // Non-fatal; proceed regardless.
    }

    await _foregroundService.start();
    _nativeEventsSub = _native.events.listen((_) {
      // Buffer-underrun signals are diagnostic-only for M2 -- surfaced via
      // [events] in case a caller wants to log/telemetry them, but no
      // corrective action is taken automatically (§3.6: buffer sizing needs
      // real-device validation before that would even be well-founded).
    });

    await _native.play();
    return _gateOutbound(outbound);
  }

  /// Safety net for the AEC-fallback mute below: reported on a real device
  /// ("when I didn't talk for a while it stopped the mic") -- if the
  /// `notifyModelSpeaking(false)` signal that's supposed to un-mute never
  /// arrives cleanly for any reason (a turnComplete event that doesn't
  /// fire, a session hiccup), the mic would otherwise stay muted for the
  /// rest of the call with no recovery path and nothing visibly wrong to
  /// the person -- a real problem for a crisis line. No single spoken
  /// utterance should plausibly run this long, so this is a backstop, not
  /// a normal code path.
  static const _micMuteWatchdogTimeout = Duration(seconds: 12);
  Timer? _micMuteWatchdog;

  /// Tells the pipeline whether the model is currently speaking, so the
  /// local VAD hint (§3.5) and the AEC-unavailable mic-mute fallback (§3.4)
  /// know when to engage. The application layer derives this from
  /// `serverContent`/turn-complete events on the Gemini session.
  void notifyModelSpeaking(bool speaking) {
    _modelSpeaking = speaking;
    _vad.reset();
    if (!speaking) {
      _unmuteForAec();
    } else if (!_echoCancellationAvailable) {
      // No hardware AEC: the safe fallback is muting local capture for the
      // duration of model audio rather than risking the model hearing (and
      // responding to) itself. This trades true barge-in for correctness on
      // these devices — DESIGN.md §3.4 requires this be surfaced to the UI,
      // which reads [echoCancellationAvailable].
      _micMutedForAec = true;
      _micMuteWatchdog?.cancel();
      _micMuteWatchdog = Timer(_micMuteWatchdogTimeout, _unmuteForAec);
    }
  }

  void _unmuteForAec() {
    _micMuteWatchdog?.cancel();
    _micMuteWatchdog = null;
    _micMutedForAec = false;
    unawaited(_native.setVolume(1.0));
  }

  /// The barge-in primitive: flush the native playback ring buffer and
  /// restore full volume, ready for the next utterance. Call this only on
  /// the server's authoritative `interrupted` signal (§3.5) — never on the
  /// local VAD hint alone.
  Future<void> flushPlayback() async {
    await _native.pause();
    await _native.flush();
    await _native.setVolume(1.0);
    await _native.play();
  }

  Future<void> playInboundChunk(Uint8List pcm16) => _native.write(pcm16);

  Future<void> pausePlayback() => _native.pause();

  Future<void> resumePlayback() => _native.play();

  Future<void> stop() async {
    _focusGraceTimer?.cancel();
    _focusGraceTimer = null;
    _micMuteWatchdog?.cancel();
    _micMuteWatchdog = null;
    await _rawVadSub?.cancel();
    _rawVadSub = null;
    await _focusSub?.cancel();
    _focusSub = null;
    await _nativeEventsSub?.cancel();
    _nativeEventsSub = null;
    // Found on a real device: the call-ended notification ("still on the
    // line") kept showing after the in-app call had ended. Root cause: this
    // teardown ran mic/native/focus release sequentially and only called
    // `_foregroundService.stop()` at the very end -- one real-device hiccup
    // in any earlier step (mic/native platform-channel throwing) aborted
    // the rest of stop() and skipped it, leaving the foreground service (and
    // its persistent notification) running indefinitely. Releasing the
    // foreground/mic privilege matters more than a clean teardown of an
    // already-failed step, so it now runs in `finally`, unconditionally.
    try {
      await _mic.stop();
      await _native.pause();
      await _native.flush();
      await _native.release();
      await _focus.stop();
    } finally {
      await _foregroundService.stop();
    }
  }

  Future<void> dispose() async {
    await stop();
    await _mic.dispose();
    await _focus.dispose();
    if (!_events.isClosed) await _events.close();
  }

  Stream<Uint8List> _gateOutbound(Stream<Uint8List> source) async* {
    await for (final chunk in source) {
      if (_micMutedForAec) continue;
      yield chunk;
    }
  }

  void _onRawMicFragment(Uint8List fragment) {
    if (!_modelSpeaking || !_echoCancellationAvailable) return;
    final speaking = _vad.addChunk(fragment);
    if (speaking) {
      unawaited(_native.setVolume(_duckVolume));
      _events.add(const AudioPipelineLocalVadDucked());
    }
  }

  void _onFocusSignal(FocusSignal signal) {
    switch (signal) {
      case FocusSignal.lostPermanently:
        unawaited(_native.pause());
        _events.add(const AudioPipelinePausedByFocusLoss(permanent: true));
        _startFocusGraceTimer();
      case FocusSignal.lostTransient:
        unawaited(_native.pause());
        _events.add(const AudioPipelinePausedByFocusLoss(permanent: false));
      case FocusSignal.resumed:
        _focusGraceTimer?.cancel();
        _focusGraceTimer = null;
        unawaited(_native.play());
        _events.add(const AudioPipelineResumed());
      case FocusSignal.becomingNoisy:
        unawaited(_native.pause());
        _events.add(const AudioPipelinePausedByBecomingNoisy());
    }
  }

  void _startFocusGraceTimer() {
    _focusGraceTimer?.cancel();
    // 45s: the midpoint of DESIGN.md §3.7's ~30-60s grace window. If focus
    // isn't regained by then, the application layer (which owns the Gemini
    // session, not this pipeline) is told to close the session gracefully.
    _focusGraceTimer = Timer(const Duration(seconds: 45), () {
      _events.add(const AudioPipelineFocusGraceExpired());
    });
  }
}

/// Signals the application layer reacts to — status/UI updates, or (for
/// [AudioPipelineFocusGraceExpired]) a decision to close the Gemini session.
sealed class AudioPipelineEvent {
  const AudioPipelineEvent();
}

final class AudioPipelinePausedByFocusLoss extends AudioPipelineEvent {
  const AudioPipelinePausedByFocusLoss({required this.permanent});
  final bool permanent;
}

final class AudioPipelineResumed extends AudioPipelineEvent {
  const AudioPipelineResumed();
}

final class AudioPipelinePausedByBecomingNoisy extends AudioPipelineEvent {
  const AudioPipelinePausedByBecomingNoisy();
}

/// The ~30-60s grace window (§3.7) elapsed without focus being regained —
/// the application layer should close the session and show the "line
/// dropped" state from DESIGN.md §1.6.
final class AudioPipelineFocusGraceExpired extends AudioPipelineEvent {
  const AudioPipelineFocusGraceExpired();
}

/// The local energy-VAD hint fired and playback was ducked (not flushed).
final class AudioPipelineLocalVadDucked extends AudioPipelineEvent {
  const AudioPipelineLocalVadDucked();
}
