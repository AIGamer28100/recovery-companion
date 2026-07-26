import 'package:flutter/services.dart';

/// The only file that talks to the call's foreground-service platform
/// channel. Per DESIGN.md §3.9, without this Android suspends mic access
/// within seconds of losing foreground visibility (screen lock, task
/// switch), silently killing the call.
///
/// This is deliberately minimal for M2: start/stop around the call
/// lifecycle, matching a `foregroundServiceType="microphone"` declaration in
/// the manifest and a persistent notification
/// ("Recovery Companion — still on the line"). Wiring the notification's
/// tap-back-in/end-call actions to real in-app navigation and the
/// camera-background-restriction handling described in §3.9's last
/// paragraph belong to the (out-of-scope-here) crisis-screen UI milestone —
/// the service itself already declares those actions on the Kotlin side so
/// that milestone only needs to react to them, not add plumbing.
class ForegroundServiceChannel {
  const ForegroundServiceChannel();

  static const _channel = MethodChannel(
    'app.recoverycompanion.recovery_companion/foreground_service',
  );

  Future<void> start() async {
    await _channel.invokeMethod<void>('start');
  }

  Future<void> stop() async {
    await _channel.invokeMethod<void>('stop');
  }
}
