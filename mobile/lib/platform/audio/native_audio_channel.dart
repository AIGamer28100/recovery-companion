import 'dart:async';

import 'package:flutter/services.dart';

/// The only file that talks to the Kotlin side's playback platform channel.
/// Wraps `android.media.AudioTrack` (MODE_STREAM, 24kHz PCM16) plus
/// `AcousticEchoCanceler` control and `AudioManager` communication-mode
/// switching, per DESIGN.md §3.3/§3.4. See
/// `android/app/src/main/kotlin/.../audio/NativeAudioChannel.kt` for the
/// native implementation this talks to.
class NativeAudioChannel {
  NativeAudioChannel()
      : _method = const MethodChannel(_methodChannelName),
        _events = const EventChannel(_eventChannelName);

  static const _methodChannelName =
      'app.recoverycompanion.recovery_companion/native_audio';
  static const _eventChannelName =
      'app.recoverycompanion.recovery_companion/native_audio_events';

  final MethodChannel _method;
  final EventChannel _events;
  Stream<NativeAudioEvent>? _eventStream;

  /// Initializes the native `AudioTrack` (24kHz, mono, PCM16, MODE_STREAM)
  /// and puts `AudioManager` into `MODE_IN_COMMUNICATION`. Returns whether
  /// hardware `AcousticEchoCanceler` was available and enabled — surfaced so
  /// the UI can show the "tap to interrupt" fallback affordance when false
  /// (§3.4).
  Future<bool> init() async {
    final result = await _method.invokeMethod<bool>('init');
    return result ?? false;
  }

  /// Writes one chunk of 24kHz PCM16 audio to the playback buffer.
  Future<void> write(Uint8List pcm16) async {
    await _method.invokeMethod<void>('write', pcm16);
  }

  /// Pauses playback without discarding buffered audio (used for focus-loss
  /// pause, not barge-in — barge-in uses [flush]).
  Future<void> pause() async {
    await _method.invokeMethod<void>('pause');
  }

  /// The barge-in primitive: pause, drop every buffered sample, and leave
  /// the track ready to `play()` clean for the next utterance. Per §3.3 this
  /// precise flush is the entire reason a container-based Dart audio player
  /// wasn't used.
  Future<void> flush() async {
    await _method.invokeMethod<void>('flush');
  }

  Future<void> play() async {
    await _method.invokeMethod<void>('play');
  }

  /// 0.0-1.0. Used by the client-side energy-VAD hint to duck (not flush)
  /// local playback the moment the user starts talking — see §3.5.
  Future<void> setVolume(double volume) async {
    await _method.invokeMethod<void>('setVolume', volume);
  }

  /// Tears down the `AudioTrack` and restores `AudioManager.MODE_NORMAL`.
  Future<void> release() async {
    await _method.invokeMethod<void>('release');
  }

  /// Buffer-underrun / echo-cancellation-availability signals from the
  /// native side.
  Stream<NativeAudioEvent> get events {
    return _eventStream ??= _events
        .receiveBroadcastStream()
        .map((event) => NativeAudioEvent.fromWire(event));
  }
}

sealed class NativeAudioEvent {
  const NativeAudioEvent();

  static NativeAudioEvent fromWire(Object? event) {
    if (event is Map) {
      final type = event['type'];
      if (type == 'underrun') return const PlaybackBufferUnderrun();
    }
    return const UnknownNativeAudioEvent();
  }
}

/// The native ring buffer ran dry — playback stuttered. Diagnostic signal
/// only; DESIGN.md §3.6 flags real buffer sizing as something to validate on
/// a device, not guess.
final class PlaybackBufferUnderrun extends NativeAudioEvent {
  const PlaybackBufferUnderrun();
}

final class UnknownNativeAudioEvent extends NativeAudioEvent {
  const UnknownNativeAudioEvent();
}
