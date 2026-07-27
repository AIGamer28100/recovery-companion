// Unit tests for the pure luminance-diff motion detector ported from
// `videoStream.ts`'s `motionSinceLastFrame`, plus the keyframe-interval
// gate. No `camera`/`image` imports needed — this is exactly the math
// `live_camera_stream.dart` calls, isolated for testing.

import 'package:flutter_test/flutter_test.dart';
import 'package:soter_recovery/platform/camera/motion_diff.dart';

void main() {
  group('meanLuminanceDelta', () {
    test('is zero for identical samples', () {
      expect(meanLuminanceDelta([10, 20, 30], [10, 20, 30]), 0);
    });

    test('averages the absolute per-sample delta', () {
      // deltas: 10, 0, 20 -> mean 10
      expect(meanLuminanceDelta([20, 20, 50], [10, 20, 30]), 10);
    });

    test('returns infinity for mismatched lengths', () {
      expect(meanLuminanceDelta([1, 2, 3], [1, 2]), double.infinity);
    });

    test('returns infinity for empty input', () {
      expect(meanLuminanceDelta([], []), double.infinity);
    });
  });

  group('hasMotion', () {
    test('always true with no previous baseline (first tick)', () {
      expect(hasMotion([1, 2, 3], null), isTrue);
    });

    test('false when the mean delta is below the threshold', () {
      // mean delta = 2, threshold defaults to yPlaneMotionThreshold (3).
      expect(hasMotion([12, 12], [10, 10]), isFalse);
    });

    test('true when the mean delta meets the threshold exactly', () {
      // mean delta = 3 -> >= threshold, so counts as motion.
      expect(hasMotion([13, 13], [10, 10]), isTrue);
    });

    test('true when the mean delta clearly exceeds the threshold', () {
      expect(hasMotion([100, 100], [10, 10]), isTrue);
    });

    test('respects a custom threshold', () {
      expect(hasMotion([12, 12], [10, 10], threshold: 1), isTrue);
      expect(hasMotion([12, 12], [10, 10], threshold: 10), isFalse);
    });
  });

  group('isDueForKeyframe', () {
    test('always due with no prior keyframe', () {
      expect(isDueForKeyframe(null, DateTime(2026, 1, 1), const Duration(seconds: 6)), isTrue);
    });

    test('not due before the interval elapses', () {
      final last = DateTime(2026, 1, 1, 12, 0, 0);
      final now = last.add(const Duration(seconds: 5));
      expect(isDueForKeyframe(last, now, const Duration(seconds: 6)), isFalse);
    });

    test('due once the interval has elapsed', () {
      final last = DateTime(2026, 1, 1, 12, 0, 0);
      final now = last.add(const Duration(seconds: 6));
      expect(isDueForKeyframe(last, now, const Duration(seconds: 6)), isTrue);
    });
  });
}
