import 'dart:math';

import 'package:ssb_runner/callsign/callsign_loader.dart';
import 'package:ssb_runner/contest_type/contest_type.dart';

class ContestAnswerGenerator {
  final CallsignLoader _callsignLoader;
  final ContestType _contestType;

  ContestAnswerGenerator({
    required CallsignLoader callsignLoader,
    required ContestType contestType,
  }) : _callsignLoader = callsignLoader,
       _contestType = contestType;

  ContestAnswer generateAnswer() {
    List<String> callSigns = _callsignLoader.callSigns;

    final random = Random();
    final index = random.nextInt(callSigns.length);
    final callSign = callSigns[index];

    final exchangeManager = _contestType.exchangeManager;
    final exchange = exchangeManager.generateExchange();

    return ContestAnswer(callSign: callSign, exchange: exchange);
  }
}

class ContestAnswer {
  final String callSign;
  final String exchange;

  ContestAnswer({required this.callSign, required this.exchange});
}
