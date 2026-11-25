import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssb_runner/audio/audio_alert_state.dart';
import 'package:ssb_runner/audio/audio_output_monitor.dart';
import 'package:ssb_runner/audio/audio_output_probe.dart';
import 'package:ssb_runner/l10n/app_l10n.dart';
import 'package:ssb_runner/l10n/generated/app_localizations.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/ui/main_page/audio_preflight_dialog.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _SilentProbe implements AudioOutputProbe {
  @override
  bool get supportsEvents => false;

  @override
  Stream<void> get events => const Stream<void>.empty();

  @override
  Future<AudioOutputStatus> read() async => AudioOutputStatus.unknown;

  @override
  Future<void> dispose() async {}
}

AudioOutputMonitor _monitor() {
  return AudioOutputMonitor(
    probe: _SilentProbe(),
    readEngine: () => AudioEngineStatus.unknown,
    disabled: true,
  );
}

class _Harness {
  _Harness({required this.settings, required this.monitor, required this.result});
  final AppSettings settings;
  final AudioOutputMonitor monitor;
  final ValueNotifier<bool?> result;
}

Future<_Harness> _pumpHarness(
  WidgetTester tester, {
  required AudioAlertReason reason,
  bool lowVolumeWarning = true,
}) async {
  final prefs = await SharedPreferencesWithCache.create(
    cacheOptions: const SharedPreferencesWithCacheOptions(),
  );
  final settings = AppSettings(prefs: prefs)
    ..audioPreflightLowVolumeWarning = lowVolumeWarning;
  final monitor = _monitor();
  monitor.snapshot.value = AudioMonitorSnapshot(
    reason: reason,
    volume: 0.05,
  );

  final result = ValueNotifier<bool?>(null);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                result.value = await confirmAudioPreflight(
                  context: context,
                  monitor: monitor,
                  settings: settings,
                );
              },
              child: const Text('RUN'),
            ),
          ),
        ),
      ),
    ),
  );
  addTearDown(monitor.dispose);
  return _Harness(settings: settings, monitor: monitor, result: result);
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('a healthy output starts without a dialog', (tester) async {
    final harness = await _pumpHarness(
      tester,
      reason: AudioAlertReason.none,
    );

    await tester.tap(find.text('RUN'));
    await tester.pump();

    expect(harness.result.value, isTrue);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('a dismissed low volume does not block', (tester) async {
    final harness = await _pumpHarness(
      tester,
      reason: AudioAlertReason.low,
      lowVolumeWarning: false,
    );

    await tester.tap(find.text('RUN'));
    await tester.pump();

    expect(harness.result.value, isTrue);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('a low volume blocks and start-anyway keeps the warning', (
    tester,
  ) async {
    final harness = await _pumpHarness(
      tester,
      reason: AudioAlertReason.low,
    );

    await tester.tap(find.text('RUN'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text("Don't warn about low volume"), findsOneWidget);

    await tester.tap(find.text('Start anyway'));
    await tester.pumpAndSettle();

    expect(harness.result.value, isTrue);
    expect(harness.settings.audioPreflightLowVolumeWarning, isTrue);
  });

  testWidgets('ticking the checkbox writes the setting when starting', (
    tester,
  ) async {
    final harness = await _pumpHarness(
      tester,
      reason: AudioAlertReason.low,
    );

    await tester.tap(find.text('RUN'));
    await tester.pumpAndSettle();

    await tester.tap(find.text("Don't warn about low volume"));
    await tester.pump();
    await tester.tap(find.text('Start anyway'));
    await tester.pumpAndSettle();

    expect(harness.result.value, isTrue);
    expect(harness.settings.audioPreflightLowVolumeWarning, isFalse);
  });

  testWidgets('a mute has no dismiss checkbox', (tester) async {
    final harness = await _pumpHarness(
      tester,
      reason: AudioAlertReason.muted,
    );

    await tester.tap(find.text('RUN'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text("Don't warn about low volume"), findsNothing);
    expect(find.text('Check again'), findsOneWidget);

    await tester.tap(find.text('Start anyway'));
    await tester.pumpAndSettle();
    expect(harness.result.value, isTrue);
  });

  testWidgets('an engine failure offers retry instead of recheck', (
    tester,
  ) async {
    final harness = await _pumpHarness(
      tester,
      reason: AudioAlertReason.engineDown,
    );

    await tester.tap(find.text('RUN'));
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Open system sound settings'), findsNothing);

    await tester.tap(find.text('Start anyway'));
    await tester.pumpAndSettle();
    expect(harness.result.value, isTrue);
  });

  testWidgets('a recovered output closes the dialog and starts', (
    tester,
  ) async {
    final harness = await _pumpHarness(
      tester,
      reason: AudioAlertReason.muted,
    );

    await tester.tap(find.text('RUN'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    // The monitor polled and found the output healthy again.
    harness.monitor.snapshot.value = const AudioMonitorSnapshot();
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(harness.result.value, isTrue);
  });
}
