import 'package:flutter/widgets.dart';
import 'package:ssb_runner/audio/payload_to_audio.dart';

sealed class AudioPlayType {}

class NoPlay extends AudioPlayType {}

class PlayCall extends AudioPlayType {
  final String callToPlay;
  final bool isMe;

  PlayCall({required this.callToPlay, this.isMe = false});
}

class PlayExchange extends AudioPlayType {
  final String exchangeToPlay;
  final bool isMe;

  PlayExchange({required String exchange, required this.isMe})
    : exchangeToPlay = exchange.exchangePadZerosIfNeeded();
}

class PlayCallExchange extends AudioPlayType {
  final String call;
  final String exchangeToPlay;
  final bool isMe;

  PlayCallExchange({
    required this.call,
    required String exchange,
    required this.isMe,
  }) : exchangeToPlay = exchange.exchangePadZerosIfNeeded();
}

const _exchangeMinLength = 3;

extension ExchangePadZeroExtension on String {
  String exchangePadZerosIfNeeded() {
    if (isEmpty || !characters.every((chat) => chat.isNumber())) {
      return this;
    }

    return padLeft(_exchangeMinLength, '0');
  }
}
