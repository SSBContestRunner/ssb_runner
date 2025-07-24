import 'package:ssb_runner/contest_run/data/score_data.dart';
import 'package:ssb_runner/contest_run/log/extract_prefix.dart';
import 'package:ssb_runner/contest_type/score_calculator.dart';
import 'package:ssb_runner/db/app_database.dart';
import 'package:ssb_runner/dxcc/dxcc_manager.dart';

class WpxScoreCalculator implements ScoreCalculator {
  final DxccManager dxccManager;
  final String stationContinent;
  final String _stationCallsign;

  WpxScoreCalculator({
    required String stationCallsign,
    required this.dxccManager,
  }) : _stationCallsign = stationCallsign,
       stationContinent = dxccManager.findCallSignContinet(stationCallsign);

  @override
  String get stationCallsign => _stationCallsign;

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
