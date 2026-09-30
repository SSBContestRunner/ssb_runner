import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/ui/qso_result_table/qso_result_list/qso_result.dart';
import 'package:ssb_runner/ui/qso_result_table/qso_result_list/qso_result_row.dart';

void main() {
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
