import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:ssb_runner/audio/pcm_to_wav.dart';

/// A single, already-queued audio segment.
///
/// Implementations wrap the engine's per-segment playback state. [AudioPlayer]
/// subscribes to [finished] before calling [start], so a completion event can
/// never be missed.
abstract interface class AudioSegment {
  /// Emits once when the segment has finished playing (or was stopped).
  Stream<void> get finished;

  /// Whether a voice was actually allocated by [start].
  bool get hasVoice;

  /// Starts playback. Called exactly once.
  void start();

  /// Stops the voice, if one is playing.
  Future<void> stop();

  /// Releases the underlying resources.
  Future<void> dispose();
}

/// Creates and plays short PCM segments.
///
/// The indirection keeps [AudioPlayer]'s queueing logic independent of the
/// native engine, which makes it unit-testable.
abstract interface class AudioEngine {
  bool get isInitialized;

  /// Queues [pcm] into a new single-use segment, or returns null when the
  /// segment could not be created.
  AudioSegment? createSegment(Uint8List pcm);

  /// Starts a constant, looping receiver noise bed.
  ///
  /// [pcm] is raw 24 kHz mono 16-bit little-endian PCM; the engine wraps it in
  /// a WAV container so it can be loaded as a normal, reliably loopable source.
  /// Returns true when a looping voice was started, and false when the engine
  /// was not ready, in which case the caller may retry.
  ///
  /// The bed lives outside the segment queue on purpose: if it were queued,
  /// silent gaps would look like "incoming audio playing" and would distort
  /// [AudioPlayer.isPlaying], the watchdog and the state machine timing
  /// (design §5.1).
  Future<bool> startNoiseBed(Uint8List pcm, {double volume = 0.0});

  /// Adjusts the bed gain immediately. A no-op when no bed is active.
  void setNoiseBedVolume(double volume);

  /// Smoothly fades the bed to [volume] over [time].
  ///
  /// Used for the AGC-style ducking while a signal is being received and for
  /// the release back to the idle floor afterwards.
  void fadeNoiseBedVolume(double volume, Duration time);

  /// Stops and releases the noise bed.
  Future<void> stopNoiseBed();
}

/// [AudioEngine] backed by flutter_soloud.
///
/// Each segment is a `BufferingType.released` buffer stream that is marked
/// complete with [SoLoud.setDataIsEnded] and played exactly once. Completion is
/// reported by [AudioSource.allInstancesFinished].
class SoLoudAudioEngine implements AudioEngine {
  SoLoudAudioEngine();

  AudioSource? _noiseSource;
  SoundHandle? _noiseHandle;

  /// Bumped whenever the bed is (re)started or stopped, so a slow [loadMem]
  /// that loses the race is disposed instead of playing behind a newer bed.
  int _noiseGeneration = 0;

  @override
  bool get isInitialized => SoLoud.instance.isInitialized;

  @override
  AudioSegment? createSegment(Uint8List pcm) {
    final source = SoLoud.instance.setBufferStream(
      bufferingType: BufferingType.released,
      channels: Channels.mono,
      bufferingTimeNeeds: 0.1,
    );

    try {
      SoLoud.instance.addAudioDataStream(source, pcm);
      SoLoud.instance.setDataIsEnded(source);
    } catch (_) {
      SoLoud.instance.disposeSource(source).catchError((_) {});
      rethrow;
    }

    return _SoLoudAudioSegment(source);
  }

  @override
  Future<bool> startNoiseBed(Uint8List pcm, {double volume = 0.0}) async {
    await stopNoiseBed();
    if (!SoLoud.instance.isInitialized || pcm.isEmpty) {
      return false;
    }

    // A decoded in-memory WAV loops sample-accurately for as long as the
    // session runs. A `BufferingType.released` stream must not be used here:
    // it frees data as it plays, so the bed would go silent after one pass.
    final generation = ++_noiseGeneration;
    try {
      final source = await SoLoud.instance.loadMem(
        'noise_bed.wav',
        pcm16ToWav(pcm),
      );

      if (generation != _noiseGeneration || !SoLoud.instance.isInitialized) {
        await SoLoud.instance.disposeSource(source).catchError((_) {});
        return false;
      }

      final handle = SoLoud.instance.play(
        source,
        looping: true,
        volume: volume,
      );
      if (source.handles.isEmpty) {
        await SoLoud.instance.disposeSource(source).catchError((_) {});
        return false;
      }

      _noiseSource = source;
      _noiseHandle = handle;
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void setNoiseBedVolume(double volume) {
    final handle = _noiseHandle;
    if (handle == null || !SoLoud.instance.isInitialized) {
      return;
    }
    SoLoud.instance.setVolume(handle, volume);
  }

  @override
  void fadeNoiseBedVolume(double volume, Duration time) {
    final handle = _noiseHandle;
    if (handle == null || !SoLoud.instance.isInitialized) {
      return;
    }
    try {
      SoLoud.instance.fadeVolume(handle, volume, time);
    } catch (_) {
      // A fade on a just-stopped voice is harmless; the next duck/release
      // recomputes the target anyway.
    }
  }

  @override
  Future<void> stopNoiseBed() async {
    _noiseGeneration++;
    final handle = _noiseHandle;
    final source = _noiseSource;
    _noiseHandle = null;
    _noiseSource = null;

    if (handle != null && SoLoud.instance.isInitialized) {
      await SoLoud.instance.stop(handle).catchError((_) {});
    }
    if (source != null && SoLoud.instance.isInitialized) {
      await SoLoud.instance.disposeSource(source).catchError((_) {});
    }
  }
}

class _SoLoudAudioSegment implements AudioSegment {
  _SoLoudAudioSegment(this._source);

  final AudioSource _source;
  SoundHandle? _handle;

  @override
  Stream<void> get finished => _source.allInstancesFinished;

  @override
  bool get hasVoice => _source.handles.isNotEmpty;

  @override
  void start() {
    _handle = SoLoud.instance.play(_source);
  }

  @override
  Future<void> stop() {
    final handle = _handle;
    if (handle == null) {
      return Future<void>.value();
    }
    return SoLoud.instance.stop(handle);
  }

  @override
  Future<void> dispose() => SoLoud.instance.disposeSource(_source);
}
