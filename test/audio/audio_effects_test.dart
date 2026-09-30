import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/audio/audio_engine.dart';
import 'package:ssb_runner/audio/audio_player.dart';
import 'package:ssb_runner/training/training_profile.dart';

Uint8List _pcm([int samples = 60]) {
  final bytes = Uint8List(samples * 2);
  final data = ByteData.sublistView(bytes);
  for (var index = 0; index < samples; index++) {
    data.setInt16(index * 2, (index * 400) - 12000, Endian.little);
  }
  return bytes;
}

const _advanced = AudioTrainingProfile(
  difficulty: TrainingDifficulty.advanced,
  volume: 1,
  questionSeed: 7,
  audioSeed: 7,
);

void main() {
  test('same seed and parameters produce identical bytes', () {
    final first = AudioTrainingEffects(_advanced).apply(_pcm());
    final second = AudioTrainingEffects(_advanced).apply(_pcm());
    expect(first, second);
  });

  test('advanced playback rate shortens the clip', () {
    final input = _pcm();
    final output = AudioTrainingEffects(_advanced).apply(input);
    expect(output.length, lessThan(input.length));
  });

  test('empty input is returned unchanged', () {
    final empty = Uint8List(0);
    expect(AudioTrainingEffects(_advanced).apply(empty), empty);
  });

  test('QSB phase carries across clips instead of restarting', () {
    final effects = AudioTrainingEffects(_advanced);
    expect(effects.phase, 0);

    effects.apply(_pcm());
    expect(effects.phase, greaterThan(0));

    final continued = effects.apply(_pcm());
    final restarted = AudioTrainingEffects(_advanced).apply(_pcm());
    expect(continued, isNot(equals(restarted)));
  });

  test('operator audio is never processed', () {
    final engine = _RecordingEngine();
    final player = AudioPlayer(engine: engine);
    const profile = AudioTrainingProfile(
      difficulty: TrainingDifficulty.advanced,
      volume: 1,
      questionSeed: 1,
      audioSeed: 1,
    );
    player.setTrainingProfile(profile);
    player.startPlay();

    final mine = _pcm();
    final theirs = _pcm();
    player.addAudioData(mine, isMyAudio: true);
    player.addAudioData(theirs, isMyAudio: false);

    expect(engine.createdPcm, hasLength(2));
    expect(engine.createdPcm[0], mine);
    expect(engine.createdPcm[1], isNot(equals(theirs)));
  });
}

class _RecordingEngine implements AudioEngine {
  final List<Uint8List> createdPcm = <Uint8List>[];

  @override
  bool get isInitialized => true;

  @override
  AudioSegment? createSegment(Uint8List pcm) {
    createdPcm.add(pcm);
    return null;
  }

  @override
  Future<void> startNoiseBed(Uint8List pcm, {double volume = 0.0}) async {}

  @override
  void setNoiseBedVolume(double volume) {}

  @override
  Future<void> stopNoiseBed() async {}
}
