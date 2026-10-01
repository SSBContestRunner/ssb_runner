import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/audio/audio_engine.dart';
import 'package:ssb_runner/audio/audio_player.dart';
import 'package:ssb_runner/audio/noise_bed.dart';
import 'package:ssb_runner/training/training_profile.dart';

const int _sampleRate = 24000;

void main() {
  test('noise bed generation is deterministic for a seed', () {
    const duration = Duration(seconds: 2);
    final first = generateNoiseBedPcm(seed: 42, duration: duration);
    final second = generateNoiseBedPcm(seed: 42, duration: duration);
    final other = generateNoiseBedPcm(seed: 43, duration: duration);

    expect(first, second);
    expect(first, isNot(equals(other)));
    expect(first.length, 2 * _sampleRate * 2); // 2 s of 16-bit mono
  });

  test('noise bed sits in the bright SSB audio passband', () {
    final pcm = generateNoiseBedPcm(
      seed: 7,
      duration: const Duration(seconds: 2),
      qrnPerSecond: 0,
    );
    final low = _bandPower(pcm, 80, 200);
    final mid = _bandPower(pcm, 800, 1600);
    final upper = _bandPower(pcm, 1800, 2600);
    final high = _bandPower(pcm, 6000, 9000);

    // 2nd-order high-pass removes the rumble the old one-pole low-pass left.
    expect(mid, greaterThan(low * 2));
    // 4th-order low-pass removes the hiss above the SSB filter.
    expect(mid, greaterThan(high * 4));
    // The passband stays broad and bright up to ~2700 Hz.
    expect(upper, greaterThan(mid / 6));
  });

  test('noise bed loop seam is continuous', () {
    final pcm = generateNoiseBedPcm(
      seed: 5,
      duration: const Duration(seconds: 2),
    );
    final data = ByteData.sublistView(pcm);
    final count = pcm.length ~/ 2;
    var meanStep = 0.0;
    for (var index = 1; index < count; index++) {
      meanStep += (data.getInt16(index * 2, Endian.little) -
              data.getInt16((index - 1) * 2, Endian.little))
          .abs();
    }
    meanStep /= (count - 1);
    final seam = (data.getInt16(0, Endian.little) -
            data.getInt16((count - 1) * 2, Endian.little))
        .abs();
    expect(seam, lessThan(meanStep * 8));
  });

  test('QRN raises the crash peaks above the steady hiss', () {
    final quiet = generateNoiseBedPcm(
      seed: 11,
      duration: const Duration(seconds: 4),
      qrnPerSecond: 0,
    );
    final stormy = generateNoiseBedPcm(
      seed: 11,
      duration: const Duration(seconds: 4),
      qrnPerSecond: 2,
    );
    expect(_peak(stormy), greaterThan(_peak(quiet)));
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

  test('a received signal ducks the bed and finishing releases it', () async {
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

    player.addAudioData(Uint8List(16));
    expect(engine.bedFades, isNotEmpty);
    expect(
      engine.bedFades.last.volume,
      closeTo(profile.noiseBedLevel * 0.45, 1e-9),
    );

    engine.segments.single.finish();
    await pumpEventQueue();
    expect(engine.bedFades.last.volume, closeTo(profile.noiseBedLevel, 1e-9));
  });

  test('an own transmission mutes the bed', () async {
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

    player.addAudioData(Uint8List(16), isMyAudio: true);
    expect(engine.bedFades.last.volume, 0.0);
  });
}

double _peak(Uint8List pcm) {
  final data = ByteData.sublistView(pcm);
  var peak = 0;
  for (var index = 0; index < pcm.length ~/ 2; index++) {
    final value = data.getInt16(index * 2, Endian.little).abs();
    if (value > peak) peak = value;
  }
  return peak.toDouble();
}

/// Average Goertzel power across several frequencies inside a band, which is
/// enough to compare the shaped noise spectrum without pulling in an FFT.
double _bandPower(Uint8List pcm, double lowHz, double highHz) {
  const steps = 24;
  final data = ByteData.sublistView(pcm);
  final count = pcm.length ~/ 2;
  var total = 0.0;
  for (var step = 0; step < steps; step++) {
    final frequency = lowHz + (highHz - lowHz) * step / (steps - 1);
    total += _goertzel(data, count, frequency / _sampleRate);
  }
  return total / steps;
}

double _goertzel(ByteData data, int count, double normalizedFrequency) {
  final omega = 2 * pi * normalizedFrequency;
  final coefficient = 2 * cos(omega);
  var s1 = 0.0;
  var s2 = 0.0;
  for (var index = 0; index < count; index++) {
    final s0 = data.getInt16(index * 2, Endian.little) + coefficient * s1 - s2;
    s2 = s1;
    s1 = s0;
  }
  return s1 * s1 + s2 * s2 - coefficient * s1 * s2;
}

class _FakeNoiseEngine implements AudioEngine {
  final List<_FakeSegment> segments = <_FakeSegment>[];
  Uint8List? noiseBedPcm;
  double noiseBedVolume = 0;
  int startNoiseBedCalls = 0;
  int stopNoiseBedCalls = 0;
  final List<({double volume, Duration time})> bedFades = [];

  @override
  bool get isInitialized => true;

  @override
  AudioSegment? createSegment(Uint8List pcm) {
    final segment = _FakeSegment();
    segments.add(segment);
    return segment;
  }

  @override
  Future<bool> startNoiseBed(Uint8List pcm, {double volume = 0.0}) async {
    startNoiseBedCalls++;
    noiseBedPcm = pcm;
    noiseBedVolume = volume;
    return true;
  }

  @override
  void setNoiseBedVolume(double volume) {
    noiseBedVolume = volume;
  }

  @override
  void fadeNoiseBedVolume(double volume, Duration time) {
    bedFades.add((volume: volume, time: time));
  }

  @override
  Future<void> stopNoiseBed() async {
    stopNoiseBedCalls++;
  }
}

class _FakeSegment implements AudioSegment {
  final StreamController<void> _finished = StreamController<void>.broadcast();

  @override
  Stream<void> get finished => _finished.stream;

  @override
  bool get hasVoice => true;

  @override
  void start() {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    if (!_finished.isClosed) {
      await _finished.close();
    }
  }

  void finish() {
    if (!_finished.isClosed) {
      _finished.add(null);
    }
  }
}
