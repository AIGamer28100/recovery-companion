/// Pure landmark-motion counting math for the on-device pose-tracking
/// feature -- reduced to plain Dart doubles/timestamps so [OscillationCounter],
/// [repSignal]/[breathSignal], and [PoseMotionCounter] are all unit-testable
/// without any `google_mlkit_pose_detection`/`camera` import. Mirrors how
/// `motion_diff.dart` isolates `live_camera_stream.dart`'s YUV motion-gating
/// math from the plugin calls themselves -- `pose_tracker.dart` is the only
/// file that builds a [PoseSample] from a real ML Kit `Pose` and the only
/// one importing ML Kit at all.
library;

/// One frame's worth of the body landmark positions the counters need,
/// already reduced to plain vertical (y) coordinates in the source image's
/// own coordinate space (pixels, per ML Kit's `PoseLandmark`) -- scale
/// normalization (against torso height) happens inside [repSignal]/
/// [breathSignal], not here, so this stays a simple data holder.
class PoseSample {
  const PoseSample({
    required this.timestamp,
    required this.shoulderMidY,
    required this.hipMidY,
    required this.wristMidY,
    required this.ankleMidY,
  });

  final DateTime timestamp;

  /// Midpoint y of the two shoulder landmarks -- one end of "torso height",
  /// and the breathing signal's own reference point.
  final double shoulderMidY;

  /// Midpoint y of the two hip landmarks -- the other end of "torso height".
  final double hipMidY;

  /// Midpoint y of the two wrist landmarks -- the arm half of the rep
  /// signal (a smaller y means the wrists are higher/raised, since image y
  /// grows downward).
  final double wristMidY;

  /// Midpoint y of the two ankle landmarks -- the leg half of the rep
  /// signal (feet lifting off the ground shows up as a smaller y here too).
  final double ankleMidY;
}

/// Shoulder-to-hip distance, floored well above zero so a degenerate/near-
/// coincident detection (landmarks collapsed onto each other from a bad
/// frame) can't blow up the normalization below into a huge spurious swing.
double _torsoHeight(PoseSample s) {
  final height = (s.hipMidY - s.shoulderMidY).abs();
  return height < 0.02 ? 0.02 : height;
}

/// Hip-to-ankle distance, same flooring as [_torsoHeight] -- used only as
/// [breathSignal]'s normalization scale, deliberately NOT the shoulder-hip
/// distance: the legs don't move during breathing, so this stays a stable
/// scale reference frame-to-frame, whereas normalizing the shoulder
/// position by a shoulder-hip distance would be circular (the shoulder
/// term would appear on both sides of the ratio and cancel to a constant).
double _legHeight(PoseSample s) {
  final height = (s.hipMidY - s.ankleMidY).abs();
  return height < 0.02 ? 0.02 : height;
}

/// A single scalar "limb extension" signal for jumping-jack-style reps:
/// the average of how far the wrists are raised above the shoulders and how
/// far the ankles are lifted above the hips, each normalized by torso
/// height so the signal doesn't depend on distance from the camera. This is
/// a deliberately simple proxy for "arms/legs moving through a repetitive
/// vertical range" -- not a biomechanically precise jumping-jack detector.
double repSignal(PoseSample s) {
  final torso = _torsoHeight(s);
  final armRaise = (s.shoulderMidY - s.wristMidY) / torso;
  final legLift = (s.hipMidY - s.ankleMidY) / torso;
  return (armRaise + legLift) / 2;
}

/// The breathing signal: the shoulders' vertical position (shoulders rise
/// slightly on inhale, fall on exhale), normalized by [_legHeight] rather
/// than shoulder-hip torso height precisely so the shoulder term doesn't
/// also appear in its own denominator -- see that function's doc comment.
double breathSignal(PoseSample s) {
  final scale = _legHeight(s);
  return (s.hipMidY - s.shoulderMidY) / scale;
}

enum _SweepPhase { low, high }

/// Generic hysteresis peak/trough cycle counter for a smoothed 1-D signal.
/// One "cycle" is the signal climbing at least [minAmplitude] above its most
/// recent trough (entering the "high" phase), then falling back at least
/// [minAmplitude] from its peak (returning to "low") -- that full swing,
/// timed within [minPeriod]..[maxPeriod], counts as one rep/breath. Shared
/// by both counters in [PoseMotionCounter], just with different tuning:
/// simple peak/trough detection on a smoothed signal, exactly per the
/// feature's intentionally narrow scope -- not a general activity
/// recognizer.
class OscillationCounter {
  OscillationCounter({
    required this.minAmplitude,
    required this.minPeriod,
    required this.maxPeriod,
    this.smoothingAlpha = 0.35,
  });

  /// Minimum swing (in whatever units the signal is already normalized to)
  /// before a half-cycle registers.
  final double minAmplitude;

