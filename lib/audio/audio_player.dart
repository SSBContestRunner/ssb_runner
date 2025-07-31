import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:ssb_runner/main.dart';

class AudioPlayer {
  AudioSource? _audioSource;
  SoundHandle? _handle;

  final _isMyAudioMap = <int, bool>{};

  bool get isStarted {
    return _handle != null;
  }

  Future<void> startPlay() async {
    final audioSource = _createAudioSource();
    _audioSource = audioSource;
    _handle = await SoLoud.instance.play(audioSource);
  }

  AudioSource _createAudioSource() {
    return SoLoud.instance.setBufferStream(
      bufferingType: BufferingType.released,
      channels: Channels.mono,
      bufferingTimeNeeds: 0.1,
    );
  }

  void stopPlay() {
    final handleVal = _handle;
    if (handleVal == null) {
      return;
    }
    _isMyAudioMap.clear();
    SoLoud.instance.stop(handleVal);

    final audioSource = _audioSource;
    if (audioSource != null) {
      SoLoud.instance.resetBufferStream(audioSource);
      SoLoud.instance.disposeSource(audioSource);
    }

    _audioSource = null;
    _handle = null;
  }

  bool isPlaying() {
    final audioSource = _audioSource;
    if (_handle == null || audioSource == null) {
      return false;
    }

    return SoLoud.instance.getBufferSize(audioSource) > 0;
  }

  bool isMePlaying() {
    final audioSource = _audioSource;

    if (audioSource == null) {
      return false;
    }

    final alreadyPlayedTime = SoLoud.instance.getStreamTimeConsumed(
      audioSource,
    );

    logger.d(
      'alreadyPlayedTime: ${alreadyPlayedTime.inMilliseconds}, _isMyAudioPlaying: $_isMyAudioMap',
    );

    final isOperationAudio =
        _isMyAudioMap.entries.firstWhereOrNull((entry) {
          return entry.key > alreadyPlayedTime.inMilliseconds;
        })?.value ==
        true;

    return isPlaying() && isOperationAudio;
  }

  void resetStream() {
    final audioSource = _audioSource;

    if (audioSource == null) {
      return;
    }

    SoLoud.instance.resetBufferStream(audioSource);
  }

  void addAudioData(
    Uint8List pcmData, {
    bool isResetCurrentStream = false,
    bool isMyAudio = false,
  }) {
    final handleVal = _handle;

    if (handleVal == null) {
      return;
    }

    final audioSource = _audioSource;

    if (audioSource == null) {
      return;
    }

    if (isResetCurrentStream) {
      SoLoud.instance.resetBufferStream(audioSource);
      _isMyAudioMap.clear();
    }

    final alreadyPlayedDuration = SoLoud.instance.getStreamTimeConsumed(
      audioSource,
    );

    SoLoud.instance.addAudioDataStream(audioSource, pcmData);

    final currentBufferedDuration = SoLoud.instance.getLength(audioSource);

    final taggedTime =
        alreadyPlayedDuration.inMilliseconds +
        currentBufferedDuration.inMilliseconds +
        3200;
    _isMyAudioMap[taggedTime] = isMyAudio;
  }
}
