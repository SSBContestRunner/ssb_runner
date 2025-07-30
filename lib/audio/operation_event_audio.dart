import 'dart:typed_data';

import 'package:ssb_runner/audio/payload_to_audio.dart';
import 'package:ssb_runner/common/concat_bytes.dart';
import 'package:ssb_runner/contest_run/state_machine/single_call/audio_play_type.dart';

const globalRunPath = 'Global/RUN';

Future<Uint8List> cqAudioData(String callSign) async {
  final cqAudioData = await loadAssetsWavPcmData('$globalRunPath/CQ.wav');
  final callSignAudioData = await payloadToAudioData(callSign, isMe: true);
  return concatUint8List([cqAudioData, callSignAudioData]);
}

Future<Uint8List> exchangeAudioData(String exchange) async {
  return exchangeToAudioData(exchange.exchangePadZerosIfNeeded(), isMe: true);
}
