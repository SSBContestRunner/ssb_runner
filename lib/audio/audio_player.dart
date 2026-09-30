import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:ssb_runner/logging/app_logger.dart';

/// Plays short PCM segments sequentially.
///
/// Every segment is played by its own single-use [AudioSource] (a
/// `BufferingType.released` buffer stream) that is marked complete with
/// [SoLoud.setDataIsEnded]. Completion is driven by the engine's
/// [AudioSource.allInstancesFinished] event instead of by polling buffer sizes
/// or stream time. That matters because flutter_soloud 5.x parks the output
/// device after 500 ms without an active voice, which used to freeze the old
/// time-based "still playing" check and stall the state machine.
///
/// Segments added with `isResetCurrentStream: false` are queued and played
/// after the current one; `isResetCurrentStream: true` interrupts and replaces
/// the queue.
class AudioPlayer {
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
    if (!SoLoud.instance.isInitialized) {
      log.warn(
        'audio engine not initialized, dropping segment',
        tag: 'audio.player',
      );
      return;
    }

    final source = SoLoud.instance.setBufferStream(
      bufferingType: BufferingType.released,
      channels: Channels.mono,
      bufferingTimeNeeds: 0.1,
    );

    try {
      SoLoud.instance.addAudioDataStream(source, segment.pcm);
      SoLoud.instance.setDataIsEnded(source);
    } catch (error, stackTrace) {
      log.error(
        'failed to queue audio segment',
        tag: 'audio.player',
        error: error,
        stackTrace: stackTrace,
      );
      SoLoud.instance.disposeSource(source).catchError((_) {});
      return;
    }

    final generation = ++_generation;
    final active = _ActiveSegment(source: source, isMyAudio: segment.isMyAudio);
    _active = active;

    // Listen before play() so even a very short clip cannot be missed.
    active.finishedSubscription = source.allInstancesFinished.listen(
      (_) => _onSegmentFinished(generation),
    );

    // Safety net: never leave the queue stuck if the engine fails to report
    // the voice ending.
    active.watchdog = Timer(
      _estimateDuration(segment.pcm.lengthInBytes) + const Duration(seconds: 3),
      () => _onSegmentFinished(generation),
    );

    try {
      active.handle = SoLoud.instance.play(source);
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

    if (source.handles.isEmpty) {
      // `play()` could not allocate a voice (e.g. the active voice cap was
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

  /// The app's audio is 16-bit mono PCM at 24 kHz.
  Duration _estimateDuration(int byteLength) {
    final sampleCount = byteLength ~/ 2;
    return Duration(microseconds: sampleCount * 1000000 ~/ 24000);
  }
}

class _PendingSegment {
  const _PendingSegment(this.pcm, this.isMyAudio);

  final Uint8List pcm;
  final bool isMyAudio;
}

class _ActiveSegment {
  _ActiveSegment({required this.source, required this.isMyAudio});

  final AudioSource source;
  final bool isMyAudio;

  SoundHandle? handle;
  Timer? watchdog;
  StreamSubscription<void>? finishedSubscription;

  void dispose({bool stopVoice = false}) {
    watchdog?.cancel();
    watchdog = null;

    finishedSubscription?.cancel();
    finishedSubscription = null;

    final handleVal = handle;
    if (stopVoice && handleVal != null) {
      SoLoud.instance.stop(handleVal).catchError((_) {});
    }

    SoLoud.instance.disposeSource(source).catchError((_) {});
  }
}
