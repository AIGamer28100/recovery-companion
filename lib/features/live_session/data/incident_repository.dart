import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/relapse_stage.dart';

/// The only place `cloud_firestore` is touched for the
/// `users/{uid}/incidents` and `users/{uid}/alerts` subcollections. A
/// faithful Dart port of `src/lib/incidents.ts` (`recordRelapseIncident`)
/// and `src/lib/events.ts` (`logCaregiverAlert`) — field names, types, and
/// size caps must match `firestore.rules`' `isValidIncident()`/
/// `isValidAlert()` byte-for-byte, or the caregiver dashboard silently
/// breaks or the write gets rejected outright.
///
/// See the field-by-field comparison against `firestore.rules` in this
/// milestone's report; summarized here:
///   - `isValidIncident()`: only `stage`, `observation`, `frame`, `createdAt`
///     allowed; `stage` in `['intervening','escalated']`; `observation`
///     string <= 500 chars; `frame` optional string <= 400000 chars;
///     `createdAt` a recent server timestamp.
///   - `isValidAlert()`: only `script`, `triggeredBy`, `createdAt` allowed;
///     `script` string <= 2000 chars; `triggeredBy` in the fixed allowed-values
///     list (includes `'relapse_risk'`); `createdAt` a recent server timestamp.
abstract class IncidentRepository {
  /// Mirrors `recordRelapseIncident` in `incidents.ts`. [evidenceJpeg], when
  /// present, is embedded as a base64 JPEG data URL under the `frame` field
  /// — this is the one deliberate, disclosed exception to camera frames
  /// being ephemeral (DESIGN.md §4.4).
  Future<void> recordRelapseIncident({
    required String uid,
    required RelapseStage stage,
    required String observation,
    Uint8List? evidenceJpeg,
  });

  /// Mirrors `logCaregiverAlert` in `events.ts`. [triggeredBy] must be one of
  /// `firestore.rules`' `isValidAlert()` allowed values — this app only ever
  /// passes `'relapse_risk'`.
  Future<void> logCaregiverAlert({
    required String uid,
    required String script,
    required String triggeredBy,
  });
}

/// `isValidIncident()`'s cap on `observation` — matches `incidents.ts`
/// slicing to 500 chars before writing.
const incidentObservationMaxChars = 500;

/// `isValidAlert()`'s cap on `script`.
const caregiverAlertScriptMaxChars = 2000;

/// Builds the `frame` field value from a JPEG buffer — a base64 data URL,
/// matching what `captureFrame`/`recordRelapseIncident` produce on the web
/// (`canvas.toDataURL('image/jpeg', ...)` yields the same `data:image/jpeg;
/// base64,...` shape). Pure, so it's testable without Firestore.
String encodeEvidenceFrame(Uint8List jpeg) => 'data:image/jpeg;base64,${base64Encode(jpeg)}';

/// Slices an observation to `firestore.rules`' 500-char cap, mirroring
/// `observation.slice(0, 500)` in `incidents.ts`. Pure, testable.
String truncateObservation(String observation) {
  if (observation.length <= incidentObservationMaxChars) return observation;
  return observation.substring(0, incidentObservationMaxChars);
}

/// The exact caregiver-alert script template used at `stage == escalated`,
/// ported verbatim from the inline template literal in `useLiveSession.ts`'s
/// `flagRelapseRisk` handler (NOT `generateCaregiverScript`/
/// `generatePersonalizedCaregiverScript` in `gemini.ts` — the web's actual
/// wiring for this specific alert is a plain template, not a Gemini call;
/// see this milestone's report for where that was verified). Pure, testable.
String buildRelapseAlertScript(String observation) {
  final text = observation.trim().isEmpty ? 'possible substance use observed on camera' : observation;
  return 'Urgent: $text';
}

class FirestoreIncidentRepository implements IncidentRepository {
  FirestoreIncidentRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _incidents(String uid) =>
      _firestore.collection('users').doc(uid).collection('incidents');

  CollectionReference<Map<String, dynamic>> _alerts(String uid) =>
      _firestore.collection('users').doc(uid).collection('alerts');

  @override
  Future<void> recordRelapseIncident({
    required String uid,
    required RelapseStage stage,
    required String observation,
    Uint8List? evidenceJpeg,
  }) async {
    await _incidents(uid).add({
      'stage': stage.name,
      'observation': truncateObservation(observation),
      if (evidenceJpeg != null) 'frame': encodeEvidenceFrame(evidenceJpeg),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> logCaregiverAlert({
    required String uid,
    required String script,
    required String triggeredBy,
  }) async {
    final truncated =
        script.length > caregiverAlertScriptMaxChars ? script.substring(0, caregiverAlertScriptMaxChars) : script;
    await _alerts(uid).add({
      'script': truncated,
      'triggeredBy': triggeredBy,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
