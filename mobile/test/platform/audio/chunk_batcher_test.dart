import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:recovery_companion/platform/audio/chunk_batcher.dart';

void main() {
  test('batches fragments until targetBytes is reached', () async {
    final batcher = ChunkBatcher(targetBytes: 10, maxWait: const Duration(seconds: 10));
    final controller = StreamController<Uint8List>();

    final resultsFuture = batcher.batch(controller.stream).toList();

    controller.add(Uint8List.fromList(List.filled(4, 1)));
    controller.add(Uint8List.fromList(List.filled(4, 2)));
    // Total so far: 8 bytes, below target of 10 — no chunk emitted yet.
    controller.add(Uint8List.fromList(List.filled(4, 3)));
    // Total: 12 bytes >= 10 — a chunk should flush now.
    await controller.close();

    final results = await resultsFuture;
    expect(results, hasLength(1));
    expect(results.first, hasLength(12));
  });

  test('flushes a partial trailing chunk when the source closes', () async {
    final batcher = ChunkBatcher(targetBytes: 100, maxWait: const Duration(seconds: 10));
    final controller = StreamController<Uint8List>();

    final resultsFuture = batcher.batch(controller.stream).toList();

    controller.add(Uint8List.fromList(List.filled(5, 9)));
    await controller.close();

    final results = await resultsFuture;
    expect(results, hasLength(1));
    expect(results.first, hasLength(5));
  });

  test('flushes on maxWait even if targetBytes is never reached', () async {
    final batcher = ChunkBatcher(
      targetBytes: 100000,
      maxWait: const Duration(milliseconds: 20),
    );
    final controller = StreamController<Uint8List>();

    final results = <Uint8List>[];
    final sub = batcher.batch(controller.stream).listen(results.add);

    controller.add(Uint8List.fromList(List.filled(3, 7)));
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(results, hasLength(1));
    expect(results.first, hasLength(3));

    await sub.cancel();
    await controller.close();
  });

  test('emits nothing for an empty source', () async {
    final batcher = ChunkBatcher();
    final controller = StreamController<Uint8List>();

    final resultsFuture = batcher.batch(controller.stream).toList();
    await controller.close();

    final results = await resultsFuture;
    expect(results, isEmpty);
  });
}
