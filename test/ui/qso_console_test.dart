import 'dart:async';

import 'package:drift/drift.dart' hide isNull;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/audio/audio_loader.dart';
import 'package:ssb_runner/audio/audio_player.dart';
import 'package:ssb_runner/callsign/callsign_loader.dart';
import 'package:ssb_runner/contest_run/key_event_handler.dart';
import 'package:ssb_runner/contest_run/new/contest_data_manager.dart';
import 'package:ssb_runner/contest_run/new/contest_input_handler.dart';
import 'package:ssb_runner/contest_run/new/contest_manager.dart';
import 'package:ssb_runner/contest_run/new/contest_operation_event_handler.dart';
import 'package:ssb_runner/contest_run/new/contest_running_manager.dart';
import 'package:ssb_runner/contest_run/score_manager.dart';
import 'package:ssb_runner/contest_run/state_machine/single_call/single_call_run_event.dart';
import 'package:ssb_runner/contest_run/state_machine/single_call/single_call_run_state.dart';
import 'package:ssb_runner/db/app_database.dart';
import 'package:ssb_runner/dxcc/dxcc_manager.dart';
import 'package:ssb_runner/l10n/generated/app_localizations.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/training/training_profile.dart';
import 'package:ssb_runner/ui/main_page/qso_console.dart';
import 'package:ssb_runner/ui/main_page/settings_cubits.dart';
import 'package:ssb_runner/ui/qso_result_table/qso_result_list/qso_result.dart';
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

  testWidgets('the keyboard entry stays visible when the action row wraps', (
    tester,
  ) async {
    final harness = await _createHarness();
    await _pumpConsole(tester, harness, width: 1024, consoleWidth: 660);

    expect(find.byIcon(Icons.keyboard_outlined), findsOneWidget);
    expect(find.text('Wipe'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.keyboard_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Keyboard reference'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  testWidgets('nine actions split into two balanced rows of one cell width', (
    tester,
  ) async {
    final harness = await _createHarness();
    await _pumpConsole(tester, harness, width: 1024, consoleWidth: 668);

    const labels = [
      'CQ',
      'EXCH',
      'TU',
      '<my>',
      '<his>',
      'B4',
      'AGN',
      'NIL',
      'Wipe',
    ];
    final tops = {
      for (final label in labels) label: tester.getRect(find.text(label)).top,
    };
    final firstRowTop = tops['CQ']!;

    expect(
      tops.values.where((top) => (top - firstRowTop).abs() < 1).length,
      5,
      reason: '9 actions must be split 5 + 4 so F12 is not left alone',
    );
    expect(
      (tops['B4']! - firstRowTop).abs(),
      closeTo(52, 0.5),
      reason: 'row pitch is the 44px button plus the 8px gap',
    );

    final buttonSizes = {
      for (final label in labels)
        tester
            .getSize(
              find
                  .ancestor(
                    of: find.text(label),
                    matching: find.byType(InkWell),
                  )
                  .first,
            )
            .toString(),
    };
    expect(buttonSizes, hasLength(1), reason: 'every cell shares one width');
    expect(
      tester
          .getSize(
            find
                .ancestor(of: find.text('CQ'), matching: find.byType(InkWell))
                .first,
          )
          .height,
      44,
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('a wide console stops stretching the action cells at 280px', (
    tester,
  ) async {
    final harness = await _createHarness();
    await _pumpConsole(tester, harness, width: 1800, consoleWidth: 1600);

    expect(
      tester
          .getSize(
            find
                .ancestor(of: find.text('CQ'), matching: find.byType(InkWell))
                .first,
          )
          .width,
      280,
    );

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

  testWidgets('the console shows call, RST, sent and received in order', (
    tester,
  ) async {
    final harness = await _createHarness();
    await _pumpConsole(tester, harness, width: 1024, consoleWidth: 668);

    const keys = [
      Key('call-field'),
      Key('rst-field'),
      Key('sent-exchange-field'),
      Key('received-exchange-field'),
    ];
    final lefts = [
      for (final key in keys) tester.getTopLeft(find.byKey(key)).dx,
    ];
    expect(
      lefts,
      orderedEquals([...lefts]..sort()),
      reason: 'Call → RST → sent → received, matching N1MM order',
    );

    final rst = tester.widget<TextField>(find.byKey(keys[1]));
    expect(rst.readOnly, isTrue);
    expect(rst.canRequestFocus, isFalse);
    expect(rst.controller!.text, '59');
    expect(rst.decoration!.suffixText, isNull);

    final sent = tester.widget<TextField>(find.byKey(keys[2]));
    expect(sent.readOnly, isTrue);
    expect(sent.canRequestFocus, isFalse);
    expect(sent.decoration!.labelText, 'Sent');
    expect(sent.controller!.text, '001');
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);

    final received = tester.widget<TextField>(find.byKey(keys[3]));
    expect(received.decoration!.labelText, 'Rcvd');
    expect(received.readOnly, isFalse);

    expect(tester.takeException(), isNull);
  });

  testWidgets('a configured CQ zone is shown in its spoken form', (
    tester,
  ) async {
    final harness = await _createHarness();
    harness.settings
      ..contestId = 'CQ-WW-SSB'
      ..setStationExchangeValue('CQ-WW-SSB', 'cqZone', '5');
    await _pumpConsole(tester, harness, width: 1024, consoleWidth: 668);

    final sent = tester.widget<TextField>(
      find.byKey(const Key('sent-exchange-field')),
    );
    expect(
      sent.controller!.text,
      '05',
      reason: 'the audio reads zero-five for a configured 5',
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('an unconfigured exchange shows a dash', (tester) async {
    final harness = await _createHarness();
    harness.settings.contestId = 'IARU-HF';
    await _pumpConsole(tester, harness, width: 1024, consoleWidth: 668);

    expect(_sentText(tester), '—');
    expect(tester.takeException(), isNull);
  });

  testWidgets('F2 only moves focus to the received exchange', (tester) async {
    final harness = await _createHarness();
    await _pumpConsole(tester, harness, width: 1024, consoleWidth: 668);

    harness.inputHandler.onRstFilled(true);
    await tester.pump();

    final rst = tester.widget<TextField>(find.byKey(const Key('rst-field')));
    expect(rst.controller!.text, '59');
    final received = tester.widget<TextField>(
      find.byKey(const Key('received-exchange-field')),
    );
    expect(received.focusNode!.hasFocus, isTrue);

    expect(tester.takeException(), isNull);
  });

  testWidgets('the four fields fit the 640px console without overflow', (
    tester,
  ) async {
    final harness = await _createHarness();
    await _pumpConsole(tester, harness, width: 1024, consoleWidth: 640);

    expect(tester.takeException(), isNull);
    // The read-only cells keep enough room for their fixed values.
    expect(
      tester.getSize(find.byKey(const Key('rst-field'))).width,
      greaterThan(50),
    );
    expect(
      tester.getSize(find.byKey(const Key('sent-exchange-field'))).width,
      greaterThan(80),
    );
  });

  testWidgets('Tab skips the two read-only fields', (tester) async {
    final harness = await _createHarness();
    await _pumpConsole(tester, harness, width: 1024, consoleWidth: 668);

    await tester.tap(find.byKey(const Key('call-field')));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    final received = tester.widget<TextField>(
      find.byKey(const Key('received-exchange-field')),
    );
    expect(
      received.focusNode!.hasFocus,
      isTrue,
      reason: 'RST and the sent exchange must not join the Tab order',
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('the lock icon deep links to the station settings on standby', (
    tester,
  ) async {
    final harness = await _createHarness();
    harness.settings.contestId = 'CQ-WW-SSB';
    await _pumpConsole(tester, harness, width: 1024, consoleWidth: 668);

    await tester.tap(find.byIcon(Icons.lock_outline));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Settings'), findsOneWidget);
    expect(
      find.text('CQ Zone'),
      findsOneWidget,
      reason: 'the drawer opens on the field that owns the sent exchange',
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('standby previews the first QSO even with a finished log', (
    tester,
  ) async {
    final harness = await _createHarness();
    final manager = ContestManager(contestDataManager: harness.dataManager);
    final list = _StubQsoRecordListCubit(
      appDatabase: harness.dataManager.appDatabase,
      contestManager: manager,
    )..setRecords(2);
    await _pumpConsole(
      tester,
      harness,
      manager: manager,
      recordListCubit: list,
      width: 1024,
      consoleWidth: 668,
    );

    expect(
      _sentText(tester),
      '001',
      reason: 'standby must not reuse the previous run list length',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a logged QSO advances the sent serial while running', (
    tester,
  ) async {
    final harness = await _createHarness();
    final runningManager = _FakeRunningManager();
    final manager = _RunningContestManager(
      contestDataManager: harness.dataManager,
      runningManager: runningManager,
    );
    final list = _StubQsoRecordListCubit(
      appDatabase: harness.dataManager.appDatabase,
      contestManager: manager,
    )..setRecords(1);
    await _pumpConsole(
      tester,
      harness,
      manager: manager,
      recordListCubit: list,
      width: 1024,
      consoleWidth: 668,
    );

    expect(_sentText(tester), '002');

    list.setRecords(2);
    await tester.pump();
    await tester.pump();

    expect(
      _sentText(tester),
      '003',
      reason: 'D3: the field moves to the next serial right after logging',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the lock is disabled while a session runs', (tester) async {
    final harness = await _createHarness();
    final manager = _RunningContestManager(
      contestDataManager: harness.dataManager,
      runningManager: _FakeRunningManager(),
    );
    await _pumpConsole(
      tester,
      harness,
      manager: manager,
      width: 1024,
      consoleWidth: 668,
    );

    final lock = find.byIcon(Icons.lock_outline);
    expect(
      tester
          .widget<Tooltip>(
            find.ancestor(of: lock, matching: find.byType(Tooltip)),
          )
          .message,
      "Locked while the contest runs; stop to edit",
    );

    await tester.tap(lock);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Settings'), findsNothing);
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

/// Reports a running session without building a real running manager, so the
/// console's sent field can be exercised in its running branch.
class _RunningContestManager extends ContestManager {
  _RunningContestManager({
    required super.contestDataManager,
    required this.runningManager,
  });

  final ContestRunningManager runningManager;

  @override
  bool get isContestRunning => true;

  @override
  Stream<bool> get isContestRunningStream => Stream<bool>.value(true);

  @override
  ContestRunningManager? get contestRunningManager => runningManager;
}

/// The only members [QsoConsoleCubit] touches while it binds to a session.
class _FakeRunningManager implements ContestRunningManager {
  @override
  final String runId = 'test-run';

  @override
  final TrainingDifficulty difficulty = TrainingDifficulty.beginner;

  @override
  SingleCallRunState get currentState => WaitingSubmitCall(
    currentCallAnswer: 'A1AAA',
    currentExchangeAnswer: '59 001',
    pileupCallsigns: const [],
  );

  @override
  Stream<SingleCallRunState> get stateStream =>
      Stream<SingleCallRunState>.empty();

  @override
  ContestOperationEventHandler get contestOperationEventHandler =>
      _operationHandler;

  @override
  ScoreManager get scoreManager => throw UnimplementedError();

  @override
  void stop() {}

  final _operationHandler = _FakeOperationHandler();
}

class _FakeOperationHandler implements ContestOperationEventHandler {
  @override
  Stream<int> get inputControlStream => Stream<int>.empty();

  @override
  Future<void> handleOperationEvent(OperationEvent event) async {}

  @override
  void handleInputAreaEvent() {}

  @override
  Future<Uint8List> obtainMyCqAudioData() async => Uint8List(0);

  @override
  Future<Uint8List> obtainMySentExchangeAudioData() async => Uint8List(0);

  @override
  Future<Uint8List> obtainHisCallAndMyExchange(String hisCall) async =>
      Uint8List(0);

  @override
  void transition(SingleCallRunEvent event) {}
}

/// Lets a test set the raw logged-row count (DUPE rows included) directly,
/// because the real cubit only listens to the database.
class _StubQsoRecordListCubit extends QsoRecordListCubit {
  _StubQsoRecordListCubit({
    required super.appDatabase,
    required super.contestManager,
  });

  void setRecords(int count) {
    emit([
      for (var index = 0; index < count; index++)
        QsoResult(
          call: QsoResultField(data: 'A1AAA', isCorrect: true),
          exchange: QsoResultField(data: '001', isCorrect: true),
          utc: '00:00',
          corrections: '',
        ),
    ]);
  }
}

String _sentText(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(const Key('sent-exchange-field')))
    .controller!
    .text;

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
  ContestManager? manager,
  QsoRecordListCubit? recordListCubit,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 720);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final contestManager =
      manager ?? ContestManager(contestDataManager: harness.dataManager);
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
            RepositoryProvider<DxccManager>.value(
              value: harness.dataManager.dxccManager,
            ),
            RepositoryProvider<ContestInputHandler>.value(
              value: harness.inputHandler,
            ),
          ],
          child: MultiBlocProvider(
            providers: [
              BlocProvider(
                create: (_) =>
                    MainSettingsCubit(contestManager: contestManager),
              ),
              BlocProvider(
                create: (_) =>
                    ContestSettingCubit(appSettings: harness.settings),
              ),
              BlocProvider(
                create: (_) =>
                    StationCallsignCubit(appSettings: harness.settings),
              ),
              BlocProvider(
                create: (_) => TrainingOptionsCubit(harness.settings),
              ),
              // Mirrors MainPage: the sent-exchange field reads the raw row
              // count (DUPE included) once a run has started.
              BlocProvider(
                create: (context) =>
                    recordListCubit ??
                    QsoRecordListCubit(
                      appDatabase: harness.dataManager.appDatabase,
                      contestManager: contestManager,
                    ),
              ),
            ],
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: consoleWidth, child: const QsoConsole()),
            ),
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
