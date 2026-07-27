import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart' as cam;
import 'package:camera_platform_interface/camera_platform_interface.dart' as cam_platform;
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;

/// Wraps `camera`'s `CameraPreview` so the presentation layer
/// (`live_call_screen.dart`) never needs its own `package:camera` import
/// just to render the live feed — the only `camera` package name it needs
/// is `CameraController`'s type, already re-exported narrowly by
/// `LiveSessionController.cameraController`.
class LiveCameraPreview extends StatelessWidget {
  const LiveCameraPreview({super.key, required this.controller});

  final cam.CameraController controller;

  @override
  Widget build(BuildContext context) => cam.CameraPreview(controller);
}

/// Reverted off motion-gating back to the web's original steady 1fps
/// (DESIGN.md §4.1/§4.2 superseded — see the note there): real-device
/// testing found the luminance-diff gate under-sensitive to genuinely
/// meaningful but visually subtle motion (a hand lifting to take a sip of
/// water, same failure mode already documented for breathing in the
/// now-deleted `motion_diff.dart`), so the model was reasoning off a frame
/// up to 6s stale and narrating actions it hadn't actually been shown. A
/// steady 1fps send is simpler and gives real, current visual grounding
/// every tick instead of tuning a threshold that keeps finding new subtle
/// motions it misses. `PoseTracker`/`PoseMotionCounter` (continuous, off the
/// same raw `onCameraImage` stream, unaffected by this) remain the
/// real-time local trigger source layered on top.
const cameraTickInterval = Duration(milliseconds: 1000);

/// Width of the frame actually sent to the model — close to the web's 512px
/// `FRAME_WIDTH`, even though capture already requests a low preset, since
/// that still leaves headroom to trim before sending.
const cameraSendFrameWidth = 480;

/// ~0.55 on the web's 0-1 scale, matching `videoStream.ts`'s `JPEG_QUALITY`.
const cameraSendJpegQuality = 55;

/// Matches `captureFrame` in `incidents.ts` exactly (320px width, 0.45
/// quality) so incident evidence quality parity holds between the two apps.
const evidenceFrameWidth = 320;
const evidenceJpegQuality = 45;

/// Owns the `camera` package's continuous image stream and JPEG encoding for
/// both the live-streamed frames and the one evidence snapshot
/// `flagRelapseRisk` captures. The only file that imports both `camera` and
/// `image` — everything above this layer only ever sees JPEG [Uint8List]s,
/// never a `CameraImage`/`CameraController`.
///
/// Per DESIGN.md §4.1, the image stream is started once and left running
/// continuously for as long as the camera is on rather than stopping/
/// restarting per tick (`startImageStream`/`stopImageStream` has real
/// latency/overhead on Android) — every tick now sends what it has, since
/// motion-gating was reverted (§4.1's superseding note).
class LiveCameraStream {
  LiveCameraStream({required this.onFrame, this.onCameraImage, this.onCameraLost});

  /// Called with a JPEG-encoded frame whenever motion-gating decides one is
  /// due (moved enough since the last one sent, or the keyframe interval
  /// elapsed).
  final void Function(Uint8List jpeg) onFrame;

  /// Called with EVERY raw frame from the single `startImageStream`
  /// callback below -- not motion-gated, unlike [onFrame]. Added so
  /// on-device pose tracking (`PoseTracker`, wired from
  /// `LiveSessionController`) can run continuously off the exact same
  /// image stream instead of starting a second `startImageStream` consumer,
  /// which Android does not support cleanly alongside this one (see this
  /// class's own doc comment on why the stream is started once and left
  /// running). Optional and null by default -- a no-op cost when pose
  /// tracking isn't active.
  final void Function(cam.CameraImage image)? onCameraImage;

  /// Fired when the OS/CameraX itself closes or errors out the camera
  /// out from under us -- found on a real device: another app or system
  /// component claiming camera priority ("Camera access priorities have
  /// changed" / "CameraUnavailable" in logcat) can silently kill the feed
  /// while our own state still believes the camera is on, with nothing
  /// visibly wrong and no way to recover. Subscribed via
  /// `CameraPlatform.instance.onCameraError`/`onCameraClosing` right after
  /// `initialize()` -- `CameraController` itself only captures its OWN
  /// first error internally (for `value.hasError`) and nothing calls that,
  /// so this needs its own explicit listener.
  final void Function(String reason)? onCameraLost;

  cam.CameraController? _controller;
  Timer? _tick;
  cam.CameraImage? _latestImage;
  StreamSubscription<cam_platform.CameraErrorEvent>? _errorSub;
  StreamSubscription<cam_platform.CameraClosingEvent>? _closingSub;

  /// Exposes the live controller for a `CameraPreview` widget. Null until
  /// [start] resolves.
  cam.CameraController? get controller => _controller;

  bool get isRunning => _controller != null;

