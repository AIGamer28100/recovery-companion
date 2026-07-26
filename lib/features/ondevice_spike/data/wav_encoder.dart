import 'dart:typed_data';

/// Wraps raw little-endian PCM16 mono samples (as produced by
/// `MicCapture`/`ChunkBatcher`, see `lib/platform/audio/mic_capture.dart`) in
/// a minimal 44-byte RIFF/WAVE header.
///
/// `flutter_gemma`'s audio input path (`Message.withAudio`) expects a WAV
/// container rather than bare PCM bytes -- its own example app records via
/// `record`'s `AudioEncoder.wav` for exactly this reason. This is a
/// standalone spike utility, not a copy of any production/plugin code: it is
/// just the well-known 44-byte canonical WAV header format.
Uint8List pcm16ToWav(
  Uint8List pcmBytes, {
  int sampleRate = 16000,
  int numChannels = 1,
  int bitsPerSample = 16,
}) {
  final byteRate = sampleRate * numChannels * (bitsPerSample ~/ 8);
  final blockAlign = numChannels * (bitsPerSample ~/ 8);
  final dataLength = pcmBytes.length;
  final header = ByteData(44);

  void writeAscii(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      header.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  writeAscii(0, 'RIFF');
  header.setUint32(4, 36 + dataLength, Endian.little);
  writeAscii(8, 'WAVE');
  writeAscii(12, 'fmt ');
  header.setUint32(16, 16, Endian.little); // fmt chunk size (PCM)
  header.setUint16(20, 1, Endian.little); // audio format: 1 = PCM
  header.setUint16(22, numChannels, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, byteRate, Endian.little);
  header.setUint16(32, blockAlign, Endian.little);
  header.setUint16(34, bitsPerSample, Endian.little);
  writeAscii(36, 'data');
  header.setUint32(40, dataLength, Endian.little);

  final wav = BytesBuilder(copy: false);
  wav.add(header.buffer.asUint8List());
  wav.add(pcmBytes);
  return wav.takeBytes();
}
