import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';

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
}

/// [AudioEngine] backed by flutter_soloud.
///
/// Each segment is a `BufferingType.released` buffer stream that is marked
/// complete with [SoLoud.setDataIsEnded] and played exactly once. Completion is
/// reported by [AudioSource.allInstancesFinished].
class SoLoudAudioEngine implements AudioEngine {
  const SoLoudAudioEngine();

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
