import 'package:ssb_runner/contest_run/data/score_data.dart';
import 'package:ssb_runner/contest_run/qso_duplicates.dart';
import 'package:ssb_runner/common/extract_prefix.dart';
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
       stationContinent = dxccManager.findCallSignContinent(stationCallsign);

  @override
  String get stationCallsign => _stationCallsign;

  @override
  CorrectnessType calculateCorrectness(QsoTableData submitQso) =>
      calculateLogCheckCorrectness(submitQso, callsignPenaltyMultiple: 2);

  @override
  ScoreData calculateScore(List<QsoTableData> qsos) {
    qsos = uniqueQsos(qsos);
    final multipliers = qsos
        .map((qso) => extractPrefix(qso.callsign))
        .where((prefix) => prefix.isNotEmpty)
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
    final qsoContinent = dxccManager.findCallSignContinent(qso.callsign);

    if (qsoContinent.isEmpty) {
      return 1;
    }

    if (qsoContinent != stationContinent) {
      return 3;
    }

    return 1;
  }
}
