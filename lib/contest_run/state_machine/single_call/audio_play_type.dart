import 'package:flutter/widgets.dart';
import 'package:ssb_runner/audio/payload_to_audio.dart';

sealed class AudioPlayType {}

class NoPlay extends AudioPlayType {}

class PlayExchange extends AudioPlayType {
  final String exchangeToPlay;
  final bool isMe;

  PlayExchange({required String exchange, required this.isMe})
    : exchangeToPlay = _padZerosIfNeeded(exchange);

  static String _padZerosIfNeeded(String exchange) {
    if (exchange.isEmpty ||
        !exchange.characters.every((chat) => chat.isNumber())) {
      return exchange;
    }

    int padLength;

    if (exchange.length == 1) {
      padLength = 2;
    } else if (exchange.length == 2) {
      padLength = 1;
    } else {
      padLength = 0;
    }

    return exchange.padLeft(padLength, '0');
  }
}

class PlayCallExchange extends AudioPlayType {
  final String call;
  final String exchange;
  final bool isMe;

  PlayCallExchange({
    required this.call,
    required this.exchange,
    required this.isMe,
  });
}
