import 'dart:typed_data';

/// Wraps raw 16-bit little-endian PCM in a minimal 44-byte RIFF/WAVE header.
///
/// [SoLoud.loadMem] only accepts a complete, decodable audio file, so the
/// generated receiver noise bed is wrapped before it is handed to the engine.
/// Looping a decoded in-memory source is sample-accurate, unlike looping a
/// [BufferingType.released] buffer stream (which frees data as it plays).
Uint8List pcm16ToWav(
  Uint8List pcm, {
  int sampleRate = 24000,
  int channels = 1,
}) {
  const bitsPerSample = 16;
  final blockAlign = channels * bitsPerSample ~/ 8;
  final byteRate = sampleRate * blockAlign;

  final header = ByteData(44);
  header.setUint32(0, 0x52494646, Endian.big); // 'RIFF'
  header.setUint32(4, 36 + pcm.length, Endian.little); // chunk size
  header.setUint32(8, 0x57415645, Endian.big); // 'WAVE'
  header.setUint32(12, 0x666D7420, Endian.big); // 'fmt '
  header.setUint32(16, 16, Endian.little); // PCM subchunk size
  header.setUint16(20, 1, Endian.little); // PCM format
  header.setUint16(22, channels, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, byteRate, Endian.little);
  header.setUint16(32, blockAlign, Endian.little);
  header.setUint16(34, bitsPerSample, Endian.little);
  header.setUint32(36, 0x64617461, Endian.big); // 'data'
  header.setUint32(40, pcm.length, Endian.little);

  final wav = Uint8List(44 + pcm.length);
  wav.setRange(0, 44, header.buffer.asUint8List());
  wav.setRange(44, wav.length, pcm);
  return wav;
}
