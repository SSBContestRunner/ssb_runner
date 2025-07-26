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
