/// Pure luminance-diff motion detection, ported from `videoStream.ts`'s
/// `motionSinceLastFrame`. No `camera`/`image` imports here on purpose —
/// this file is the testable math, kept separate from `live_camera_stream.dart`
/// (which does the actual YUV sampling and JPEG encoding) so the threshold
/// logic can be unit-tested without a camera plugin or device.
library;

/// Below this mean per-sample delta the scene is treated as unchanged.
///
/// The web's `MOTION_THRESHOLD` (6) was tuned against an RGBA canvas
/// red-channel sample; DESIGN.md §4.2 already flagged it as unvalidated for
/// the YUV Y-plane path. Real-device feedback confirmed the risk concretely:
/// subtle motion (a chest rising and falling during a breathing exercise)
/// often fell below 6, so frames were only reliably sent on the 6s keyframe
/// fallback rather than tracking the exercise live. Lowered to 3 -- still a
/// starting point, not a fully calibrated value (that needs recorded mean
/// deltas for genuinely-still vs. moving scenes on real hardware), but
/// deliberately biased toward "sends too often" over "misses real motion"
/// now that the latter has a confirmed real-world failure mode and the
/// former's cost is just data/battery, bounded by the thermal guardrail
/// (§4.3).
const int yPlaneMotionThreshold = 3;

/// Mean absolute delta between two equal-length sample lists (e.g. a
/// downsampled luminance thumbnail). Returns `double.infinity` if the
/// lengths mismatch or either is empty — treated as "definitely moved" by
/// callers, matching the web's `Number.POSITIVE_INFINITY` fallback for "no
/// previous thumbnail yet".
double meanLuminanceDelta(List<int> current, List<int> previous) {
  if (current.isEmpty || current.length != previous.length) {
    return double.infinity;
  }
  var total = 0;
  for (var i = 0; i < current.length; i++) {
    total += (current[i] - previous[i]).abs();
  }
  return total / current.length;
}

/// Whether the scene has moved enough since [previous] to warrant sending a
/// fresh frame. A null [previous] (no baseline yet, i.e. the very first
/// tick) is always treated as motion, matching `videoStream.ts` sending its
/// first frame unconditionally.
bool hasMotion(List<int> current, List<int>? previous, {int threshold = yPlaneMotionThreshold}) {
  if (previous == null) return true;
  return meanLuminanceDelta(current, previous) >= threshold;
}

/// Whether a frame is due purely because the keyframe interval elapsed,
/// independent of motion — matches `videoStream.ts`'s `dueForKeyframe`.
/// [lastKeyframeAt] of `null` (never sent one yet) is always due.
bool isDueForKeyframe(DateTime? lastKeyframeAt, DateTime now, Duration keyframeInterval) {
  if (lastKeyframeAt == null) return true;
  return now.difference(lastKeyframeAt) >= keyframeInterval;
}
