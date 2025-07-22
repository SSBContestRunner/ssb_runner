import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ssb_runner/audio/wav_to_pcm.dart';

/// Helper method, to transfrom CALL or EXCHANGE to audio data
Future<Uint8List> payloadToAudioData(String payload, {bool isMe = false}) async {
  final result = BytesBuilder();

  for (final char in payload.characters) {
    final fileName = char.toAudioFilename();
    final parentPath = _obtainParentDirName(isMe);
    final path = '$parentPath/$fileName';

    final pcmData = await loadAssetsWavPcmData(path);

    result.add(pcmData);
  }

  return result.toBytes();
}

Future<Uint8List> exchangeToAudioData({bool isMe = false}) async {
  final parentDirName = _obtainParentDirName(isMe);
  final filename = isMe ? 'RUN/exch.wav' : 'Common/5_9.wav';
  final filePath = '$parentDirName/$filename';
  return loadAssetsWavPcmData(filePath);
}

Future<Uint8List> loadAssetsWavPcmData(String filePath) async {
  final bytes = Uint8List.sublistView(await rootBundle.load('assets/voice/$filePath'));
  final pcmData = await wavToPcm(bytes);

  return pcmData;
}

String _obtainParentDirName(bool isMe) {
  return isMe ? 'Global' : 'English-US';
}

RegExp _alpha = RegExp(r'^[a-zA-Z]+$');

extension _CharToAudioFilenaem on String {
  String toAudioFilename() {
    final stringBuffer = StringBuffer();

    if (isNumber()) {
      stringBuffer.write('Number/');
    }

    final uppercased = toUpperCase();

    if (uppercased.isLetter()) {
      stringBuffer.write('ICAO/');
    }

    stringBuffer.write(uppercased);
    stringBuffer.write('.wav');

    return stringBuffer.toString();
  }

  bool isNumber() {
    final codeUnit = codeUnitAt(0);
    return codeUnit ^ 0x30 <= 9;
  }

  bool isLetter() {
    return _alpha.hasMatch(this);
  }
}
