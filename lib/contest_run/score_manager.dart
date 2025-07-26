import 'dart:async';

import 'package:ssb_runner/contest_run/data/score_data.dart';
import 'package:ssb_runner/contest_type/score_calculator.dart';
import 'package:ssb_runner/db/app_database.dart';

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
    required this.scoreCalculator,
  });

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
