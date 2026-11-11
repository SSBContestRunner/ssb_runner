import 'dart:async';

import 'package:drift/drift.dart' hide isNull;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:ssb_runner/training/pending_replay.dart';
import 'package:ssb_runner/ui/main_page/main_page.dart';
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
import 'package:toastification/toastification.dart';

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

  testWidgets('最小窗口下五语言四态都不滚动，只读格不被裁', (tester) async {
    await _ensureAppFonts();
    // Content area 1108x772 (the macOS window frame is about 1108x796).
    const size = Size(1108, 772);
    const locales = [
      Locale('en'),
      Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
      Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      Locale('ja'),
      Locale('de'),
    ];

    for (final locale in locales) {
      for (final scale in const [1.0, 1.3]) {
        for (final state in const ['running', 'armed', 'paused', 'resuming']) {
          final context = '${locale.toLanguageTag()} x$scale $state';
          final manager = await _pumpMainPage(
            tester,
            size,
            locale: locale,
            textScale: scale,
            phase: _phaseFor(state),
            armed: state == 'armed',
          );

          expect(
            tester.takeException(),
            isNull,
            reason: 'nothing may overflow at $context',
          );

          final scroll = _sessionBodyScroll(tester).maxScrollExtent;
          expect(
            scroll,
            0,
            reason: 'the session card must not scroll at $context',
          );

          for (final field in const [
            (key: Key('rst-field'), name: 'RST 59'),
            (key: Key('sent-exchange-field'), name: 'sent exchange 599'),
          ]) {
            final metrics = _fieldMetrics(tester, field.key);
            expect(
              metrics.needed,
              lessThanOrEqualTo(metrics.visible),
              reason: '${field.name} is clipped at $context',
            );
          }

          final strip = find.byKey(const Key('resumeStrip'));
          if (state == 'resuming') {
            final l10n = AppLocalizations.of(tester.element(strip));
            expect(
              find.descendant(of: strip, matching: find.text(l10n.resumeHint)),
              findsNothing,
              reason: 'the hint lives in the tooltip at $context',
            );
            expect(
              find.byTooltip(l10n.resumeHint),
              findsOneWidget,
              reason: 'the hint stays reachable at $context',
            );
            expect(
              tester.getSize(strip).height,
              lessThan(64),
              reason: 'the strip must stay a single row at $context',
            );
          } else {
            expect(strip, findsNothing);
          }

          await _tearDown(tester, manager);
        }
      }
    }
  });

  testWidgets('恢复中跳过只恢复一次，提示仍可从 tooltip 读到', (tester) async {
    await _ensureAppFonts();
    final manager = await _pumpMainPage(
      tester,
      const Size(1108, 772),
      phase: ContestSessionPhase.resuming,
    );

    expect(find.text('Resume now'), findsOneWidget);
    expect(
      find.byTooltip(
        'Continues from the pause point, not from the start of the question',
      ),
      findsOneWidget,
      reason: 'the compact strip moves the hint into the tooltip',
    );

    await tester.tap(find.text('Resume now'));
    await tester.pump();

    expect(manager.completeResumeCalls, 1);
    expect(find.text('Pause training'), findsOneWidget);
    expect(find.byKey(const Key('resumeStrip')), findsNothing);
    expect(manager.completeResumeCalls, 1, reason: 'skip must be idempotent');

    await _tearDown(tester, manager);
  });

  testWidgets('恢复中倒计时三秒后自动完成且只完成一次', (tester) async {
    await _ensureAppFonts();
    final manager = await _pumpMainPage(
      tester,
      const Size(1108, 772),
      phase: ContestSessionPhase.resuming,
    );

    expect(find.text('3'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('2'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('1'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));

    expect(manager.completeResumeCalls, 1);
    expect(find.text('Pause training'), findsOneWidget);
    expect(find.byKey(const Key('resumeStrip')), findsNothing);

    await _tearDown(tester, manager);
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
  final database = _neverOpenedDatabase;
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

/// Pumps the whole page so the session card gets the height the real window
/// gives it (body rows, rules card and margins included).
Future<_PhaseContestManager> _pumpMainPage(
  WidgetTester tester,
  Size size, {
  Locale locale = const Locale('en'),
  double textScale = 1,
  ContestSessionPhase phase = ContestSessionPhase.running,
  bool armed = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final prefs = await SharedPreferencesWithCache.create(
    cacheOptions: const SharedPreferencesWithCacheOptions(),
  );
  final settings = AppSettings(prefs: prefs);
  if (armed) {
    settings.armReplay(_armedReplay());
  }
  final database = _neverOpenedDatabase;
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
  final manager = _PhaseContestManager(
    contestDataManager: dataManager,
    initialPhase: phase,
  );

  await tester.pumpWidget(
    ToastificationWrapper(
      child: MaterialApp(
        theme: AppTheme.light,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: MultiRepositoryProvider(
          providers: [
            RepositoryProvider<AppSettings>.value(value: settings),
            RepositoryProvider<AppDatabase>.value(value: database),
            RepositoryProvider<DxccManager>.value(value: dxccManager),
            RepositoryProvider<ContestManager>.value(value: manager),
            RepositoryProvider<ContestTimer>.value(
              value: manager.contestTimer,
            ),
            RepositoryProvider<ContestInputHandler>.value(value: inputHandler),
          ],
          child: const Scaffold(body: MainPage()),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return manager;
}

Future<void> _tearDown(WidgetTester tester, _PhaseContestManager manager) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  manager.dispose();
}

typedef _FieldMetrics = ({double visible, double needed});

_FieldMetrics _fieldMetrics(WidgetTester tester, Key fieldKey) {
  final editable = find.descendant(
    of: find.byKey(fieldKey),
    matching: find.byType(EditableText),
  );
  final state = tester.state<EditableTextState>(editable);
  final render = state.renderEditable;
  final text = state.textEditingValue.text;
  if (text.isEmpty) {
    return (visible: render.size.width, needed: 0);
  }
  final boxes = render.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: text.length),
  );
  return (
    visible: render.size.width,
    needed: boxes.fold<double>(
      0,
      (max, box) => box.right > max ? box.right : max,
    ),
  );
}

ContestSessionPhase _phaseFor(String state) => switch (state) {
  'running' => ContestSessionPhase.running,
  'paused' => ContestSessionPhase.paused,
  'resuming' => ContestSessionPhase.resuming,
  _ => ContestSessionPhase.idle,
};

PendingReplay _armedReplay() => PendingReplay(
  runId: 'run-1',
  contestId: 'CQ-WW-SSB',
  contestName: 'CQ WW SSB',
  modeId: 'single',
  difficultyId: 'beginner',
  questionSeed: 1,
  audioSeed: 1,
  armedAtUtc: DateTime.utc(2026, 11, 7, 12),
);

ScrollPosition _sessionBodyScroll(WidgetTester tester) {
  final scroller = find.descendant(
    of: find.byType(SessionPanel),
    matching: find.byType(SingleChildScrollView),
  );
  final scrollable = find.descendant(
    of: scroller,
    matching: find.byType(Scrollable),
  );
  return tester.state<ScrollableState>(scrollable).position;
}

bool _appFontsLoaded = false;

Future<void> _ensureAppFonts() async {
  if (_appFontsLoaded) return;
  _appFontsLoaded = true;
  await (FontLoader(
    'Iosevka',
  )..addFont(rootBundle.load('fonts/Iosevka-Regular-sub.ttf'))).load();
  await (FontLoader('Noto Sans SC')
        ..addFont(rootBundle.load('fonts/NotoSansSC-Regular-sub.otf'))
        ..addFont(rootBundle.load('fonts/NotoSansSC-Medium-sub.otf'))
        ..addFont(rootBundle.load('fonts/NotoSansSC-Bold-sub.otf')))
      .load();
}

final AppDatabase _neverOpenedDatabase = AppDatabase(
  LazyDatabase(
    () async => throw StateError('The layout widgets must not touch the database.'),
  ),
);

/// Starts in the running phase and records every [stopContest] /
/// [completeResume] call instead of touching the database.
class _PhaseContestManager extends ContestManager {
  _PhaseContestManager({
    required super.contestDataManager,
    ContestSessionPhase initialPhase = ContestSessionPhase.running,
  }) : _phase = initialPhase;

  final _phaseController = StreamController<ContestSessionPhase>.broadcast();
  ContestSessionPhase _phase;

  int stopCalls = 0;
  int completeResumeCalls = 0;

  @override
  ContestSessionPhase get sessionPhase => _phase;

  @override
  Stream<ContestSessionPhase> get sessionPhaseStream =>
      _phaseController.stream;

  @override
  bool get isContestRunning => _phase != ContestSessionPhase.idle;

  /// A three-digit sent exchange, so the narrow cell is measured against the
  /// widest value the format can produce with a serial.
  @override
  String myExchangeFor(int qsoNumber) => '599';

  void setPhase(ContestSessionPhase phase) {
    _phase = phase;
    _phaseController.add(phase);
  }

  @override
  void stopContest({String reason = 'stopped'}) {
    stopCalls++;
    _phase = ContestSessionPhase.idle;
    _phaseController.add(_phase);
  }

  @override
  void completeResume() {
    completeResumeCalls++;
    setPhase(ContestSessionPhase.running);
  }

  void dispose() => _phaseController.close();
}
