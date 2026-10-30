import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/contest_run/data/score_data.dart';
import 'package:ssb_runner/contest_run/score_manager.dart';
import 'package:ssb_runner/contest_type/score_calculator.dart';
import 'package:ssb_runner/db/app_database.dart';

void main() {
  test(
    'duplicates cannot add verified contacts, points or penalties',
    () async {
      final manager = ScoreManager(
        contestId: 'run-1',
        stationCallsign: 'BI1ABC',
        scoreCalculator: _PenaltyScoreCalculator(),
      );
      final raw = <ScoreData>[];
      final verified = <ScoreData>[];
      final rawSub = manager.rawScoreDataStream.stream.listen(raw.add);
      final verifiedSub = manager.verifiedScoreDataStream.stream.listen(
        verified.add,
      );
      final first = _qso(1);
      final duplicate = _qso(
        2,
      ).copyWith(callsign: ' ja1xyz ', exchange: '999', exchangeCorrect: '998');
      manager.addQso([first], first);
      manager.addQso([first, duplicate], duplicate);
      await pumpEventQueue();
      for (final scores in [raw, verified]) {
        expect(scores.last.count, 1);
        expect(scores.last.score, scores.first.score);
        expect(scores.last.multiple, scores.first.multiple);
      }
      final next = _qso(
        3,
      ).copyWith(callsign: 'K1ABC', callsignCorrect: 'K1ABC');
      manager.addQso([first, duplicate, next], next);
      await pumpEventQueue();
      expect(raw.last.count, 2);
      expect(verified.last.count, 2);
      expect(verified.last.score, 6);
      await rawSub.cancel();
      await verifiedSub.cancel();
      await manager.rawScoreDataStream.close();
      await manager.verifiedScoreDataStream.close();
    },
  );
  // Regression: a cancelled single-subscription controller can never be
  // listened to again, which crashed the score area when a replayed session
  // started (Bad state: Stream has already been listened to).
  test('score streams can be cancelled and listened to again', () async {
    final manager = ScoreManager(
      contestId: 'run-1',
      stationCallsign: 'BI1ABC',
      scoreCalculator: _FakeScoreCalculator(),
    );

    final firstRaw = <ScoreData>[];
    final firstVerified = <ScoreData>[];
    final firstRawSub = manager.rawScoreDataStream.stream.listen(firstRaw.add);
    final firstVerifiedSub = manager.verifiedScoreDataStream.stream.listen(
      firstVerified.add,
    );

    manager.addQso([_qso(1)], _qso(1));
    await pumpEventQueue();
    await firstRawSub.cancel();
    await firstVerifiedSub.cancel();

    final secondRaw = <ScoreData>[];
    final secondVerified = <ScoreData>[];
    final secondRawSub = manager.rawScoreDataStream.stream.listen(
      secondRaw.add,
    );
    final secondVerifiedSub = manager.verifiedScoreDataStream.stream.listen(
      secondVerified.add,
    );

    manager.addQso([_qso(1), _qso(2)], _qso(2));
    await pumpEventQueue();
    await secondRawSub.cancel();
    await secondVerifiedSub.cancel();

    expect(firstRaw, isNotEmpty);
    expect(firstVerified, isNotEmpty);
    expect(secondRaw, isNotEmpty);
    expect(secondVerified, isNotEmpty);
  });
}

class _PenaltyScoreCalculator extends _FakeScoreCalculator {
  @override
  CorrectnessType calculateCorrectness(QsoTableData qso) =>
      qso.callsign == qso.callsignCorrect
      ? Correct()
      : Penalty(penaltyMultiple: 2);
}

QsoTableData _qso(int id) => QsoTableData(
  id: id,
  utcInSeconds: id * 10,
  runId: 'run-1',
  stationCallsign: 'BI1ABC',
  callsign: 'JA1XYZ',
  callsignCorrect: 'JA1XYZ',
  exchange: '$id',
  exchangeCorrect: '$id',
);

class _FakeScoreCalculator implements ScoreCalculator {
  @override
  String get stationCallsign => 'BI1ABC';

  @override
  CorrectnessType calculateCorrectness(QsoTableData submitQso) => Correct();

  @override
  ScoreData calculateScore(List<QsoTableData> qsos) =>
      ScoreData(count: qsos.length, multiple: 1, score: qsos.length * 3);
}
