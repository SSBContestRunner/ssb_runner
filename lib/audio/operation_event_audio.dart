import 'dart:typed_data';

import 'package:ssb_runner/audio/payload_to_audio.dart';

const globalRunPath = 'Global/RUN';

Future<Uint8List> cqAudioData(String callSign) async {
  final cqAudioData = await loadAssetsWavPcmData('$globalRunPath/CQ.wav');
  final callSignAudioData = await payloadToAudioData(callSign, isMe: true);
  return _concatUint8List([cqAudioData, callSignAudioData]);
}

Future<Uint8List> exchangeAudioData(String exchange) async {
  final exchangeAudioData = await loadAssetsWavPcmData(
    '$globalRunPath/exch.wav',
  );

  final payloadAudioData = await payloadToAudioData(exchange, isMe: true);
  return _concatUint8List([exchangeAudioData, payloadAudioData]);
}

Uint8List _concatUint8List(List<Uint8List> lists) {
  final bytesBuilder = BytesBuilder();

  for (final bytes in lists) {
    bytesBuilder.add(bytes);
  }
  return bytesBuilder.toBytes();
}
