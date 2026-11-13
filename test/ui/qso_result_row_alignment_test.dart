import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/ui/qso_result_table/qso_result_list/qso_result.dart';
import 'package:ssb_runner/ui/qso_result_table/qso_result_list/qso_result_row.dart';
import 'package:ssb_runner/ui/qso_result_table/qso_voice_replay_button.dart';
import 'package:ssb_runner/ui/theme/app_theme.dart';

/// The five shipped locales; none of them should change the row metrics.
const _locales = <Locale>[
  Locale('en'),
  Locale('zh'),
  Locale('zh', 'CN'),
  Locale('zh', 'TW'),
  Locale('ja'),
];

const _scales = <double>[1.0, 1.3];

QsoResult _item({required bool withReplay}) {
  return QsoResult(
    id: 7,
    call: QsoResultField(data: 'BG7TVF', isCorrect: false),
    exchange: QsoResultField(data: '0012', isCorrect: false),
    utc: '14:23:45',
    corrections: 'BG7TVF 0012',
    correctCall: 'BG7TVF',
    correctExchange: '0012',
    accentDir: 'US',
    phonicTypeId: 'standard',
    callPhonicDirs: const ['Common'],
    exchangePhonicDirs: const ['Number'],
    hasCorrection: true,
    canReplay: withReplay,
  );
}

Future<void> _pump(
  WidgetTester tester,
  QsoResult item, {
  required Locale locale,
  required double scale,
  bool isPlaying = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      locale: locale,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 644,
              child: QsoRecordRow(
                item: item,
                isPlaying: isPlaying,
                onReplay: item.canReplay ? () {} : null,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void _expectCentred(WidgetTester tester, String label, String text) {
  final rowRect = tester.getRect(find.byType(QsoRecordRow));
  final textRect = tester.getRect(find.text(text));
  final top = textRect.top - rowRect.top;
  final bottom = rowRect.bottom - textRect.bottom;
  expect(
    (top - bottom).abs(),
    lessThanOrEqualTo(0.5),
    reason: '$label "$text" top=$top bottom=$bottom',
  );
}

void main() {
  testWidgets('every cell is centred inside the 42 dp row', (tester) async {
    final loader = FontLoader('Iosevka')
      ..addFont(rootBundle.load('fonts/Iosevka-Regular-sub.ttf'));
    await loader.load();

    for (final withReplay in [false, true]) {
      for (final locale in _locales) {
        for (final scale in _scales) {
          final item = _item(withReplay: withReplay);
          await _pump(tester, item, locale: locale, scale: scale);

          final rowRect = tester.getRect(find.byType(QsoRecordRow));
          expect(rowRect.height, 42);

          final label =
              '${locale.languageCode}_${locale.countryCode} '
              'x$scale replay=$withReplay';
          _expectCentred(tester, label, item.utc);
          _expectCentred(tester, label, item.call.data);
          _expectCentred(tester, label, item.exchange.data);
          _expectCentred(tester, label, item.corrections);

          final button = find.byType(QsoVoiceReplayButton);
          if (withReplay) {
            final buttonRect = tester.getRect(button);
            expect(buttonRect.width, 48);
            expect(buttonRect.height, 42);
            expect(buttonRect.top, rowRect.top);
            // The action column stays flush with the row's 12 dp padding.
            expect(buttonRect.right, rowRect.right - 12);
            expect(tester.takeException(), isNull);
          } else {
            expect(button, findsNothing);
          }
        }
      }
    }
  });

  testWidgets('replay button keeps its hit area and playback bar', (
    tester,
  ) async {
    final item = _item(withReplay: true);
    await _pump(
      tester,
      item,
      locale: const Locale('en'),
      scale: 1.3,
      isPlaying: true,
    );

    var taps = 0;
    // Rebuild with a counting callback.
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData(textScaler: const TextScaler.linear(1.3)),
          child: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 644,
                child: QsoRecordRow(
                  item: item,
                  isPlaying: true,
                  onReplay: () => taps++,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final rowRect = tester.getRect(find.byType(QsoRecordRow));
    final buttonRect = tester.getRect(find.byType(QsoVoiceReplayButton));
    expect(buttonRect.size, const Size(48, 42));

    // Tapping the top edge of the 42 dp hit area still fires.
    await tester.tapAt(Offset(buttonRect.center.dx, buttonRect.top + 2));
    await tester.pump();
    expect(taps, 1);

    final bar = tester.getRect(
      find.descendant(
        of: find.byType(QsoRecordRow),
        matching: find.byType(ColoredBox),
      ),
    );
    // The bar sits at the content edge (inside the 12 dp row padding) and
    // spans the full 42 dp row.
    expect(bar.width, 3);
    expect(bar.height, 42);
    expect(bar.left, rowRect.left + 12);
    expect(bar.top, rowRect.top);
  });
}
