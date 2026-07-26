import 'dart:async';
import 'dart:typed_data';

/// Batches a stream of raw PCM byte fragments (as delivered by `record`'s
/// `startStream()`, which does no framing of its own) into chunks sized for
/// handoff to the Live session, per DESIGN.md §3.2.
///
/// 16kHz x 16-bit mono = 32,000 bytes/sec = 32 bytes/ms, so a 100-200ms
/// target window is 3,200-6,400 bytes. A chunk is emitted as soon as it
/// reaches [targetBytes], or after [maxWait] elapses since the last emission
/// even if short — a call that just started (or a quiet mic) must not stall
/// forever waiting to fill a buffer that a burst of silence never completes.
///
/// Pure Dart, no platform/plugin imports — testable with a fake source
/// stream, per DESIGN.md §2.5 ("framing math" unit tests).
class ChunkBatcher {
  ChunkBatcher({
    this.targetBytes = 4800, // ~150ms at 16kHz/16-bit mono, the midpoint of
    // the 100-200ms range DESIGN.md §3.2 calls a starting point pending
    // real round-trip measurement.
    this.maxWait = const Duration(milliseconds: 200),
  });

  final int targetBytes;
  final Duration maxWait;

  /// Wraps [source] and returns a new stream of batched chunks. Closes when
  /// [source] closes, flushing any partial trailing chunk first.
  Stream<Uint8List> batch(Stream<Uint8List> source) {
    late StreamController<Uint8List> controller;
    final buffer = BytesBuilder(copy: false);
    Timer? flushTimer;
    StreamSubscription<Uint8List>? sub;

    void flush() {
      flushTimer?.cancel();
      flushTimer = null;
      if (buffer.isEmpty) return;
      controller.add(buffer.takeBytes());
    }

    void scheduleFlush() {
      flushTimer ??= Timer(maxWait, flush);
    }

    controller = StreamController<Uint8List>(
      onListen: () {
        sub = source.listen(
          (fragment) {
            buffer.add(fragment);
            if (buffer.length >= targetBytes) {
              flush();
            } else {
              scheduleFlush();
            }
          },
          onError: controller.addError,
          onDone: () {
            flush();
            controller.close();
          },
        );
      },
      onCancel: () {
        flushTimer?.cancel();
        return sub?.cancel();
      },
    );
    return controller.stream;
  }
}
