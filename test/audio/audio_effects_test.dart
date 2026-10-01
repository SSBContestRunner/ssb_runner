import 'dart:math';
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

  test('in-signal noise is band-limited to the SSB passband', () {
    // Silence in: the output is only the added SNR noise, so its spectrum is
    // exactly the shaper's response.
    final output = AudioTrainingEffects(_advanced).apply(_silence());
    final low = _bandPower(output, 80, 200);
    final mid = _bandPower(output, 800, 1600);
    final high = _bandPower(output, 6000, 9000);

    expect(mid, greaterThan(low * 2));
    expect(mid, greaterThan(high * 4));
  });

  test('in-signal noise keeps the in-band level it replaced', () {
    final output = AudioTrainingEffects(_advanced).apply(_silence());
    // Uniform white on [-1, 1] scaled by snrNoise, reduced to the part of its
    // power that falls inside the 300–2700 Hz passband.
    final expected = TrainingDifficulty.advanced.snrNoise *
        32767 *
        (1 / sqrt(3)) *
        sqrt((2700 - 300) / (24000 / 2));
    expect(_rms(output), closeTo(expected, expected * 0.25));
  });
}

Uint8List _silence([int samples = 24000]) => Uint8List(samples * 2);

double _rms(Uint8List pcm) {
  final data = ByteData.sublistView(pcm);
  var sumSquares = 0.0;
  final count = pcm.length ~/ 2;
  for (var index = 0; index < count; index++) {
    final value = data.getInt16(index * 2, Endian.little).toDouble();
    sumSquares += value * value;
  }
  return sqrt(sumSquares / count);
}

/// Average Goertzel power across a band, enough to compare the shaped noise
/// spectrum without pulling in an FFT.
double _bandPower(Uint8List pcm, double lowHz, double highHz) {
  const steps = 24;
  const sampleRate = 24000.0;
  final data = ByteData.sublistView(pcm);
  final count = pcm.length ~/ 2;
  var total = 0.0;
  for (var step = 0; step < steps; step++) {
    final frequency = lowHz + (highHz - lowHz) * step / (steps - 1);
    total += _goertzel(data, count, frequency / sampleRate);
  }
  return total / steps;
}

double _goertzel(ByteData data, int count, double normalizedFrequency) {
  final coefficient = 2 * cos(2 * pi * normalizedFrequency);
  var s1 = 0.0;
  var s2 = 0.0;
  for (var index = 0; index < count; index++) {
    final s0 = data.getInt16(index * 2, Endian.little) + coefficient * s1 - s2;
    s2 = s1;
    s1 = s0;
  }
  return s1 * s1 + s2 * s2 - coefficient * s1 * s2;
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
  Future<bool> startNoiseBed(Uint8List pcm, {double volume = 0.0}) async => true;

  @override
  void setNoiseBedVolume(double volume) {}

  @override
  void fadeNoiseBedVolume(double volume, Duration time) {}

  @override
  Future<void> stopNoiseBed() async {}
}
