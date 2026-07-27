import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart' show CameraController;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../platform/audio/audio_pipeline.dart';
import '../../../platform/camera/camera_availability_probe.dart';
import '../../../platform/camera/live_camera_stream.dart';
import '../../../platform/camera/pose_motion_counter.dart';
import '../../../platform/camera/pose_tracker.dart';
import '../../../platform/camera/thermal_status_channel.dart';
import '../../auth/data/auth_repository.dart';
import '../data/gemini_live_repository.dart';
import '../data/incident_repository.dart';
import '../data/session_memory_repository.dart';
import '../domain/camera_availability.dart';
import '../domain/live_call_event.dart';
import '../domain/live_session_status.dart';
import '../domain/pose_motion_notes.dart';
import '../domain/relapse_stage.dart';

/// Called when the model invokes `flagRelapseRisk`. Defaults to a real
/// Firestore-writing implementation (`LiveSessionController._defaultFlagRelapseRisk`)
/// — this is only injectable so tests can substitute a fake without touching
/// Firebase; production never passes anything else. The returned
/// [FlagRelapseRiskResult] is what actually happened, not an assumption
/// derived from `stage` — see that result type's doc comment for the bug
/// this closes.
typedef FlagRelapseRiskCallback = Future<FlagRelapseRiskResult> Function(RelapseRiskArgs args);

const _unset = Object();

