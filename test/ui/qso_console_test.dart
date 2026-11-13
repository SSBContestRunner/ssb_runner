import 'dart:async';

import 'package:drift/drift.dart' hide isNull;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:ssb_runner/contest_run/state_machine/single_call/audio_play_type.dart';
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
import 'package:toastification/toastification.dart';

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

    // Wipe has no localized action label, so its tooltip carries the
    // description that used to live on the static F12 shortcut row.
    final wipeTooltip = tester.widget<Tooltip>(
      find.ancestor(of: find.text('Wipe'), matching: find.byType(Tooltip)),
    );
    expect(wipeTooltip.message, 'clear the input fields');

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

  testWidgets('spare keys hide only the key cap, never the action button', (
    tester,
  ) async {
    final harness = await _createHarness();
    await _pumpConsole(tester, harness);

    await harness.settings.setFunctionKeyBindings([
      for (final key in FunctionKey.values)
        FunctionKeyBinding(
          key,
          key == FunctionKey.f1 ? null : key.defaultAction,
        ),
    ]);
    await tester.pump();

    expect(
      find.text('CQ'),
      findsOneWidget,
      reason: 'the action stays clickable',
    );
    expect(
      find.text('F1'),
      findsNothing,
      reason: 'the key cap follows the binding',
    );
    final cq = tester.widget<InkWell>(
      find.ancestor(of: find.text('CQ'), matching: find.byType(InkWell)).first,
    );
    expect(cq.onTap != null, isTrue);
    await tester.tap(find.text('CQ'));
    await tester.pump();

    await harness.settings.setFunctionKeyBindings([
      for (final key in FunctionKey.values) FunctionKeyBinding(key, null),
    ]);
    await tester.pump();

    for (final label in [
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
      expect(find.text(label), findsOneWidget, reason: '$label stays visible');
    }
    for (var index = 1; index <= 12; index++) {
      expect(find.text('F$index'), findsNothing);
    }

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

  testWidgets('分号键在该阶段无效时给出一条轻提示', (tester) async {
    final harness = await _createHarness();
    final ignoredController = StreamController<OperationEvent>.broadcast();
    addTearDown(ignoredController.close);
    final manager = _RunningContestManager(
      contestDataManager: harness.dataManager,
      runningManager: _FakeRunningManager(
        ignoredShortcutStream: ignoredController.stream,
      ),
    );
    await _pumpConsole(
      tester,
      harness,
      manager: manager,
      withToastOverlay: true,
    );
    // 让 cubit 先绑定到运行中的 manager 与它的忽略流。
    await tester.pump();

    ignoredController.add(OperationEvent.hisCallAndMyExchange);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Nothing to send right now'), findsOneWidget);

    // 让 toast 自动关闭并播完退场动画，避免留下未完成的计时器。
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('暂停期输入框拒绝键入且不丢草稿，恢复后可继续编辑', (tester) async {
    final harness = await _createHarness();
    final phases = StreamController<ContestSessionPhase>.broadcast();
    addTearDown(phases.close);
    final manager = _PhaseContestManager(
      contestDataManager: harness.dataManager,
      runningManager: _FakeRunningManager(),
      phaseController: phases,
      initial: ContestSessionPhase.running,
    );
    final list = _StubQsoRecordListCubit(
      appDatabase: harness.dataManager.appDatabase,
      contestManager: manager,
    );
    await _pumpConsole(
      tester,
      harness,
      manager: manager,
      recordListCubit: list,
      width: 1024,
      consoleWidth: 668,
      withToastOverlay: true,
    );

    final callField = find.byKey(const Key('call-field'));
    await tester.enterText(callField, 'JA1ABC');
    await tester.pump();
    expect(_callText(tester), 'JA1ABC');

    manager.setPhase(ContestSessionPhase.paused);
    await tester.pump();

    expect(
      tester.widget<TextField>(callField).readOnly,
      isTrue,
      reason: 'paused runs must refuse typing, paste and IME',
    );
    expect(
      tester.widget<TextField>(callField).focusNode!.hasFocus,
      isTrue,
      reason: 'the lock must not move focus away from the field',
    );

    await tester.enterText(callField, 'XX9XXX');
    await tester.pump();
    expect(
      _callText(tester),
      'JA1ABC',
      reason: 'pausing must freeze the draft instead of clearing it',
    );
    expect(list.state, isEmpty, reason: 'no QSO may be recorded while paused');
    expect(find.text('Nothing to send right now'), findsNothing);

    manager.setPhase(ContestSessionPhase.resuming);
    await tester.pump();
    await tester.enterText(callField, 'XX9XXX');
    await tester.pump();
    expect(
      _callText(tester),
      'JA1ABC',
      reason: 'the 3-2-1 window is still locked',
    );

    manager.setPhase(ContestSessionPhase.running);
    await tester.pump();
    expect(
      tester.widget<TextField>(callField).readOnly,
      isFalse,
      reason: 'completing the resume restores the original editing path',
    );
    expect(
      tester.widget<TextField>(callField).focusNode!.hasFocus,
      isTrue,
      reason: 'focus survives the pause and resume round trip',
    );

    await tester.enterText(callField, 'K2XYZ');
    await tester.pump();
    expect(
      _callText(tester),
      'K2XYZ',
      reason: 'resuming restores normal editing and keeps focus',
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

  testWidgets('phase hints never truncate at the minimum window', (
    tester,
  ) async {
    await _ensureAppFonts();
    final harness = await _createHarness();
    const locales = [
      Locale('en'),
      Locale('zh'),
      Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
      Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      Locale('ja'),
    ];
    final states = <SingleCallRunState>[
      WaitingSubmitCall(
        currentCallAnswer: 'A1AAA',
        currentExchangeAnswer: '59 001',
      ),
      HeRepeatCorrectCallAnswer(
        currentCallAnswer: 'A1AAA',
        currentExchangeAnswer: '59 001',
        submitCall: 'A1AAA',
      ),
      HeAskForExchange(
        currentCallAnswer: 'A1AAA',
        currentExchangeAnswer: '59 001',
        submitCall: 'A1AAA',
        isPlayMyCall: false,
      ),
      WaitingSubmitMyExchange(
        currentCallAnswer: 'A1AAA',
        currentExchangeAnswer: '59 001',
        submitCall: 'A1AAA',
        audioPlayType: NoPlay(),
        isOperateInput: true,
      ),
      ReportMyExchange(
        currentCallAnswer: 'A1AAA',
        currentExchangeAnswer: '59 001',
        submitCall: 'A1AAA',
        myExchange: '59 001',
        audioPlayType: NoPlay(),
        isOperateInput: true,
      ),
      QsoEnd(
        currentCallAnswer: 'A1AAA',
        currentExchangeAnswer: '59 001',
        submitCall: 'A1AAA',
        submitExchange: '59 001',
      ),
      SpListeningCq(
        currentCallAnswer: 'A1AAA',
        currentExchangeAnswer: '59 001',
      ),
      SpWaitingHisExchange(
        currentCallAnswer: 'A1AAA',
        currentExchangeAnswer: '59 001',
      ),
      SpQsoEnd(
        currentCallAnswer: 'A1AAA',
        currentExchangeAnswer: '59 001',
        myExchange: '59 001',
      ),
    ];
    final truncated = <String>[];

    Future<void> measure(String label) async {
      final hint = find.byKey(const Key('phase-hint'));
      expect(hint, findsOneWidget, reason: label);
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: hint, matching: find.byType(RichText)),
      );
      if (paragraph.didExceedMaxLines) truncated.add(label);
    }

    for (final locale in locales) {
      for (final scale in const [1.0, 1.3]) {
        for (final state in states) {
          await _pumpConsole(
            tester,
            harness,
            width: 1108,
            height: 796,
            consoleWidth: 678,
            textScale: scale,
            locale: locale,
            manager: _RunningContestManager(
              contestDataManager: harness.dataManager,
              runningManager: _FakeRunningManager(state: state),
            ),
          );
          await tester.pump();
          await measure('$locale x$scale ${state.runtimeType}');
        }

        final phases = StreamController<ContestSessionPhase>.broadcast();
        addTearDown(phases.close);
        await _pumpConsole(
          tester,
          harness,
          width: 1108,
          height: 796,
          consoleWidth: 678,
          textScale: scale,
          locale: locale,
          manager: _PhaseContestManager(
            contestDataManager: harness.dataManager,
            runningManager: _FakeRunningManager(state: states[2]),
            phaseController: phases,
            initial: ContestSessionPhase.paused,
          ),
        );
        await tester.pump();
        await measure('$locale x$scale paused');
      }
    }

    expect(truncated, isEmpty, reason: truncated.join('\n'));
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

/// Reports a running session whose phase the test can drive, so the console's
/// pause lock can be exercised without a real running manager.
class _PhaseContestManager extends _RunningContestManager {
  _PhaseContestManager({
    required super.contestDataManager,
    required super.runningManager,
    required this.phaseController,
    ContestSessionPhase initial = ContestSessionPhase.idle,
  }) : _phase = initial;

  final StreamController<ContestSessionPhase> phaseController;
  ContestSessionPhase _phase;

  @override
  ContestSessionPhase get sessionPhase => _phase;

  @override
  Stream<ContestSessionPhase> get sessionPhaseStream => phaseController.stream;

  void setPhase(ContestSessionPhase phase) {
    _phase = phase;
    phaseController.add(phase);
  }
}

/// The only members [QsoConsoleCubit] touches while it binds to a session.
class _FakeRunningManager
    with WidgetsBindingObserver
    implements ContestRunningManager {
  _FakeRunningManager({
    Stream<OperationEvent>? ignoredShortcutStream,
    SingleCallRunState? state,
  }) : _ignoredShortcutStream =
           ignoredShortcutStream ?? const Stream<OperationEvent>.empty(),
       _state =
           state ??
           WaitingSubmitCall(
             currentCallAnswer: 'A1AAA',
             currentExchangeAnswer: '59 001',
             pileupCallsigns: const [],
           );

  final Stream<OperationEvent> _ignoredShortcutStream;
  final SingleCallRunState _state;

  @override
  final String runId = 'test-run';

  @override
  final TrainingDifficulty difficulty = TrainingDifficulty.beginner;

  @override
  SingleCallRunState get currentState => _state;

  @override
  Stream<SingleCallRunState> get stateStream =>
      const Stream<SingleCallRunState>.empty();

  @override
  Stream<OperationEvent> get ignoredShortcutStream => _ignoredShortcutStream;

  @override
  ContestOperationEventHandler get contestOperationEventHandler =>
      _operationHandler;

  @override
  ScoreManager get scoreManager => throw UnimplementedError();

  @override
  void pause() {}

  @override
  void resume() {}

  @override
  void stop() {}

  final _operationHandler = _FakeOperationHandler();
}

class _FakeOperationHandler implements ContestOperationEventHandler {
  @override
  Stream<int> get inputControlStream => Stream<int>.empty();

  @override
  Future<bool> handleOperationEvent(OperationEvent event) async => true;

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

  @override
  void pause() {}

  @override
  void resume() {}
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

String _callText(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(const Key('call-field')))
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
  double height = 720,
  double consoleWidth = 874,
  double textScale = 1,
  Locale locale = const Locale('en'),
  ContestManager? manager,
  QsoRecordListCubit? recordListCubit,
  bool withToastOverlay = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final contestManager =
      manager ?? ContestManager(contestDataManager: harness.dataManager);
  final app = MaterialApp(
    theme: AppTheme.light,
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
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
              create: (_) => MainSettingsCubit(contestManager: contestManager),
            ),
            BlocProvider(
              create: (_) => ContestSettingCubit(appSettings: harness.settings),
            ),
            BlocProvider(
              create: (_) =>
                  StationCallsignCubit(appSettings: harness.settings),
            ),
            BlocProvider(create: (_) => TrainingOptionsCubit(harness.settings)),
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
  );
  await tester.pumpWidget(
    withToastOverlay ? ToastificationWrapper(child: app) : app,
  );
  await tester.pump();
}

/// Shared by every harness so the process only ever holds one database instance.
final AppDatabase _neverOpenedDatabase = AppDatabase(
  LazyDatabase(() async => throw StateError('no db')),
);

Future<_Harness> _createHarness() async {
  final prefs = await SharedPreferencesWithCache.create(
    cacheOptions: const SharedPreferencesWithCacheOptions(),
  );
  final settings = AppSettings(prefs: prefs);
  final database = _neverOpenedDatabase;
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
