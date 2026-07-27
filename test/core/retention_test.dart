import 'package:flutter_test/flutter_test.dart';
import 'package:soter_recovery/core/retention.dart';

void main() {
  group('retentionExpiresAt', () {
    test('returns exactly 180 days after the given instant', () {
      final now = DateTime.utc(2026, 1, 1);
      final result = retentionExpiresAt(now);
      expect(retentionDays, 180);
      expect(result.difference(now), const Duration(days: 180));
    });

    test('normalizes to UTC', () {
      final now = DateTime(2026, 1, 1);
      final result = retentionExpiresAt(now);
      expect(result.isUtc, isTrue);
    });

    test('defaults to DateTime.now() when no instant is passed', () {
      final before = DateTime.now().toUtc();
      final result = retentionExpiresAt();
      final after = DateTime.now().toUtc();
      expect(
        result.isAfter(before.add(const Duration(days: 180)).subtract(const Duration(seconds: 1))),
        isTrue,
      );
      expect(
        result.isBefore(after.add(const Duration(days: 180)).add(const Duration(seconds: 1))),
        isTrue,
      );
    });
  });
}
