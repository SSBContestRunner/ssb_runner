import 'dart:io';
import 'dart:typed_data';

import 'package:ssb_runner/audio/noise_bed.dart';
import 'package:ssb_runner/audio/pcm_to_wav.dart';
import 'package:ssb_runner/training/training_profile.dart';

/// Renders audition copies of the generated receiver noise bed into `debug/`.
///
/// Run with `dart run tool/noise_bed_preview.dart` after changing the bed DSP.
void main() {
  const seed = 20250930;
  final bed = generateNoiseBedPcm(seed: seed, qrnPerSecond: 0.35);
  _write('debug/noise_bed_raw.wav', bed);

  for (final difficulty in TrainingDifficulty.values) {
    _write(
      'debug/noise_bed_${difficulty.id}.wav',
      _scale(bed, difficulty.noiseBedLevel),
    );
  }

  final voice = _readWavPcm('assets/voice/JP/Common/ROGER_YOU_ARE_59.wav');
  // A weak DX signal at ~50% of the local voice level, heard through the
  // Standard floor (roughly +6 dB in-band SNR). The callsign should stay
  // copyable, which is the point of the exercise.
  _write(
    'debug/noise_bed_with_weak_signal.wav',
    _mix(_scale(voice, 0.5), bed, TrainingDifficulty.standard.noiseBedLevel),
  );

  // Full receive chain: playback rate + QSB + band-limited in-signal SNR
  // noise, then the Standard floor underneath.
  const profile = AudioTrainingProfile(
    difficulty: TrainingDifficulty.standard,
    volume: 1,
    questionSeed: 1,
    audioSeed: seed,
  );
  final processed = AudioTrainingEffects(profile).apply(voice);
  _write(
    'debug/noise_bed_with_full_chain.wav',
    _mix(processed, bed, TrainingDifficulty.standard.noiseBedLevel),
  );
  stdout.writeln('noise bed previews written to debug/');
}

Uint8List _scale(Uint8List pcm, double gain) {
  final data = ByteData.sublistView(pcm);
  final out = Uint8List(pcm.length);
  final output = ByteData.sublistView(out);
  for (var index = 0; index < pcm.length ~/ 2; index++) {
    final value = (data.getInt16(index * 2, Endian.little) * gain).round();
    output.setInt16(index * 2, value.clamp(-32768, 32767), Endian.little);
  }
  return out;
}

Uint8List _mix(Uint8List voice, Uint8List bed, double bedGain) {
  final voiceData = ByteData.sublistView(voice);
  final bedData = ByteData.sublistView(bed);
  final out = Uint8List(voice.length);
  final output = ByteData.sublistView(out);
  for (var index = 0; index < voice.length ~/ 2; index++) {
    final noise = (bedData.getInt16((index * 2) % bed.length, Endian.little) * bedGain).round();
    final mixed = voiceData.getInt16(index * 2, Endian.little) + noise;
    output.setInt16(index * 2, mixed.clamp(-32768, 32767), Endian.little);
  }
  return out;
}

Uint8List _readWavPcm(String path) {
  final bytes = File(path).readAsBytesSync();
  final data = ByteData.sublistView(bytes);
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final size = data.getUint32(offset + 4, Endian.little);
    if (id == 'data') {
      return Uint8List.sublistView(bytes, offset + 8, offset + 8 + size);
    }
    offset += 8 + size;
  }
  throw FormatException('no data chunk in $path');
}

void _write(String path, Uint8List pcm) {
  File(path).writeAsBytesSync(pcm16ToWav(pcm));
}
