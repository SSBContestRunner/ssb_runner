import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/audio/audio_engine.dart';
import 'package:ssb_runner/audio/audio_player.dart';

Uint8List _pcm([int length = 8]) => Uint8List(length);

void main() {
  late FakeAudioEngine engine;
  late AudioPlayer player;

  setUp(() {
    engine = FakeAudioEngine();
    player = AudioPlayer(engine: engine);
  });

  tearDown(() {
    player.stopPlay();
  });

  test('does nothing until startPlay is called', () {
    player.addAudioData(_pcm());
    expect(engine.segments, isEmpty);
    expect(player.isPlaying(), isFalse);
  });

  test('plays the first segment immediately after startPlay', () {
    player.startPlay();
    player.addAudioData(_pcm());

    expect(engine.segments, hasLength(1));
    expect(engine.segments.single.started, isTrue);
    expect(player.isPlaying(), isTrue);
  });

  test('queues later segments until the active one finishes', () async {
    player.startPlay();
    player.addAudioData(_pcm());
    player.addAudioData(_pcm());

    expect(engine.segments, hasLength(1));
    expect(player.isPlaying(), isTrue);

    engine.segments.single.finish();
    await pumpEventQueue();

    expect(engine.segments, hasLength(2));
    expect(engine.segments[1].started, isTrue);
    expect(player.isPlaying(), isTrue);
  });

  test('isPlaying becomes false once the queue drains', () async {
    player.startPlay();
    player.addAudioData(_pcm());

    engine.segments.single.finish();
    await pumpEventQueue();

    expect(player.isPlaying(), isFalse);
  });

  test('reset interrupts the active segment and drops the queue', () async {
    player.startPlay();
    player.addAudioData(_pcm()); // A
    player.addAudioData(_pcm()); // B, queued behind A
    player.addAudioData(_pcm(), isResetCurrentStream: true); // C, interrupts

    expect(engine.segments, hasLength(2)); // A and C only
    expect(engine.segments[0].stopped, isTrue);
    expect(engine.segments[0].disposed, isTrue);
    expect(engine.segments[1].started, isTrue);

    // A's late completion must not advance the queue.
    engine.segments[0].finish();
    await pumpEventQueue();
    expect(engine.segments, hasLength(2));
    expect(engine.segments[1].disposed, isFalse);
  });

  test('isMePlaying reflects the active segment', () async {
    player.startPlay();
    player.addAudioData(_pcm(), isMyAudio: false);
    expect(player.isMePlaying(), isFalse);

    player.addAudioData(_pcm(), isMyAudio: true);
    engine.segments[0].finish();
    await pumpEventQueue();

    expect(player.isMePlaying(), isTrue);
  });

  test('resetStream stops everything', () {
    player.startPlay();
    player.addAudioData(_pcm());
    player.resetStream();

    expect(player.isPlaying(), isFalse);
    expect(engine.segments.single.stopped, isTrue);
    expect(engine.segments.single.disposed, isTrue);
  });

  test('stopPlay drops queued work and ignores later adds', () {
    player.startPlay();
    player.addAudioData(_pcm());
    player.stopPlay();
    player.addAudioData(_pcm());

    expect(engine.segments, hasLength(1));
    expect(player.isPlaying(), isFalse);
  });

  test('skips a segment when the engine allocates no voice', () async {
    engine.hasVoice = (index) => index != 0; // only the first allocation fails
    player.startPlay();
    player.addAudioData(_pcm()); // A, no voice
    player.addAudioData(_pcm()); // B, has a voice

    await pumpEventQueue();

    expect(engine.segments, hasLength(2));
    expect(engine.segments[0].started, isTrue);
    expect(engine.segments[1].started, isTrue);
    expect(player.isPlaying(), isTrue);
  });

  test('watchdog advances when a completion event never arrives', () async {
    player = AudioPlayer(
      engine: engine,
      estimateDuration: (_) => Duration.zero,
      watchdogMargin: Duration.zero,
    );
    player.startPlay();
    player.addAudioData(_pcm()); // A never reports completion
    player.addAudioData(_pcm()); // B

    expect(engine.segments, hasLength(1));

    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(engine.segments, hasLength(2));
    expect(engine.segments[1].started, isTrue);
  });
}

class FakeAudioEngine implements AudioEngine {
  final List<FakeAudioSegment> segments = <FakeAudioSegment>[];

  @override
  bool isInitialized = true;

  /// Whether the segment at [index] should get a voice.
  bool Function(int index) hasVoice = (_) => true;

  @override
  AudioSegment? createSegment(Uint8List pcm) {
    final index = segments.length;
    final segment = FakeAudioSegment(hasVoice: hasVoice(index));
    segments.add(segment);
    return segment;
  }
}

class FakeAudioSegment implements AudioSegment {
  FakeAudioSegment({required this.hasVoice});

  final StreamController<void> _finished = StreamController<void>.broadcast();

  @override
  bool hasVoice;

  bool started = false;
  bool stopped = false;
  bool disposed = false;

  @override
  Stream<void> get finished => _finished.stream;

  @override
  void start() {
    started = true;
  }

  @override
  Future<void> stop() async {
    stopped = true;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
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
