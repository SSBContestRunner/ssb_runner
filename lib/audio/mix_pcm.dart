import 'dart:typed_data';

/// Mixes 16-bit mono PCM clips. Offsets are intentionally short so pile-up
/// callers overlap while the first (target) caller remains recognisable.
Uint8List mixPcm16(List<Uint8List> clips, {int offsetSamples = 3600}) {
  if (clips.isEmpty) return Uint8List(0);
  if (clips.length == 1) return clips.first;
  final lengths = <int>[
    for (var index = 0; index < clips.length; index++)
      clips[index].length ~/ 2 + index * offsetSamples,
  ];
  final output = Int32List(lengths.reduce((a, b) => a > b ? a : b));
  for (var clipIndex = 0; clipIndex < clips.length; clipIndex++) {
    final source = ByteData.sublistView(clips[clipIndex]);
    final offset = clipIndex * offsetSamples;
    for (var sample = 0; sample < clips[clipIndex].length ~/ 2; sample++) {
      output[offset + sample] += source.getInt16(sample * 2, Endian.little);
    }
  }
  final bytes = Uint8List(output.length * 2);
  final data = ByteData.sublistView(bytes);
  for (var sample = 0; sample < output.length; sample++) {
    data.setInt16(
      sample * 2,
      (output[sample] ~/ clips.length).clamp(-32768, 32767).toInt(),
      Endian.little,
    );
  }
  return bytes;
}
