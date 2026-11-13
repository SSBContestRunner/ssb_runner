import 'package:ssb_runner/contest_run/data/score_data.dart';
import 'package:ssb_runner/db/app_database.dart';

abstract interface class ScoreCalculator {
  final String stationCallsign;

  ScoreCalculator({required this.stationCallsign});

  CorrectnessType calculateCorrectness(QsoTableData submitQso);
  ScoreData calculateScore(List<QsoTableData> qsos);
}

sealed class CorrectnessType {}

final class Correct extends CorrectnessType {}

final class Incorrect extends CorrectnessType {}

final class Penalty extends CorrectnessType {
  final int penaltyMultiple;

  Penalty({required this.penaltyMultiple});
}

/// Contest log check: a wrong callsign is NIL plus a fixed QSO-point penalty,
/// while a wrong exchange is NIL only. Shared so every contest (including
/// WPX) scores the same categories the same way.
CorrectnessType calculateLogCheckCorrectness(
  QsoTableData submitQso, {
  required int callsignPenaltyMultiple,
}) {
  if (submitQso.callsignCorrect == submitQso.callsign &&
      submitQso.exchange == submitQso.exchangeCorrect) {
    return Correct();
  }

  if (submitQso.callsign != submitQso.callsignCorrect) {
    return Penalty(penaltyMultiple: callsignPenaltyMultiple);
  }

  return Incorrect();
}
