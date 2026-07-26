/// Round-trip latency for one spike turn: mic stops -> Gemma responds ->
/// TTS starts speaking. Deliberately coarse (wall-clock `DateTime` deltas,
/// not tracing) -- this is a feasibility spike, not instrumentation for
/// production.
class SpikeLatency {
  const SpikeLatency({
    required this.micStoppedAt,
    required this.modelRespondedAt,
    required this.ttsStartedAt,
  });

  final DateTime micStoppedAt;
  final DateTime modelRespondedAt;
  final DateTime ttsStartedAt;

  Duration get inferenceDuration => modelRespondedAt.difference(micStoppedAt);
  Duration get ttsStartDelay => ttsStartedAt.difference(modelRespondedAt);
  Duration get totalRoundTrip => ttsStartedAt.difference(micStoppedAt);

  @override
  String toString() =>
      'inference=${inferenceDuration.inMilliseconds}ms, '
      'tts-start-delay=${ttsStartDelay.inMilliseconds}ms, '
      'total=${totalRoundTrip.inMilliseconds}ms';
}
