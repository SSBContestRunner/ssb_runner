import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';

class AudioPlayer {
  AudioSource? _audioSource;
  SoundHandle? _handle;

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
    );
  }

  void stopPlay() {
    final handleVal = _handle;
    if (handleVal != null) {
      SoLoud.instance.stop(handleVal);

      final audioSource = _audioSource;
      if (audioSource != null) {
        SoLoud.instance.resetBufferStream(audioSource);
        SoLoud.instance.disposeSource(audioSource);
      }

      _audioSource = null;
      _handle = null;
    }
  }

  bool isPlaying() {
    final audioSource = _audioSource;
    if (_handle == null || audioSource == null) {
      return false;
    }

    return SoLoud.instance.getLength(audioSource) > Duration.zero;
  }

  void addAudioData(Uint8List pcmData) {
    final handleVal = _handle;

    if (handleVal == null) {
      return;
    }

    final audioSource = _audioSource;

    if (audioSource != null) {
      SoLoud.instance.addAudioDataStream(audioSource, pcmData);
    }
  }
}
