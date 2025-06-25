import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';

class AudioPlayer {
  AudioSource? _audioSource;

  bool get isStarted {
    return _audioSource != null;
  }

  void startPlay() {
    _audioSource = SoLoud.instance.setBufferStream(channels: Channels.mono);
  }

  void addPcmData(Uint8List pcmData) {
    final audioSourceVal = _audioSource;
    if (audioSourceVal != null) {
      SoLoud.instance.addAudioDataStream(audioSourceVal, pcmData);
    }
  }

  void stopPlay() {
    final audioSourceVal = _audioSource;
    if (audioSourceVal != null) {
      SoLoud.instance.resetBufferStream(audioSourceVal);
    }

    _audioSource = null;
  }
}
