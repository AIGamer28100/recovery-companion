/// Mirrors `Status` in `useLiveSession.ts`.
enum LiveSessionStatus { idle, connecting, live, error }

/// One line of live transcript. Mirrors `TranscriptLine` in
/// `useLiveSession.ts`.
class TranscriptLine {
  const TranscriptLine({required this.fromUser, required this.text});

  final bool fromUser;
  final String text;

  /// Found on a real device: consecutive transcript fragments from the Live
  /// API don't reliably carry their own leading/trailing whitespace at word
  /// boundaries -- raw concatenation (what `useLiveSession.ts`'s
  /// `appendTranscript` also does, so this isn't a porting regression, it's
  /// a pre-existing gap in both apps) produced real, reproducible
  /// run-together text ("Theeveningwentwell"). Insert a single space at the
  /// join UNLESS either side already supplies one, or the new chunk opens
  /// with punctuation that shouldn't have a space before it -- avoids both
  /// the run-together bug and a new double-space bug on fragments that
  /// *did* already carry their own leading space.
  static final _noSpaceBeforePattern = RegExp(r"^[.,!?;:')\]}]");

  TranscriptLine append(String chunk) {
    if (chunk.isEmpty) return this;
    final needsSpace = text.isNotEmpty &&
        !RegExp(r'\s$').hasMatch(text) &&
        !chunk.startsWith(RegExp(r'\s')) &&
        !_noSpaceBeforePattern.hasMatch(chunk);
    return TranscriptLine(fromUser: fromUser, text: needsSpace ? '$text $chunk' : text + chunk);
  }
}

/// Whether hardware acoustic echo cancellation is available on this device.
/// Surfaced so the presentation layer can show a "tap to interrupt" fallback
/// affordance when true barge-in isn't safe to rely on (DESIGN.md §3.4).
enum EchoCancellationAvailability { available, unavailable, unknown }
