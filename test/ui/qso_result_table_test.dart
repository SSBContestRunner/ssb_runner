import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/db/app_database.dart';
import 'package:ssb_runner/ui/qso_result_table/qso_result_list/qso_result.dart';
import 'package:ssb_runner/ui/qso_result_table/qso_result_list/qso_result_row.dart';

void main() {
  test('duplicate records stay visible with DUPE and exchange corrections', () {
    final first = QsoTableData(
      id: 1,
      utcInSeconds: 31,
      runId: 'run-1',
      stationCallsign: 'BG7TVF',
      callsign: '4X6ZM',
      callsignCorrect: '4X6ZM',
      exchange: '2500',
      exchangeCorrect: '2500',
    );
    final duplicate = first.copyWith(id: 2, utcInSeconds: 73, exchange: '2501');
    final rows = qsoResultsFromRecords([duplicate, first]);
    expect(rows, hasLength(2));
    expect(rows[0].call.data, '4X6ZM');
    expect(rows[0].utc, '00:01:13');
    expect(rows[0].corrections, 'DUPE 2500');
    expect(rows[1].corrections, isEmpty);
  });
  testWidgets('a long cell ellipsises instead of overflowing the row', (
    tester,
  ) async {
    // A both-wrong QSO renders the whole correction ("correct call" plus
    // "correct exchange") in one cell. At a narrow width that text is wider
    // than its column, which used to make the row report a RenderFlex
    // overflow (crash log: "overflowed by 0.501 pixels on the right").
    final item = QsoResult(
      call: QsoResultField(data: 'K1ABCDEFGHIJ', isCorrect: false),
      exchange: QsoResultField(data: '1500', isCorrect: false),
      utc: '00:05:12',
      corrections: 'K1ABCDEFGHIJ 1500',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: QsoRecordRow(item: item, isAlternate: false),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('K1ABCDEFGHIJ 1500'), findsOneWidget);
  });
}
