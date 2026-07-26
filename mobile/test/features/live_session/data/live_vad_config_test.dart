// Verifies the ported VAD tuning values match `REALTIME_INPUT_CONFIG` in
// `src/lib/liveVad.ts` exactly (silenceDurationMs: 1400, prefixPaddingMs: 400,
// END_SENSITIVITY_LOW, START_SENSITIVITY_LOW). See live_vad_config.dart's doc
// comment for why this isn't wired into the live session yet in this
// milestone (firebase_ai 3.14.1 has no realtimeInputConfig passthrough).

import 'package:flutter_test/flutter_test.dart';
import 'package:recovery_companion/features/live_session/data/live_vad_config.dart';

void main() {
  test('matches the exact values ported from liveVad.ts', () {
    final json = liveRealtimeInputConfig.toJson();

    expect(json, {
      'automaticActivityDetection': {
        'silenceDurationMs': 1400,
        'prefixPaddingMs': 400,
        'endOfSpeechSensitivity': 'END_SENSITIVITY_LOW',
        'startOfSpeechSensitivity': 'START_SENSITIVITY_LOW',
      },
    });
  });
}
