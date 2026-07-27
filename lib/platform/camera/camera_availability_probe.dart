import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../features/live_session/domain/camera_availability.dart';

/// The only file that combines `camera` + `permission_handler` to answer "is
/// a camera genuinely usable right now" — the Android analogue of
/// `detectCameraAvailability` in `cameraAvailability.ts`.
///
/// Deliberately never requests the permission itself, mirroring the web's
/// "don't call `getUserMedia`, which would trigger the prompt as a side
/// effect of merely checking" rule (`cameraAvailability.ts`'s doc comment) —
/// this only reads whatever the user has already decided.
Future<CameraAvailability> detectCameraAvailability() async {
  List<CameraDescription> cameras;
  try {
    cameras = await availableCameras();
  } catch (_) {
    return CameraAvailability.unsupported;
  }
  if (cameras.isEmpty) {
    return const CameraAvailability(state: CameraState.none, canOffer: false);
  }

  PermissionStatus status;
  try {
    status = await Permission.camera.status;
  } catch (_) {
    // Permission plumbing failed to answer at all — treat as available
    // rather than blocked, since hardware is confirmed present and the
    // system permission dialog can still resolve this when actually used.
    return const CameraAvailability(state: CameraState.available, canOffer: true);
  }

  // A permanent denial is the decisive, "don't bother asking" signal —
  // mirrors the web's decisive `denied` check. A plain (not-yet-decided)
  // denial is still promptable, so it counts as available, same as the web
  // treating "no decision yet" as available.
  if (status.isPermanentlyDenied) {
    return const CameraAvailability(state: CameraState.blocked, canOffer: false);
  }
  return const CameraAvailability(state: CameraState.available, canOffer: true);
}
