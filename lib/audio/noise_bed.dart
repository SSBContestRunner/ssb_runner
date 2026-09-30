import 'dart:math';
import 'dart:typed_data';

/// Generates a short, seamlessly loopable receiver noise bed.
///
/// Programmatic generation keeps the voice submodule and its asset manifest
/// untouched, and makes the bed reproducible from a seed (design §5.2 option A).
/// One-pole low-pass filtering turns white noise into the band-limited hiss of
/// a receiver audio passband.
Uint8List generateNoiseBedPcm({
  required int seed,
  int sampleRate = 24000,
  Duration duration = const Duration(seconds: 2),
}) {
  final sampleCount = sampleRate * duration.inMilliseconds ~/ 1000;
  final bytes = Uint8List(sampleCount * 2);
  final data = ByteData.sublistView(bytes);
  final random = Random(seed);
  const alpha = 0.15;
  var filtered = 0.0;
  for (var index = 0; index < sampleCount; index++) {
    final white = random.nextDouble() * 2 - 1;
    filtered += alpha * (white - filtered);
    // Undo the one-pole gain and scale to a modest fraction of full scale; the
    // difficulty level is applied on top of this when the bed is played.
    final value = (filtered / alpha) * 0.35;
    data.setInt16(
      index * 2,
      (value * 32767).round().clamp(-32768, 32767),
      Endian.little,
    );
  }
  return bytes;
}
