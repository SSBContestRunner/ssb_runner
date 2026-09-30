import 'dart:math';
import 'dart:typed_data';

/// Mixes the target caller at full gain with weighted interferers, then applies
/// a `tanh` soft limiter. Unrelated to [mixPcm16]'s plain averaging: the point
/// of pile-up training is to copy the target, so the target must not be
/// attenuated by the number of interferers.
Uint8List mixPileup(
  Uint8List target,
  List<Uint8List> interferers, {
  double interfererGain = 0.5,
  int offsetSamples = 3600,
}) {
  if (interferers.isEmpty) return target;

  final targetSamples = target.length ~/ 2;
  var lengthSamples = targetSamples;
  for (var index = 0; index < interferers.length; index++) {
    final end = interferers[index].length ~/ 2 + (index + 1) * offsetSamples;
    if (end > lengthSamples) lengthSamples = end;
  }

  final accumulator = Float64List(lengthSamples);
  _accumulate(accumulator, target, 0, 1.0);
  for (var index = 0; index < interferers.length; index++) {
    _accumulate(
      accumulator,
      interferers[index],
      (index + 1) * offsetSamples,
      interfererGain,
    );
  }

  final bytes = Uint8List(lengthSamples * 2);
  final data = ByteData.sublistView(bytes);
  for (var sample = 0; sample < lengthSamples; sample++) {
    // tanh keeps peaks rounded instead of producing a hard-clipped plateau.
    final limited = (_tanh(accumulator[sample] / 32768) * 32767).round();
    data.setInt16(sample * 2, limited.clamp(-32768, 32767), Endian.little);
  }
  return bytes;
}

double _tanh(double value) {
  if (value > 20) return 1;
  if (value < -20) return -1;
  final exponential = exp(2 * value);
  return (exponential - 1) / (exponential + 1);
}

void _accumulate(
  Float64List output,
  Uint8List source,
  int offset,
  double gain,
) {
  final data = ByteData.sublistView(source);
  final samples = source.length ~/ 2;
  for (var sample = 0; sample < samples; sample++) {
    output[offset + sample] += data.getInt16(sample * 2, Endian.little) * gain;
  }
}
