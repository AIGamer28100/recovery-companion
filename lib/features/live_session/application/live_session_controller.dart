import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../platform/audio/audio_pipeline.dart';
import '../../auth/data/auth_repository.dart';
import '../data/gemini_live_repository.dart';
import '../data/session_memory_repository.dart';
import '../domain/live_call_event.dart';
import '../domain/live_session_status.dart';
import '../domain/relapse_stage.dart';

/// Called when the model invokes `flagRelapseRisk`. This milestone (M2, the
/// audio pipeline) only guarantees the tool-call plumbing exists — the
/// actual Firestore incident write + caregiver alert
/// (`recordRelapseIncident`/`logCaregiverAlert` in `src/lib/incidents.ts` and
/// `src/lib/events.ts`) is TODO for a later task, which wires a real
/// implementation of this callback in from the presentation layer.
typedef FlagRelapseRiskCallback = Future<void> Function(RelapseRiskArgs args);

const _unset = Object();

class LiveSessionState {
  const LiveSessionState({
    this.status = LiveSessionStatus.idle,
    this.lines = const [],
    this.incidentStage,
    this.echoCancellationAvailability = EchoCancellationAvailability.unknown,
    this.errorMessage,
    this.isModelSpeaking = false,
  });

  final LiveSessionStatus status;
  final List<TranscriptLine> lines;
  final RelapseStage? incidentStage;
  final EchoCancellationAvailability echoCancellationAvailability;
  final String? errorMessage;

  /// Drives the Live Call screen's orb between its "listening" and
  /// "speaking" shapes (DESIGN.md §1.3/§1.4, amendments §A.5.1/§A.5.3): true
  /// while model audio is actively streaming, false the instant a barge-in
  /// (`LiveInterrupted`) or turn-complete signal arrives — set in the same
  /// state update that triggers `flushPlayback()`, so the visible shift is
  /// same-frame with the audio cut, not just audibly present.
  final bool isModelSpeaking;

  LiveSessionState copyWith({
    LiveSessionStatus? status,
    List<TranscriptLine>? lines,
    Object? incidentStage = _unset,
    EchoCancellationAvailability? echoCancellationAvailability,
    Object? errorMessage = _unset,
    bool? isModelSpeaking,
  }) {
    return LiveSessionState(
      status: status ?? this.status,
      lines: lines ?? this.lines,
      incidentStage: identical(incidentStage, _unset)
          ? this.incidentStage
          : incidentStage as RelapseStage?,
      echoCancellationAvailability:
          echoCancellationAvailability ?? this.echoCancellationAvailability,
      errorMessage: identical(errorMessage, _unset) ? this.errorMessage : errorMessage as String?,
      isModelSpeaking: isModelSpeaking ?? this.isModelSpeaking,
    );
  }
}

/// Orchestrates the whole live-session lifecycle: the audio pipeline (mic,
/// playback, echo cancellation, focus/foreground-service) and the Gemini
/// Live session, wiring outbound mic chunks to the session and inbound
/// audio/barge-in/tool-call events back into the pipeline and UI state.
/// Mirrors `useLiveSession.ts`'s role, per DESIGN.md §2.2.
///
/// Deliberately does NOT own the crisis-screen UI, camera streaming, or the
/// real `flagRelapseRisk` Firestore write — see the class docs above and
/// DESIGN.md's M2 scope for why.
class LiveSessionController extends Notifier<LiveSessionState> {
  LiveSessionController({
    LiveSessionRepository? repository,
    AudioPipeline? audioPipeline,
    SessionMemoryRepository? sessionMemory,
    FlagRelapseRiskCallback? onFlagRelapseRisk,
  })  : _repository = repository,
        _audioPipeline = audioPipeline,
        _sessionMemory = sessionMemory,
        _onFlagRelapseRisk = onFlagRelapseRisk;

  LiveSessionRepository? _repository;
  AudioPipeline? _audioPipeline;
  SessionMemoryRepository? _sessionMemory;
  final FlagRelapseRiskCallback? _onFlagRelapseRisk;

