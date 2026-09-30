import 'dart:async';
import 'dart:typed_data';

import 'package:ssb_runner/audio/audio_engine.dart';
import 'package:ssb_runner/logging/app_logger.dart';

/// Plays short PCM segments sequentially.
///
/// Segments added with `isResetCurrentStream: false` are queued and played
/// after the current one; `isResetCurrentStream: true` interrupts and replaces
/// the queue. Completion is driven by [AudioSegment.finished] instead of by
/// polling buffer sizes or stream time. That matters because flutter_soloud
/// 5.x parks the output device after 500 ms without an active voice, which used
/// to freeze the old time-based "still playing" check and stall the state
/// machine.
class AudioPlayer {
  AudioPlayer({
    AudioEngine engine = const SoLoudAudioEngine(),
    Duration Function(int byteLength)? estimateDuration,
    Duration watchdogMargin = const Duration(seconds: 3),
  }) : _engine = engine,
       _estimateDuration = estimateDuration ?? _defaultEstimateDuration,
       _watchdogMargin = watchdogMargin;

  final AudioEngine _engine;
  final Duration Function(int byteLength) _estimateDuration;
  final Duration _watchdogMargin;

  final List<_PendingSegment> _pending = <_PendingSegment>[];
  _ActiveSegment? _active;

  /// Bumped whenever the current segment is superseded, so a late completion
  /// event from an already replaced segment is ignored.
  int _generation = 0;

  bool _stopped = true;

  bool get isStarted => !_stopped;

  Future<void> startPlay() async {
    _reset();
    _stopped = false;
  }

  void stopPlay() {
    _reset();
    _stopped = true;
  }

  /// Drops everything queued or playing.
  void resetStream() {
    _reset();
  }

  bool isPlaying() => _active != null || _pending.isNotEmpty;

  bool isMePlaying() => _active?.isMyAudio ?? false;

  void addAudioData(
    Uint8List pcmData, {
    bool isResetCurrentStream = false,
    bool isMyAudio = false,
  }) {
    if (_stopped || pcmData.isEmpty) {
      return;
    }

    if (isResetCurrentStream) {
      _reset();
    }

    _pending.add(_PendingSegment(pcmData, isMyAudio));
    _pump();
  }

  void _reset() {
    _generation++;
    _pending.clear();

    final active = _active;
    _active = null;
    active?.dispose(stopVoice: true);
  }

  void _pump() {
    if (_stopped || _active != null || _pending.isEmpty) {
      return;
    }

    _startSegment(_pending.removeAt(0));
  }

  void _startSegment(_PendingSegment segment) {
    if (!_engine.isInitialized) {
      log.warn(
        'audio engine not initialized, dropping segment',
        tag: 'audio.player',
      );
      return;
    }

    AudioSegment? audioSegment;
    try {
      audioSegment = _engine.createSegment(segment.pcm);
    } catch (error, stackTrace) {
      log.error(
        'failed to queue audio segment',
        tag: 'audio.player',
        error: error,
        stackTrace: stackTrace,
      );
      return;
    }

    if (audioSegment == null) {
      log.warn(
        'audio engine could not create a segment, dropping it',
        tag: 'audio.player',
      );
      return;
    }

    final generation = ++_generation;
    final active = _ActiveSegment(
      audioSegment: audioSegment,
      isMyAudio: segment.isMyAudio,
    );
    _active = active;

    // Listen before start() so even a very short clip cannot be missed.
    active.finishedSubscription = audioSegment.finished.listen(
      (_) => _onSegmentFinished(generation),
    );

    // Safety net: never leave the queue stuck if the engine fails to report
    // the voice ending.
    active.watchdog = Timer(
      _estimateDuration(segment.pcm.lengthInBytes) + _watchdogMargin,
      () => _onSegmentFinished(generation),
    );

    try {
      audioSegment.start();
    } catch (error, stackTrace) {
      log.error(
        'failed to play audio segment',
        tag: 'audio.player',
        error: error,
        stackTrace: stackTrace,
      );
      _onSegmentFinished(generation);
      return;
    }

    if (!audioSegment.hasVoice) {
      // `start()` could not allocate a voice (e.g. the active voice cap was
      // reached), so no completion event will arrive.
      log.warn(
        'audio voice could not be allocated, skipping segment',
        tag: 'audio.player',
      );
      _onSegmentFinished(generation);
    }
  }

  void _onSegmentFinished(int generation) {
    if (generation != _generation) {
      return;
    }

    final active = _active;
    _active = null;
    active?.dispose();

    _pump();
  }
}

/// The app's audio is 16-bit mono PCM at 24 kHz.
Duration _defaultEstimateDuration(int byteLength) {
  final sampleCount = byteLength ~/ 2;
  return Duration(microseconds: sampleCount * 1000000 ~/ 24000);
}

class _PendingSegment {
  const _PendingSegment(this.pcm, this.isMyAudio);

  final Uint8List pcm;
  final bool isMyAudio;
}

class _ActiveSegment {
  _ActiveSegment({required this.audioSegment, required this.isMyAudio});

  final AudioSegment audioSegment;
  final bool isMyAudio;

  Timer? watchdog;
  StreamSubscription<void>? finishedSubscription;

  void dispose({bool stopVoice = false}) {
    watchdog?.cancel();
    watchdog = null;

    finishedSubscription?.cancel();
    finishedSubscription = null;

    if (stopVoice) {
      audioSegment.stop().catchError((_) {});
    }

    audioSegment.dispose().catchError((_) {});
  }
}
