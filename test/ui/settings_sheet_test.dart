import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/audio/accent_policy.dart';
import 'package:ssb_runner/audio/audio_loader.dart';
import 'package:ssb_runner/audio/audio_player.dart';
import 'package:ssb_runner/callsign/callsign_loader.dart';
import 'package:ssb_runner/contest_run/new/contest_data_manager.dart';
import 'package:ssb_runner/contest_run/new/contest_input_handler.dart';
import 'package:ssb_runner/contest_run/new/contest_manager.dart';
import 'package:ssb_runner/db/app_database.dart';
import 'package:ssb_runner/dxcc/dxcc_manager.dart';
import 'package:ssb_runner/l10n/generated/app_localizations.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/settings/settings_issue.dart';
import 'package:ssb_runner/training/pending_replay.dart';
import 'package:ssb_runner/training/training_profile.dart';
import 'package:ssb_runner/ui/main_page/settings_cubits.dart';
import 'package:ssb_runner/ui/main_page/settings_sheet.dart';
import 'package:ssb_runner/ui/theme/app_theme.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:toastification/toastification.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('theme mode defaults to light and persists across instances', () async {
    final prefs = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(),
    );
    final settings = AppSettings(prefs: prefs);
    expect(settings.themeMode, ThemeMode.light);

    settings.themeMode = ThemeMode.dark;
    expect(settings.themeMode, ThemeMode.dark);
    expect(AppSettings(prefs: prefs).themeMode, ThemeMode.dark);
  });

  test('saving function keys bumps the revision for live views', () async {
    final prefs = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(),
    );
    final settings = AppSettings(prefs: prefs);
    final before = settings.functionKeysRevision.value;

    await settings.setFunctionKeyBindings([
      for (final key in FunctionKey.values) FunctionKeyBinding(key, null),
    ]);

    expect(settings.functionKeysRevision.value, before + 1);
  });

  testWidgets('Japanese labels fit inside the 480px drawer', (tester) async {
    final harness = await _pumpSheet(tester, locale: const Locale('ja'));

    expect(find.text('設定'), findsOneWidget);
    expect(find.text('コンテストと局'), findsOneWidget);
    expect(find.text('トレーニング'), findsOneWidget);
    expect(find.text('オーディオ'), findsOneWidget);
    expect(find.text('システム'), findsOneWidget);
    expect(tester.takeException(), isNull);

    harness.dispose();
  });

  testWidgets('the drawer exposes four categories and merges contest/station', (
    tester,
  ) async {
    final harness = await _pumpSheet(tester);

    expect(find.text('Contest & station'), findsOneWidget);
    expect(find.text('Training'), findsOneWidget);
    expect(find.text('Audio'), findsOneWidget);
    expect(find.text('System'), findsOneWidget);

    expect(find.text('Contest'), findsOneWidget);
    expect(find.text('My station'), findsOneWidget);
    expect(find.text('Name'), findsOneWidget);
    // CQ WPX has no station exchange field, only the contest exchange line.
    expect(find.text('Exchange'), findsOneWidget);

    await _openTab(tester, 'Training');
    expect(find.text('Training mode'), findsOneWidget);
    expect(find.text('Run'), findsOneWidget);
    expect(find.text('S&P'), findsOneWidget);
    expect(find.text('Pile-up'), findsOneWidget);
    expect(find.text('Duration'), findsOneWidget);
    expect(find.text('Difficulty'), findsOneWidget);

    await _openTab(tester, 'Audio');
    expect(find.textContaining('Incoming audio'), findsOneWidget);
    expect(find.text('Incoming accent'), findsOneWidget);
    expect(find.text('Phonic type'), findsOneWidget);

    await _openTab(tester, 'System');
    expect(find.text('Function keys'), findsOneWidget);
    expect(find.text('Past sessions'), findsOneWidget);
    expect(find.text('Verbose logging'), findsOneWidget);
    expect(find.text('Copy diagnostics'), findsOneWidget);
    expect(find.text('Export logs'), findsOneWidget);

    expect(tester.takeException(), isNull);
    harness.dispose();
  });

  testWidgets('CQ WPX explains the serial instead of showing an input', (
    tester,
  ) async {
    final harness = await _pumpSheet(tester);

    expect(
      find.text(
        'The serial is generated automatically from your completed QSOs.',
      ),
      findsOneWidget,
    );
    // Only the contest exchange line still shows "59 #".
    expect(find.text('59 #'), findsOneWidget);
    // The preview connects the upcoming serial to the fixed RST.
    expect(find.text('Transmitted'), findsOneWidget);
    expect(find.text('59 001'), findsOneWidget);
    expect(find.text('RST fixed at 59'), findsOneWidget);
    expect(
      find.text(
        'The serial follows your QSO count; the console shows it read-only.',
      ),
      findsOneWidget,
    );

    expect(tester.takeException(), isNull);
    harness.dispose();
  });

  testWidgets('the station panel previews the configured exchange as spoken', (
    tester,
  ) async {
    final harness = await _pumpSheet(
      tester,
      configure: (settings) {
        settings
          ..contestId = 'CQ-WW-SSB'
          ..setStationExchangeValue('CQ-WW-SSB', 'cqZone', '5');
      },
    );

    expect(find.text('59 05'), findsOneWidget);
    expect(find.text('RST fixed at 59'), findsOneWidget);
    expect(
      find.text('05 comes from CQ Zone above; the console shows it read-only.'),
      findsOneWidget,
    );

    expect(tester.takeException(), isNull);
    harness.dispose();
  });

  testWidgets('the preview follows the field while typing', (tester) async {
    final harness = await _pumpSheet(
      tester,
      configure: (settings) => settings.contestId = 'CQ-WW-SSB',
    );

    expect(find.text('Not set'), findsOneWidget);
    expect(
      find.text('Fill CQ Zone in My station; a run cannot start without it.'),
      findsOneWidget,
    );

    await tester.enterText(find.widgetWithText(TextField, 'CQ Zone'), '24');
    await tester.pump();

    expect(find.text('59 24'), findsOneWidget);

    expect(tester.takeException(), isNull);
    harness.dispose();
  });

  testWidgets('switching contest updates contest and station fields at once', (
    tester,
  ) async {
    final harness = await _pumpSheet(tester);

    expect(find.text('59 #'), findsOneWidget);
    expect(
      find.text(
        'The serial is generated automatically from your completed QSOs.',
      ),
      findsOneWidget,
    );

    harness.contestCubit.changeContest('CQ-WW-SSB');
    await tester.pump();
    await tester.pump();

    expect(find.text('59 #'), findsNothing);
    expect(
      find.text(
        'The serial is generated automatically from your completed QSOs.',
      ),
      findsNothing,
    );
    expect(find.text('59 Zone'), findsOneWidget);
    expect(find.text('CQ Zone'), findsOneWidget);
    expect(find.text('My station'), findsOneWidget);

    harness.contestCubit.changeContest('ARRL-DX');
    await tester.pump();

    expect(
      find.text('59 State/Province (W/VE) / 59 Power (DX)'),
      findsOneWidget,
    );
    expect(find.text('Power'), findsOneWidget);

    expect(tester.takeException(), isNull);
    harness.dispose();
  });

  testWidgets('running a session locks contest and station but keeps rules', (
    tester,
  ) async {
    final harness = await _pumpSheet(tester, running: true);

    expect(
      find.text(
        "Settings can't be changed while a session runs. Stop it first.",
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<DropdownMenu<String>>(find.byType(DropdownMenu<String>))
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('station-callsign')))
          .enabled,
      isFalse,
    );

    await tester.tap(find.text('Contest rules'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('CQ WPX rules'), findsOneWidget);

    expect(tester.takeException(), isNull);
    harness.dispose();
  });

  testWidgets(
    'an armed replay locks contest controls and cancelling restores them',
    (tester) async {
      final harness = await _pumpSheet(
        tester,
        configure: (settings) {
          settings
            ..contestId = 'CQ-WW-SSB'
            ..stationCallsign = 'BI1QJQ'
            ..contestDuration = 30
            ..setStationExchangeValue('CQ-WW-SSB', 'cqZone', '5');
          settings.armReplay(
            PendingReplay(
              runId: 'wpx-run',
              contestId: 'CQ-WPX',
              contestName: 'CQ WPX',
              modeId: 'run',
              difficultyId: 'standard',
              questionSeed: 42,
              audioSeed: 43,
              armedAtUtc: DateTime.utc(2026, 1, 1, 10, 30),
            ),
          );
        },
      );

      expect(find.text('Replay armed'), findsOneWidget);
      expect(find.textContaining('Replaying CQ WPX'), findsOneWidget);
      expect(
        tester
            .widget<DropdownMenu<String>>(find.byType(DropdownMenu<String>))
            .enabled,
        isFalse,
      );

      await _openTab(tester, 'Training');
      expect(
        tester
            .widget<SegmentedButton<TrainingMode>>(
              find.byType(SegmentedButton<TrainingMode>),
            )
            .onSelectionChanged,
        isNull,
      );
      expect(
        tester
            .widget<DropdownMenu<TrainingDifficulty>>(
              find.byType(DropdownMenu<TrainingDifficulty>),
            )
            .enabled,
        isFalse,
      );

      await tester.tap(find.text('Cancel replay'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Replay armed'), findsNothing);
      expect(harness.settings.pendingReplay, isNull);
      expect(harness.settings.contestId, 'CQ-WW-SSB');

      await _openTab(tester, 'Contest & station');
      expect(
        tester
            .widget<DropdownMenu<String>>(find.byType(DropdownMenu<String>))
            .enabled,
        isTrue,
      );
      await _openTab(tester, 'Training');
      expect(
        tester
            .widget<SegmentedButton<TrainingMode>>(
              find.byType(SegmentedButton<TrainingMode>),
            )
            .onSelectionChanged,
        isNotNull,
      );

      // Let the cancellation toast close before the test ends.
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
      harness.dispose();
    },
  );

  testWidgets('past sessions are disabled while a session runs', (
    tester,
  ) async {
    final harness = await _pumpSheet(tester, running: true);
    await _openTab(tester, 'System');

    expect(
      find.text("Past sessions can't be opened while a session runs."),
      findsOneWidget,
    );

    await tester.tap(find.text('Past sessions'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('No completed sessions yet.'), findsNothing);

    expect(tester.takeException(), isNull);
    harness.dispose();
  });

  testWidgets('duration clamps to the maximum like the previous settings', (
    tester,
  ) async {
    final harness = await _pumpSheet(tester);
    await _openTab(tester, 'Training');

    await tester.enterText(find.byType(TextFormField), '999');
    await tester.pump();

    expect(harness.optionsCubit.state.duration, 120);
    expect(_durationText(tester), '120');
    // Let the "max duration" toast close so no timer stays pending.
    await tester.pump(const Duration(seconds: 3));

    expect(tester.takeException(), isNull);
    harness.dispose();
  });

  testWidgets('incoming accent selection is persisted from the audio tab', (
    tester,
  ) async {
    final harness = await _pumpSheet(tester);
    await _openTab(tester, 'Audio');

    expect(harness.settings.incomingAccent, IncomingAccent.auto);

    await tester.tap(find.byType(DropdownMenu<IncomingAccent>));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('UK').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(harness.settings.incomingAccent, IncomingAccent.uk);
    expect(tester.takeException(), isNull);
    harness.dispose();
  });

  testWidgets('function keys open the reference and customize all twelve', (
    tester,
  ) async {
    final harness = await _pumpSheet(tester);
    await _openTab(tester, 'System');

    await tester.tap(find.text('Function keys'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Keyboard reference'), findsOneWidget);

    await tester.tap(find.text('Customize function keys'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(12));

    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(harness.settings.functionKeyBindings, hasLength(12));
    expect(
      harness.settings.functionKeyBindings[FunctionKey.f12.index].action,
      OperationAction.wipe,
    );

    await tester.tap(find.text('Close'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Keyboard reference'), findsNothing);

    expect(tester.takeException(), isNull);
    harness.dispose();
  });

  testWidgets('a deep link opens the drawer on the requested tab', (
    tester,
  ) async {
    final harness = await _pumpSheet(tester, initialTab: SettingsTab.training);

    expect(find.text('Training mode'), findsOneWidget);
    expect(find.text('Duration'), findsOneWidget);
    // The contest/station page stays offstage.
    expect(find.text('My station'), findsNothing);

    expect(tester.takeException(), isNull);
    harness.dispose();
  });

  testWidgets('a deep link marks the offending field with its issue', (
    tester,
  ) async {
    final harness = await _pumpSheet(
      tester,
      focusFieldKey: SettingsFocusKeys.stationCallsign,
    );

    expect(find.text('Please set station callsign'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('station-callsign')))
          .autofocus,
      isTrue,
    );

    expect(tester.takeException(), isNull);
    harness.dispose();
  });

  testWidgets('an exchange deep link marks and focuses the station field', (
    tester,
  ) async {
    final harness = await _pumpSheet(
      tester,
      configure: (settings) => settings
        ..contestId = 'CQ-WW-SSB'
        ..stationCallsign = 'BI1QJQ'
        ..contestDuration = 30,
      focusFieldKey: SettingsFocusKeys.exchangeField('cqZone'),
    );

    expect(find.text('59 Zone'), findsOneWidget);
    expect(find.text('Please set CQ Zone'), findsOneWidget);

    expect(tester.takeException(), isNull);
    harness.dispose();
  });

  testWidgets('a deep link stays read-only while a session runs', (
    tester,
  ) async {
    final harness = await _pumpSheet(
      tester,
      running: true,
      focusFieldKey: SettingsFocusKeys.stationCallsign,
    );

    final field = tester.widget<TextField>(
      find.byKey(const Key('station-callsign')),
    );
    expect(field.enabled, isFalse);
    expect(field.autofocus, isFalse);
    expect(find.text('Please set station callsign'), findsOneWidget);

    expect(tester.takeException(), isNull);
    harness.dispose();
  });

  testWidgets('tabs with unfinished settings are labelled for screen readers', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final harness = await _pumpSheet(tester);

    expect(
      find.bySemanticsLabel(RegExp('Contest & station.*1 item to fix')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('Training.*1 item to fix')),
      findsOneWidget,
    );

    semantics.dispose();
    expect(tester.takeException(), isNull);
    harness.dispose();
  });

  testWidgets('the duration deep link lands on the training error', (
    tester,
  ) async {
    final harness = await _pumpSheet(
      tester,
      initialTab: SettingsTab.training,
      focusFieldKey: SettingsFocusKeys.trainingDuration,
    );

    expect(
      find.text('Duration must be set and greater than 0'),
      findsOneWidget,
    );

    expect(tester.takeException(), isNull);
    harness.dispose();
  });

  testWidgets('practice seed and history dialogs open from the drawer', (
    tester,
  ) async {
    final harness = await _pumpSheet(tester);

    await _openTab(tester, 'Training');
    await tester.tap(find.text('Practice seed').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Copy question seed'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await _openTab(tester, 'System');
    await tester.tap(find.text('Past sessions'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('No completed sessions yet.'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    harness.dispose();
  });
}

Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

String _durationText(WidgetTester tester) {
  return tester
      .widget<EditableText>(
        find.descendant(
          of: find.byType(TextFormField),
          matching: find.byType(EditableText),
        ),
      )
      .controller
      .text;
}

typedef _Harness = ({
  AppSettings settings,
  ContestSettingCubit contestCubit,
  TrainingOptionsCubit optionsCubit,
  void Function() dispose,
});

Future<_Harness> _pumpSheet(
  WidgetTester tester, {
  bool running = false,
  Locale locale = const Locale('en'),
  SettingsTab initialTab = SettingsTab.contestStation,
  String? focusFieldKey,
  void Function(AppSettings settings)? configure,
}) async {
  final prefs = await SharedPreferencesWithCache.create(
    cacheOptions: const SharedPreferencesWithCacheOptions(),
  );
  final settings = AppSettings(prefs: prefs);
  configure?.call(settings);
  final database = _createNeverOpenedDatabase();
  final dxccManager = DxccManager(database: database);
  final inputHandler = ContestInputHandler();
  final dataManager = ContestDataManager(
    audioLoader: AudioLoader(),
    audioPlayer: AudioPlayer(),
    appSettings: settings,
    appDatabase: database,
    callsignLoader: CallsignLoader(),
    dxccManager: dxccManager,
    inputHandler: inputHandler,
  );
  final manager = running
      ? _RunningContestManager(contestDataManager: dataManager)
      : ContestManager(contestDataManager: dataManager);

  final runningCubit = MainSettingsCubit(contestManager: manager);
  final contestCubit = ContestSettingCubit(appSettings: settings);
  final stationCubit = StationCallsignCubit(appSettings: settings);
  final optionsCubit = TrainingOptionsCubit(settings);

  await tester.pumpWidget(
    ToastificationWrapper(
      child: MaterialApp(
        theme: AppTheme.light,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MultiRepositoryProvider(
          providers: [
            RepositoryProvider<AppSettings>.value(value: settings),
            RepositoryProvider<DxccManager>.value(value: dxccManager),
            RepositoryProvider<ContestManager>.value(value: manager),
          ],
          child: MultiBlocProvider(
            providers: [
              BlocProvider<MainSettingsCubit>.value(value: runningCubit),
              BlocProvider<ContestSettingCubit>.value(value: contestCubit),
              BlocProvider<StationCallsignCubit>.value(value: stationCubit),
              BlocProvider<TrainingOptionsCubit>.value(value: optionsCubit),
            ],
            child: Scaffold(
              body: SettingsSheet(
                initialTab: initialTab,
                focusFieldKey: focusFieldKey,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();

  return (
    settings: settings,
    contestCubit: contestCubit,
    optionsCubit: optionsCubit,
    dispose: () {
      runningCubit.close();
      contestCubit.close();
      stationCubit.close();
      optionsCubit.close();
    },
  );
}

class _RunningContestManager extends ContestManager {
  _RunningContestManager({required super.contestDataManager});

  @override
  bool get isContestRunning => true;

  @override
  Stream<bool> get isContestRunningStream => const Stream<bool>.empty();
}

AppDatabase? _neverOpenedDatabase;

/// The settings widgets may not touch the database, so a lazy executor keeps
/// the tests free of platform channels and the native sqlite library.
AppDatabase _createNeverOpenedDatabase() =>
    _neverOpenedDatabase ??= AppDatabase(
      LazyDatabase(
        () async => throw StateError(
          'The settings widgets must not touch the database.',
        ),
      ),
    );
