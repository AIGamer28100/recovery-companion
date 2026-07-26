// Verifies the pure helpers ported from `sessionMemory.ts`'s `describeGap`
// and `partOfDay` match the original's behavior exactly — these are the only
// parts of the continuity-briefing logic testable without a live Firestore
// instance (`buildContinuityBriefing`/`saveSessionTranscript` themselves are
// thin Firestore I/O wrappers around this pure logic).

import 'package:flutter_test/flutter_test.dart';
import 'package:soter_recovery/features/live_session/data/session_memory_repository.dart';

void main() {
  group('partOfDay', () {
    test('buckets hours into the same five ranges as sessionMemory.ts', () {
      expect(partOfDay(0), 'the middle of the night');
      expect(partOfDay(4), 'the middle of the night');
      expect(partOfDay(5), 'the morning');
      expect(partOfDay(11), 'the morning');
      expect(partOfDay(12), 'the afternoon');
      expect(partOfDay(16), 'the afternoon');
      expect(partOfDay(17), 'the evening');
      expect(partOfDay(20), 'the evening');
      expect(partOfDay(21), 'late at night');
      expect(partOfDay(23), 'late at night');
    });
  });

  group('describeGap', () {
    test('reports minutes (unpluralized) for gaps under an hour', () {
      final now = DateTime(2026, 1, 1, 12, 30);
      expect(describeGap(now.subtract(const Duration(minutes: 30)), now), 'about 30 minutes ago');
    });

    test('floors sub-minute gaps to "about 1 minutes ago"', () {
      final now = DateTime(2026, 1, 1, 12, 0, 30);
      expect(describeGap(now.subtract(const Duration(seconds: 10)), now), 'about 1 minutes ago');
    });

    test('reports singular/plural hours for gaps under a day', () {
      final now = DateTime(2026, 1, 1, 13, 0);
      expect(describeGap(now.subtract(const Duration(hours: 1)), now), 'about 1 hour ago');
      expect(describeGap(now.subtract(const Duration(hours: 5)), now), 'about 5 hours ago');
    });

    test('reports singular/plural days for gaps of a day or more', () {
      final now = DateTime(2026, 1, 10, 12, 0);
      expect(describeGap(now.subtract(const Duration(days: 1)), now), 'about 1 day ago');
      expect(describeGap(now.subtract(const Duration(days: 3)), now), 'about 3 days ago');
    });
  });
}
