import 'dart:math' as math;
import 'dart:typed_data';

/// A lightweight, local, energy-based voice-activity detector for the
/// *outbound* mic stream, per DESIGN.md §3.5.
///
/// This is deliberately not authoritative for barge-in — it is only used to
/// duck local playback volume as an early hint while the model is speaking,
/// closing the perceptual gap before the server's own `interrupted` signal
/// round-trips back. A false positive here (a breath, a cough, echo
/// bleed-through) just causes a slight, harmless volume dip; it must never
/// be wired to a hard flush, which is reserved for the server's confirmed
/// signal.
///
/// Pure Dart, no plugin imports — testable with synthetic PCM16 buffers.
class EnergyVad {
  EnergyVad({
    this.threshold = 500,
    this.hangoverChunks = 2,
  });

  /// RMS threshold (on a 16-bit PCM scale, so 0-32767) above which a chunk is
  /// considered speech. 500 is a conservative starting point deliberately on
  /// the quiet side — DESIGN.md flags per-device tuning as needing a real
  /// microphone, not a guess (§3.6/§9).
  final double threshold;

  /// Number of consecutive below-threshold chunks required before
  /// `isSpeaking` reports false again, so a brief dip mid-word doesn't
  /// immediately un-duck the playback.
  final int hangoverChunks;

  int _quietStreak = 0;
  bool _speaking = false;

  /// Feeds one PCM16 little-endian mono chunk and returns the current
  /// speaking state after considering it.
  bool addChunk(Uint8List pcm16) {
    final rms = _rms(pcm16);
    if (rms >= threshold) {
      _quietStreak = 0;
      _speaking = true;
    } else {
      _quietStreak++;
      if (_quietStreak >= hangoverChunks) {
        _speaking = false;
      }
    }
    return _speaking;
  }

  void reset() {
    _quietStreak = 0;
    _speaking = false;
  }

  static double _rms(Uint8List pcm16) {
    if (pcm16.length < 2) return 0;
    final samples = ByteData.sublistView(pcm16);
    final sampleCount = pcm16.length ~/ 2;
    if (sampleCount == 0) return 0;
    var sumSquares = 0.0;
    for (var i = 0; i < sampleCount; i++) {
      final sample = samples.getInt16(i * 2, Endian.little);
      sumSquares += sample * sample;
    }
    return math.sqrt(sumSquares / sampleCount);
  }
}
