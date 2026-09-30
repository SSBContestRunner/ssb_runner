import 'dart:math';
import 'dart:typed_data';

import 'package:ssb_runner/audio/ssb_passband.dart';

/// Receiver noise bed: the sound of an SSB receiver sitting on an empty
/// frequency (design §5.2).
///
/// The bed emulates the audio passband of an HF SSB receiver after detection:
///
/// * band-limited hiss roughly 300–2700 Hz (2nd-order high-pass + 4th-order
///   low-pass), so it sounds like the "沙沙" hiss of a real passband instead
///   of the low rumble a plain low-pass used to produce;
/// * a slow breathing envelope (a couple of dB over several seconds) so the
///   floor is never a dead, unchanging drone;
/// * sparse, band-limited QRN crashes that scale with the difficulty;
/// * an equal-power seam crossfade, so [SoLoud] can loop the buffer forever
///   without a click every loop.
///
/// The output is deterministic for a seed, which keeps a training session
/// reproducible and needs no noise asset in the voice submodule.
Uint8List generateNoiseBedPcm({
  required int seed,
  int sampleRate = 24000,
  Duration duration = const Duration(seconds: 8),
  double qrnPerSecond = 0.35,
}) {
  final loopSamples = sampleRate * duration.inMilliseconds ~/ 1000;
  final fadeSamples = (sampleRate * _seamCrossfade.inMilliseconds ~/ 1000)
      .clamp(1, loopSamples ~/ 4);
  final totalSamples = loopSamples + fadeSamples;
  final random = Random(seed);
  final raw = Float64List(totalSamples);

  // White noise plus sparse QRN bursts. Bursts are generated before the
  // band-pass filter so they pick up the same 300–2700 Hz character as the
  // hiss instead of sounding like clean digital clicks.
  final burstProbability = qrnPerSecond / sampleRate;
  var burstRemaining = 0;
  var burstEnvelope = 0.0;
  var burstDecay = 0.0;
  for (var index = 0; index < totalSamples; index++) {
    var value = random.nextDouble() * 2 - 1;
    if (burstRemaining <= 0 && random.nextDouble() < burstProbability) {
      final milliseconds = 4 + random.nextDouble() * 16; // 4–20 ms crash
      final burstSamples = (milliseconds * sampleRate / 1000).round();
      burstRemaining = burstSamples;
      burstEnvelope = 3 + random.nextDouble() * 5; // 3–8× the white noise
      // Decay to ~5% over the burst, i.e. three time constants.
      burstDecay = exp(-3 / burstSamples);
    }
    if (burstRemaining > 0) {
      value += (random.nextDouble() * 2 - 1) * burstEnvelope;
      burstEnvelope *= burstDecay;
      burstRemaining--;
    }
    raw[index] = value;
  }

  // Bright SSB passband, shared with the in-signal SNR noise so both have the
  // same colour (2nd-order high-pass at 300 Hz + 4th-order low-pass at
  // 2700 Hz). The bed re-normalises its level below anyway.
  final shaper = SsbNoiseShaper(sampleRate: sampleRate);
  final shaped = Float64List(totalSamples);
  for (var index = 0; index < totalSamples; index++) {
    shaped[index] = shaper.process(raw[index]);
  }

  // Slow breathing. The envelope uses integer cycles over the loop, so it is
  // periodic with the loop and survives the seam crossfade unchanged.
  final loopSeconds = loopSamples / sampleRate;
  for (var index = 0; index < totalSamples; index++) {
    final seconds = index / sampleRate;
    final breath =
        1.0 +
        0.12 * sin(2 * pi * seconds / loopSeconds * 3 + 0.6) +
        0.06 * sin(2 * pi * seconds / loopSeconds * 7 + 2.4);
    shaped[index] *= breath;
  }

  // Equal-power seam crossfade: the head is blended with the extra tail so
  // wrapping from the last sample back to the first is continuous.
  final loop = Float64List(loopSamples);
  for (var index = 0; index < loopSamples; index++) {
    if (index < fadeSamples) {
      final theta = (pi / 2) * index / fadeSamples;
      loop[index] =
          shaped[index] * sin(theta) + shaped[loopSamples + index] * cos(theta);
    } else {
      loop[index] = shaped[index];
    }
  }

  // Normalise to a fixed RMS so the difficulty gains mean the same thing
  // regardless of the filter and QRN settings.
  var sumSquares = 0.0;
  for (final sample in loop) {
    sumSquares += sample * sample;
  }
  final rms = sqrt(sumSquares / loopSamples);
  final scale = rms == 0 ? 0.0 : _referenceRms / rms;

  final bytes = Uint8List(loopSamples * 2);
  final data = ByteData.sublistView(bytes);
  for (var index = 0; index < loopSamples; index++) {
    final value = (loop[index] * scale).clamp(-1.0, 1.0);
    data.setInt16(index * 2, (value * 32767).round(), Endian.little);
  }
  return bytes;
}

/// Loop length of the seam crossfade; long enough to hide the wrap without
/// noticeably shortening the useful noise.
const Duration _seamCrossfade = Duration(milliseconds: 100);

/// Full-scale RMS of the generated bed. Difficulty multipliers scale down
/// from here (see [TrainingDifficulty.noiseBedLevel]).
const double _referenceRms = 0.12;

