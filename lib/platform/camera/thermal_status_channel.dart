import 'package:flutter/services.dart';

/// Mirrors the subset of Android's `PowerManager.THERMAL_STATUS_*` ordinals
/// (API 29+) DESIGN.md §4.3 acts on. Ordinal order matters — [fromWireValue]
/// depends on it matching the platform constants exactly.
enum ThermalStatus {
  none,
  light,
  moderate,
  severe,
  critical,
  emergency,
  shutdown,
  unknown;

  /// DESIGN.md §4.3: degrade to audio-only at `THERMAL_STATUS_SEVERE` or
  /// above. [unknown] (probe failed, or API < 29) is never treated as severe
  /// — a guardrail that can't be evaluated correctly must not fire.
  bool get isSevereOrAbove => this != ThermalStatus.unknown && index >= ThermalStatus.severe.index;

  static ThermalStatus fromWireValue(Object? value) {
    const ordinals = [
      ThermalStatus.none,
      ThermalStatus.light,
      ThermalStatus.moderate,
      ThermalStatus.severe,
      ThermalStatus.critical,
      ThermalStatus.emergency,
      ThermalStatus.shutdown,
    ];
    if (value is! int || value < 0 || value >= ordinals.length) return ThermalStatus.unknown;
    return ordinals[value];
  }
}

/// The only file that talks to the thermal-status platform channel. Wraps
/// `PowerManager.getCurrentThermalStatus()` / `addThermalStatusListener`
/// (API 29+) per DESIGN.md §4.3. See
/// `android/app/src/main/kotlin/.../camera/ThermalStatusChannel.kt` for the
/// native side — below API 29 it always reports [ThermalStatus.unknown]
/// rather than attempting a guardrail the OS doesn't support.
class ThermalStatusChannel {
  ThermalStatusChannel()
      : _method = const MethodChannel(_methodChannelName),
        _events = const EventChannel(_eventChannelName);

  static const _methodChannelName = 'app.recoverycompanion.recovery_companion/thermal_status';
  static const _eventChannelName =
      'app.recoverycompanion.recovery_companion/thermal_status_events';

  final MethodChannel _method;
  final EventChannel _events;
  Stream<ThermalStatus>? _stream;

  Future<ThermalStatus> currentStatus() async {
    try {
      final result = await _method.invokeMethod<int>('getCurrentThermalStatus');
      return ThermalStatus.fromWireValue(result);
    } on PlatformException {
      return ThermalStatus.unknown;
    }
  }

  /// Fires on every native thermal status change while listened to. Cheap
  /// to leave subscribed for the lifetime of a live call — the native side
  /// only registers its OS-level listener while something is listening here.
  Stream<ThermalStatus> get statusChanges {
    return _stream ??=
        _events.receiveBroadcastStream().map((event) => ThermalStatus.fromWireValue(event));
  }
}
