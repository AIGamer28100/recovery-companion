/// Silent director-note text for the on-device rep/breath counts computed by
/// ML Kit pose tracking (`platform/camera/pose_tracker.dart`). Follows the
/// exact bracket convention `camera_availability.dart`'s
/// `cameraOnDirectorNote`/`cameraOffDirectorNote` establish -- this is model
/// input read by Gemini, not UI copy shown to a person, so it is written in
/// the same voice deliberately. Plain Dart, no camera/ML Kit imports.
library;

/// Sent whenever `LiveSessionController`'s throttled pose-tracking wiring
/// has a fresh rep and/or breath count to report. At least one of [reps]/
/// [breaths] having changed since the last note is the caller's
/// responsibility -- this just formats whatever current totals it's given.
String poseMotionDirectorNote({required int reps, required int breaths}) {
  final parts = <String>[];
  if (reps > 0) {
    parts.add('$reps rep${reps == 1 ? '' : 's'} (arm/leg movement, e.g. jumping jacks)');
  }
  if (breaths > 0) {
    parts.add('$breaths breath cycle${breaths == 1 ? '' : 's'} (shoulder/chest rise and fall)');
  }
  final counted = parts.isEmpty ? 'no completed reps or breath cycles yet' : parts.join(' and ');
  return '[Silent director note, not from the user. On-device motion tracking (not the camera frames '
      "you see) has counted $counted so far this exercise. This is a precise, continuous count -- use "
      'it to pace your own spoken counting and coaching rhythm rather than guessing from occasional '
      'frames. Do not announce this note itself or mention that tracking exists; just count along '
      'naturally, as if you were watching closely yourself.]';
}
