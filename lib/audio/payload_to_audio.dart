import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ssb_runner/audio/wav_to_pcm.dart';
import 'package:ssb_runner/common/concat_bytes.dart';

/// Helper method, to transfrom CALL or EXCHANGE to audio data
Future<Uint8List> payloadToAudioData(
  String payload, {
  bool isMe = false,
}) async {
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

Future<Uint8List> exchangeToAudioData(
  String exchange, {
  bool isMe = false,
}) async {
  final dirName = _obtainParentDirName(isMe);
  final exchangeFilePath = isMe
      ? '$dirName/RUN/exch.wav'
      : '$dirName/Common/rogeryouare59.wav';

  final exchangeAudioData = await loadAssetsWavPcmData(exchangeFilePath);

  final payloadAudioData = await payloadToAudioData(exchange, isMe: isMe);
  return concatUint8List([exchangeAudioData, payloadAudioData]);
}

Future<Uint8List> loadAssetsWavPcmData(String filePath) async {
  final bytes = Uint8List.sublistView(
    await rootBundle.load('assets/voice/$filePath'),
  );
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

    if (isNumber() || this == '/') {
      stringBuffer.write('Number/');
    }

    final uppercased = toUpperCase();

    if (uppercased.isLetter()) {
      stringBuffer.write('ICAO/');
    }

    if (this == '/') {
      stringBuffer.write('Portable');
    } else {
      stringBuffer.write(uppercased);
    }
    stringBuffer.write('.wav');

    return stringBuffer.toString();
  }
}

extension StringExtension on String {
  bool isNumber() {
    final codeUnit = codeUnitAt(0);
    return codeUnit ^ 0x30 <= 9;
  }

  bool isLetter() {
    return _alpha.hasMatch(this);
  }
}
