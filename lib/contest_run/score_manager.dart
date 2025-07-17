import 'dart:async';

import 'package:ssb_contest_runner/contest_run/contests.dart';
import 'package:ssb_contest_runner/contest_run/data/score_data.dart';
import 'package:ssb_contest_runner/contest_run/log/extract_prefix.dart';
import 'package:ssb_contest_runner/db/app_database.dart';
import 'package:ssb_contest_runner/dxcc/dxcc_manager.dart';

const CQ_WPX = 'CQ-WPX';

class ScoreManager {
  final String contestId;
  final String stationCallsign;

  final ScoreCalculator scoreCalculator;

  ScoreData _rawScoreData = ScoreData.initial();
  ScoreData _verifiedScoreData = ScoreData.initial();

  final rawScoreDataStream = StreamController<ScoreData>();
  final verifiedScoreDataStream = StreamController<ScoreData>();

  ScoreManager({
    required this.contestId,
    required this.stationCallsign,
    required DxccManager dxccManager,
  }) : scoreCalculator = _contestIdToScoreCalculator(
         contestId,
         stationCallsign,
         dxccManager,
       );

  void addQso(List<QsoTableData> qsos, QsoTableData submitQso) {
    final newRawScoreData = scoreCalculator.calculateScore(qsos);

    final diffScore = newRawScoreData.score - _rawScoreData.score;
    final diffMultiple = newRawScoreData.multiple - _rawScoreData.multiple;

    final correctness = scoreCalculator.calculateCorrectness(submitQso);

    _rawScoreData = newRawScoreData;

    switch (correctness) {
      case Correct():
        _verifiedScoreData = _verifiedScoreData.copyWith(
          count: _verifiedScoreData.count + 1,
          score: _verifiedScoreData.score + diffScore,
          multiple: _verifiedScoreData.multiple + diffMultiple,
        );
        break;
      case Incorrect():
        break;
      case Penalty():
        _verifiedScoreData = _verifiedScoreData.copyWith(
          count: _verifiedScoreData.count,
          score:
              newRawScoreData.score - correctness.penaltyMultiple * diffScore,
          multiple: _verifiedScoreData.multiple,
        );
        break;
    }

    rawScoreDataStream.sink.add(_rawScoreData);
    verifiedScoreDataStream.sink.add(_verifiedScoreData);
  }
}

ScoreCalculator _contestIdToScoreCalculator(
  String stationCallsign,
  String contestId,
  DxccManager dxccManager,
) {
  return WpxScoreCalculator(
    stationCallsign: stationCallsign,
    dxccManager: dxccManager,
  );
}

abstract interface class ScoreCalculator {
  final String stationCallsign;

  ScoreCalculator({required this.stationCallsign});

  CorrectnessType calculateCorrectness(QsoTableData submitQso);
  ScoreData calculateScore(List<QsoTableData> qsos);
}

class WpxScoreCalculator extends ScoreCalculator {
  final DxccManager dxccManager;
  final String stationContinent;

  WpxScoreCalculator({
    required super.stationCallsign,
    required this.dxccManager,
  }) : stationContinent = dxccManager.findCallSignContinet(stationCallsign);

  @override
  CorrectnessType calculateCorrectness(QsoTableData submitQso) {
    if (submitQso.callsignCorrect == submitQso.callsign &&
        submitQso.exchange == submitQso.exchangeCorrect) {
      return Correct();
    }

    if (submitQso.callsign != submitQso.callsignCorrect) {
      return Penalty(penaltyMultiple: 2);
    }

    return Incorrect();
  }

  @override
  ScoreData calculateScore(List<QsoTableData> qsos) {
    final multipliers = qsos
        .map((qso) => extractPrefix(qso.callsign))
        .toSet()
        .length;

    final baseScores = qsos.fold(
      0,
      (acc, qso) => acc + _obtainQsoBasePoint(qso),
    );

    final score = baseScores * multipliers;

    return ScoreData(count: qsos.length, multiple: multipliers, score: score);
  }

  int _obtainQsoBasePoint(QsoTableData qso) {
    final qsoContinent = dxccManager.findCallSignContinet(qso.callsign);

    if (qsoContinent.isEmpty) {
      return 1;
    }

    if (qsoContinent != stationContinent) {
      return 3;
    }

    return 1;
  }
}

sealed class CorrectnessType {}

final class Correct extends CorrectnessType {}

final class Incorrect extends CorrectnessType {}

final class Penalty extends CorrectnessType {
  final int penaltyMultiple;

  Penalty({required this.penaltyMultiple});
}
