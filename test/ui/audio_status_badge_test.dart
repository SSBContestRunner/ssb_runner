import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/audio/audio_alert_state.dart';
import 'package:ssb_runner/audio/audio_output_monitor.dart';
import 'package:ssb_runner/audio/audio_output_probe.dart';
import 'package:ssb_runner/l10n/app_l10n.dart';
import 'package:ssb_runner/l10n/generated/app_localizations.dart';
import 'package:ssb_runner/ui/main_page/audio_status_badge.dart';

Widget _app({AudioOutputMonitor? monitor}) {
  final badge = const Scaffold(
    body: Center(child: AudioStatusBadge()),
  );

  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: appLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: monitor == null
        ? badge
        : MultiRepositoryProvider(
            providers: [
              RepositoryProvider<AudioOutputMonitor>.value(value: monitor),
            ],
            child: badge,
          ),
  );
}

AudioOutputMonitor _monitor() {
  return AudioOutputMonitor(
    probe: const UnsupportedAudioOutputProbe(),
    readEngine: () => AudioEngineStatus.unknown,
    disabled: true,
  );
}

void main() {
  testWidgets('no monitor means no badge', (tester) async {
    await tester.pumpWidget(_app());

    expect(find.byKey(const Key('audioStatusBadge')), findsNothing);
  });

  testWidgets('a healthy output has no badge', (tester) async {
    final monitor = _monitor();
    addTearDown(monitor.dispose);
    await tester.pumpWidget(_app(monitor: monitor));

    expect(find.byKey(const Key('audioStatusBadge')), findsNothing);
  });

  testWidgets('an alert inserts the badge with the reason as tooltip', (
    tester,
  ) async {
    final monitor = _monitor();
    addTearDown(monitor.dispose);
    await tester.pumpWidget(_app(monitor: monitor));

    monitor.snapshot.value = const AudioMonitorSnapshot(
      reason: AudioAlertReason.muted,
      volume: 0.12,
    );
    await tester.pump();

    expect(find.byKey(const Key('audioStatusBadge')), findsOneWidget);
    expect(find.byIcon(Icons.volume_off_outlined), findsOneWidget);
    expect(
      find.byTooltip('System output is muted; call audio will not be heard'),
      findsOneWidget,
    );
  });

  testWidgets('the low-volume tooltip carries the current percentage', (
    tester,
  ) async {
    final monitor = _monitor();
    addTearDown(monitor.dispose);
    await tester.pumpWidget(_app(monitor: monitor));

    monitor.snapshot.value = const AudioMonitorSnapshot(
      reason: AudioAlertReason.low,
      volume: 0.05,
    );
    await tester.pump();

    expect(
      find.byTooltip(
        'System volume is only 5%; call audio may be hard to hear',
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.volume_down_outlined), findsOneWidget);
    expect(find.byIcon(Icons.volume_off_outlined), findsNothing);
  });

  testWidgets('clicking the badge opens the details dialog', (tester) async {
    final monitor = _monitor();
    addTearDown(monitor.dispose);
    await tester.pumpWidget(_app(monitor: monitor));

    monitor.snapshot.value = const AudioMonitorSnapshot(
      reason: AudioAlertReason.low,
      volume: 0.08,
      deviceName: 'Speakers',
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('audioStatusBadge')));
    await tester.pumpAndSettle();

    expect(find.text('Current volume 8%'), findsOneWidget);
    expect(find.text('Speakers'), findsOneWidget);
    expect(find.text('Open system sound settings'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
  });

  testWidgets('a recovered output removes the badge again', (tester) async {
    final monitor = _monitor();
    addTearDown(monitor.dispose);
    await tester.pumpWidget(_app(monitor: monitor));

    monitor.snapshot.value = const AudioMonitorSnapshot(
      reason: AudioAlertReason.noDevice,
    );
    await tester.pump();
    expect(find.byKey(const Key('audioStatusBadge')), findsOneWidget);

    monitor.snapshot.value = const AudioMonitorSnapshot();
    await tester.pump();
    expect(find.byKey(const Key('audioStatusBadge')), findsNothing);
  });
}
