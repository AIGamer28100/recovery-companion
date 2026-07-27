// Unit tests for the pure pose-landmark motion-counting math used by the
// on-device rep/breath tracking feature. No `camera`/`google_mlkit_*`
// imports needed -- this is exactly the math `pose_tracker.dart` calls,
// isolated for testing, mirroring `motion_diff_test.dart`'s style.

import 'package:flutter_test/flutter_test.dart';
import 'package:soter_recovery/platform/camera/pose_motion_counter.dart';

PoseSample _sample({
  required DateTime at,
  double shoulderMidY = 100,
  double hipMidY = 200,
  double wristMidY = 100,
  double ankleMidY = 300,
}) {
  return PoseSample(
    timestamp: at,
    shoulderMidY: shoulderMidY,
    hipMidY: hipMidY,
    wristMidY: wristMidY,
    ankleMidY: ankleMidY,
  );
}

void main() {
  group('repSignal', () {
    test('is zero when wrists/ankles sit at their neutral (shoulder/hip) position', () {
      final s = _sample(at: DateTime(2026), shoulderMidY: 100, hipMidY: 200, wristMidY: 100, ankleMidY: 200);
      expect(repSignal(s), 0);
    });

    test('rises when wrists are raised above the shoulders (smaller y)', () {
      final neutral = _sample(at: DateTime(2026), shoulderMidY: 100, hipMidY: 200, wristMidY: 100, ankleMidY: 200);
      final raised = _sample(at: DateTime(2026), shoulderMidY: 100, hipMidY: 200, wristMidY: 50, ankleMidY: 200);
      expect(repSignal(raised), greaterThan(repSignal(neutral)));
    });

    test('rises when ankles lift toward the hips (smaller y, e.g. a small jump)', () {
      final neutral = _sample(at: DateTime(2026), shoulderMidY: 100, hipMidY: 200, wristMidY: 100, ankleMidY: 300);
      final lifted = _sample(at: DateTime(2026), shoulderMidY: 100, hipMidY: 200, wristMidY: 100, ankleMidY: 250);
      expect(repSignal(lifted), greaterThan(repSignal(neutral)));
    });
  });

  group('breathSignal', () {
    test('rises when the shoulders rise (smaller y) relative to the hips', () {
      final resting = _sample(at: DateTime(2026), shoulderMidY: 100, hipMidY: 200);
      final inhaled = _sample(at: DateTime(2026), shoulderMidY: 95, hipMidY: 200);
      expect(breathSignal(inhaled), greaterThan(breathSignal(resting)));
    });
  });

  group('OscillationCounter', () {
    test('counts one full swing above and back below the amplitude threshold', () {
      final counter = OscillationCounter(
        minAmplitude: 0.3,
        minPeriod: const Duration(milliseconds: 50),
        maxPeriod: const Duration(seconds: 5),
        smoothingAlpha: 1, // no smoothing lag, for deterministic test values
      );
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      expect(counter.addSample(0.0, t0), isFalse);
      expect(counter.addSample(0.5, t0.add(const Duration(milliseconds: 100))), isFalse); // crosses into "high"
      expect(counter.addSample(1.0, t0.add(const Duration(milliseconds: 200))), isFalse); // new peak
      expect(
        counter.addSample(0.6, t0.add(const Duration(milliseconds: 400))),
        isTrue,
      ); // falls back >= 0.3 from the peak -> cycle complete
      expect(counter.count, 1);
    });

    test('does not count a swing smaller than minAmplitude', () {
      final counter = OscillationCounter(
        minAmplitude: 0.5,
        minPeriod: const Duration(milliseconds: 50),
        maxPeriod: const Duration(seconds: 5),
        smoothingAlpha: 1,
      );
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      counter.addSample(0.0, t0);
      counter.addSample(0.2, t0.add(const Duration(milliseconds: 100)));
      counter.addSample(0.0, t0.add(const Duration(milliseconds: 200)));
      expect(counter.count, 0);
    });

    test('rejects a cycle completed faster than minPeriod', () {
      final counter = OscillationCounter(
        minAmplitude: 0.3,
        minPeriod: const Duration(milliseconds: 500),
        maxPeriod: const Duration(seconds: 5),
        smoothingAlpha: 1,
      );
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      counter.addSample(0.0, t0);
      counter.addSample(1.0, t0.add(const Duration(milliseconds: 50))); // crosses high, cycle "starts" here
      final completed = counter.addSample(0.0, t0.add(const Duration(milliseconds: 100))); // too fast
      expect(completed, isFalse);
      expect(counter.count, 0);
    });

    test('rejects a cycle slower than maxPeriod', () {
      final counter = OscillationCounter(
        minAmplitude: 0.3,
        minPeriod: const Duration(milliseconds: 50),
        maxPeriod: const Duration(seconds: 2),
        smoothingAlpha: 1,
      );
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      counter.addSample(0.0, t0);
      counter.addSample(1.0, t0.add(const Duration(milliseconds: 100)));
      final completed = counter.addSample(0.0, t0.add(const Duration(seconds: 10)));
      expect(completed, isFalse);
      expect(counter.count, 0);
    });

    test('counts multiple consecutive full swings', () {
      final counter = OscillationCounter(
        minAmplitude: 0.3,
        minPeriod: const Duration(milliseconds: 10),
        maxPeriod: const Duration(seconds: 5),
        smoothingAlpha: 1,
      );
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      var t = t0;
      Duration step(int ms) => Duration(milliseconds: ms);
      counter.addSample(0.0, t);
      for (var i = 0; i < 3; i++) {
        t = t.add(step(50));
        counter.addSample(1.0, t); // up
        t = t.add(step(50));
        counter.addSample(0.0, t); // back down -> completes a cycle
      }
      expect(counter.count, 3);
    });
  });

  group('PoseMotionCounter', () {
    test('reports a rep event once a jumping-jack-like arm swing completes', () {
      final counter = PoseMotionCounter(
        repCounter: OscillationCounter(
          minAmplitude: 0.3,
          minPeriod: const Duration(milliseconds: 10),
          maxPeriod: const Duration(seconds: 5),
          smoothingAlpha: 1,
        ),
        breathCounter: OscillationCounter(
          minAmplitude: 10, // effectively disabled for this test
          minPeriod: const Duration(milliseconds: 10),
          maxPeriod: const Duration(seconds: 5),
        ),
      );
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      final neutral = _sample(at: t0, shoulderMidY: 100, hipMidY: 200, wristMidY: 100, ankleMidY: 300);
      final armsUp = _sample(
        at: t0.add(const Duration(milliseconds: 100)),
        shoulderMidY: 100,
        hipMidY: 200,
        wristMidY: 20,
        ankleMidY: 300,
      );
      final backDown = _sample(
        at: t0.add(const Duration(milliseconds: 300)),
        shoulderMidY: 100,
        hipMidY: 200,
        wristMidY: 100,
        ankleMidY: 300,
      );

      expect(counter.addSample(neutral), isEmpty);
      expect(counter.addSample(armsUp), isEmpty);
      final events = counter.addSample(backDown);

      expect(events, hasLength(1));
      expect(events.single.kind, PoseMotionKind.rep);
      expect(events.single.totalCount, 1);
      expect(counter.totalReps, 1);
      expect(counter.totalBreaths, 0);
    });
  });
}
