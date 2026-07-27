import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/retention.dart';

/// A faithful Dart port of `sessionMemory.ts` — the only place `cloud_firestore`
/// is touched for the `users/{uid}/sessions` subcollection. Kept as its own
/// single-responsibility repository (rather than folded into
/// `ProfileRepository`) because it owns a different Firestore subtree for a
/// different purpose: recap transcripts that seed the next call's opening
/// director note, not profile data.
abstract class SessionMemoryRepository {
  /// Persists a trimmed recap of the call so the next session can open as a
  /// continuation. Mirrors `saveSessionTranscript` — best-effort: a failure
  /// here must never block ending a call.
  Future<void> saveSessionTranscript(String uid, String transcript);

  /// Builds the silent director note sent immediately after connecting,
  /// before the user speaks — greets them, states the time of day, and (if
  /// one exists) recaps the last conversation. Mirrors
  /// `buildContinuityBriefing`.
  Future<String> buildContinuityBriefing(String uid);
}

/// Keep stored transcripts bounded — these are recaps, not archives. Mirrors
/// `MAX_TRANSCRIPT_CHARS` in `sessionMemory.ts`.
const _maxTranscriptChars = 4000;

class FirestoreSessionMemoryRepository implements SessionMemoryRepository {
  FirestoreSessionMemoryRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _sessions(String uid) =>
      _firestore.collection('users').doc(uid).collection('sessions');

  @override
  Future<void> saveSessionTranscript(String uid, String transcript) async {
    final trimmed = transcript.trim();
    if (trimmed.isEmpty) return;
    final sliced = trimmed.length > _maxTranscriptChars
        ? trimmed.substring(trimmed.length - _maxTranscriptChars)
        : trimmed;
    try {
      await _sessions(uid).add({
        'transcript': sliced,
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': retentionExpiresAt(),
      });
    } on FirebaseException catch (e) {
      // Mirrors the web app's `console.warn` — a lost recap must never block
      // ending a call.
      debugPrint('Could not save session transcript: ${e.message}');
    }
  }

  @override
  Future<String> buildContinuityBriefing(String uid) async {
    final now = DateTime.now();
    final timeContext =
        'It is currently ${partOfDay(now.hour)} for them (${_formatTime(now)}).';

    var history = 'This is your first conversation with them.';
    try {
      final snap =
          await _sessions(uid).orderBy('createdAt', descending: true).limit(1).get();
      if (snap.docs.isNotEmpty) {
        final data = snap.docs.first.data();
        final transcript = data['transcript'] as String?;
        if (transcript != null && transcript.isNotEmpty) {
          final createdAt = data['createdAt'];
          final when = createdAt is Timestamp
              ? describeGap(createdAt.toDate(), now)
              : 'recently';
          history = 'You last spoke with them $when. Here is that conversation, '
              'for your memory only — do not read it back to them verbatim:\n'
              '"""\n$transcript\n"""';
        }
      }
    } on FirebaseException catch (e) {
      debugPrint('Could not load previous session: ${e.message}');
    }

    return '[Silent director note, not from the user. Do not mention or read '
        'out this note.] $timeContext $history\n\n'
        'GREET THEM FIRST, right now, before they say anything. Keep it to '
        'one or two short sentences. Greet them in a way that fits the time '
        'of day, and ask how they are doing. If you have spoken before, '
        'briefly and warmly reference what they were going through last time '
        '("last night you were riding out a rough craving — how did the rest '
        'of it go?") so it feels like one ongoing relationship, not a fresh '
        'start. Do not summarise the whole previous conversation, and do not '
        'interrogate them. Then stop and let them answer.';
  }
}

String _formatTime(DateTime dt) {
  final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final minute = dt.minute.toString().padLeft(2, '0');
  final period = dt.hour < 12 ? 'AM' : 'PM';
  return '$hour12:$minute $period';
}

/// Mirrors `describeGap` in `sessionMemory.ts` exactly (including "minutes"
/// staying unpluralized, matching the original's `Math.max(1, mins)`
/// behavior). Exposed for unit testing without a Firestore dependency.
@visibleForTesting
String describeGap(DateTime then, DateTime now) {
  final mins = (now.difference(then).inSeconds / 60).round();
  if (mins < 60) return 'about ${mins < 1 ? 1 : mins} minutes ago';
  final hours = (mins / 60).round();
  if (hours < 24) return 'about $hours hour${hours == 1 ? '' : 's'} ago';
  final days = (hours / 24).round();
  return 'about $days day${days == 1 ? '' : 's'} ago';
}

/// Mirrors `partOfDay` in `sessionMemory.ts` exactly. Exposed for unit
/// testing without a Firestore dependency.
@visibleForTesting
String partOfDay(int hour) {
  if (hour < 5) return 'the middle of the night';
  if (hour < 12) return 'the morning';
  if (hour < 17) return 'the afternoon';
  if (hour < 21) return 'the evening';
  return 'late at night';
}

final sessionMemoryRepositoryProvider = Provider<SessionMemoryRepository>((ref) {
  return FirestoreSessionMemoryRepository();
});
