import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:ssb_runner/audio/audio_engine.dart';
import 'package:ssb_runner/audio/payload_to_audio.dart';
import 'package:ssb_runner/logging/app_logger.dart';

/// Plays a short sample so the operator can confirm the output is audible.
///
/// Uses [AudioEngine.createSegment] directly instead of the [AudioPlayer] queue,
/// because no session is running while the settings drawer is open. The sample
/// carries the asset's own level: the in-app "receiver volume" is a PCM-layer
/// gain inside a training profile and deliberately not applied here
/// (design §5 E2, D6).
class AudioCheckService {
  AudioCheckService({AudioEngine? engine})
    : _engine = engine ?? SoLoudAudioEngine();

  /// A fixed, already shipped clip: it also proves the asset decode path works.
  static const String _sampleAsset = 'Global/Common/CQ.wav';

  /// Upper bound for one sample; the clip is ~0.8 s.
  static const Duration _playbackTimeout = Duration(seconds: 3);

  final AudioEngine _engine;
  bool _playing = false;

  bool get isPlaying => _playing;

  /// Plays the sample and resolves once it finished.
  ///
  /// Returns false when nothing could be played, in which case the caller
  /// reports the failure through the shared notification.
  Future<bool> play() async {
    if (_playing) return false;
    _playing = true;

    AudioSegment? segment;
    try {
      if (!_engine.isInitialized) return false;

      var pcm = await loadExactAssetsWavPcmData(_sampleAsset);
      if (pcm.isEmpty) {
        // The asset is part of the bundle, so this only happens on a broken
        // install; a generated tone still confirms that audio works.
        pcm = generateTestTonePcm();
      }
      if (pcm.isEmpty) return false;

      segment = _engine.createSegment(pcm);
      if (segment == null) return false;

      // Subscribe first, like AudioPlayer does, so a short clip cannot finish
      // before anyone listens.
      final finished = segment.finished.first;
      segment.start();
      if (!segment.hasVoice) return false;

      await finished.timeout(_playbackTimeout, onTimeout: () {});
      return true;
    } catch (error, stackTrace) {
      log.warn(
        'audio check playback failed',
        tag: 'audio.check',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    } finally {
      try {
        await segment?.dispose();
      } catch (_) {
        // The voice is already gone on a failed start.
      }
      _playing = false;
    }
  }
}

/// Generates the fallback sample: 700 Hz then 1000 Hz, 30 ms fades.
///
/// 24 kHz mono 16-bit little-endian, the format every other segment uses.
Uint8List generateTestTonePcm({
  int sampleRate = 24000,
  double durationSeconds = 0.8,
}) {
  const firstFrequency = 700.0;
  const secondFrequency = 1000.0;
  const amplitude = 0.25;
  const fadeSeconds = 0.03;

  final sampleCount = (sampleRate * durationSeconds).round();
  if (sampleCount <= 0) return Uint8List(0);

  final fadeSamples = max(1, (sampleRate * fadeSeconds).round());
  final data = ByteData(sampleCount * 2);

  for (var index = 0; index < sampleCount; index++) {
    final isSecondTone = index >= sampleCount ~/ 2;
    final frequency = isSecondTone ? secondFrequency : firstFrequency;
    final frequencyIndex = isSecondTone ? index - sampleCount ~/ 2 : index;
    final seconds = frequencyIndex / sampleRate;

    // Fade in at the start and out at the end of each tone so neither half
    // clicks.
    final positionInHalf = frequencyIndex;
    final halfLength = isSecondTone
        ? sampleCount - sampleCount ~/ 2
        : sampleCount ~/ 2;
    final fadeIn = min(1.0, positionInHalf / fadeSamples);
    final fadeOut = min(1.0, (halfLength - positionInHalf) / fadeSamples);
    final envelope = min(fadeIn, fadeOut);

    final value = sin(2 * pi * frequency * seconds) * amplitude * envelope;
    data.setInt16(index * 2, (value * 32767).round(), Endian.little);
  }

  return data.buffer.asUint8List();
}
