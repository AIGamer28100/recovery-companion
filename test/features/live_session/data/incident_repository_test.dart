// Covers the pure helpers in `incident_repository.dart` — the only parts
// testable without a live Firestore instance (`FirestoreIncidentRepository`
// itself is a thin I/O wrapper, same convention as
// `session_memory_repository_test.dart`).

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:soter_recovery/features/live_session/data/incident_repository.dart';

void main() {
  group('truncateObservation', () {
    test('leaves short observations untouched', () {
      expect(truncateObservation('reached for a bottle'), 'reached for a bottle');
    });

    test('slices at exactly firestore.rules\' 500-char cap', () {
      final long = 'a' * 600;
      final result = truncateObservation(long);
      expect(result.length, incidentObservationMaxChars);
      expect(result, 'a' * 500);
    });

    test('leaves a string exactly at the cap untouched', () {
      final exact = 'a' * incidentObservationMaxChars;
      expect(truncateObservation(exact), exact);
    });
  });

  group('buildRelapseAlertScript', () {
    test('wraps a real observation with the exact "Urgent:" template', () {
      expect(
        buildRelapseAlertScript('reached for a bottle on the desk and started pouring a glass'),
        'Urgent: reached for a bottle on the desk and started pouring a glass',
      );
    });

    test('falls back to the exact default text for an empty observation', () {
      expect(buildRelapseAlertScript(''), 'Urgent: possible substance use observed on camera');
    });

    test('falls back for a whitespace-only observation too', () {
      expect(buildRelapseAlertScript('   '), 'Urgent: possible substance use observed on camera');
    });
  });

  group('encodeEvidenceFrame', () {
    test('produces a base64 JPEG data URL matching the web\'s canvas.toDataURL shape', () {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final url = encodeEvidenceFrame(bytes);
      expect(url, startsWith('data:image/jpeg;base64,'));
      final decoded = base64Decode(url.split(',').last);
      expect(decoded, bytes);
    });
  });
}
