import 'package:ssb_contest_runner/contest_run/data/score_data.dart';
import 'package:ssb_contest_runner/contest_run/log/extract_prefix.dart';
import 'package:ssb_contest_runner/db/app_database.dart';
import 'package:ssb_contest_runner/db/table/qso_table.dart';
import 'package:ssb_contest_runner/dxcc/dxcc_manager.dart';

const CQ_WPX = 'CQ-WPX';

class ScoreManager {
  final String contestId;
  final String stationCallsign;

  final ScoreCalculator scoreCalculator;

  ScoreData rawScoreData = ScoreData.initial();
  ScoreData verifiedScoreData = ScoreData.initial();

  ScoreManager({
    required this.contestId,
    required this.stationCallsign,
    required DxccManager dxccManager,
  }) : scoreCalculator = _contestIdToScoreCalculator(
         contestId,
         stationCallsign,
         dxccManager,
       );

  void addQso(List<QsoTableData> qsos, QsoTableData submitQso, QsoTableData answerQso) {
    final newRawScoreData = scoreCalculator.calculateScore(qsos);

    final diffScore = newRawScoreData.score - rawScoreData.score;
    final diffMultiple = newRawScoreData.multiple - rawScoreData.multiple;

    final correctness = scoreCalculator.calculateCorrectness(
      submitQso,
      answerQso,
    );

    rawScoreData = newRawScoreData;

    switch (correctness) {
      case Correct():
        verifiedScoreData = verifiedScoreData.copyWith(
          count: verifiedScoreData.count + 1,
          score: verifiedScoreData.score + diffScore,
          multiple: verifiedScoreData.multiple + diffMultiple,
        );
        break;
      case Incorrect():
        break;
      case Penalty():
        verifiedScoreData = verifiedScoreData.copyWith(
          count: verifiedScoreData.count,
          score:
              newRawScoreData.score - correctness.penaltyMultiple * diffScore,
          multiple: verifiedScoreData.multiple,
        );
        break;
    }
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

  CorrectnessType calculateCorrectness(QsoTableData submitQso, QsoTableData answerQso);
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
  CorrectnessType calculateCorrectness(QsoTableData submitQso, QsoTableData answerQso) {
    if (submitQso == answerQso) {
      return Correct();
    }

    if (submitQso.callsign != answerQso.callsign) {
      return Penalty(penaltyMultiple: 2);
    }

    return Incorrect();
  }

  @override
  ScoreData calculateScore(List<Qso> qsos) {
    final multipliers = qsos
        .map((qso) => extractPrefix(qso.call))
        .toSet()
        .length;

    final baseScores = qsos.fold(
      0,
      (acc, qso) => acc + _obtainQsoBasePoint(qso),
    );

    final score = baseScores * multipliers;

    return ScoreData(count: qsos.length, multiple: multipliers, score: score);
  }

  int _obtainQsoBasePoint(Qso qso) {
    final qsoContinent = dxccManager.findCallSignContinet(qso.call);

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
