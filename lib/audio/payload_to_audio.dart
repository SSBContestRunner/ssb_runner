import 'package:flutter/services.dart';
import 'package:ssb_runner/audio/audio_loader.dart';
import 'package:ssb_runner/audio/wav_to_pcm.dart';

String obtainAssetDir(bool isMe, int dxccId) {
  return isMe ? myAudioAccentDir : obtainAccentByDxccId(dxccId);
}

String obtainRstAudioFileName(bool isMe, {bool isCallsignCorrect = true}) {
  if (isMe) {
    return 'EXCH.wav';
  }

  return isCallsignCorrect ? 'ROGER_YOU_ARE_59.wav' : '5_9.wav';
}

Future<Uint8List> loadAssetsWavPcmData(String filePath) async {
  final bytes = Uint8List.sublistView(
    await rootBundle.load('assets/voice/$filePath'),
  );
  final pcmData = await wavToPcm(bytes);

  return pcmData;
}

RegExp _alpha = RegExp(r'^[a-zA-Z]+$');

extension StringExtension on String {
  bool isNumber() {
    final codeUnit = codeUnitAt(0);
    return codeUnit ^ 0x30 <= 9;
  }

  bool isLetter() {
    return _alpha.hasMatch(this);
  }
}
