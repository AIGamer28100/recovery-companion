import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_ai/firebase_ai.dart';

import '../domain/live_call_event.dart';
import 'live_safety_tool.dart';
import 'live_session_tee.dart';

/// The only place `firebase_ai`'s Live types (`getLiveGenerativeModel`
/// equivalent, `LiveSession`, `LiveServerMessage`, ...) are touched, per
/// DESIGN.md §2.4. Model id, generation config, and the `flagRelapseRisk`
/// tool declaration live here, ported from `geminiLive.ts`/`safetyTools.ts`.
abstract class LiveSessionRepository {
  Future<LiveSessionHandle> connect();
}

/// Confirmed against Firebase AI Logic docs (see `geminiLive.ts`): the
/// current Gemini Developer API (free tier) Live model id.
const _liveModelId = 'gemini-2.5-flash-native-audio-preview-12-2025';

/// Placeholder only — the clinically-grounded system instruction rewrite is
/// a separate, already-completed research task
/// (`mobile/UX_AND_CLINICAL_GROUNDING.md` §B.8) for whoever wires up the
/// real Live Call screen. This milestone only needs the session-setup shape
/// to exist.
const _placeholderSystemInstruction =
    'You are a warm, trauma-informed recovery companion in a real-time '
    'spoken conversation. (Placeholder instruction — see '
    'UX_AND_CLINICAL_GROUNDING.md §B.8 for the real one, ported by a later '
    'task.)';

const _audioMimeType = 'audio/pcm;rate=16000';

class FirebaseLiveSessionRepository implements LiveSessionRepository {
  FirebaseLiveSessionRepository({FirebaseAI? ai}) : _ai = ai ?? FirebaseAI.googleAI();

  final FirebaseAI _ai;

  @override
  Future<LiveSessionHandle> connect() async {
    final model = _ai.liveGenerativeModel(
      model: _liveModelId,
      liveGenerationConfig: LiveGenerationConfig(
        responseModalities: [ResponseModalities.audio],
        // Surfaces both sides of the conversation as text, mirroring
        // `geminiLive.ts` — important when audio is unclear or the room is
        // loud.
        inputAudioTranscription: AudioTranscriptionConfig(),
        outputAudioTranscription: AudioTranscriptionConfig(),
        // Keeps time-to-first-word roughly flat over a long call — see
        // `geminiLive.ts`'s comment on why an 8k target was too aggressive.
        contextWindowCompression: ContextWindowCompressionConfig(
          triggerTokens: 28000,
          slidingWindow: SlidingWindow(targetTokens: 20000),
        ),
      ),
      systemInstruction: Content.text(_placeholderSystemInstruction),
      tools: [buildRelapseRiskTool()],
    );

    // NOTE: `liveRealtimeInputConfig` (live_vad_config.dart) is deliberately
    // NOT passed here. See that file's doc comment — firebase_ai 3.14.1 has
    // no `realtimeInputConfig` passthrough and no in-Dart equivalent of the
    // web app's WebSocket.prototype.send monkey-patch. This is a flagged,
    // known deviation pending a follow-up spike, not an oversight.
    final session = await model.connect();
    return LiveSessionHandle._(session);
  }
}

/// A connected Live session, exposing only domain-safe types
/// ([LiveCallEvent]) — never `firebase_ai`'s `LiveSession`/`LiveServerMessage`
/// — to anything above the data layer.
class LiveSessionHandle {
  LiveSessionHandle._(this._session) {
    _tee = LiveSessionTee<LiveServerResponse>(_session.receive, onMessage: _handleMessage);
    // Drives the tee's single internal consumer loop. The real fan-out work
    // happens inside `_handleMessage` before each message is yielded, so
    // this listener's body can be a no-op — its only job is to keep the
    // `async*` generator advancing.
    _driveSub = _tee.receive().listen(
          (_) {},
          onError: (Object err, StackTrace st) {
            _emitClosed('The line dropped. Try again.');
          },
          onDone: () => _emitClosed(null),
        );
  }

  final LiveSession _session;
  late final LiveSessionTee<LiveServerResponse> _tee;
  StreamSubscription<LiveServerResponse>? _driveSub;
  final StreamController<LiveCallEvent> _events = StreamController<LiveCallEvent>.broadcast();
  bool _closedEmitted = false;

  /// Every decoded event from the session: transcripts, audio chunks,
  /// barge-in signals, tool calls, and the terminal close event.
  Stream<LiveCallEvent> get events => _events.stream;

  Future<void> sendAudioChunk(Uint8List pcm16) {
    return _session.sendAudioRealtime(InlineDataPart(_audioMimeType, pcm16));
  }

  /// Sends a silent director-note-style message on the side channel —
  /// mirrors `session.sendTextRealtime` usage in `useLiveSession.ts`
  /// (continuity briefings, camera-state notes).
  Future<void> sendTextRealtime(String text) => _session.sendTextRealtime(text);

  Future<void> sendToolResponse({
    required String name,
    String? id,
    required Map<String, Object?> response,
  }) {
    return _session.sendToolResponse([FunctionResponse(name, response, id: id)]);
  }

  Future<void> close() async {
    await _driveSub?.cancel();
    _driveSub = null;
    try {
      await _session.close();
    } finally {
      if (!_events.isClosed) await _events.close();
    }
  }

  void _handleMessage(LiveServerResponse response) {
    for (final event in _mapMessage(response.message)) {
      if (!_events.isClosed) _events.add(event);
    }
  }

  void _emitClosed(String? error) {
    if (_closedEmitted) return;
    _closedEmitted = true;
    if (!_events.isClosed) _events.add(LiveSessionClosed(error: error));
  }

  static List<LiveCallEvent> _mapMessage(LiveServerMessage message) {
    return switch (message) {
      LiveServerContent() => _mapServerContent(message),
      LiveServerToolCall() => (message.functionCalls ?? const [])
          .map(
            (call) => LiveToolCallRequested(
              callId: call.id,
              name: call.name,
              args: call.args,
            ),
          )
          .toList(),
      // `LiveServerSetupComplete` (setup handshake ack) isn't publicly
      // exported by `firebase_ai`, so it can't be named here — it, along
      // with `LiveServerToolCallCancellation`/`GoingAwayNotice`/
      // `SessionResumptionUpdate`, carries nothing this milestone's audio
      // pipeline needs to act on.
      LiveServerMessage() => const [],
    };
  }

  static List<LiveCallEvent> _mapServerContent(LiveServerContent content) {
    final events = <LiveCallEvent>[];

    if (content.interrupted == true) {
      events.add(const LiveInterrupted());
    }

    final inputText = content.inputTranscription?.text;
    if (inputText != null && inputText.isNotEmpty) {
      events.add(LiveTranscriptFragment(text: inputText, fromUser: true));
    }
    final outputText = content.outputTranscription?.text;
    if (outputText != null && outputText.isNotEmpty) {
      events.add(LiveTranscriptFragment(text: outputText, fromUser: false));
    }

    final parts = content.modelTurn?.parts ?? const [];
    for (final part in parts) {
      if (part is InlineDataPart && part.mimeType.startsWith('audio/')) {
        events.add(LiveAudioChunk(part.bytes));
      }
    }

    if (content.turnComplete == true) {
      events.add(const LiveTurnComplete());
    }

    return events;
  }
}