  /// A completed cycle faster than this is treated as noise, not a real
  /// rep/breath.
  final Duration minPeriod;

  /// A completed cycle slower than this is treated as two unrelated drifts,
  /// not one continuous rep/breath.
  final Duration maxPeriod;

  /// Exponential-smoothing factor applied to every incoming sample before
  /// peak/trough tracking -- higher reacts faster but admits more noise.
  final double smoothingAlpha;

  double? _smoothed;
  double _troughValue = 0;
  double _peakValue = 0;
  _SweepPhase _phase = _SweepPhase.low;
  DateTime? _cycleStartedAt;
  int _count = 0;

  int get count => _count;

  /// Feeds one new (value, timestamp) sample. Returns true iff this sample
  /// completed a new cycle (bumping [count]).
  bool addSample(double value, DateTime at) {
    final previous = _smoothed;
    final smoothed = previous == null ? value : previous + smoothingAlpha * (value - previous);
    _smoothed = smoothed;

    if (previous == null) {
      // First sample ever -- nothing to compare against yet, just seed the
      // trough/peak trackers.
      _troughValue = smoothed;
      _peakValue = smoothed;
      return false;
    }

    switch (_phase) {
      case _SweepPhase.low:
        if (smoothed < _troughValue) _troughValue = smoothed;
        if (smoothed - _troughValue >= minAmplitude) {
          _phase = _SweepPhase.high;
          _peakValue = smoothed;
          _cycleStartedAt = at;
        }
        return false;
      case _SweepPhase.high:
        if (smoothed > _peakValue) _peakValue = smoothed;
        if (_peakValue - smoothed >= minAmplitude) {
          _phase = _SweepPhase.low;
          _troughValue = smoothed;
          final startedAt = _cycleStartedAt;
          _cycleStartedAt = null;
          if (startedAt != null) {
            final period = at.difference(startedAt);
            if (period >= minPeriod && period <= maxPeriod) {
              _count++;
              return true;
            }
          }
        }
        return false;
    }
  }
}

/// What kind of completed cycle a [PoseMotionEvent] reports.
enum PoseMotionKind { rep, breath }

/// One completed rep or breath cycle, with the running total so far this
/// session -- deliberately a total, not a delta, so a consumer that misses
/// or throttles some events (see `LiveSessionController`'s ~2s director-note
/// throttle) never loses track of the true count.
class PoseMotionEvent {
  const PoseMotionEvent({required this.kind, required this.totalCount});

  final PoseMotionKind kind;
  final int totalCount;
}

/// Unvalidated starting-point tuning -- there is no way to calibrate these
/// against a real device in this environment (see `motion_diff.dart`'s
/// `yPlaneMotionThreshold` doc comment for the same honest caveat on a
/// sibling threshold). Reps: a deliberate, clearly-raised arm/leg swing,
/// roughly a quarter of the shoulder-to-hip distance, completing in well
/// under a slow walk's cadence but not faster than a real human can move.
/// Breaths: a much smaller shoulder swing over a much slower window.
const repMinAmplitude = 0.22;
const repMinPeriod = Duration(milliseconds: 250);
const repMaxPeriod = Duration(seconds: 4);
const breathMinAmplitude = 0.035;
const breathMinPeriod = Duration(milliseconds: 1500);
const breathMaxPeriod = Duration(seconds: 10);

/// Combines the rep and breath [OscillationCounter]s behind one call site:
/// feed it a [PoseSample] per processed frame, get back whichever cycle(s)
/// it just completed (almost always zero or one; both firing on the exact
/// same sample is possible but rare).
class PoseMotionCounter {
  PoseMotionCounter({OscillationCounter? repCounter, OscillationCounter? breathCounter})
      : _rep = repCounter ??
            OscillationCounter(minAmplitude: repMinAmplitude, minPeriod: repMinPeriod, maxPeriod: repMaxPeriod),
        _breath = breathCounter ??
            OscillationCounter(
                minAmplitude: breathMinAmplitude, minPeriod: breathMinPeriod, maxPeriod: breathMaxPeriod);

  final OscillationCounter _rep;
  final OscillationCounter _breath;

  int get totalReps => _rep.count;
  int get totalBreaths => _breath.count;

  List<PoseMotionEvent> addSample(PoseSample sample) {
    final events = <PoseMotionEvent>[];
    if (_rep.addSample(repSignal(sample), sample.timestamp)) {
      events.add(PoseMotionEvent(kind: PoseMotionKind.rep, totalCount: _rep.count));
    }
    if (_breath.addSample(breathSignal(sample), sample.timestamp)) {
      events.add(PoseMotionEvent(kind: PoseMotionKind.breath, totalCount: _breath.count));
    }
    return events;
  }
}
