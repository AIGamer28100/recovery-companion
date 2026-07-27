// Covers the pure tool-call response shaping extracted from
// `LiveSessionController._handleToolCall`. This is the regression test for
// the fixed bug: the response must only ever claim `caregiverNotified: true`
// when the caller explicitly says so (i.e. a real write happened) — it must
// never be inferred from `stage` alone inside the shaping function itself.

import 'package:flutter_test/flutter_test.dart';
import 'package:soter_recovery/features/live_session/domain/relapse_stage.dart';

void main() {
  group('RelapseRiskArgs.fromToolArgs', () {
    test('parses a well-formed escalated call', () {
      final args = RelapseRiskArgs.fromToolArgs({'stage': 'escalated', 'observation': 'poured a drink'});
      expect(args.stage, RelapseStage.escalated);
      expect(args.observation, 'poured a drink');
    });

    test('defaults an unrecognized/missing stage to intervening', () {
      expect(RelapseRiskArgs.fromToolArgs({}).stage, RelapseStage.intervening);
      expect(RelapseRiskArgs.fromToolArgs({'stage': 'nonsense'}).stage, RelapseStage.intervening);
    });

    test('defaults a missing observation to an empty string', () {
      expect(RelapseRiskArgs.fromToolArgs({'stage': 'intervening'}).observation, '');
    });
  });

  group('buildFlagRelapseRiskResponse', () {
    test('reports caregiverNotified exactly as passed in, for escalated', () {
      expect(
        buildFlagRelapseRiskResponse(stage: RelapseStage.escalated, caregiverNotified: true),
        {'ok': true, 'stage': 'escalated', 'caregiverNotified': true},
      );
    });

    test('never fabricates caregiverNotified: true just because stage is escalated', () {
      // This is the exact shape of the bug being fixed: a caller that did
      // NOT actually notify the caregiver (e.g. the alert write failed but
      // the incident write succeeded, or a test double reports false) must
      // have that reflected honestly, even at stage == escalated.
      expect(
        buildFlagRelapseRiskResponse(stage: RelapseStage.escalated, caregiverNotified: false),
        {'ok': true, 'stage': 'escalated', 'caregiverNotified': false},
      );
    });

    test('intervening never claims the caregiver was notified', () {
      expect(
        buildFlagRelapseRiskResponse(stage: RelapseStage.intervening, caregiverNotified: false),
        {'ok': true, 'stage': 'intervening', 'caregiverNotified': false},
      );
    });
  });

  test('flagRelapseRiskFailureResponse never claims ok or a side effect', () {
    expect(flagRelapseRiskFailureResponse, {'ok': false});
  });
}