class LiveSessionState {
  const LiveSessionState({
    this.status = LiveSessionStatus.idle,
    this.lines = const [],
    this.incidentStage,
    this.echoCancellationAvailability = EchoCancellationAvailability.unknown,
    this.errorMessage,
    this.isModelSpeaking = false,
    this.cameraOn = false,
    this.cameraDegradedByThermal = false,
    this.cameraErrorMessage,
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

  /// True while the camera is actively streaming. Never persisted — reset to
  /// false on every `endCall`/new `LiveSessionState()`, per DESIGN.md §4.4's
  /// "opt-in every session, never remembered" requirement.
  final bool cameraOn;

  /// True if the camera was just turned off by the thermal guardrail
  /// (DESIGN.md §4.3) rather than a manual tap — lets the UI show a banner
  /// explaining why, instead of silently reverting the toggle.
  final bool cameraDegradedByThermal;

  /// One-shot transient message (e.g. "camera access is blocked") for the UI
  /// to surface as a snackbar via `ref.listen`, distinct from [errorMessage]
  /// which drives the full error status line — a camera failure must never
  /// end the call.
  final String? cameraErrorMessage;

  LiveSessionState copyWith({
    LiveSessionStatus? status,
    List<TranscriptLine>? lines,
    Object? incidentStage = _unset,
    EchoCancellationAvailability? echoCancellationAvailability,
    Object? errorMessage = _unset,
    bool? isModelSpeaking,
    bool? cameraOn,
    bool? cameraDegradedByThermal,
    Object? cameraErrorMessage = _unset,
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
      cameraOn: cameraOn ?? this.cameraOn,
      cameraDegradedByThermal: cameraDegradedByThermal ?? this.cameraDegradedByThermal,
      cameraErrorMessage: identical(cameraErrorMessage, _unset)
          ? this.cameraErrorMessage
          : cameraErrorMessage as String?,
    );
  }
}

/// Orchestrates the whole live-session lifecycle: the audio pipeline (mic,
/// playback, echo cancellation, focus/foreground-service), the camera
/// stream (motion-gated frame sending, the thermal guardrail), and the
/// Gemini Live session — wiring outbound mic/video to the session and
/// inbound audio/barge-in/tool-call events back into the pipeline and UI
/// state, including the real `flagRelapseRisk` Firestore write. Mirrors
/// `useLiveSession.ts`'s role, per DESIGN.md §2.2.
///
/// Deliberately does NOT own the crisis-screen UI itself — see
/// `live_call_screen.dart`.
class LiveSessionController extends Notifier<LiveSessionState> {
  LiveSessionController({
    LiveSessionRepository? repository,
    AudioPipeline? audioPipeline,
    SessionMemoryRepository? sessionMemory,
    IncidentRepository? incidentRepository,
    LiveCameraStream? cameraStream,
    ThermalStatusChannel? thermalStatusChannel,
    PoseTracker? poseTracker,
    FlagRelapseRiskCallback? onFlagRelapseRisk,
  })  : _repository = repository,
        _audioPipeline = audioPipeline,
        _sessionMemory = sessionMemory,
        _incidentRepository = incidentRepository,
        _cameraStream = cameraStream,
        _thermalStatusChannel = thermalStatusChannel,
        _poseTracker = poseTracker,
        _onFlagRelapseRisk = onFlagRelapseRisk;

  LiveSessionRepository? _repository;
  AudioPipeline? _audioPipeline;
  SessionMemoryRepository? _sessionMemory;
  IncidentRepository? _incidentRepository;
  LiveCameraStream? _cameraStream;
  ThermalStatusChannel? _thermalStatusChannel;
  PoseTracker? _poseTracker;
  final FlagRelapseRiskCallback? _onFlagRelapseRisk;

  LiveSessionHandle? _handle;
  StreamSubscription<LiveCallEvent>? _eventsSub;
  StreamSubscription<Uint8List>? _outboundSub;
  StreamSubscription<AudioPipelineEvent>? _pipelineEventsSub;
  StreamSubscription<ThermalStatus>? _thermalSub;

  /// Whatever the last camera-availability probe returned — used to word the
  /// director notes sent on toggle correctly for this device. Re-probed at
  /// call start and on each toggle, mirroring `useLiveSession.ts` re-probing
  /// at call time "rather than trusting mount-time state".
  CameraAvailability _cameraAvailability = CameraAvailability.unsupported;

  /// Throttled state for turning `PoseTracker`'s rep/breath events into
  /// director notes -- at most one note every [_poseNoteMinGap], and only
  /// when the totals have actually changed since the last one sent. Reset
  /// whenever the camera (and pose tracking with it) starts, so counts
  /// never bleed across camera-on/off toggles within a call.
  static const _poseNoteMinGap = Duration(seconds: 2);
  int _latestReps = 0;
  int _latestBreaths = 0;
  int _lastSentReps = 0;
  int _lastSentBreaths = 0;
  DateTime? _lastPoseNoteAt;

  /// Bumped on every `endCall`/dispose so a session opened during teardown
  /// can't resurrect itself — mirrors `callGenerationRef` in
  /// `useLiveSession.ts`.
  int _generation = 0;

  LiveSessionRepository get _repo => _repository ??= FirebaseLiveSessionRepository();
  AudioPipeline get _pipeline => _audioPipeline ??= AudioPipeline();
  SessionMemoryRepository get _memory =>
      _sessionMemory ??= FirestoreSessionMemoryRepository();
  IncidentRepository get _incidents => _incidentRepository ??= FirestoreIncidentRepository();
  LiveCameraStream get _camera => _cameraStream ??= LiveCameraStream(
        onFrame: _onCameraFrame,
        // Feeds every raw frame from the same single image stream to pose
        // tracking, alongside (not instead of) the motion-gated Gemini
        // frame path above -- see `LiveCameraStream.onCameraImage`'s doc
        // comment for why this isn't a second `startImageStream` call.
        // Reads the field directly rather than the `_pose` getter so frames
        // that arrive before pose tracking has actually been started
        // (`_startCamera`'s brief window) are just silently dropped.
        onCameraImage: (image) => _poseTracker?.processFrame(image),
        onCameraLost: _onCameraLost,
      );
  ThermalStatusChannel get _thermal => _thermalStatusChannel ??= ThermalStatusChannel();
  PoseTracker get _pose => _poseTracker ??= PoseTracker(onMotionEvent: _onPoseMotionEvent);

  /// Always non-null: falls back to [_defaultFlagRelapseRisk], the real
  /// Firestore-writing implementation, unless a test injected its own via
  /// the constructor. This is the fix for the bug where production wired no
  /// callback at all and silently reported success — there is no longer a
  /// "no callback" state to fall into.
  FlagRelapseRiskCallback get _flagRelapseRiskHandler => _onFlagRelapseRisk ?? _defaultFlagRelapseRisk;

  /// The active camera controller, so the UI can build a `CameraPreview`
  /// from it — null unless `state.cameraOn` is true. This is the one place
  /// outside `platform/camera/` that names a `camera` package type, and only
  /// for that type signature; all camera control/streaming logic itself
  /// stays in `LiveCameraStream`.
  CameraController? get cameraController => _cameraStream?.controller;

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
      String? briefing;
      if (uid != null) {
        try {
          briefing = await _memory.buildContinuityBriefing(uid);
        } catch (_) {
          // Proceed without a briefing rather than fail the call.
        }
      }

      // Re-probed at call time rather than trusting any earlier state — the
      // person may have changed the OS permission since the app last asked.
      // Mirrors `useLiveSession.ts` calling `detectCameraAvailability()`
      // fresh in `startCall`, right before sending the `[Camera: ...]` note.
      try {
        _cameraAvailability = await detectCameraAvailability();
      } catch (_) {
        _cameraAvailability = CameraAvailability.unsupported;
      }
      final cameraNote = '[Camera: ${describeCameraForModel(_cameraAvailability, false)}]';
      final combinedNote = briefing == null || briefing.isEmpty ? cameraNote : '$briefing\n\n$cameraNote';
      if (!isStale()) unawaited(handle.sendTextRealtime(combinedNote));

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
    await _thermalSub?.cancel();
    _thermalSub = null;
    try {
      await _poseTracker?.stop();
    } catch (_) {
      // already torn down
    }
    try {
      await _cameraStream?.stop();
    } catch (_) {
      // already torn down
    }
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

  /// Turns the camera on if it's off, or off if it's on — the only entry
  /// point the UI calls. A no-op unless the call is actually live, since
  /// there is no session to send director notes over otherwise.
  Future<void> toggleCamera() async {
    if (state.status != LiveSessionStatus.live) return;
    if (state.cameraOn) {
      await _stopCamera(thermal: false);
    } else {
      await _startCamera();
    }
  }

  Future<void> _startCamera() async {
    final handle = _handle;
    if (handle == null) return;
    try {
      _cameraAvailability = await detectCameraAvailability();
      await _camera.start();
      state = state.copyWith(cameraOn: true, cameraDegradedByThermal: false, cameraErrorMessage: null);
      // Only listen for thermal changes while the camera is actually
      // running — mic+network alone isn't the load profile DESIGN.md §4.3
      // is guarding against.
      _thermalSub ??= _thermal.statusChanges.listen(_onThermalStatusChanged);
      unawaited(handle.sendTextRealtime(cameraOnDirectorNote(_cameraAvailability)));
      // Pose tracking rides the same camera-on/off lifecycle as the camera
      // itself — never a separate always-on feature. Reset the throttled
      // note state so a fresh camera-on session starts its rep/breath
      // counts from zero rather than carrying over a previous segment's.
      _latestReps = 0;
      _latestBreaths = 0;
      _lastSentReps = 0;
      _lastSentBreaths = 0;
      _lastPoseNoteAt = null;
      _pose.start(sensorOrientationDegrees: _cameraStream?.controller?.description.sensorOrientation ?? 0);
    } catch (_) {
      state = state.copyWith(
        cameraErrorMessage: 'Camera access is blocked, but the conversation is still going.',
      );
    }
  }

  Future<void> _stopCamera({required bool thermal, bool lost = false}) async {
    if (!state.cameraOn) return;
    await _thermalSub?.cancel();
    _thermalSub = null;
    try {
      await _poseTracker?.stop();
    } catch (_) {
      // best-effort
    }
    try {
      await _camera.stop();
    } catch (_) {
      // best-effort
    }
    state = state.copyWith(
      cameraOn: false,
      cameraDegradedByThermal: thermal,
      cameraErrorMessage: lost ? 'Your camera stopped unexpectedly, but the conversation is still going.' : null,
    );
    final note = thermal
        ? cameraThermalDegradeDirectorNote()
        : lost
            ? cameraLostDirectorNote()
            : cameraOffDirectorNote(_cameraAvailability);
    unawaited(_handle?.sendTextRealtime(note));
  }

  /// DESIGN.md §4.3: on `THERMAL_STATUS_SEVERE` or above, proactively
  /// degrade to audio-only rather than let the OS throttle or kill the app
  /// unpredictably — mirrors the manual camera-off path, just triggered by
  /// the phone instead of a tap.
  void _onThermalStatusChanged(ThermalStatus status) {
    if (status.isSevereOrAbove && state.cameraOn) {
      unawaited(_stopCamera(thermal: true));
    }
  }

  /// Reacts to `LiveCameraStream.onCameraLost` -- found on a real device:
  /// the OS/another app reclaiming camera priority can silently kill the
  /// feed while our own state still believes the camera is on. Mirrors the
  /// thermal-guardrail's graceful-degrade pattern (§4.3) rather than leaving
  /// the UI showing a dead camera indefinitely.
  void _onCameraLost(String reason) {
    if (state.cameraOn) {
      unawaited(_stopCamera(thermal: false, lost: true));
    }
  }

  void _onCameraFrame(Uint8List jpeg) {
    unawaited(_handle?.sendVideoRealtime(jpeg));
  }

  /// Records the latest rep/breath totals from `PoseTracker` and, if the
  /// throttle window has elapsed, sends an updated director note. Totals
  /// (not deltas) mean a note skipped by the throttle is never lost
  /// information — the next note sent, whenever that is, carries whatever
  /// is current at that point.
  void _onPoseMotionEvent(PoseMotionEvent event) {
    switch (event.kind) {
      case PoseMotionKind.rep:
        _latestReps = event.totalCount;
      case PoseMotionKind.breath:
        _latestBreaths = event.totalCount;
    }
    _maybeSendPoseNote();
  }

  void _maybeSendPoseNote() {
    final handle = _handle;
    if (handle == null) return;
    if (_latestReps == _lastSentReps && _latestBreaths == _lastSentBreaths) return;
    final now = DateTime.now();
    final last = _lastPoseNoteAt;
    if (last != null && now.difference(last) < _poseNoteMinGap) return;
    _lastPoseNoteAt = now;
    _lastSentReps = _latestReps;
    _lastSentBreaths = _latestBreaths;
    unawaited(handle.sendTextRealtime(poseMotionDirectorNote(reps: _latestReps, breaths: _latestBreaths)));
  }

  /// The real `flagRelapseRisk` side effect: writes the incident (with an
  /// evidence snapshot if the camera happens to be on), and — only at
  /// `stage == escalated` — the caregiver alert. Mirrors the
  /// `recordRelapseIncident`/`logCaregiverAlert` sequence in
  /// `useLiveSession.ts`'s tool-call handler exactly, including that a
  /// failure partway through (e.g. the alert write fails after the incident
  /// write succeeded) surfaces as an overall failure to the model — the web
  /// has the same partial-write characteristic, not a gap introduced here.
  Future<FlagRelapseRiskResult> _defaultFlagRelapseRisk(RelapseRiskArgs args) async {
    final uid = ref.read(authRepositoryProvider).currentUser?.uid;
    if (uid == null) {
      throw StateError('No signed-in user to record a relapse-risk incident for.');
    }
    final evidence = state.cameraOn ? _camera.captureEvidenceFrame() : null;
    await _incidents.recordRelapseIncident(
      uid: uid,
      stage: args.stage,
      observation: args.observation,
      evidenceJpeg: evidence,
    );
    if (args.stage != RelapseStage.escalated) {
      return const FlagRelapseRiskResult(caregiverNotified: false);
    }
    await _incidents.logCaregiverAlert(
      uid: uid,
      script: buildRelapseAlertScript(args.observation),
      triggeredBy: 'relapse_risk',
    );
    return const FlagRelapseRiskResult(caregiverNotified: true);
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
      await _handle?.sendToolResponse(name: name, id: callId, response: flagRelapseRiskFailureResponse);
      return;
    }
    final parsed = RelapseRiskArgs.fromToolArgs(args);
    try {
      // Always a real handler (see `_flagRelapseRiskHandler`'s doc comment)
      // — `caregiverNotified` below reflects what this call actually did,
      // never an assumption inferred from `stage` alone.
      final result = await _flagRelapseRiskHandler(parsed);
      state = state.copyWith(incidentStage: parsed.stage);
      await _handle?.sendToolResponse(
        name: name,
        id: callId,
        response: buildFlagRelapseRiskResponse(stage: parsed.stage, caregiverNotified: result.caregiverNotified),
      );
    } catch (_) {
      await _handle?.sendToolResponse(name: name, id: callId, response: flagRelapseRiskFailureResponse);
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
