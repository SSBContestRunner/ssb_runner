import 'dart:math';

import 'package:ssb_runner/callsign/callsign_loader.dart';
import 'package:ssb_runner/common/normalize_callsign.dart';
import 'package:ssb_runner/contest_type/contest_type.dart';
import 'package:ssb_runner/training/session_random.dart';
import 'package:ssb_runner/training/training_profile.dart';

/// The contract both the live generator and the replay engine satisfy.
abstract interface class AnswerSource {
  ContestAnswer generateAnswer();
}

/// An expected end of a finite question sequence, not a generation failure.
class AnswerSourceExhausted implements Exception {
  const AnswerSourceExhausted(this.reason);

  final String reason;

  @override
  String toString() => 'AnswerSourceExhausted: $reason';
}

class ContestAnswerGenerator implements AnswerSource {
  final CallsignLoader _callsignLoader;
  final ContestType _contestType;
  final TrainingMode _mode;
  final TrainingDifficulty _difficulty;
  final SessionRandom _random;
  late final List<String> _remainingCallsigns = _callsignLoader.callSigns
      .map(normalizeCallsign)
      .where((call) => call.isNotEmpty)
      .toSet()
      .toList();

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
    if (_remainingCallsigns.isEmpty) {
      throw const AnswerSourceExhausted('callsign_pool_exhausted');
    }
    // Swap-remove draws targets without replacement in O(1). Retry reuses the
    // current state and never draws here. Past targets also leave the pileup.
    final index = _random.nextCallsignIndex(_remainingCallsigns.length);
    final callSign = _remainingCallsigns[index];
    _remainingCallsigns[index] = _remainingCallsigns.last;
    _remainingCallsigns.removeLast();

    final exchangeManager = _contestType.exchangeManager;
    final exchange = exchangeManager.generateExchange(
      _random,
      callerCallsign: callSign,
    );

    final desiredCount = _mode == TrainingMode.pileup
        ? max(2, _difficulty.pileupCallers + 1)
        : 1;
    final pileupCount = min(desiredCount, _remainingCallsigns.length + 1);
    final pileupCallsigns = <String>[callSign];
    // Partial Fisher-Yates over virtual indices: finite even for a tiny pool
    // or a random source that repeatedly returns the same index.
    final swaps = <int, int>{};
    var available = _remainingCallsigns.length;
    while (pileupCallsigns.length < pileupCount) {
      final draw = _random.nextCallsignIndex(available);
      final selected = swaps[draw] ?? draw;
      available--;
      swaps[draw] = swaps[available] ?? available;
      pileupCallsigns.add(_remainingCallsigns[selected]);
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
