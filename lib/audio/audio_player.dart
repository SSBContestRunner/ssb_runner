import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';

class AudioPlayer {
  final AudioSource _audioSource = SoLoud.instance.setBufferStream(
    bufferingType: BufferingType.released,
    channels: Channels.mono,
  );

  SoundHandle? _handle;

  bool get isStarted {
    return _handle != null;
  }

  Future<void> startPlay() async {
    _handle = await SoLoud.instance.play(_audioSource);
  }

  void stopPlay() {
    final handleVal = _handle;
    if (handleVal != null) {
      SoLoud.instance.stop(handleVal);
      SoLoud.instance.resetBufferStream(_audioSource);
      _handle = null;
    }
  }

  bool isPlaying() {
    if (_handle == null) {
      return false;
    }

    return SoLoud.instance.getLength(_audioSource) > Duration.zero;
  }

  void resetAndPlay(Uint8List pcmData) {
    final handleVal = _handle;
    if (handleVal == null) {
      return;
    }

    // SoLoud.instance.resetBufferStream(_audioSource);
    SoLoud.instance.addAudioDataStream(_audioSource, pcmData);
  }
}
