/// Mirrors `CameraState`/`CameraAvailability`/`describeCameraForModel` in
/// `src/lib/cameraAvailability.ts`, adapted for Android hardware+permission
/// probing (`../../../platform/camera/camera_availability_probe.dart`)
/// instead of browser `navigator.mediaDevices`/Permissions APIs. Plain Dart,
/// no `camera`/`permission_handler` imports — those stay confined to the
/// probe file, per DESIGN.md §2.3's layering rule.
library;

enum CameraState {
  /// Hardware present and either already granted or still promptable.
  available,

  /// Hardware present but the user has explicitly (permanently) blocked
  /// camera access.
  blocked,

  /// No camera hardware on this device.
  none,

  /// Availability couldn't be determined (probe failed, or ran on a
  /// platform without a working `camera` plugin implementation).
  unsupported,
}

class CameraAvailability {
  const CameraAvailability({required this.state, required this.canOffer});

  /// True only when it's actually worth offering the camera to the user.
  final CameraState state;
  final bool canOffer;

  static const unsupported = CameraAvailability(state: CameraState.unsupported, canOffer: false);
}

/// The line handed to the model so it knows whether offering the camera
/// makes sense — ported verbatim in meaning from `describeCameraForModel` in
/// `cameraAvailability.ts`. This exact wording is read by the model, not a
/// person, so it is not paraphrased freely; only "in their browser" was
/// swapped for "on their device" since there is no browser here.
String describeCameraForModel(CameraAvailability availability, bool isOn) {
  if (isOn) {
    return 'Their camera is currently ON — you can see them. Use it to coach and validate what they do.';
  }
  switch (availability.state) {
    case CameraState.available:
      return 'Their camera is currently OFF, but a working camera IS available and there is a camera '
          'button on their screen. If you want to coach them through something physical, ask them '
          'once to turn it on and say why it helps.';
    case CameraState.blocked:
      return 'They have BLOCKED camera access on their device. Do NOT ask them to turn the camera on — '
          'you cannot see them and asking would only frustrate them. Coach entirely by voice.';
    case CameraState.none:
      return 'This device has NO camera at all. Never ask them to turn on a camera or to show you '
          'anything. Coach entirely by voice, and rely on what you hear and what they tell you.';
    case CameraState.unsupported:
      return 'Camera availability is unknown on this device. Do not ask them to turn on a camera. '
          'Coach entirely by voice.';
  }
}

/// The exact silent director-note text sent when the camera is switched OFF
/// (manually or via the thermal guardrail), ported word-for-word from
/// `toggleCamera` in `useLiveSession.ts` — this is model input, not UI copy,
/// so it is not paraphrased.
String cameraOffDirectorNote(CameraAvailability availability) {
  return '[Silent director note, not from the user. Their camera is now OFF — you can no longer '
      'see them. Do not comment on it. Keep coaching by voice alone. '
      '${describeCameraForModel(availability, false)}]';
}

/// The exact silent director-note text sent when the camera is switched ON,
/// ported word-for-word from `toggleCamera` in `useLiveSession.ts`.
String cameraOnDirectorNote(CameraAvailability availability) {
  return '[Silent director note, not from the user. ${describeCameraForModel(availability, true)} '
      'Do not announce this or thank them; just start using it. Say nothing right now unless '
      'you were mid-exercise with them.]';
}

/// Director note for the thermal guardrail (DESIGN.md §4.3): "tell the model
/// via a director note that mirrors the manual-camera-off path". Has no web
/// equivalent — the browser has no comparable thermal API — so this is new
/// copy, not a port, but deliberately shaped like [cameraOffDirectorNote] so
/// the model treats it the same way (stop asking about the camera, don't
/// comment), plus an explicit reason so it doesn't read the moment as the
/// person choosing to hide from it.
String cameraThermalDegradeDirectorNote() {
  return '[Silent director note, not from the user. Their camera has just been turned OFF '
      "automatically because their phone is overheating — this was not their choice, so don't "
      'comment on it or mention the phone. You can no longer see them. Keep coaching by voice alone.]';
}
