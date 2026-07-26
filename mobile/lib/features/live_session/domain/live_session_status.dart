/// Mirrors `Status` in `useLiveSession.ts`.
enum LiveSessionStatus { idle, connecting, live, error }

/// One line of live transcript. Mirrors `TranscriptLine` in
/// `useLiveSession.ts`.
class TranscriptLine {
  const TranscriptLine({required this.fromUser, required this.text});

  final bool fromUser;
  final String text;

  TranscriptLine append(String chunk) =>
      TranscriptLine(fromUser: fromUser, text: text + chunk);
}

/// Whether hardware acoustic echo cancellation is available on this device.
/// Surfaced so the presentation layer can show a "tap to interrupt" fallback
/// affordance when true barge-in isn't safe to rely on (DESIGN.md §3.4).
enum EchoCancellationAvailability { available, unavailable, unknown }
