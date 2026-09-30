import 'dart:async';
import 'dart:typed_data';

import 'package:ssb_runner/audio/audio_engine.dart';
import 'package:ssb_runner/audio/noise_bed.dart';
import 'package:ssb_runner/logging/app_logger.dart';
import 'package:ssb_runner/training/training_profile.dart';

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
    AudioEngine? engine,
    Duration Function(int byteLength)? estimateDuration,
    Duration watchdogMargin = const Duration(seconds: 3),
  }) : _engine = engine ?? SoLoudAudioEngine(),
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

  AudioTrainingProfile? _trainingProfile;
  AudioTrainingEffects? _effects;
  Uint8List? _noiseBedPcm;

  /// A bed start that is still wanted but has not succeeded yet, for example
  /// because the engine was not initialized. It is retried on the next audio
  /// pump so a whole session cannot silently lose its floor.
  bool _bedWanted = false;
  bool _bedStarting = false;

  /// AGC model: a received signal pulls the floor down, and the floor recovers
  /// after the transmission ends. Transmitting mutes the receiver, so the
  /// operator's own audio ducks the floor all the way down.
  static const Duration _bedDuckAttack = Duration(milliseconds: 30);
  static const Duration _bedDuckRelease = Duration(milliseconds: 350);
  static const double _receivedSignalDuck = 0.45;
  static const double _ownSignalDuck = 0.0;

  bool get isStarted => !_stopped;

  /// Installs (or clears) the per-session training profile.
  ///
  /// Only incoming stations are processed; the operator's own audio is queued
  /// untouched. The receiver noise bed lives outside the segment queue and is
  /// started or stopped here so it never disturbs [isPlaying].
  void setTrainingProfile(AudioTrainingProfile? profile) {
    _trainingProfile = profile;
    _effects = profile == null ? null : AudioTrainingEffects(profile);
    _noiseBedPcm = profile == null
        ? null
        : generateNoiseBedPcm(
            seed: profile.audioSeed,
            qrnPerSecond: profile.qrnRate,
          );

    if (!isStarted) {
      _bedWanted = false;
      return;
    }
    if (profile == null) {
      _bedWanted = false;
      _engine.stopNoiseBed().catchError((_) {});
    } else {
      _bedWanted = true;
      _ensureNoiseBed();
    }
  }

  /// Realtime bed gain adjustment from the settings page.
  void setNoiseBedVolume(double volume) {
    _engine.setNoiseBedVolume(volume);
  }

  /// Starts the bed when one is wanted and the engine is ready.
  void _ensureNoiseBed() {
    if (!_bedWanted || _bedStarting || !_engine.isInitialized) {
      return;
    }
    unawaited(_startNoiseBed());
  }

  Future<void> _startNoiseBed() async {
    final pcm = _noiseBedPcm;
    final profile = _trainingProfile;
    if (pcm == null || profile == null) {
      _bedWanted = false;
      return;
    }

    _bedStarting = true;
    final started = await _engine.startNoiseBed(
      pcm,
      volume: profile.noiseBedLevel,
    );
    _bedStarting = false;

    if (!_bedWanted) {
      return;
    }
    // On failure keep `_bedWanted` set and retry on the next pump.
    _bedWanted = !started;
  }

  /// Ducks the floor as if an AGC were reacting to the signal being played.
  void _duckBedFor(bool isMyAudio) {
    final profile = _trainingProfile;
    if (profile == null) {
      return;
    }
    final target =
        profile.noiseBedLevel * (isMyAudio ? _ownSignalDuck : _receivedSignalDuck);
    _engine.fadeNoiseBedVolume(target, _bedDuckAttack);
  }

  /// Releases the floor back to the idle level after a transmission.
  void _releaseBed() {
    final profile = _trainingProfile;
    if (profile == null) {
      return;
    }
    _engine.fadeNoiseBedVolume(profile.noiseBedLevel, _bedDuckRelease);
  }

  Future<void> startPlay() async {
    _reset();
    _stopped = false;
    if (_trainingProfile != null) {
      _bedWanted = true;
      _ensureNoiseBed();
    }
  }

  void stopPlay() {
    _reset();
    _stopped = true;
    _bedWanted = false;
    _engine.stopNoiseBed().catchError((_) {});
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
    _ensureNoiseBed();

    if (isResetCurrentStream) {
      _reset();
    }

    final effects = _effects;
    final processed = !isMyAudio && effects != null
        ? effects.apply(pcmData)
        : pcmData;

    _pending.add(_PendingSegment(processed, isMyAudio));
    _pump();
  }

  void _reset() {
    _generation++;
    _pending.clear();

    final active = _active;
    _active = null;
    active?.dispose(stopVoice: true);

    if (!_stopped) {
      _releaseBed();
    }
  }

  void _pump() {
    _ensureNoiseBed();
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
    _duckBedFor(segment.isMyAudio);

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

    // Restore the idle floor once the queue has drained; a segment started by
    // `_pump()` already ducked it again.
    if (_active == null) {
      _releaseBed();
    }
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
