import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/audio/audio_engine.dart';
import 'package:ssb_runner/audio/audio_player.dart';
import 'package:ssb_runner/audio/noise_bed.dart';
import 'package:ssb_runner/training/training_profile.dart';

void main() {
  test('noise bed generation is deterministic for a seed', () {
    final first = generateNoiseBedPcm(seed: 42);
    final second = generateNoiseBedPcm(seed: 42);
    final other = generateNoiseBedPcm(seed: 43);

    expect(first, second);
    expect(first, isNot(equals(other)));
    expect(first.length, 2 * 24000 * 2 ~/ 2 * 2); // 2 s of 16-bit mono
  });

  test('startPlay starts the bed and stopPlay stops it', () async {
    final engine = _FakeNoiseEngine();
    final player = AudioPlayer(engine: engine);
    const profile = AudioTrainingProfile(
      difficulty: TrainingDifficulty.standard,
      volume: 1,
      questionSeed: 1,
      audioSeed: 1,
    );

    player.setTrainingProfile(profile);
    await player.startPlay();

    expect(engine.startNoiseBedCalls, 1);
    expect(engine.noiseBedVolume, TrainingDifficulty.standard.noiseBedLevel);
    expect(engine.noiseBedPcm, isNotNull);

    player.stopPlay();
    expect(engine.stopNoiseBedCalls, greaterThanOrEqualTo(1));
  });

  test('the bed stays outside the segment queue', () async {
    final engine = _FakeNoiseEngine();
    final player = AudioPlayer(engine: engine);
    const profile = AudioTrainingProfile(
      difficulty: TrainingDifficulty.advanced,
      volume: 1,
      questionSeed: 1,
      audioSeed: 1,
    );

    player.setTrainingProfile(profile);
    await player.startPlay();

    expect(player.isPlaying(), isFalse);
    expect(engine.segments, isEmpty);
  });
}

class _FakeNoiseEngine implements AudioEngine {
  final List<Object> segments = <Object>[];
  Uint8List? noiseBedPcm;
  double noiseBedVolume = 0;
  int startNoiseBedCalls = 0;
  int stopNoiseBedCalls = 0;

  @override
  bool get isInitialized => true;

  @override
  AudioSegment? createSegment(Uint8List pcm) {
    segments.add(pcm);
    return null;
  }

  @override
  Future<void> startNoiseBed(Uint8List pcm, {double volume = 0.0}) async {
    startNoiseBedCalls++;
    noiseBedPcm = pcm;
    noiseBedVolume = volume;
  }

  @override
  void setNoiseBedVolume(double volume) {
    noiseBedVolume = volume;
  }

  @override
  Future<void> stopNoiseBed() async {
    stopNoiseBedCalls++;
  }
}
