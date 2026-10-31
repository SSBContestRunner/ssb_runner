import 'dart:math';

import 'package:ssb_runner/callsign/callsign_loader.dart';
import 'package:ssb_runner/common/normalize_callsign.dart';
import 'package:ssb_runner/contest_type/contest_type.dart';
import 'package:ssb_runner/training/session_random.dart';
import 'package:ssb_runner/training/training_profile.dart';

/// The contract both the live generator and the replay engine satisfy.
abstract interface class AnswerSource {
  /// [requeueCallsign] is the station abandoned by F1: it returns to the pool
  /// and, in pile-up mode with a non-empty pool, stays audible this round as an
  /// interferer (never the main clip). Pool-empty cases fall back to that
  /// callsign as the main audio instead of ending the run.
  ContestAnswer generateAnswer({String? requeueCallsign});
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
  ContestAnswer generateAnswer({String? requeueCallsign}) {
    final requeued = requeueCallsign == null
        ? ''
        : normalizeCallsign(requeueCallsign);

    // Pool exhausted but the operator just abandoned a station: keep training
    // going with it as the main audio rather than ending the sequence. It is
    // consumed this round, so it does not go back into the pool.
    if (_remainingCallsigns.isEmpty) {
      if (requeued.isEmpty) {
        throw const AnswerSourceExhausted('callsign_pool_exhausted');
      }
      return ContestAnswer(
        callSign: requeued,
        exchange: _generateExchange(requeued),
        pileupCallsigns: [requeued],
        mode: _mode,
      );
    }

    // Swap-remove draws targets without replacement in O(1). Retry reuses the
    // current state and never draws here. Past targets also leave the pileup.
    // The abandoned station is not back in the pool yet, so it cannot become
    // the main target of this round.
    final index = _random.nextCallsignIndex(_remainingCallsigns.length);
    final callSign = _remainingCallsigns[index];
    _remainingCallsigns[index] = _remainingCallsigns.last;
    _remainingCallsigns.removeLast();

    final exchange = _generateExchange(callSign);

    final desiredCount = _mode == TrainingMode.pileup
        ? max(2, _difficulty.pileupCallers + 1)
        : 1;
    // Pile-up contract: `pileupCallsigns[0]` is the main clip, `[1..]` are the
    // interferers. The abandoned station is pinned at index 1 so the operator
    // hears it fighting for the next round.
    final pileupCallsigns = <String>[callSign];
    final candidates = _remainingCallsigns
        .where((call) => call != requeued)
        .toList();
    if (_mode == TrainingMode.pileup &&
        requeued.isNotEmpty &&
        requeued != callSign) {
      pileupCallsigns.add(requeued);
    }
    final pileupCount = min(
      desiredCount,
      candidates.length + pileupCallsigns.length,
    );
    // Partial Fisher-Yates over virtual indices: finite even for a tiny pool
    // or a random source that repeatedly returns the same index.
    final swaps = <int, int>{};
    var available = candidates.length;
    while (pileupCallsigns.length < pileupCount) {
      final draw = _random.nextCallsignIndex(available);
      final selected = swaps[draw] ?? draw;
      available--;
      swaps[draw] = swaps[available] ?? available;
      pileupCallsigns.add(candidates[selected]);
    }

    // Return the abandoned station to the pool so later rounds can draw it as
    // the main target again.
    if (requeued.isNotEmpty &&
        requeued != callSign &&
        !_remainingCallsigns.contains(requeued)) {
      _remainingCallsigns.add(requeued);
    }

    return ContestAnswer(
      callSign: callSign,
      exchange: exchange,
      pileupCallsigns: pileupCallsigns,
      mode: _mode,
    );
  }

  String _generateExchange(String callSign) {
    return _contestType.exchangeManager.generateExchange(
      _random,
      callerCallsign: callSign,
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