  /// Starts the front camera at [cam.ResolutionPreset.low] — DESIGN.md §4.1:
  /// "asking the sensor for less data in the first place is strictly cheaper
  /// than discarding it after capture" — with NV21 frames for cheap JPEG
  /// encoding on the send path.
  Future<void> start() async {
    if (_controller != null) return;
    final cameras = await cam.availableCameras();
    if (cameras.isEmpty) {
      throw StateError('No camera available on this device.');
    }
    final front = cameras.firstWhere(
      (c) => c.lensDirection == cam.CameraLensDirection.front,
      orElse: () => cameras.first,
    );
    final controller = cam.CameraController(
      front,
      cam.ResolutionPreset.low,
      enableAudio: false,
      imageFormatGroup: cam.ImageFormatGroup.nv21,
    );
    try {
      await controller.initialize();
      // Found on a real device: the sensor never refocused on its own after
      // the initial lock -- `camera`'s CameraController doesn't set
      // continuous autofocus by default on every device/API level, so this
      // has to be requested explicitly. Best-effort: some front cameras
      // (fixed-focus modules, common on budget devices) don't support
      // FocusMode.auto at all and will throw -- that's not a real failure,
      // it just means this device never had adjustable focus to begin with.
      try {
        await controller.setFocusMode(cam.FocusMode.auto);
      } catch (_) {
        // No adjustable focus on this camera -- nothing to fix, proceed.
      }
    } catch (_) {
      await controller.dispose();
      rethrow;
    }
    _controller = controller;
    _errorSub = cam_platform.CameraPlatform.instance.onCameraError(controller.cameraId).listen((event) {
      onCameraLost?.call(event.description);
    });
    _closingSub = cam_platform.CameraPlatform.instance.onCameraClosing(controller.cameraId).listen((_) {
      onCameraLost?.call('Camera closed by the system.');
    });
    await controller.startImageStream((image) {
      _latestImage = image;
      onCameraImage?.call(image);
    });
    _tick = Timer.periodic(cameraTickInterval, (_) => _onTick());
  }

  Future<void> stop() async {
    _tick?.cancel();
    _tick = null;
    await _errorSub?.cancel();
    _errorSub = null;
    await _closingSub?.cancel();
    _closingSub = null;
    _latestImage = null;
    final controller = _controller;
    _controller = null;
    if (controller == null) return;
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {
      // Best-effort — already tearing down.
    }
    await controller.dispose();
  }

  void _onTick() {
    final image = _latestImage;
    if (image == null) return;
    final jpeg = _encodeJpeg(image, targetWidth: cameraSendFrameWidth, quality: cameraSendJpegQuality);
    if (jpeg != null) onFrame(jpeg);
  }

  /// Captures the single evidence snapshot for `flagRelapseRisk` — the one
  /// deliberate, disclosed exception to "frames are ephemeral" (DESIGN.md
  /// §4.4). Uses whatever the most recently streamed frame was rather than
  /// waiting on a fresh one: the moment already passed by the time the tool
  /// call resolves, and a newly-captured frame could show something
  /// different from what actually triggered the call.
  Uint8List? captureEvidenceFrame() {
    final image = _latestImage;
    if (image == null) return null;
    return _encodeJpeg(image, targetWidth: evidenceFrameWidth, quality: evidenceJpegQuality);
  }

  static Uint8List? _encodeJpeg(cam.CameraImage image, {required int targetWidth, required int quality}) {
    final rgb = _nv21ToRgbImage(image);
    if (rgb == null) return null;
    final resized = targetWidth < rgb.width
        ? img.copyResize(rgb, width: targetWidth, interpolation: img.Interpolation.linear)
        : rgb;
    return img.encodeJpg(resized, quality: quality);
  }

  /// Standard BT.601 NV21 (Y plane + interleaved VU) to RGB conversion.
  /// `camera_android_camerax` reports a single tightly-packed NV21 plane
  /// (`bytesPerRow == width`, no row padding) when
  /// [cam.ImageFormatGroup.nv21] is requested, so no stride handling beyond
  /// the Y-plane's own `bytesPerRow` is needed here.
  static img.Image? _nv21ToRgbImage(cam.CameraImage image) {
    if (image.planes.isEmpty) return null;
    final width = image.width;
    final height = image.height;
    final nv21 = image.planes.first.bytes;
    final ySize = width * height;
    if (nv21.length < ySize + (ySize ~/ 2)) return null;

    final rgb = Uint8List(width * height * 3);
    var rgbIndex = 0;
    for (var y = 0; y < height; y++) {
      final uvRowOffset = (y >> 1) * width;
      for (var x = 0; x < width; x++) {
        final yValue = nv21[y * width + x] & 0xff;
        final uvCol = (x >> 1) * 2;
        final vIndex = ySize + uvRowOffset + uvCol;
        final v = nv21[vIndex] & 0xff;
        final u = nv21[vIndex + 1] & 0xff;

        final c = yValue - 16;
        final d = u - 128;
        final e = v - 128;

        rgb[rgbIndex++] = _clampByte((298 * c + 409 * e + 128) >> 8);
        rgb[rgbIndex++] = _clampByte((298 * c - 100 * d - 208 * e + 128) >> 8);
        rgb[rgbIndex++] = _clampByte((298 * c + 516 * d + 128) >> 8);
      }
    }
    return img.Image.fromBytes(
      width: width,
      height: height,
      bytes: rgb.buffer,
      numChannels: 3,
      order: img.ChannelOrder.rgb,
    );
  }

  static int _clampByte(int value) => value < 0 ? 0 : (value > 255 ? 255 : value);
}
