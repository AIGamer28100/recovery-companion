/// Mirrors `RelapseStage` in `src/lib/safetyTools.ts`. `intervening` = the
/// model just saw the first sign and is trying to stop it; `escalated` = the
/// person continued despite the model's intervention, which is the caregiver
/// notification trigger.
///
/// NOTE: this milestone (M2, the audio pipeline) only needs the *shape* of
/// this tool call to exist so the session can receive it and reply — the
/// actual Firestore incident-writing and caregiver-alert side effects are
/// explicitly out of scope here (a separate task owns `flagRelapseRisk`'s
/// real implementation, matching `src/lib/incidents.ts`/`src/lib/events.ts`).
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
