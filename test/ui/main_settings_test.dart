import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/audio/audio_loader.dart';
import 'package:ssb_runner/audio/audio_player.dart';
import 'package:ssb_runner/callsign/callsign_loader.dart';
import 'package:ssb_runner/contest_run/new/contest_data_manager.dart';
import 'package:ssb_runner/contest_run/new/contest_input_handler.dart';
import 'package:ssb_runner/contest_run/new/contest_manager.dart';
import 'package:ssb_runner/db/app_database.dart';
import 'package:ssb_runner/dxcc/dxcc_manager.dart';
import 'package:ssb_runner/l10n/generated/app_localizations.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/ui/main_settings/main_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('Contest and Exchange fill the panel width on separate rows', (
    tester,
  ) async {
    final settings = await _createSettings();
    // ARRL has the longest exchange label
    // ("59 State/Province (W/VE) / 59 Power (DX)").
    settings.contestId = 'ARRL-DX';

    await _pumpSettings(tester, settings);

    // SettingItem pads 14px on each side of the 370px sidebar.
    const contentWidth = 370.0 - 28.0;

    final dropdown = find.byType(DropdownMenu<String>);
    expect(dropdown, findsOneWidget);
    expect(tester.getSize(dropdown).width, contentWidth);

    final exchange = _exchangeField();
    expect(exchange, findsOneWidget);
    expect(tester.getSize(exchange).width, contentWidth);

    // The two fields must be stacked, so the long exchange label gets the whole
    // width instead of being clipped beside the name.
    expect(
      tester.getBottomLeft(dropdown).dy,
      lessThanOrEqualTo(tester.getTopLeft(exchange).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the info button opens the rules for the current contest', (
    tester,
  ) async {
    final settings = await _createSettings();

    await _pumpSettings(tester, settings);
    await _openRulesDialog(tester);

    expect(find.text('CQ WPX rules'), findsOneWidget);
    expect(find.text('You send: 59 + 3-digit serial number'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the rules dialog follows the contest selected in Settings', (
    tester,
  ) async {
    final settings = await _createSettings();

    await _pumpSettings(tester, settings);
    // A full-page test cannot use find.byIcon: the bottom panel has its own
    // info icon, so the rules button is located by key.
    _contestCubit(tester).changeContest('CQ-WW-SSB');
    await tester.pump();

    await _openRulesDialog(tester);

    expect(find.text('CQ WW rules'), findsOneWidget);
    expect(find.text('You send: 59 + CQ zone'), findsOneWidget);
    expect(find.text('You send: 59 + 3-digit serial number'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing the rules dialog removes it', (tester) async {
    final settings = await _createSettings();

    await _pumpSettings(tester, settings);
    await _openRulesDialog(tester);

    await tester.tap(find.text('Close'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('CQ WPX rules'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the rules button stays clickable while a contest is running', (
    tester,
  ) async {
    final settings = await _createSettings();

    await _pumpSettings(
      tester,
      settings,
      contestManager: (contestDataManager) =>
          _RunningContestManager(contestDataManager: contestDataManager),
    );

    // Settings are read-only during a run, but the rules stay available.
    expect(
      tester
          .widget<DropdownMenu<String>>(find.byType(DropdownMenu<String>))
          .enabled,
      isFalse,
    );
    expect(tester.widget<TextField>(_exchangeField()).enabled, isFalse);

    await _openRulesDialog(tester);

    expect(find.text('CQ WPX rules'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// A ContestManager that reports an active run without starting one, so the
/// settings panel enters its read-only state.
class _RunningContestManager extends ContestManager {
  _RunningContestManager({required super.contestDataManager});

  @override
  bool get isContestRunning => true;

  @override
  Stream<bool> get isContestRunningStream => const Stream<bool>.empty();
}

ContestSettingCubit _contestCubit(WidgetTester tester) =>
    BlocProvider.of<ContestSettingCubit>(
      tester.element(find.byType(DropdownMenu<String>)),
    );

/// Opens the rules dialog. The idle dropdown keeps a cursor animation running,
/// so pumpAndSettle would time out; pump the dialog transition explicitly.
Future<void> _openRulesDialog(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('contest-rules-button')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Finder _exchangeField() => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == 'Exchange',
);

Future<AppSettings> _createSettings() async {
  final prefs = await SharedPreferencesWithCache.create(
    cacheOptions: const SharedPreferencesWithCacheOptions(),
  );
  return AppSettings(prefs: prefs);
}

Future<void> _pumpSettings(
  WidgetTester tester,
  AppSettings settings, {
  ContestManager Function(ContestDataManager)? contestManager,
}) async {
  final database = _createNeverOpenedDatabase();
  final dxccManager = DxccManager(database: database);
  final contestDataManager = ContestDataManager(
    audioLoader: AudioLoader(),
    audioPlayer: AudioPlayer(),
    appSettings: settings,
    appDatabase: database,
    callsignLoader: CallsignLoader(),
    dxccManager: dxccManager,
    inputHandler: ContestInputHandler(),
  );
  final manager =
      contestManager?.call(contestDataManager) ??
      ContestManager(contestDataManager: contestDataManager);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MultiRepositoryProvider(
        providers: [
          RepositoryProvider<AppSettings>.value(value: settings),
          RepositoryProvider<DxccManager>.value(value: dxccManager),
          RepositoryProvider<ContestManager>.value(value: manager),
        ],
        child: const Scaffold(body: MainSettings()),
      ),
    ),
  );
  // No pumpAndSettle: an idle DropdownMenu keeps a blinking cursor scheduled.
  await tester.pump();
}

AppDatabase? _neverOpenedDatabase;

/// None of the settings widgets may touch the database, so a lazy executor
/// keeps the tests free of platform channels and the native sqlite library.
/// The instance is shared so drift does not warn about multiple databases.
AppDatabase _createNeverOpenedDatabase() =>
    _neverOpenedDatabase ??= AppDatabase(
      drift.LazyDatabase(
        () async => throw StateError(
          'The settings widgets must not touch the database.',
        ),
      ),
    );
