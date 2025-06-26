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

  void addPcmData(Uint8List pcmData) {
    SoLoud.instance.addAudioDataStream(_audioSource, pcmData);
  }

  void stopPlay() {
    final handleVal = _handle;
    if (handleVal != null) {
      SoLoud.instance.stop(handleVal);
      SoLoud.instance.resetBufferStream(_audioSource);
      _handle = null;
    }
  }
}
