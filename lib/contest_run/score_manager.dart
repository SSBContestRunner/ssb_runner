import 'package:ssb_contest_runner/contest_run/data/qso.dart';
import 'package:ssb_contest_runner/contest_run/data/score_data.dart';
import 'package:ssb_contest_runner/contest_run/log/extract_prefix.dart';

const CQ_WPX = 'CQ-WPX';

class ScoreManager {
  final String contestId;
  final String stationCallsign;

  final ScoreCalculator scoreCalculator;

  ScoreData rawScoreData = ScoreData.initial();
  ScoreData verifiedScoreData = ScoreData.initial();

  ScoreManager({required this.contestId, required this.stationCallsign})
    : scoreCalculator = _contestIdToScoreCalculator(contestId, stationCallsign);

  void addQso(List<Qso> qsos, Qso submitQso, Qso answerQso) {
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
          score: verifiedScoreData.score - diffScore,
          multiple: verifiedScoreData.multiple - diffMultiple,
        );
        break;
    }
  }
}

ScoreCalculator _contestIdToScoreCalculator(
  String stationCallsign,
  String contestId,
) {
  return WpxScoreCalculator(stationCallsign: stationCallsign);
}

abstract interface class ScoreCalculator {
  final String stationCallsign;

  ScoreCalculator({required this.stationCallsign});

  CorrectnessType calculateCorrectness(Qso submitQso, Qso answerQso);
  ScoreData calculateScore(List<Qso> qsos);
}

class WpxScoreCalculator extends ScoreCalculator {
  WpxScoreCalculator({required super.stationCallsign});

  @override
  CorrectnessType calculateCorrectness(Qso submitQso, Qso answerQso) {
    if (submitQso == answerQso) {
      return Correct();
    }

    if (submitQso.call != answerQso.call) {
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

    // TODO: implement calculateScore
    throw UnimplementedError();
  }
}

sealed class CorrectnessType {}

final class Correct extends CorrectnessType {}

final class Incorrect extends CorrectnessType {}

final class Penalty extends CorrectnessType {
  final int penaltyMultiple;

  Penalty({required this.penaltyMultiple});
}
