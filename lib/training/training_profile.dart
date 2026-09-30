import 'dart:math';
import 'dart:typed_data';

import 'package:ssb_runner/training/session_random.dart';

/// A practice profile is intentionally independent from a contest definition.
/// This keeps one ruleset usable in a clean beginner exercise and in a noisy
/// pile-up without duplicating the scoring implementation.
enum TrainingMode {
  run('run', 'Run', 'Callers answer your CQ in sequence'),
  searchAndPounce(
    'search-and-pounce',
    'S&P',
    'Find and work one station at a time',
  ),
  pileup('pileup', 'Pile-up', 'Choose the target from overlapping callers');

  const TrainingMode(this.id, this.label, this.description);
  final String id;
  final String label;
  final String description;

  static TrainingMode fromId(String? id) => TrainingMode.values.firstWhere(
    (mode) => mode.id == id,
    orElse: () => TrainingMode.run,
  );
}

/// Difficulty separates the receiver noise bed (constant hiss between signals)
/// from the in-signal SNR noise and the QSB envelope (see design §5.2).
enum TrainingDifficulty {
  beginner(
    'beginner',
    'Beginner',
    playbackRate: 1.0,
    noiseBedLevel: 0.02,
    snrNoise: 0.00,
    qsbDepth: 0.00,
    qsbRate: 0.0,
    pileupCallers: 0,
    pileupOffsetSamples: 7200,
  ),
  standard(
    'standard',
    'Standard',
    playbackRate: 1.08,
    noiseBedLevel: 0.07,
    snrNoise: 0.04,
    qsbDepth: 0.10,
    qsbRate: 0.5,
    pileupCallers: 1,
    pileupOffsetSamples: 7200,
  ),
  advanced(
    'advanced',
    'Advanced',
    playbackRate: 1.18,
    noiseBedLevel: 0.15,
    snrNoise: 0.10,
    qsbDepth: 0.22,
    qsbRate: 1.0,
    pileupCallers: 2,
    pileupOffsetSamples: 3600,
  );

  const TrainingDifficulty(
    this.id,
    this.label, {
    required this.playbackRate,
    required this.noiseBedLevel,
    required this.snrNoise,
    required this.qsbDepth,
    required this.qsbRate,
    required this.pileupCallers,
    required this.pileupOffsetSamples,
  });

  final String id;
  final String label;
  final double playbackRate;

  /// Constant receiver noise bed gain (applied to the generated bed PCM).
  final double noiseBedLevel;

  /// Noise added on top of each signal clip.
  final double snrNoise;
  final double qsbDepth;
  final double qsbRate;

  /// Interfering callers mixed behind the target in pile-up mode.
  final int pileupCallers;

  /// Sample offset between pile-up callers at the project's 24 kHz rate.
  final int pileupOffsetSamples;

  static TrainingDifficulty fromId(String? id) =>
      TrainingDifficulty.values.firstWhere(
        (difficulty) => difficulty.id == id,
        orElse: () => TrainingDifficulty.standard,
      );
}

/// Session-level training parameters. Two independent seeds keep the question
/// sequence reproducible without the audio environment (and vice versa).
class AudioTrainingProfile {
  const AudioTrainingProfile({
    required this.difficulty,
    required this.volume,
    required this.questionSeed,
    required this.audioSeed,
  });

  final TrainingDifficulty difficulty;
  final double volume;
  final int questionSeed;
  final int audioSeed;

  double get playbackRate => difficulty.playbackRate;
  double get noiseBedLevel => difficulty.noiseBedLevel;
  double get snrNoise => difficulty.snrNoise;
  double get qsbDepth => difficulty.qsbDepth;
  double get qsbRate => difficulty.qsbRate;

  factory AudioTrainingProfile.fromDifficulty({
    required TrainingDifficulty difficulty,
    required double volume,
    required int questionSeed,
    required int audioSeed,
  }) => AudioTrainingProfile(
    difficulty: difficulty,
    volume: volume,
    questionSeed: questionSeed,
    audioSeed: audioSeed,
  );
}

/// Applies deterministic, deliberately modest effects to remote-station PCM.
///
/// Input/output is mono 16-bit little-endian PCM at the project's 24 kHz rate.
/// One instance is created per session so the QSB phase is continuous across
/// clips instead of restarting from the loudest point every transmission.
class AudioTrainingEffects {
  AudioTrainingEffects(this.profile)
    : _random = SessionRandom(profile.audioSeed);

  final AudioTrainingProfile profile;
  final SessionRandom _random;

  /// Session-level QSB phase in radians, carried across clips.
  double _phase = 0;

  double get phase => _phase;

  Uint8List apply(Uint8List pcm) {
    if (pcm.isEmpty) return pcm;

    final rateAdjusted = _resampleLinear(pcm, profile.playbackRate);
    final bytes = Uint8List.fromList(rateAdjusted);
    final data = ByteData.sublistView(bytes);
    const sampleRate = 24000.0;
    final startPhase = _phase;
    final angularRate = 2 * pi * profile.qsbRate;

    for (var offset = 0; offset + 1 < bytes.length; offset += 2) {
      final sample = data.getInt16(offset, Endian.little);
      final second = (offset / 2) / sampleRate;
      final fade =
          1 -
          profile.qsbDepth *
              (0.5 + 0.5 * sin(startPhase + second * angularRate));
      final noise = profile.snrNoise == 0
          ? 0.0
          : (_random.nextAudioUnit() * 2 - 1) * 32767 * profile.snrNoise;
      final adjusted = (sample * fade + noise) * profile.volume;
      data.setInt16(
        offset,
        adjusted.clamp(-32768, 32767).round(),
        Endian.little,
      );
    }

    if (profile.qsbRate > 0) {
      final seconds = (bytes.length / 2) / sampleRate;
      _phase = (startPhase + seconds * angularRate) % (2 * pi);
    }
    return bytes;
  }

  /// Linear-interpolating resample; avoids the aliasing of nearest-neighbour
  /// dropping at the Advanced playback rate.
  static Uint8List _resampleLinear(Uint8List pcm, double rate) {
    if (rate <= 1.001 || rate <= 0) return Uint8List.fromList(pcm);
    final inputSamples = pcm.length ~/ 2;
    if (inputSamples == 0) return Uint8List(0);
    final outputSamples = max(1, (inputSamples / rate).floor());
    final input = ByteData.sublistView(pcm);
    final output = Uint8List(outputSamples * 2);
    final outputData = ByteData.sublistView(output);
    for (var index = 0; index < outputSamples; index++) {
      final position = index * rate;
      final left = min(position.floor(), inputSamples - 1);
      final right = min(inputSamples - 1, left + 1);
      final fraction = position - left;
      final a = input.getInt16(left * 2, Endian.little);
      final b = input.getInt16(right * 2, Endian.little);
      outputData.setInt16(
        index * 2,
        (a + (b - a) * fraction).round().clamp(-32768, 32767),
        Endian.little,
      );
    }
    return output;
  }
}
