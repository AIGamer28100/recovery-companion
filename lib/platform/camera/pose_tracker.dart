import 'dart:async';
import 'dart:ui' show Size;

import 'package:camera/camera.dart' as cam;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'pose_motion_counter.dart';

/// The only file in the app that imports `google_mlkit_pose_detection` or
/// `google_mlkit_commons` -- mirrors the layering rule `live_camera_stream.dart`
/// already establishes for `camera`+`image` (see that file's and
/// `LiveSessionController.cameraController`'s doc comments): everything
/// above this layer only ever sees plain [PoseMotionEvent]s, never an ML Kit
/// `Pose`/`InputImage`.
///
/// Runs Google ML Kit's on-device Pose Detection -- entirely local, nothing
/// here is ever sent to Gemini or any other cloud model -- continuously on
/// the SAME NV21 frames `LiveCameraStream` already pulls from its one
/// `startImageStream` callback (see that class's `onCameraImage` hook, added
/// alongside this feature). There is deliberately no second
/// `startImageStream` call: `LiveCameraStream`'s own doc comment already
/// establishes a single continuous image stream as the design (Android does
/// not cleanly support two concurrent image-stream consumers on one
/// `CameraController`), and this class just taps into that same stream
/// rather than competing with it.
///
/// Feeds landmark positions through the pure counters in
/// `pose_motion_counter.dart` and reports completed rep/breath cycles via
/// [onMotionEvent]. Never talks to the Gemini Live session itself -- turning
/// counts into director notes and sending them is `LiveSessionController`'s
/// job, same as it already owns turning camera-availability state into
/// director notes.
class PoseTracker {
  PoseTracker({required this.onMotionEvent});

  final void Function(PoseMotionEvent event) onMotionEvent;

  PoseDetector? _detector;
  PoseMotionCounter? _counter;
  int _rotationDegrees = 0;

  /// True while a `processImage` call is in flight. `PoseDetector.processImage`
  /// is a bare `MethodChannel.invokeMethod` round-trip (confirmed by reading
  /// the plugin source, `pose_detector.dart`) -- the actual ML Kit inference
  /// runs natively and the call is fully async, so awaiting it never blocks
  /// Flutter's UI isolate. What it doesn't do on its own is rate-limit: if
  /// frames arrive faster than native inference completes, nothing stops
  /// this method from being called again before the previous call resolves.
  /// This flag is that rate limit -- frames are simply dropped while one is
  /// already being processed, the same "drop what we don't have time for"
  /// approach `LiveCameraStream`'s own motion-gating already uses for the
  /// Gemini-frame path.
  bool _busy = false;

  bool get isRunning => _detector != null;

  static const _minLandmarkLikelihood = 0.5;

  /// Starts the detector for this camera-on session.
  /// [sensorOrientationDegrees] is the active camera's
  /// `CameraDescription.sensorOrientation` (see `LiveCameraStream.controller`)
  /// -- captured once here rather than recomputed per frame, since it does
  /// not change mid-session. Assumes the phone is held portrait-up while
  /// talking, which is the app's expected usage; there is no continuous
  /// device-orientation compensation, deliberately matching the same
  /// simplifying assumption `live_camera_stream.dart`'s own JPEG-encoding
  /// path already makes for the frames sent to Gemini (neither path
  /// rotates against live device orientation).
  void start({required int sensorOrientationDegrees}) {
    if (_detector != null) return;
    _rotationDegrees = sensorOrientationDegrees;
    _detector = PoseDetector(options: PoseDetectorOptions(mode: PoseDetectionMode.stream));
    _counter = PoseMotionCounter();
    _busy = false;
  }

  Future<void> stop() async {
    final detector = _detector;
    _detector = null;
    _counter = null;
    _busy = false;
    if (detector == null) return;
    try {
      await detector.close();
    } catch (_) {
      // Best-effort -- already tearing down.
    }
  }

