import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart' as cam;
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;

import 'motion_diff.dart';

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

/// Tick interval — widened from the web's 1000ms per DESIGN.md §4.1 ("Phone
/// camera pipelines... cost more CPU per frame pulled than a browser's
/// `drawImage`"), landing in the middle of the specified 1500-2000ms band.
// Tightened from DESIGN.md's original 1750ms after real-device feedback:
// paced coaching (counting breaths, jumping jacks) felt laggy against the
// model's spoken cadence -- the model can only react to what it's been
// sent, and 1750ms between checks is a long gap relative to a ~4s breath
// cycle. 800ms is a middle ground between the web's original 1000ms and
// the mobile-specific widening DESIGN.md §4.1 argued for on CPU/battery
// grounds -- the thermal guardrail (§4.3) is the intended safety net if
// this proves too aggressive on a real device, not a reason to avoid
// tightening it here.
const cameraTickInterval = Duration(milliseconds: 800);

/// Matches `KEYFRAME_INTERVAL_MS` in `videoStream.ts` — DESIGN.md §4.1 calls
/// out no reason to diverge, since it's tuned against the same
/// `contextWindowCompression` behavior on both apps.
const cameraKeyframeInterval = Duration(seconds: 6);

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

/// Small luminance thumbnail used only for the motion-diff comparison —
/// matches `DIFF_W`/`DIFF_H` in `videoStream.ts`.
const _diffW = 32;
const _diffH = 24;

/// Owns the `camera` package's continuous image stream, motion-gated frame
/// selection, and JPEG encoding for both the live-streamed frames and the
/// one evidence snapshot `flagRelapseRisk` captures. The only file that
/// imports both `camera` and `image` — everything above this layer only
/// ever sees JPEG [Uint8List]s, never a `CameraImage`/`CameraController`.
///
/// Per DESIGN.md §4.1, the image stream is started once and left running
/// continuously for as long as the camera is on; frames are discarded on
/// ticks that don't need evaluating rather than stopping/restarting the
/// pipeline (`startImageStream`/`stopImageStream` has real latency/overhead
/// on Android).
class LiveCameraStream {
  LiveCameraStream({required this.onFrame});

  /// Called with a JPEG-encoded frame whenever motion-gating decides one is
  /// due (moved enough since the last one sent, or the keyframe interval
  /// elapsed).
  final void Function(Uint8List jpeg) onFrame;

  cam.CameraController? _controller;
  Timer? _tick;
  cam.CameraImage? _latestImage;
  List<int>? _prevThumb;
  DateTime? _lastKeyframeAt;

  /// Exposes the live controller for a `CameraPreview` widget. Null until
  /// [start] resolves.
  cam.CameraController? get controller => _controller;

  bool get isRunning => _controller != null;

  /// Starts the front camera at [cam.ResolutionPreset.low] — DESIGN.md §4.1:
  /// "asking the sensor for less data in the first place is strictly cheaper
  /// than discarding it after capture" — with NV21 frames so motion-diff can
  /// sample the Y-plane directly without an RGBA conversion.
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
    _prevThumb = null;
    _lastKeyframeAt = null;
    await controller.startImageStream((image) => _latestImage = image);
    _tick = Timer.periodic(cameraTickInterval, (_) => _onTick());
  }

  Future<void> stop() async {
    _tick?.cancel();
    _tick = null;
    _latestImage = null;
    _prevThumb = null;
    _lastKeyframeAt = null;
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

    final now = DateTime.now();
    final dueForKeyframe = isDueForKeyframe(_lastKeyframeAt, now, cameraKeyframeInterval);
    final thumb = _sampleLuminance(image, _diffW, _diffH);
    final moved = hasMotion(thumb, _prevThumb);
    _prevThumb = thumb;

    if (!moved && !dueForKeyframe) return;
    _lastKeyframeAt = now;

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

  /// Samples the Y (luminance) plane directly on a coarse grid — cheaper
  /// than the web's approach, which has to stride through an RGBA canvas
  /// buffer to read one channel per pixel (DESIGN.md §4.1); an NV21 Y-plane
  /// byte is already a plain luminance sample.
  static List<int> _sampleLuminance(cam.CameraImage image, int outW, int outH) {
    final yPlane = image.planes.first;
    final bytes = yPlane.bytes;
    final stride = yPlane.bytesPerRow;
    final width = image.width;
    final height = image.height;
    final samples = List<int>.filled(outW * outH, 0);
    for (var oy = 0; oy < outH; oy++) {
      final sy = (oy * height) ~/ outH;
      final rowOffset = sy * stride;
      for (var ox = 0; ox < outW; ox++) {
        final sx = (ox * width) ~/ outW;
        samples[oy * outW + ox] = bytes[rowOffset + sx];
      }
    }
    return samples;
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
