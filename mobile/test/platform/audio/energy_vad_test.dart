import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:soter_recovery/platform/audio/energy_vad.dart';

Uint8List _pcm16Of(int sampleValue, int sampleCount) {
  final bytes = ByteData(sampleCount * 2);
  for (var i = 0; i < sampleCount; i++) {
    bytes.setInt16(i * 2, sampleValue, Endian.little);
  }
  return bytes.buffer.asUint8List();
}

void main() {
  test('reports not speaking for silence', () {
    final vad = EnergyVad(threshold: 500, hangoverChunks: 2);
    final silentChunk = _pcm16Of(0, 160);

    expect(vad.addChunk(silentChunk), isFalse);
  });

  test('reports speaking for a loud chunk', () {
    final vad = EnergyVad(threshold: 500, hangoverChunks: 2);
    final loudChunk = _pcm16Of(10000, 160);

    expect(vad.addChunk(loudChunk), isTrue);
  });

  test('hangover keeps speaking=true across a brief dip', () {
    final vad = EnergyVad(threshold: 500, hangoverChunks: 2);
    final loud = _pcm16Of(10000, 160);
    final quiet = _pcm16Of(0, 160);

    expect(vad.addChunk(loud), isTrue);
    // One quiet chunk shouldn't immediately flip it off (hangoverChunks: 2).
    expect(vad.addChunk(quiet), isTrue);
    // A second consecutive quiet chunk should.
    expect(vad.addChunk(quiet), isFalse);
  });

  test('reset clears speaking state', () {
    final vad = EnergyVad(threshold: 500, hangoverChunks: 1);
    vad.addChunk(_pcm16Of(10000, 160));
    vad.reset();

    expect(vad.addChunk(_pcm16Of(0, 160)), isFalse);
  });
}
