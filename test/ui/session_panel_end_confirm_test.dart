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
import 'package:ssb_runner/contest_run/new/contest_timer.dart';
import 'package:ssb_runner/db/app_database.dart';
import 'package:ssb_runner/dxcc/dxcc_manager.dart';
import 'package:ssb_runner/l10n/generated/app_localizations.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/ui/main_page/session_panel.dart';
import 'package:ssb_runner/ui/main_page/settings_cubits.dart';
import 'package:ssb_runner/ui/qso_result_table/qso_result_list/qso_result_list_cubit.dart';
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

  testWidgets('运行态点结束本局先确认，取消后会话继续、确认后才结束', (
    tester,
  ) async {
    final harness = await _createHarness();
    await _pumpSessionPanel(tester, harness);

    expect(find.text('Pause training'), findsOneWidget);
    expect(find.text('End session'), findsOneWidget);

    await tester.tap(find.text('End session'));
    await tester.pumpAndSettle();

    expect(find.text('End this session?'), findsOneWidget);
    expect(
      find.text(
        'Unfinished questions and remaining time will be lost; already logged QSOs are kept.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(harness.manager.stopCalls, 0);
    expect(find.text('End this session?'), findsNothing);
    expect(
      find.text('Pause training'),
      findsOneWidget,
      reason: 'cancelling must leave the run untouched',
    );

    await tester.tap(find.text('End session'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('End and view review'));
    await tester.pumpAndSettle();

    expect(harness.manager.stopCalls, 1);
    expect(find.text('End this session?'), findsNothing);
    expect(
      find.text('Start training'),
      findsOneWidget,
      reason: 'confirming ends the run and returns the panel to idle',
    );

    expect(tester.takeException(), isNull);
  });
}

typedef _Harness = ({
  AppSettings settings,
  ContestDataManager dataManager,
  _PhaseContestManager manager,
});

Future<_Harness> _createHarness() async {
  final prefs = await SharedPreferencesWithCache.create(
    cacheOptions: const SharedPreferencesWithCacheOptions(),
  );
  final settings = AppSettings(prefs: prefs);
  final database = AppDatabase(
    LazyDatabase(() async => throw StateError('no db')),
  );
  final dataManager = ContestDataManager(
    audioLoader: AudioLoader(),
    audioPlayer: AudioPlayer(),
    appSettings: settings,
    appDatabase: database,
    callsignLoader: CallsignLoader(),
    dxccManager: DxccManager(database: database),
    inputHandler: ContestInputHandler(),
  );
  final manager = _PhaseContestManager(contestDataManager: dataManager);
  return (settings: settings, dataManager: dataManager, manager: manager);
}

Future<void> _pumpSessionPanel(WidgetTester tester, _Harness harness) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1280, 720);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MultiRepositoryProvider(
        providers: [
          RepositoryProvider<AppSettings>.value(value: harness.settings),
          RepositoryProvider<ContestManager>.value(value: harness.manager),
          RepositoryProvider<ContestTimer>.value(
            value: harness.manager.contestTimer,
          ),
          RepositoryProvider<DxccManager>.value(
            value: harness.dataManager.dxccManager,
          ),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider(
              create: (_) => ContestSettingCubit(appSettings: harness.settings),
            ),
            BlocProvider(
              create: (_) => TrainingOptionsCubit(harness.settings),
            ),
            BlocProvider(
              create: (_) => QsoRecordListCubit(
                appDatabase: harness.dataManager.appDatabase,
                contestManager: harness.manager,
              ),
            ),
          ],
          child: const Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 372,
                height: 620,
                child: SessionPanel(),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// Starts in the running phase and records every [stopContest] call instead of
/// touching the database.
class _PhaseContestManager extends ContestManager {
  _PhaseContestManager({required super.contestDataManager})
    : _phase = ContestSessionPhase.running;

  final _phaseController = StreamController<ContestSessionPhase>.broadcast();
  ContestSessionPhase _phase;

  int stopCalls = 0;

  @override
  ContestSessionPhase get sessionPhase => _phase;

  @override
  Stream<ContestSessionPhase> get sessionPhaseStream =>
      _phaseController.stream;

  @override
  bool get isContestRunning => _phase != ContestSessionPhase.idle;

  @override
  void stopContest({String reason = 'stopped'}) {
    stopCalls++;
    _phase = ContestSessionPhase.idle;
    _phaseController.add(_phase);
  }
}
