import 'dart:math';

import 'package:ssb_runner/callsign/callsign_loader.dart';
import 'package:ssb_runner/contest_type/contest_type.dart';
import 'package:ssb_runner/training/session_random.dart';
import 'package:ssb_runner/training/training_profile.dart';

/// The contract both the live generator and the replay engine satisfy.
abstract interface class AnswerSource {
  ContestAnswer generateAnswer();
}

class ContestAnswerGenerator implements AnswerSource {
  final CallsignLoader _callsignLoader;
  final ContestType _contestType;
  final TrainingMode _mode;
  final TrainingDifficulty _difficulty;
  final SessionRandom _random;

  ContestAnswerGenerator({
    required CallsignLoader callsignLoader,
    required ContestType contestType,
    required TrainingMode mode,
    required TrainingDifficulty difficulty,
    required SessionRandom random,
  }) : _callsignLoader = callsignLoader,
       _contestType = contestType,
       _mode = mode,
       _difficulty = difficulty,
       _random = random;

  @override
  ContestAnswer generateAnswer() {
    List<String> callSigns = _callsignLoader.callSigns;

    final index = _random.nextCallsignIndex(callSigns.length);
    final callSign = callSigns[index];

    final exchangeManager = _contestType.exchangeManager;
    final exchange = exchangeManager.generateExchange(_random);

    final pileupCount = _mode == TrainingMode.pileup
        ? max(2, _difficulty.pileupCallers + 1)
        : 1;
    final pileupCallsigns = <String>[callSign];
    while (pileupCallsigns.length < pileupCount) {
      final contender = callSigns[_random.nextCallsignIndex(callSigns.length)];
      if (!pileupCallsigns.contains(contender)) pileupCallsigns.add(contender);
    }
    return ContestAnswer(
      callSign: callSign,
      exchange: exchange,
      pileupCallsigns: pileupCallsigns,
      mode: _mode,
    );
  }
}

class ContestAnswer {
  final String callSign;
  final String exchange;
  final List<String> pileupCallsigns;
  final TrainingMode mode;
  bool get isSearchAndPounce => mode == TrainingMode.searchAndPounce;

  ContestAnswer({
    required this.callSign,
    required this.exchange,
    required this.pileupCallsigns,
    required this.mode,
  });
}
