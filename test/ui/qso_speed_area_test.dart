import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/l10n/generated/app_localizations.dart';
import 'package:ssb_runner/ui/bottom_panel/qso_speed_area.dart';

/// The QSO records panel is 240 px wide with a 40 px inset on each side, so the
/// speed readout is laid out in a 160 px slot.
const double _readoutSlotWidth = 240.0 - 40.0 - 40.0;

const Locale _zhHans = Locale.fromSubtags(
  languageCode: 'zh',
  scriptCode: 'Hans',
);

void main() {
  testWidgets('a numeric speed reading fits the 160px slot in Chinese', (
    tester,
  ) async {
    // The Chinese unit ("QSO/小时") is wider than the English/Japanese ones and
    // pushed the reading past the slot once a QSO was logged, overflowing the
    // row (crash log: "RenderFlex overflowed by 4.7 pixels on the right").
    final l10n = await AppLocalizations.delegate.load(_zhHans);
    final speedText = '30.0 ${l10n.qsoSpeedUnit}';

    await _pumpReadout(tester, speed: 30.0, unit: l10n.qsoSpeedUnit);

    expect(tester.takeException(), isNull);
    expect(find.text(speedText), findsOneWidget);

    // The label is laid out wider than the slot, so it must be scaled down to
    // fit instead of overflowing or being clipped.
    final intrinsic = tester.getSize(find.text(speedText));
    expect(intrinsic.width, greaterThan(_readoutSlotWidth));

    final painted = tester.getRect(find.text(speedText));
    expect(painted.width, lessThanOrEqualTo(_readoutSlotWidth + 0.01));
  });

  testWidgets('the placeholder reading fits the 160px slot in Chinese', (
    tester,
  ) async {
    final l10n = await AppLocalizations.delegate.load(_zhHans);
    final speedText = '--- ${l10n.qsoSpeedUnit}';

    await _pumpReadout(tester, speed: null, unit: l10n.qsoSpeedUnit);

    expect(tester.takeException(), isNull);
    expect(find.text(speedText), findsOneWidget);
    expect(
      tester.getSize(find.byType(QsoSpeedReadout)).width,
      _readoutSlotWidth,
    );
  });
}

Future<void> _pumpReadout(
  WidgetTester tester, {
  required double? speed,
  required String unit,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: _zhHans,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: _readoutSlotWidth,
            height: 46,
            child: QsoSpeedReadout(speed: speed, unit: unit),
          ),
        ),
      ),
    ),
  );
}
