/// Ported values from `REALTIME_INPUT_CONFIG` in `src/lib/liveVad.ts` — see
/// that file's own comment for the clinical reasoning (someone in distress
/// speaks in fragments with long thinking pauses; the Live API's default
/// end-of-speech threshold is tuned for brisk back-and-forth and cuts in too
/// early).
///
/// **Known gap — read before wiring this up (verification spike, per
/// DESIGN.md §3.5):** `firebase_ai: ^3.14.1`'s `LiveSession` does NOT expose
/// `realtimeInputConfig` (confirmed by reading
/// `live_session.dart#_performWebSocketSetup`: the outbound `setup` JSON it
/// builds has no such key, and no public config type for it exists in
/// `live_api.dart`). The web app worked around the equivalent gap by
/// monkey-patching `WebSocket.prototype.send` to inject the field into the
/// outbound setup frame before it went over the wire.
///
/// That specific trick has no Dart equivalent here: `_performWebSocketSetup`
/// is a private `static` method that constructs the `WebSocketChannel` and
/// sends the setup frame itself, with no injectable seam — there is no
/// public "send" method call site final class prototype to intercept.
/// Reproducing it would mean hand-rolling the entire connection (URI/model
/// string construction, plus Firebase Auth/App Check token headers, both
/// currently assembled by `LiveGenerativeModel.connect()` and `BaseModel`'s
/// private `firebaseTokens` helper, which isn't part of the package's public
/// API) and handing the resulting socket to `LiveSession.forTesting()` — a
/// `@visibleForTesting` constructor not meant for production use, and one
/// that would still trip `flutter analyze`.
///
/// That is a materially bigger, auth-sensitive, upgrade-fragile piece of
/// work than this milestone's audio-pipeline scope, so — per the task's own
/// instruction to scope this as its own spike rather than discover it
/// mid-integration — it is **not wired to the live session in this
/// milestone**. The Live API's default VAD tuning applies until a follow-up
/// decides between: (a) forking/vendoring a patched `firebase_ai`, (b)
/// waiting for upstream to expose `realtimeInputConfig`, or (c) replacing
/// `firebase_ai`'s transport for the Live session with a hand-rolled
/// WebSocket client. This constant is kept ready to pass through the moment
/// any of those lands.
const liveRealtimeInputConfig = LiveRealtimeInputConfig(
  automaticActivityDetection: AutomaticActivityDetectionConfig(
    silenceDurationMs: 1400,
    prefixPaddingMs: 400,
    endOfSpeechSensitivity: EndOfSpeechSensitivity.low,
    startOfSpeechSensitivity: StartOfSpeechSensitivity.low,
  ),
);

class LiveRealtimeInputConfig {
  const LiveRealtimeInputConfig({required this.automaticActivityDetection});

  final AutomaticActivityDetectionConfig automaticActivityDetection;

  Map<String, Object?> toJson() => {
        'automaticActivityDetection': automaticActivityDetection.toJson(),
      };
}

class AutomaticActivityDetectionConfig {
  const AutomaticActivityDetectionConfig({
    required this.silenceDurationMs,
    required this.prefixPaddingMs,
    required this.endOfSpeechSensitivity,
    required this.startOfSpeechSensitivity,
  });

  /// Default is a few hundred ms. Just over a second lets someone say
  /// "umm... I don't... " and keep going without the model stealing the
  /// turn.
  final int silenceDurationMs;

  /// Keeps the audio just before speech is detected, so a soft "umm" or a
  /// quiet first syllable isn't clipped off the front of the turn.
  final int prefixPaddingMs;

  /// Least eager to declare the turn finished.
  final EndOfSpeechSensitivity endOfSpeechSensitivity;

  /// Don't treat every small noise or breath as the start of a new turn.
  final StartOfSpeechSensitivity startOfSpeechSensitivity;

  Map<String, Object?> toJson() => {
        'silenceDurationMs': silenceDurationMs,
        'prefixPaddingMs': prefixPaddingMs,
        'endOfSpeechSensitivity': endOfSpeechSensitivity.wireValue,
        'startOfSpeechSensitivity': startOfSpeechSensitivity.wireValue,
      };
}

enum EndOfSpeechSensitivity {
  low('END_SENSITIVITY_LOW'),
  high('END_SENSITIVITY_HIGH');

  const EndOfSpeechSensitivity(this.wireValue);
  final String wireValue;
}

enum StartOfSpeechSensitivity {
  low('START_SENSITIVITY_LOW'),
  high('START_SENSITIVITY_HIGH');

  const StartOfSpeechSensitivity(this.wireValue);
  final String wireValue;
}