  /// Called from `LiveCameraStream`'s own `startImageStream` callback with
  /// every raw frame. A no-op (silently drops the frame) whenever tracking
  /// isn't running or a previous frame is still being processed natively --
  /// see [_busy]'s doc comment.
  void processFrame(cam.CameraImage image) {
    final detector = _detector;
    final counter = _counter;
    if (detector == null || counter == null || _busy) return;
    final input = _toInputImage(image);
    if (input == null) return;
    _busy = true;
    unawaited(_process(detector, counter, input));
  }

  Future<void> _process(PoseDetector detector, PoseMotionCounter counter, InputImage input) async {
    try {
      final poses = await detector.processImage(input);
      if (poses.isEmpty) return;
      final sample = _toPoseSample(poses.first, DateTime.now());
      if (sample == null) return;
      for (final event in counter.addSample(sample)) {
        onMotionEvent(event);
      }
    } catch (_) {
      // Best-effort -- a dropped or failed inference must never affect the
      // call itself, mirroring `LiveCameraStream`'s own tolerance for
      // camera hiccups.
    } finally {
      _busy = false;
    }
  }

  /// NV21 bytes -> ML Kit [InputImage], reading the exact same plane data
  /// `LiveCameraStream._sampleLuminance`/`_nv21ToRgbImage` already sample --
  /// confirmed against `google_mlkit_commons`' [InputImageFormat.nv21],
  /// which is documented as directly Android-supported (no RGB conversion
  /// needed here, unlike the JPEG-encoding path). Matches
  /// `live_camera_stream.dart`'s own documented assumption that
  /// `camera_android_camerax` + `ImageFormatGroup.nv21` reports a single
  /// tightly-packed plane (`image.planes.first`) rather than three separate
  /// Y/U/V planes.
  InputImage? _toInputImage(cam.CameraImage image) {
    if (image.planes.isEmpty) return null;
    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: _toInputImageRotation(_rotationDegrees),
        format: InputImageFormat.nv21,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  static InputImageRotation _toInputImageRotation(int degrees) {
    switch (degrees % 360) {
      case 90:
        return InputImageRotation.rotation90deg;
      case 180:
        return InputImageRotation.rotation180deg;
      case 270:
        return InputImageRotation.rotation270deg;
      default:
        return InputImageRotation.rotation0deg;
    }
  }

  /// Extracts only the landmarks [PoseMotionCounter] needs, each gated on a
  /// minimum-confidence bar -- returns null (skip this frame entirely)
  /// rather than feed the counter a guessed position if any of them weren't
  /// detected confidently enough.
  static PoseSample? _toPoseSample(Pose pose, DateTime at) {
    double? y(PoseLandmarkType type) {
      final landmark = pose.landmarks[type];
      if (landmark == null || landmark.likelihood < _minLandmarkLikelihood) return null;
      return landmark.y;
    }

    final leftShoulder = y(PoseLandmarkType.leftShoulder);
    final rightShoulder = y(PoseLandmarkType.rightShoulder);
    final leftHip = y(PoseLandmarkType.leftHip);
    final rightHip = y(PoseLandmarkType.rightHip);
    final leftWrist = y(PoseLandmarkType.leftWrist);
    final rightWrist = y(PoseLandmarkType.rightWrist);
    final leftAnkle = y(PoseLandmarkType.leftAnkle);
    final rightAnkle = y(PoseLandmarkType.rightAnkle);
    if (leftShoulder == null ||
        rightShoulder == null ||
        leftHip == null ||
        rightHip == null ||
        leftWrist == null ||
        rightWrist == null ||
        leftAnkle == null ||
        rightAnkle == null) {
      return null;
    }

    return PoseSample(
      timestamp: at,
      shoulderMidY: (leftShoulder + rightShoulder) / 2,
      hipMidY: (leftHip + rightHip) / 2,
      wristMidY: (leftWrist + rightWrist) / 2,
      ankleMidY: (leftAnkle + rightAnkle) / 2,
    );
  }
}