  LiveSessionHandle? _handle;
  StreamSubscription<LiveCallEvent>? _eventsSub;
  StreamSubscription<Uint8List>? _outboundSub;
  StreamSubscription<AudioPipelineEvent>? _pipelineEventsSub;

  /// Bumped on every `endCall`/dispose so a session opened during teardown
  /// can't resurrect itself — mirrors `callGenerationRef` in
  /// `useLiveSession.ts`.
  int _generation = 0;

  LiveSessionRepository get _repo => _repository ??= FirebaseLiveSessionRepository();
  AudioPipeline get _pipeline => _audioPipeline ??= AudioPipeline();
  SessionMemoryRepository get _memory =>
      _sessionMemory ??= FirestoreSessionMemoryRepository();

  @override
  LiveSessionState build() {
    ref.onDispose(() {
      unawaited(endCall());
    });
    return const LiveSessionState();
  }

  Future<void> startCall() async {
    state = const LiveSessionState(status: LiveSessionStatus.connecting);
    final generation = ++_generation;
    bool isStale() => generation != _generation;

    try {
      final outbound = await _pipeline.start();
      if (isStale()) {
        await _pipeline.stop();
        return;
      }
      state = state.copyWith(
        echoCancellationAvailability: _pipeline.echoCancellationAvailable
            ? EchoCancellationAvailability.available
            : EchoCancellationAvailability.unavailable,
      );

      final handle = await _repo.connect();
      if (isStale()) {
        await handle.close();
        await _pipeline.stop();
        return;
      }
      _handle = handle;

      _outboundSub = outbound.listen((chunk) {
        unawaited(handle.sendAudioChunk(chunk));
      });
      _pipelineEventsSub = _pipeline.events.listen(_onPipelineEvent);
      _eventsSub = handle.events.listen(_onLiveCallEvent);

      // Opens every call as a continuation — greets them, states the time of
      // day, and (if one exists) recaps the last conversation — sent as a
      // silent director note before the user has said anything. Mirrors the
      // exact `buildContinuityBriefing` → `sendTextRealtime` sequence in
      // `useLiveSession.ts`'s `startCall`. Best-effort: a missing briefing
      // must never block the call from going live.
      final uid = ref.read(authRepositoryProvider).currentUser?.uid;
      if (uid != null) {
        try {
          final briefing = await _memory.buildContinuityBriefing(uid);
          if (!isStale()) unawaited(handle.sendTextRealtime(briefing));
        } catch (_) {
          // Proceed without a briefing rather than fail the call.
        }
      }

      state = state.copyWith(status: LiveSessionStatus.live);
    } catch (_) {
      await _teardown();
      state = state.copyWith(
        status: LiveSessionStatus.error,
        errorMessage: "Couldn't open the line. Check your connection and try again.",
      );
    }
  }

  Future<void> endCall() async {
    _generation++;
    await _saveTranscript();
    await _teardown();
    state = const LiveSessionState();
  }

  void dismissIncident() {
    state = state.copyWith(incidentStage: null);
  }

  /// Persists the accumulated transcript so the next call can open as a
  /// continuation. Mirrors `useLiveSession.ts`'s `endCall`: built from
  /// `state.lines` with the speaker labels swapped ("Them" for the user,
  /// "You" for the companion) because this recap is fed back to the model
  /// itself in a future session, not shown to the person.
  Future<void> _saveTranscript() async {
    final uid = ref.read(authRepositoryProvider).currentUser?.uid;
    if (uid == null) return;
    final transcript =
        state.lines.map((l) => '${l.fromUser ? 'Them' : 'You'}: ${l.text}').join('\n');
    try {
      await _memory.saveSessionTranscript(uid, transcript);
    } catch (_) {
      // Best-effort, mirrors the web app's catch-and-warn — a failed save
      // must never block ending the call.
    }
  }

