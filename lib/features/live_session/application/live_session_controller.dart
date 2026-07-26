import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../platform/audio/audio_pipeline.dart';
import '../data/gemini_live_repository.dart';
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
  });

  final LiveSessionStatus status;
  final List<TranscriptLine> lines;
  final RelapseStage? incidentStage;
  final EchoCancellationAvailability echoCancellationAvailability;
  final String? errorMessage;

  LiveSessionState copyWith({
    LiveSessionStatus? status,
    List<TranscriptLine>? lines,
    Object? incidentStage = _unset,
    EchoCancellationAvailability? echoCancellationAvailability,
    Object? errorMessage = _unset,
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
    FlagRelapseRiskCallback? onFlagRelapseRisk,
  })  : _repository = repository,
        _audioPipeline = audioPipeline,
        _onFlagRelapseRisk = onFlagRelapseRisk;

  LiveSessionRepository? _repository;
  AudioPipeline? _audioPipeline;
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
    await _teardown();
    state = const LiveSessionState();
  }

  void dismissIncident() {
    state = state.copyWith(incidentStage: null);
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
        unawaited(_pipeline.playInboundChunk(Uint8List.fromList(pcm16)));
      case LiveInterrupted():
        unawaited(_pipeline.flushPlayback());
        _pipeline.notifyModelSpeaking(false);
      case LiveTurnComplete():
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
