import 'package:drift/drift.dart' hide isNull;
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
    // Contest exchange plus the read-only station exchange line.
    expect(find.text('Exchange'), findsNWidgets(2));

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

  testWidgets('switching contest updates contest and station fields at once', (
    tester,
  ) async {
    final harness = await _pumpSheet(tester);

    expect(find.text('59 #'), findsNWidgets(2));

    harness.contestCubit.changeContest('CQ-WW-SSB');
    await tester.pump();
    await tester.pump();

    expect(find.text('59 #'), findsNothing);
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
}) async {
  final prefs = await SharedPreferencesWithCache.create(
    cacheOptions: const SharedPreferencesWithCacheOptions(),
  );
  final settings = AppSettings(prefs: prefs);
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
            child: const Scaffold(body: SettingsSheet()),
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