  Future<void> _teardown() async {
    await _eventsSub?.cancel();
    _eventsSub = null;
    await _outboundSub?.cancel();
    _outboundSub = null;
    await _pipelineEventsSub?.cancel();
    _pipelineEventsSub = null;
    final handle = _handle;
    _handle = null;
    try {
      await handle?.close();
    } catch (_) {
      // already torn down
    }
    try {
      await _pipeline.stop();
    } catch (_) {
      // already torn down
    }
  }

  void _onLiveCallEvent(LiveCallEvent event) {
    switch (event) {
      case LiveTranscriptFragment():
        _appendTranscript(event);
      case LiveAudioChunk(:final pcm16):
        _pipeline.notifyModelSpeaking(true);
        if (!state.isModelSpeaking) state = state.copyWith(isModelSpeaking: true);
        unawaited(_pipeline.playInboundChunk(Uint8List.fromList(pcm16)));
      case LiveInterrupted():
        // Same state update that triggers the flush — see `isModelSpeaking`'s
        // doc comment for why order matters here (§A.5.3's same-frame rule).
        state = state.copyWith(isModelSpeaking: false);
        unawaited(_pipeline.flushPlayback());
        _pipeline.notifyModelSpeaking(false);
      case LiveTurnComplete():
        state = state.copyWith(isModelSpeaking: false);
        _pipeline.notifyModelSpeaking(false);
      case LiveToolCallRequested(:final callId, :final name, :final args):
        unawaited(_handleToolCall(callId, name, args));
      case LiveSessionClosed(:final error):
        state = state.copyWith(
          status: error == null ? LiveSessionStatus.idle : LiveSessionStatus.error,
          errorMessage: error,
        );
    }
  }

  void _appendTranscript(LiveTranscriptFragment fragment) {
    // Transcripts arrive as small fragments, so consecutive chunks from the
    // same speaker are merged into one line — mirrors `appendTranscript` in
    // `useLiveSession.ts`.
    final lines = [...state.lines];
    if (lines.isNotEmpty && lines.last.fromUser == fragment.fromUser) {
      lines[lines.length - 1] = lines.last.append(fragment.text);
    } else {
      lines.add(TranscriptLine(fromUser: fragment.fromUser, text: fragment.text));
      if (lines.length > 40) lines.removeAt(0);
    }
    state = state.copyWith(lines: lines);
  }

  Future<void> _handleToolCall(String? callId, String name, Map<String, Object?> args) async {
    if (name != 'flagRelapseRisk') {
      await _handle?.sendToolResponse(name: name, id: callId, response: {'ok': false});
      return;
    }
    final parsed = RelapseRiskArgs.fromToolArgs(args);
    try {
      await _onFlagRelapseRisk?.call(parsed);
      state = state.copyWith(incidentStage: parsed.stage);
      await _handle?.sendToolResponse(
        name: name,
        id: callId,
        response: {
          'ok': true,
          'stage': parsed.stage.name,
          'caregiverNotified': parsed.stage == RelapseStage.escalated,
        },
      );
    } catch (_) {
      await _handle?.sendToolResponse(name: name, id: callId, response: {'ok': false});
    }
  }

  void _onPipelineEvent(AudioPipelineEvent event) {
    switch (event) {
      case AudioPipelineFocusGraceExpired():
        // The ~30-60s grace window (§3.7) elapsed with focus not regained —
        // close the session and let the (out-of-scope-here) UI show the
        // "line dropped" state from DESIGN.md §1.6.
        unawaited(endCall());
      case AudioPipelinePausedByFocusLoss():
      case AudioPipelineResumed():
      case AudioPipelinePausedByBecomingNoisy():
      case AudioPipelineLocalVadDucked():
        // Diagnostic/UI hooks only for M2 — the crisis screen (out of scope
        // here) can surface these later.
        break;
    }
  }
}

final liveSessionControllerProvider =
    NotifierProvider<LiveSessionController, LiveSessionState>(LiveSessionController.new);
