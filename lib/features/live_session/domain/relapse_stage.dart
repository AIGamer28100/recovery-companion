/// Mirrors `RelapseStage` in `src/lib/safetyTools.ts`. `intervening` = the
/// model just saw the first sign and is trying to stop it; `escalated` = the
/// person continued despite the model's intervention, which is the caregiver
/// notification trigger.
///
/// The real Firestore incident-writing and caregiver-alert side effects for
/// this tool call live in `../data/incident_repository.dart`, matching
/// `src/lib/incidents.ts`/`src/lib/events.ts`.
enum RelapseStage {
  intervening,
  escalated;

  static RelapseStage? fromWireValue(Object? value) {
    if (value == 'escalated') return RelapseStage.escalated;
    if (value == 'intervening') return RelapseStage.intervening;
    return null;
  }
}

/// The decoded arguments of a `flagRelapseRisk` tool call, per the schema in
/// `RELAPSE_RISK_TOOL` (`src/lib/safetyTools.ts`).
class RelapseRiskArgs {
  const RelapseRiskArgs({required this.stage, required this.observation});

  final RelapseStage stage;

  /// One factual sentence describing only what the model could see.
  final String observation;

  static RelapseRiskArgs fromToolArgs(Map<String, Object?> args) {
    return RelapseRiskArgs(
      stage: RelapseStage.fromWireValue(args['stage']) ?? RelapseStage.intervening,
      observation: args['observation'] as String? ?? '',
    );
  }
}

/// The outcome of actually handling a `flagRelapseRisk` call — whatever ran
/// (the real Firestore-writing default, or an injected test double) reports
/// back what genuinely happened, so the tool response sent to the model
/// reflects reality rather than an assumption. This is the structural fix
/// for the bug where `LiveSessionController` used to report
/// `caregiverNotified: true` purely because `stage == escalated`, even when
/// no callback — and therefore no real write — ever ran.
class FlagRelapseRiskResult {
  const FlagRelapseRiskResult({required this.caregiverNotified});

  /// True only if a caregiver alert document was actually written.
  final bool caregiverNotified;
}

/// Pure shaping of the success response sent back to the model for a
/// `flagRelapseRisk` call, extracted from
/// `LiveSessionController._handleToolCall` so it's testable without a live
/// session/Firestore stack. Mirrors the shape `useLiveSession.ts` returns:
/// `{ ok: true, stage, caregiverNotified }`.
Map<String, Object?> buildFlagRelapseRiskResponse({
  required RelapseStage stage,
  required bool caregiverNotified,
}) {
  return {
    'ok': true,
    'stage': stage.name,
    'caregiverNotified': caregiverNotified,
  };
}

/// The response sent when handling the call failed (or, for any other tool
/// name, since `flagRelapseRisk` is the only tool this app declares) — never
/// claims a side effect happened.
const Map<String, Object?> flagRelapseRiskFailureResponse = {'ok': false};
