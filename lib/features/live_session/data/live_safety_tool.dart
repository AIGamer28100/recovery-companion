import 'package:firebase_ai/firebase_ai.dart';

/// Dart port of `RELAPSE_RISK_TOOL` in `src/lib/safetyTools.ts`. This file
/// owns only the tool *declaration* — the real Firestore incident-writing
/// side effect (`recordRelapseIncident`/`logCaregiverAlert` in the web app)
/// lives in `../data/incident_repository.dart` and is wired in by
/// `LiveSessionController._defaultFlagRelapseRisk`.
Tool buildRelapseRiskTool() {
  return Tool.functionDeclarations([
    FunctionDeclaration(
      'flagRelapseRisk',
      'Call this ONLY when the camera clearly shows the person moving '
          'toward using a substance — reaching for, holding, opening, '
          'pouring, or preparing alcohol or drugs. Call it with '
          'stage="intervening" the first time, which captures a still frame '
          'for their record and lets you talk them down. If they continue '
          'anyway after you have tried to stop them, call it again with '
          'stage="escalated", which alerts their linked caregiver '
          'immediately. Never call this on a guess, on something you merely '
          'heard, or for ordinary drinks like water, tea, or coffee.',
      parameters: {
        'stage': Schema.enumString(
          enumValues: ['intervening', 'escalated'],
          description: '"intervening" = first sighting, you are about to '
              'try to stop them. "escalated" = you already tried and they '
              'did not stop; notify the caregiver.',
        ),
        'observation': Schema.string(
          description: 'One plain sentence describing only what you can '
              'actually see, e.g. "reached for a bottle on the desk and '
              'started pouring a glass". No speculation.',
        ),
      },
    ),
  ]);
}
