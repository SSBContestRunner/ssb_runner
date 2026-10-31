import 'dart:async';

import 'package:drift/drift.dart' hide isNull;
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
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/ui/main_page/qso_console.dart';
import 'package:ssb_runner/ui/theme/app_theme.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('only assigned actions are shown, with no Spare buttons', (
    tester,
  ) async {
    final harness = await _createHarness();
    await _pumpConsole(tester, harness);

    for (final text in [
      'CQ',
      'EXCH',
      'TU',
      '<my>',
      '<his>',
      'B4',
      'AGN',
      'NIL',
      'Wipe',
    ]) {
      expect(find.text(text), findsOneWidget);
    }
    expect(find.text('Spare'), findsNothing);
    expect(find.text('F9'), findsNothing);
    expect(find.text('F12'), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_outlined), findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  testWidgets('the repeated keyboard entry is hidden at 1024 width', (
    tester,
  ) async {
    final harness = await _createHarness();
    await _pumpConsole(tester, harness, width: 1024, consoleWidth: 660);

    // The topbar entry stays; only the action-row duplicate is removed.
    expect(find.byIcon(Icons.keyboard_outlined), findsNothing);
    expect(find.text('Wipe'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  testWidgets('saved bindings refresh the action row immediately', (
    tester,
  ) async {
    final harness = await _createHarness();
    await _pumpConsole(tester, harness);

    expect(find.text('CQ'), findsOneWidget);

    await harness.settings.setFunctionKeyBindings([
      for (final key in FunctionKey.values)
        FunctionKeyBinding(
          key,
          key == FunctionKey.f1 ? null : key.defaultAction,
        ),
    ]);
    await tester.pump();

    expect(find.text('CQ'), findsNothing);
    expect(find.text('EXCH'), findsOneWidget);
    expect(find.text('F1'), findsNothing);

    expect(tester.takeException(), isNull);
  });

  test(
    'the console cubit follows the contest lifecycle for mouse clicks',
    () async {
      final harness = await _createHarness();
      final manager = _ContestManagerSpy(
        contestDataManager: harness.dataManager,
      );

      final cubit = QsoConsoleCubit(
        contestManager: manager,
        contestInputHandler: harness.inputHandler,
      );
      addTearDown(cubit.close);

      expect(
        manager.hasRunningListener,
        isTrue,
        reason:
            'without a subscription the clicked operation event has no handler',
      );
    },
  );
}

class _ContestManagerSpy extends ContestManager {
  _ContestManagerSpy({required super.contestDataManager});

  final _runningController = StreamController<bool>.broadcast();

  @override
  Stream<bool> get isContestRunningStream => _runningController.stream;

  bool get hasRunningListener => _runningController.hasListener;
}

typedef _Harness = ({
  AppSettings settings,
  ContestDataManager dataManager,
  ContestInputHandler inputHandler,
});

Future<void> _pumpConsole(
  WidgetTester tester,
  _Harness harness, {
  double width = 1280,
  double consoleWidth = 874,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 720);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final contestManager = ContestManager(
    contestDataManager: harness.dataManager,
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: MultiRepositoryProvider(
          providers: [
            RepositoryProvider<AppSettings>.value(value: harness.settings),
            RepositoryProvider<ContestManager>.value(value: contestManager),
            RepositoryProvider<ContestInputHandler>.value(
              value: harness.inputHandler,
            ),
          ],
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: consoleWidth, child: const QsoConsole()),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<_Harness> _createHarness() async {
  final prefs = await SharedPreferencesWithCache.create(
    cacheOptions: const SharedPreferencesWithCacheOptions(),
  );
  final settings = AppSettings(prefs: prefs);
  final database = AppDatabase(
    LazyDatabase(() async => throw StateError('no db')),
  );
  final inputHandler = ContestInputHandler();
  final dataManager = ContestDataManager(
    audioLoader: AudioLoader(),
    audioPlayer: AudioPlayer(),
    appSettings: settings,
    appDatabase: database,
    callsignLoader: CallsignLoader(),
    dxccManager: DxccManager(database: database),
    inputHandler: inputHandler,
  );
  return (
    settings: settings,
    dataManager: dataManager,
    inputHandler: inputHandler,
  );
}
