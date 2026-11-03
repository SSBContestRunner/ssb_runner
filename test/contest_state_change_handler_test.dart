import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
// `Retry` also exists in test_api; hide it so the state machine's event wins.
import 'package:flutter_test/flutter_test.dart' hide Retry;
import 'package:ssb_runner/audio/accent_policy.dart';
import 'package:ssb_runner/audio/audio_engine.dart';
import 'package:ssb_runner/audio/audio_loader.dart';
import 'package:ssb_runner/audio/audio_player.dart';
import 'package:ssb_runner/callsign/callsign_loader.dart';
import 'package:ssb_runner/contest_run/data/score_data.dart';
import 'package:ssb_runner/contest_run/new/contest_answer_generator.dart';
import 'package:ssb_runner/contest_run/new/contest_data_manager.dart';
import 'package:ssb_runner/contest_run/new/contest_input_handler.dart';
import 'package:ssb_runner/contest_run/new/contest_manager.dart';
import 'package:ssb_runner/contest_run/new/contest_operation_event_handler.dart';
import 'package:ssb_runner/contest_run/new/contest_state_change_handler.dart';
import 'package:ssb_runner/contest_run/new/contest_timer.dart';
import 'package:ssb_runner/contest_run/new/run_plan.dart';
import 'package:ssb_runner/contest_run/key_event_handler.dart';
import 'package:ssb_runner/contest_run/score_manager.dart';
import 'package:ssb_runner/contest_run/state_machine/single_call/audio_play_type.dart';
import 'package:ssb_runner/contest_run/state_machine/single_call/search_and_pounce_run_state_machine.dart';
import 'package:ssb_runner/contest_run/state_machine/single_call/single_call_run_event.dart';
import 'package:ssb_runner/contest_run/state_machine/single_call/single_call_run_state.dart';
import 'package:ssb_runner/contest_run/state_machine/single_call/single_call_run_state_machine.dart';
import 'package:ssb_runner/contest_type/contest_type.dart';
import 'package:ssb_runner/contest_type/exchange_manager.dart';
import 'package:ssb_runner/contest_type/score_calculator.dart';
import 'package:ssb_runner/db/app_database.dart';
import 'package:ssb_runner/dxcc/dxcc_manager.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/logging/app_logger.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:ssb_runner/state_machine/state_machine.dart';
import 'package:ssb_runner/training/pending_replay.dart';
import 'package:ssb_runner/training/replay_answer_source.dart';
import 'package:ssb_runner/training/session_random.dart';
import 'package:ssb_runner/training/training_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Each test opens its own in-memory database on purpose.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  for (final replay in [false, true]) {
    test('完整会话：${replay ? "复盘记录" : "题池"}耗尽后停止并保存诊断与复盘', () async {
      final directory = await Directory.systemTemp.createTemp('ssb_run_test');
      final logger = AppLogger.fileBacked(
        directory: directory.path,
        header: '# test',
      );
      await logger.ready;
      installLogger(logger);
      final rig = await _rig(initialState: _qsoEnd());
      final data = rig.dataManager;
      data.callsignLoader.callSigns.add('4X6ZM');
      data.appSettings
        ..contestId = 'CQ-WPX'
        ..contestModeId = TrainingMode.searchAndPounce.id
        ..difficulty = TrainingDifficulty.beginner
        ..pendingQuestionSeed = 42
        ..pendingAudioSeed = 43;
      if (replay) {
        // There are additional unused live stations, but a recorded replay
        // must end instead of switching to a live generator at this boundary.
        data.callsignLoader.callSigns.add('K1ABC');
        data.appSettings.armReplay(
          PendingReplay(
            runId: 'recorded-run',
            contestId: 'CQ-WPX',
            contestName: 'CQ WPX',
            modeId: TrainingMode.searchAndPounce.id,
            difficultyId: TrainingDifficulty.beginner.id,
            questionSeed: 42,
            audioSeed: 43,
            armedAtUtc: DateTime.now().toUtc(),
          ),
        );
        await rig.database
            .into(rig.database.eventLogTable)
            .insert(
              EventLogTableCompanion.insert(
                runId: 'recorded-run',
                elapsedMs: 0,
                eventType: 'answer',
                createdAtUtc: 0,
                payload: jsonEncode({
                  'type': 'answer',
                  'callsign': '4X6ZM',
                  'exchange': '2500',
                  'pileupCallsigns': ['4X6ZM'],
                  'modeId': TrainingMode.searchAndPounce.id,
                }),
              ),
            );
      }
      final manager = ContestManager(contestDataManager: data);
      addTearDown(() async {
        manager.stopContest();
        await rig.dispose();
        await logger.flush();
        installLogger(AppLogger.consoleOnly());
        await directory.delete(recursive: true);
      });
      final reviewFuture = manager.reviewStream.first;
      await manager.startContest();
      expect(manager.isContestRunning, isTrue);
      final operations =
          manager.contestRunningManager!.contestOperationEventHandler;
      data.inputHandler.onCallEdit('4X6ZM');
      await operations.handleOperationEvent(OperationEvent.submit);
      await pumpEventQueue();
      data.inputHandler.onExchangeEdit('2500');
      await operations.handleOperationEvent(OperationEvent.submit);
      final review = await reviewFuture.timeout(const Duration(seconds: 5));
      expect(manager.isContestRunning, isFalse);
      expect(data.audioPlayer.isStarted, isFalse);
      expect(review.qsoCount, 1);
      expect(
        review.endReason,
        replay ? 'replay_completed' : 'callsign_pool_exhausted',
      );
      expect(await manager.countCurrentRunQso(), 1);
      final events = await (rig.database.select(
        rig.database.eventLogTable,
      )..where((row) => row.runId.equals(review.metadata.runId))).get();
      // Every run now starts with a self-describing header row; the answer
      // rows follow it.
      expect(events.where((row) => row.eventType == 'run-start'), hasLength(1));
      expect(events.where((row) => row.eventType == 'answer'), hasLength(1));
      await logger.flush();
      final logs = await File('${directory.path}/latest.log').readAsString();
      for (final field in [
        'runId="${review.metadata.runId}"',
        'questionSeed=42',
        'audioSeed=43',
        'questionIndex=1',
        'call="4X6ZM"',
        'duplicate=false',
        'reason="${review.endReason}"',
        'answerSource="${replay ? "recorded-replay" : "live"}"',
      ]) {
        expect(logs, contains(field));
      }
      if (replay) expect(logs, contains('replayRunId="recorded-run"'));
      expect(logs, isNot(contains('questionIndex=2')));
    });
  }

  group('QsoEnd 提交与推进', () {
    for (final searchAndPounce in [false, true]) {
      test('最后一题落库后结束 ${searchAndPounce ? "S&P" : "Run"} 复盘', () async {
        String? endReason;
        final rig = await _rig(
          initialState: searchAndPounce ? _spListeningCq() : _qsoEnd(),
          searchAndPounce: searchAndPounce,
          answerSource: ReplayAnswerSource([]),
          onAnswersExhausted: (reason) => endReason = reason,
        );
        if (searchAndPounce) {
          _advanceToSpQsoEnd(rig.machine);
          rig.input.onCallEdit('A1AAA');
          rig.input.onExchangeEdit('007');
        }
        await rig.handler.handleToState(rig.machine.currentState);
        expect(endReason, 'replay_completed');
        expect(
          await rig.database.select(rig.database.qsoTable).get(),
          hasLength(1),
        );
        expect(rig.input.hisCall, isEmpty);
        expect(rig.answers.calls, 0);
        await rig.dispose();
      });
    }
    test('完整抄收：落库一次并推进到下一题', () async {
      final rig = await _rig(initialState: _qsoEnd());

      await rig.handler.handleToState(rig.machine.currentState);

      final next = rig.machine.currentState;
      expect(next, isA<WaitingSubmitCall>());
      expect((next as WaitingSubmitCall).currentCallAnswer, 'C3CCC');
      expect(next.currentExchangeAnswer, '59 002');

      final qsos = await rig.database.select(rig.database.qsoTable).get();
      expect(qsos, hasLength(1));
      expect(qsos.single.callsign, 'B100IARU');
      expect(qsos.single.callsignCorrect, 'B100IARU');
      expect(qsos.single.exchange, '59 001');
      expect(qsos.single.exchangeCorrect, '59 001');

      expect(rig.input.hisCall, '');
      expect(rig.input.exchange, '');
      expect(rig.answers.calls, 1);
      await rig.dispose();
    });

    test('录入序号时更正过呼号：按更正后的呼号落库', () async {
      final rig = await _rig(
        initialState: _qsoEnd(submitCall: 'B10', correctedCall: 'B100IARU'),
      );

      await rig.handler.handleToState(rig.machine.currentState);

      final qsos = await rig.database.select(rig.database.qsoTable).get();
      expect(qsos.single.callsign, 'B100IARU');
      expect(qsos.single.callsignCorrect, 'B100IARU');
      await rig.dispose();
    });

    test('签字音频加载期间输入被清空：仍按进入时的快照落库并推进', () async {
      // 进入 QsoEnd 后 handleToState 先 await 音频加载，这段窗口里操作员
      // 仍可编辑文本框。提交值必须来自状态快照，而不是活输入。
      final loader = _GatedAudioLoader();
      final rig = await _rig(initialState: _qsoEnd(), audioLoader: loader);

      final handling = rig.handler.handleToState(rig.machine.currentState);
      rig.input.clear();
      loader.release();
      await handling;

      expect(rig.machine.currentState, isA<WaitingSubmitCall>());
      final qsos = await rig.database.select(rig.database.qsoTable).get();
      expect(qsos, hasLength(1));
      expect(qsos.single.callsign, 'B100IARU');
      expect(qsos.single.exchange, '59 001');
      await rig.dispose();
    });

    test('输入为空：跳过落库但照常推进，不冻结', () async {
      // S&P 会让这种状态出现（呼号没抄到），这里验证兜底：宁可丢一条 QSO，
      // 也不能把状态机永久留在 QsoEnd。
      final rig = await _rig(initialState: _qsoEnd(submitCall: ''));

      await rig.handler.handleToState(rig.machine.currentState);

      expect(rig.machine.currentState, isA<WaitingSubmitCall>());
      expect(await rig.database.select(rig.database.qsoTable).get(), isEmpty);
      expect(rig.input.hisCall, '');
      await rig.dispose();
    });

    test('落库失败：吞掉异常并照常推进', () async {
      final rig = await _rig(initialState: _qsoEnd());
      await rig.database.close();

      await rig.handler.handleToState(rig.machine.currentState);

      expect(rig.machine.currentState, isA<WaitingSubmitCall>());
      await rig.dispose();
    });
  });

  group('Run 抄错呼号：准入放开', () {
    test('偏差超过阈值仍进入序号阶段，不丢本轮目标', () async {
      final rig = await _rig(
        initialState: _reportMyExchange(submitCall: 'X9ZZZZ'),
      );

      await rig.handler.handleToState(rig.machine.currentState);

      final next = rig.machine.currentState;
      expect(next, isA<WaitingSubmitMyExchange>());
      final waiting = next as WaitingSubmitMyExchange;
      expect(waiting.submitCall, 'X9ZZZZ');
      expect(waiting.currentCallAnswer, 'B100IARU');
      expect(waiting.currentExchangeAnswer, '59 001');
      expect(waiting.audioPlayType, isA<PlayCallExchange>());
      expect(rig.answers.calls, 0, reason: '本轮目标不能被换成新的 pileup');
      await rig.dispose();
    });

    test('错呼号 + 正确序号：按错呼号落库，正确呼号留在 callsignCorrect', () async {
      final rig = await _rig(
        initialState: _waitingSubmitMyExchange(submitCall: 'X9ZZZZ'),
      );
      rig.input.onExchangeEdit('59 001');

      await rig.operationHandler.handleOperationEvent(OperationEvent.submit);
      await pumpEventQueue();
      expect(rig.machine.currentState, isA<QsoEnd>());
      await rig.handler.handleToState(rig.machine.currentState);

      final qsos = await rig.database.select(rig.database.qsoTable).get();
      expect(qsos, hasLength(1));
      expect(qsos.single.callsign, 'X9ZZZZ');
      expect(qsos.single.callsignCorrect, 'B100IARU');
      expect(qsos.single.exchange, '59 001');
      expect(qsos.single.exchangeCorrect, '59 001');
      await rig.dispose();
    });

    test('错呼号 + 错序号：两栏都按抄收值落库', () async {
      final rig = await _rig(
        initialState: _waitingSubmitMyExchange(submitCall: 'X9ZZZZ'),
      );
      rig.input.onExchangeEdit('59 002');

      await rig.operationHandler.handleOperationEvent(OperationEvent.submit);
      await pumpEventQueue();
      expect(rig.machine.currentState, isA<QsoEnd>());
      await rig.handler.handleToState(rig.machine.currentState);

      final qsos = await rig.database.select(rig.database.qsoTable).get();
      expect(qsos, hasLength(1));
      expect(qsos.single.callsign, 'X9ZZZZ');
      expect(qsos.single.callsignCorrect, 'B100IARU');
      expect(qsos.single.exchange, '59 002');
      expect(qsos.single.exchangeCorrect, '59 001');
      await rig.dispose();
    });

    test('F7 重放：AGN + 呼号 + RST + 序号四段，不再静音', () async {
      final loader = _CountingAudioLoader();
      final rig = await _rig(
        initialState: _waitingSubmitMyExchange(submitCall: 'X9ZZZZ'),
        audioLoader: loader,
      );

      await rig.operationHandler.handleOperationEvent(OperationEvent.agn);
      expect(rig.machine.currentState, isA<WaitingSubmitMyExchange>());
      await rig.handler.handleToState(rig.machine.currentState);

      expect(loader.calls, 4, reason: 'AGN、呼号、RST、序号四段');
      await rig.dispose();
    });
  });

  group('SpQsoEnd 提交与推进', () {
    test('完整抄收：落库一次并推进到下一台 CQ', () async {
      final rig = await _rig(
        searchAndPounce: true,
        initialState: _spListeningCq(),
      );
      _advanceToSpQsoEnd(rig.machine);

      rig.input.onCallEdit('A1AAA');
      rig.input.onExchangeEdit('007');
      await rig.handler.handleToState(rig.machine.currentState);

      final next = rig.machine.currentState;
      expect(next, isA<SpListeningCq>());
      expect((next as SpListeningCq).currentCallAnswer, 'C3CCC');

      final qsos = await rig.database.select(rig.database.qsoTable).get();
      expect(qsos, hasLength(1));
      expect(qsos.single.callsign, 'A1AAA');
      expect(qsos.single.exchange, '007');

      expect(rig.input.hisCall, '');
      await rig.dispose();
    });

    test('呼号为空：跳过落库但仍推进，不冻结', () async {
      final rig = await _rig(
        searchAndPounce: true,
        initialState: _spListeningCq(),
      );
      _advanceToSpQsoEnd(rig.machine);

      rig.input.onExchangeEdit('007');
      await rig.handler.handleToState(rig.machine.currentState);

      expect(rig.machine.currentState, isA<SpListeningCq>());
      expect(await rig.database.select(rig.database.qsoTable).get(), isEmpty);
      await rig.dispose();
    });

    test('未抄到呼号时回车不进入签字状态', () async {
      final rig = await _rig(
        searchAndPounce: true,
        initialState: _spListeningCq(),
      );
      rig.machine.transition(SpPounce());

      rig.input.onExchangeEdit('007');
      await rig.operationHandler.handleOperationEvent(OperationEvent.submit);
      expect(rig.machine.currentState, isA<SpWaitingHisExchange>());

      rig.input.onCallEdit('A1AAA');
      await rig.operationHandler.handleOperationEvent(OperationEvent.submit);
      // `_handleSubmit` is not awaited by the operation handler and awaits the
      // operator's exchange before transitioning.
      await pumpEventQueue();
      expect(rig.machine.currentState, isA<SpQsoEnd>());
      await rig.dispose();
    });
  });

  group('F1 放弃当前轮', () {
    test('四个 in-flight 状态放弃后换题，旧目标留在 PILE-UP 非主音', () async {
      for (final stateBuilder in _inFlightStateBuilders) {
        final loader = CallsignLoader()
          ..callSigns.addAll(['OLD1', 'NEW1', 'NEW2']);
        final generator = _liveGenerator(loader);
        // The round being worked on was drawn before the operator pressed F1.
        final working = generator.generateAnswer();
        final rig = await _rig(
          initialState: stateBuilder(working.callSign),
          callsignLoader: loader,
          answerSource: generator,
        );

        await rig.handler.abandonRound();

        final next = rig.machine.currentState;
        expect(next, isA<WaitingSubmitCall>());
        final waiting = next as WaitingSubmitCall;
        expect(waiting.currentCallAnswer, isNot(working.callSign));
        expect(waiting.pileupCallsigns.first, waiting.currentCallAnswer);
        expect(waiting.pileupCallsigns.skip(1), contains(working.callSign));
        await rig.dispose();
      }
    });

    test('池耗尽时旧目标降级为主音继续，不结束序列', () async {
      String? endReason;
      final loader = CallsignLoader()..callSigns.add('ONLY1');
      final generator = _liveGenerator(loader);
      final working = generator.generateAnswer();
      final rig = await _rig(
        initialState: _heAskForExchange(working.callSign),
        callsignLoader: loader,
        answerSource: generator,
        onAnswersExhausted: (reason) => endReason = reason,
      );

      await rig.handler.abandonRound();

      final next = rig.machine.currentState as WaitingSubmitCall;
      expect(next.currentCallAnswer, 'ONLY1');
      expect(next.pileupCallsigns, ['ONLY1']);
      expect(endReason, isNull);

      // Only after this round's normal QsoEnd does the empty pool end the run.
      rig.machine.transition(SubmitCall(call: 'ONLY1'));
      rig.machine.transition(SubmitHisExchange(exchange: '001'));
      rig.machine.transition(SubmitMyExchange(exchange: '001', call: 'ONLY1'));
      await rig.handler.handleToState(rig.machine.currentState);

      expect(endReason, 'callsign_pool_exhausted');
      await rig.dispose();
    });

    test('放弃路径不清空输入框，并把旧目标交给生成器', () async {
      final rig = await _rig(initialState: _heAskForExchange('B100IARU'));
      rig.input.onCallEdit('B100');
      rig.input.onExchangeEdit('59 0');

      await rig.handler.abandonRound();

      expect(rig.input.hisCall, 'B100');
      expect(rig.input.exchange, '59 0');
      expect(rig.answers.lastRequeueCallsign, 'B100IARU');
      await rig.dispose();
    });

    test('非 in-flight 状态按 F1 仍为重播 CQ 的 Retry', () async {
      var abandonCalls = 0;
      final rig = await _rig(initialState: _waitingSubmitCall('B100IARU'));
      final handler = ContestOperationEventHandler(
        contestRunId: 'run-1',
        contestDataManager: rig.dataManager,
        contestType: _FixedContestType(),
        stateMachine: rig.machine,
        inputHandler: rig.input,
        onAbandonRound: () async {
          abandonCalls++;
        },
      );

      await handler.handleOperationEvent(OperationEvent.cq);

      expect(abandonCalls, 0);
      expect(rig.machine.currentState, isA<WaitingSubmitCall>());
      await rig.dispose();
    });

    test('F12 Wipe 在 Run 的每个在途状态下都只清空输入', () async {
      final wipeStates = <SingleCallRunState Function(String)>[
        (call) => WaitingSubmitCall(
          currentCallAnswer: call,
          currentExchangeAnswer: '59 002',
        ),
        ..._inFlightStateBuilders,
      ];

      for (final build in wipeStates) {
        final loader = _CountingAudioLoader();
        final rig = await _rig(
          initialState: build('B100IARU'),
          audioLoader: loader,
        );
        rig.input.onCallEdit('B100');
        rig.input.onExchangeEdit('59 0');
        final before = rig.machine.currentState;

        await rig.operationHandler.handleOperationEvent(OperationEvent.wipe);

        expect(rig.input.hisCall, isEmpty);
        expect(rig.input.exchange, isEmpty);
        expect(rig.machine.currentState, same(before));
        expect(loader.calls, 0, reason: 'wipe must not load or play audio');
        expect(await rig.database.select(rig.database.qsoTable).get(), isEmpty);
        expect(
          await rig.database.select(rig.database.eventLogTable).get(),
          isEmpty,
        );
        await rig.dispose();
      }
    });

    test('F12 Wipe 在 S&P 下也只清空输入', () async {
      final loader = _CountingAudioLoader();
      final rig = await _rig(
        initialState: _spListeningCq(),
        searchAndPounce: true,
        audioLoader: loader,
      );
      rig.input.onCallEdit('A1AAA');
      rig.input.onExchangeEdit('007');
      final listening = rig.machine.currentState;

      await rig.operationHandler.handleOperationEvent(OperationEvent.wipe);

      expect(rig.input.hisCall, isEmpty);
      expect(rig.input.exchange, isEmpty);
      expect(rig.machine.currentState, same(listening));

      rig.machine.transition(SpPounce());
      rig.input.onCallEdit('A1AAA');
      rig.input.onExchangeEdit('007');
      final waiting = rig.machine.currentState;

      await rig.operationHandler.handleOperationEvent(OperationEvent.wipe);

      expect(rig.input.hisCall, isEmpty);
      expect(rig.input.exchange, isEmpty);
      expect(rig.machine.currentState, same(waiting));

      rig.machine.transition(
        SpSubmitHisExchange(exchange: '007', myExchange: '001'),
      );
      rig.input.onCallEdit('A1AAA');
      rig.input.onExchangeEdit('007');
      final signingOff = rig.machine.currentState;

      await rig.operationHandler.handleOperationEvent(OperationEvent.wipe);

      expect(rig.input.hisCall, isEmpty);
      expect(rig.input.exchange, isEmpty);
      expect(rig.machine.currentState, same(signingOff));
      expect(loader.calls, 0, reason: 'wipe must not load or play audio');
      expect(await rig.database.select(rig.database.qsoTable).get(), isEmpty);
      expect(
        await rig.database.select(rig.database.eventLogTable).get(),
        isEmpty,
      );
      await rig.dispose();
    });

    test('F12 清空后重新输入与提交按现有逻辑工作', () async {
      final rig = await _rig(initialState: _heAskForExchange('B100IARU'));
      rig.input.onCallEdit('B100');
      rig.input.onExchangeEdit('59 0');

      await rig.operationHandler.handleOperationEvent(OperationEvent.wipe);
      expect(rig.input.hisCall, isEmpty);
      expect(rig.input.exchange, isEmpty);

      rig.input.onExchangeEdit('59 002');
      await rig.operationHandler.handleOperationEvent(OperationEvent.submit);

      expect(rig.machine.currentState, isA<WaitingSubmitMyExchange>());
      await rig.dispose();
    });
  });

  group('分号键：他的呼号 + 我的序号', () {
    test('WaitingSubmitCall：抄到呼号后一次发射并进入 ReportMyExchange', () async {
      final loader = _CountingAudioLoader();
      final transitions =
          <Transition<SingleCallRunState, SingleCallRunEvent, Null>>[];
      final rig = await _rig(
        initialState: _waitingSubmitCall('B100IARU'),
        audioLoader: loader,
        transitionListener: transitions.add,
      );
      rig.input.onCallEdit('B100IARU');

      final handled = await rig.operationHandler.handleOperationEvent(
        OperationEvent.hisCallAndMyExchange,
      );

      expect(handled, isTrue, reason: '被接受的分号按键要报告已执行');
      final current = rig.machine.currentState;
      expect(current, isA<ReportMyExchange>());
      expect((current as ReportMyExchange).submitCall, 'B100IARU');
      expect(current.isOperateInput, isFalse);
      expect(loader.calls, 2, reason: '他的呼号 + 我的序号 两段音频');
      expect(transitions.every(_isValidTransition), isTrue);
      await rig.dispose();
    });

    test('HeRepeatCorrectCallAnswer：纠正后继续推进，不再静默', () async {
      // 回归用例：日志里 `operation event hisCallAndMyExchange` 之后没有任何
      // onTransition，分号键在这个状态下被整个吞掉。
      final loader = _CountingAudioLoader();
      final transitions =
          <Transition<SingleCallRunState, SingleCallRunEvent, Null>>[];
      final rig = await _rig(
        initialState: HeRepeatCorrectCallAnswer(
          currentCallAnswer: 'B100IARU',
          currentExchangeAnswer: '59 001',
          submitCall: 'B10',
        ),
        audioLoader: loader,
        transitionListener: transitions.add,
      );
      rig.input.onCallEdit('B100IARU');

      await rig.operationHandler.handleOperationEvent(
        OperationEvent.hisCallAndMyExchange,
      );

      final current = rig.machine.currentState;
      expect(current, isA<ReportMyExchange>());
      expect((current as ReportMyExchange).submitCall, 'B100IARU');
      expect(loader.calls, 2);
      expect(transitions.every(_isValidTransition), isTrue);
      await rig.dispose();
    });

    test('WaitingSubmitCall：空输入时重播，不播组合音频', () async {
      final loader = _CountingAudioLoader();
      final rig = await _rig(
        initialState: _waitingSubmitCall('B100IARU'),
        audioLoader: loader,
      );

      await rig.operationHandler.handleOperationEvent(
        OperationEvent.hisCallAndMyExchange,
      );

      expect(rig.machine.currentState, isA<WaitingSubmitCall>());
      expect(loader.calls, 0);
      await rig.dispose();
    });

    test('WaitingSubmitMyExchange：重播他的序号', () async {
      final loader = _CountingAudioLoader();
      final rig = await _rig(
        initialState: _inFlightStateBuilders[2]('B100IARU'),
        audioLoader: loader,
      );
      rig.input.onCallEdit('B100IARU');

      await rig.operationHandler.handleOperationEvent(
        OperationEvent.hisCallAndMyExchange,
      );

      expect(rig.machine.currentState, isA<WaitingSubmitMyExchange>());
      expect(loader.calls, 2);
      await rig.dispose();
    });

    test('HeAskForExchange：只让他重发，不播组合音频', () async {
      final loader = _CountingAudioLoader();
      final rig = await _rig(
        initialState: _heAskForExchange('B100IARU'),
        audioLoader: loader,
      );
      rig.input.onCallEdit('B100IARU');

      await rig.operationHandler.handleOperationEvent(
        OperationEvent.hisCallAndMyExchange,
      );

      expect(rig.machine.currentState, isA<HeAskForExchange>());
      expect(loader.calls, 0, reason: '他在要序号，组合音频会盖住他');
      await rig.dispose();
    });

    test('ReportMyExchange / QsoEnd：不迁移也不播音频', () async {
      for (final state in [_inFlightStateBuilders[3]('B100IARU'), _qsoEnd()]) {
        final loader = _CountingAudioLoader();
        final rig = await _rig(initialState: state, audioLoader: loader);
        rig.input.onCallEdit('B100IARU');
        final before = rig.machine.currentState;

        final handled = await rig.operationHandler.handleOperationEvent(
          OperationEvent.hisCallAndMyExchange,
        );

        expect(handled, isFalse, reason: '无动作时要让界面能提示');
        expect(rig.machine.currentState, same(before));
        expect(loader.calls, 0, reason: '${state.runtimeType} 不该发射');
        await rig.dispose();
      }
    });

    test('S&P：等价 Enter，不播组合音频', () async {
      final loader = _CountingAudioLoader();
      final rig = await _rig(
        initialState: _spListeningCq(),
        searchAndPounce: true,
        audioLoader: loader,
      );
      rig.input.onCallEdit('A1AAA');

      final first = await rig.operationHandler.handleOperationEvent(
        OperationEvent.hisCallAndMyExchange,
      );

      expect(first, isTrue);
      expect(rig.machine.currentState, isA<SpWaitingHisExchange>());
      expect(loader.calls, 0);

      // 第二次等价回车：抄到序号后提交并进入签字态。
      rig.input.onExchangeEdit('007');
      final second = await rig.operationHandler.handleOperationEvent(
        OperationEvent.hisCallAndMyExchange,
      );

      expect(second, isTrue);
      expect(rig.machine.currentState, isA<SpQsoEnd>());
      expect(loader.calls, 0);
      await rig.dispose();
    });

    test('SpQsoEnd：不迁移也不播音频', () async {
      final loader = _CountingAudioLoader();
      final rig = await _rig(
        initialState: _spListeningCq(),
        searchAndPounce: true,
        audioLoader: loader,
      );
      _advanceToSpQsoEnd(rig.machine);
      rig.input.onCallEdit('A1AAA');
      final before = rig.machine.currentState;

      final handled = await rig.operationHandler.handleOperationEvent(
        OperationEvent.hisCallAndMyExchange,
      );

      expect(handled, isFalse);
      expect(rig.machine.currentState, same(before));
      expect(loader.calls, 0);
      await rig.dispose();
    });
  });

  group('回车提交的遗留黑洞', () {
    test('WaitingSubmitMyExchange 未抄序号时重播而不是 dropped', () async {
      final transitions =
          <Transition<SingleCallRunState, SingleCallRunEvent, Null>>[];
      final rig = await _rig(
        initialState: _inFlightStateBuilders[2]('B100IARU'),
        transitionListener: transitions.add,
      );
      rig.input.onCallEdit('B100IARU');

      await rig.operationHandler.handleOperationEvent(OperationEvent.submit);
      await pumpEventQueue();

      expect(rig.machine.currentState, isA<WaitingSubmitMyExchange>());
      expect(transitions.every(_isValidTransition), isTrue);
      await rig.dispose();
    });

    test('WaitingSubmitCall 两框都填仍然提交呼号 + 序号', () async {
      final transitions =
          <Transition<SingleCallRunState, SingleCallRunEvent, Null>>[];
      final rig = await _rig(
        initialState: _waitingSubmitCall('B100IARU'),
        transitionListener: transitions.add,
      );
      rig.input.onCallEdit('B100IARU');
      rig.input.onExchangeEdit('59 001');

      await rig.operationHandler.handleOperationEvent(OperationEvent.submit);
      await pumpEventQueue();

      expect(rig.machine.currentState, isA<ReportMyExchange>());
      expect(transitions.every(_isValidTransition), isTrue);
      await rig.dispose();
    });
  });

  group('重放归属与开局提交', () {
    test('armed WPX 在 CQ WW 普通设置下按 WPX 预览并在启动后提交', () async {
      final rig = await _openReplayRig(
        settingsContestId: 'CQ-WW-SSB',
        cqZone: '5',
      );
      rig.dataManager.callsignLoader.callSigns.add('4X6ZM');
      await _insertAnswer(rig.database, 'wpx-recorded', exchange: '2500');
      rig.dataManager.appSettings.armReplay(
        _pendingFor('wpx-recorded', 'CQ-WPX'),
      );

      final manager = ContestManager(contestDataManager: rig.dataManager);
      addTearDown(() async {
        manager.stopContest();
        await pumpEventQueue();
        await rig.dispose();
      });

      // Standby preview follows the armed snapshot, not the ordinary settings.
      expect(manager.myExchangeFor(1), '001');

      final result = await manager.startContest();

      expect(result.started, isTrue);
      expect(result.source, RunPlanSource.pending);
      expect(result.abortedReason, isNull);
      expect(rig.dataManager.appSettings.contestId, 'CQ-WPX');
      expect(rig.dataManager.appSettings.pendingReplay, isNull);
      expect(manager.isContestRunning, isTrue);
      expect(manager.myExchangeFor(1), '001');

      final reviewFuture = manager.reviewStream.first;
      manager.stopContest();
      final review = await reviewFuture.timeout(const Duration(seconds: 5));
      expect(review.metadata.contestId, 'CQ-WPX');
    });

    test('armed ARRL 重放只复刻来台，我方按当前站台功率发送', () async {
      final rig = await _openReplayRig(settingsContestId: 'CQ-WPX');
      rig.dataManager.appSettings.setStationExchangeValue(
        'ARRL-DX',
        'power',
        '100',
      );
      rig.dataManager.callsignLoader.callSigns.add('4X6ZM');
      await _insertAnswer(rig.database, 'arrl-recorded', exchange: '2500');
      rig.dataManager.appSettings.armReplay(
        PendingReplay(
          runId: 'arrl-recorded',
          contestId: 'ARRL-DX',
          contestName: 'ARRL DX',
          modeId: TrainingMode.run.id,
          difficultyId: TrainingDifficulty.standard.id,
          questionSeed: 42,
          audioSeed: 43,
          armedAtUtc: DateTime.utc(2026, 1, 1),
        ),
      );

      final manager = ContestManager(contestDataManager: rig.dataManager);
      addTearDown(() async {
        manager.stopContest();
        await pumpEventQueue();
        await rig.dispose();
      });

      final result = await manager.startContest();

      expect(result.started, isTrue);
      expect(result.source, RunPlanSource.pending);
      expect(rig.dataManager.appSettings.contestId, 'ARRL-DX');
      // The recording supplies only the incoming answer; the operator's own
      // exchange comes from the current station configuration.
      expect(manager.myExchangeFor(1), '100');
    });

    test('录像头与待重放赛制冲突时中止并按普通设置开新局', () async {
      final rig = await _openReplayRig(
        settingsContestId: 'CQ-WW-SSB',
        cqZone: '5',
      );
      rig.dataManager.callsignLoader.callSigns.add('4X6ZM');
      await _insertHeader(rig.database, 'mismatch-run', contestId: 'CQ-WW-SSB');
      await _insertAnswer(rig.database, 'mismatch-run', exchange: '2500');
      rig.dataManager.appSettings.armReplay(
        _pendingFor('mismatch-run', 'CQ-WPX'),
      );

      final manager = ContestManager(contestDataManager: rig.dataManager);
      addTearDown(() async {
        manager.stopContest();
        await pumpEventQueue();
        await rig.dispose();
      });

      final result = await manager.startContest();

      expect(result.started, isTrue);
      expect(result.source, RunPlanSource.settings);
      expect(result.abortedReason, ReplayAbortReason.headerMismatch);
      // The header is only evidence: the operator's settings win.
      expect(rig.dataManager.appSettings.contestId, 'CQ-WW-SSB');
      expect(rig.dataManager.appSettings.pendingReplay, isNull);
      expect(manager.myExchangeFor(1), '05');
    });

    test('录像事件缺失时中止重放并清空待重放', () async {
      final rig = await _openReplayRig(
        settingsContestId: 'CQ-WW-SSB',
        cqZone: '5',
      );
      rig.dataManager.callsignLoader.callSigns.add('4X6ZM');
      rig.dataManager.appSettings.armReplay(
        _pendingFor('missing-log', 'CQ-WPX'),
      );

      final manager = ContestManager(contestDataManager: rig.dataManager);
      addTearDown(() async {
        manager.stopContest();
        await pumpEventQueue();
        await rig.dispose();
      });

      final result = await manager.startContest();

      expect(result.started, isTrue);
      expect(result.abortedReason, ReplayAbortReason.eventsMissing);
      expect(rig.dataManager.appSettings.contestId, 'CQ-WW-SSB');
      expect(rig.dataManager.appSettings.pendingReplay, isNull);
    });

    test('空呼号池导致启动失败时保留待重放且不改普通设置', () async {
      final rig = await _openReplayRig(settingsContestId: 'CQ-WPX');
      rig.dataManager.appSettings.armReplay(
        _pendingFor('missing-log', 'CQ-WPX'),
      );

      final manager = ContestManager(contestDataManager: rig.dataManager);
      addTearDown(() async {
        manager.stopContest();
        await pumpEventQueue();
        await rig.dispose();
      });

      final result = await manager.startContest();

      expect(result.started, isFalse);
      expect(result.notices, contains('callsign_pool_empty'));
      expect(rig.dataManager.appSettings.pendingReplay, isNotNull);
      expect(rig.dataManager.appSettings.contestId, 'CQ-WPX');
      expect(manager.isContestRunning, isFalse);
    });
  });
}

Future<void> _insertHeader(
  AppDatabase database,
  String runId, {
  required String contestId,
}) => database
    .into(database.eventLogTable)
    .insert(
      EventLogTableCompanion.insert(
        runId: runId,
        elapsedMs: 0,
        eventType: 'run-start',
        createdAtUtc: 0,
        payload: jsonEncode({
          'contestId': contestId,
          'contestName': contestId,
          'modeId': TrainingMode.run.id,
          'difficultyId': TrainingDifficulty.standard.id,
          'questionSeed': 42,
          'audioSeed': 43,
        }),
      ),
    );

Future<void> _insertAnswer(
  AppDatabase database,
  String runId, {
  required String exchange,
}) => database
    .into(database.eventLogTable)
    .insert(
      EventLogTableCompanion.insert(
        runId: runId,
        elapsedMs: 0,
        eventType: 'answer',
        createdAtUtc: 0,
        payload: jsonEncode({
          'type': 'answer',
          'callsign': '4X6ZM',
          'exchange': exchange,
          'pileupCallsigns': ['4X6ZM'],
          'modeId': TrainingMode.run.id,
        }),
      ),
    );

PendingReplay _pendingFor(String runId, String contestId) => PendingReplay(
  runId: runId,
  contestId: contestId,
  contestName: contestId,
  modeId: TrainingMode.run.id,
  difficultyId: TrainingDifficulty.standard.id,
  questionSeed: 42,
  audioSeed: 43,
  armedAtUtc: DateTime.utc(2026, 1, 1),
);

Future<_Rig> _openReplayRig({
  required String settingsContestId,
  String? cqZone,
}) async {
  final rig = await _rig(initialState: _qsoEnd());
  rig.dataManager.appSettings
    ..contestId = settingsContestId
    ..contestModeId = TrainingMode.run.id
    ..difficulty = TrainingDifficulty.standard
    ..contestDuration = 30;
  if (cqZone != null) {
    rig.dataManager.appSettings.setStationExchangeValue(
      settingsContestId,
      'cqZone',
      cqZone,
    );
  }
  return rig;
}

bool _isValidTransition(
  Transition<SingleCallRunState, SingleCallRunEvent, Null> transition,
) {
  return transition
      is TransitionValid<SingleCallRunState, SingleCallRunEvent, Null>;
}

void _advanceToSpQsoEnd(
  StateMachine<SingleCallRunState, SingleCallRunEvent, Null> machine,
) {
  machine.transition(SpPounce());
  machine.transition(SpSubmitHisExchange(exchange: '007', myExchange: '001'));
  expect(machine.currentState, isA<SpQsoEnd>());
}

QsoEnd _qsoEnd({
  String submitCall = 'B100IARU',
  String submitExchange = '59 001',
  String? correctedCall,
}) {
  return QsoEnd(
    currentCallAnswer: 'B100IARU',
    currentExchangeAnswer: '59 001',
    submitCall: submitCall,
    submitExchange: submitExchange,
    correctedCall: correctedCall,
  );
}

SpListeningCq _spListeningCq() {
  return SpListeningCq(
    currentCallAnswer: 'A1AAA',
    currentExchangeAnswer: '007',
  );
}

WaitingSubmitCall _waitingSubmitCall(String callAnswer) {
  return WaitingSubmitCall(
    currentCallAnswer: callAnswer,
    currentExchangeAnswer: '59 002',
  );
}

ReportMyExchange _reportMyExchange({
  String currentCallAnswer = 'B100IARU',
  String currentExchangeAnswer = '59 001',
  String submitCall = 'B100IARU',
}) {
  return ReportMyExchange(
    currentCallAnswer: currentCallAnswer,
    currentExchangeAnswer: currentExchangeAnswer,
    submitCall: submitCall,
    myExchange: '001',
    audioPlayType: PlayCallExchange(
      call: submitCall,
      exchange: '001',
      isMe: true,
    ),
    isOperateInput: false,
  );
}

WaitingSubmitMyExchange _waitingSubmitMyExchange({
  String currentCallAnswer = 'B100IARU',
  String currentExchangeAnswer = '59 001',
  String submitCall = 'B100IARU',
}) {
  return WaitingSubmitMyExchange(
    currentCallAnswer: currentCallAnswer,
    currentExchangeAnswer: currentExchangeAnswer,
    submitCall: submitCall,
    audioPlayType: PlayCallExchange(
      call: currentCallAnswer,
      exchange: currentExchangeAnswer,
      isMe: false,
    ),
    isOperateInput: false,
  );
}

HeAskForExchange _heAskForExchange(String callAnswer) {
  return HeAskForExchange(
    currentCallAnswer: callAnswer,
    currentExchangeAnswer: '59 002',
    submitCall: callAnswer,
    isPlayMyCall: false,
  );
}

/// The four states in which F1 means "abandon this round".
final _inFlightStateBuilders = <SingleCallRunState Function(String)>[
  (call) => HeRepeatCorrectCallAnswer(
    currentCallAnswer: call,
    currentExchangeAnswer: '59 002',
    submitCall: call,
  ),
  (call) => HeAskForExchange(
    currentCallAnswer: call,
    currentExchangeAnswer: '59 002',
    submitCall: call,
    isPlayMyCall: false,
  ),
  (call) => WaitingSubmitMyExchange(
    currentCallAnswer: call,
    currentExchangeAnswer: '59 002',
    submitCall: call,
    audioPlayType: PlayExchange(exchange: '59 002', isMe: false),
    isOperateInput: false,
  ),
  (call) => ReportMyExchange(
    currentCallAnswer: call,
    currentExchangeAnswer: '59 002',
    submitCall: call,
    myExchange: '001',
    audioPlayType: PlayExchange(exchange: '59 002', isMe: false),
    isOperateInput: false,
  ),
];

ContestAnswerGenerator _liveGenerator(CallsignLoader loader) {
  return ContestAnswerGenerator(
    callsignLoader: loader,
    contestType: _FixedContestType(),
    mode: TrainingMode.pileup,
    difficulty: TrainingDifficulty.advanced,
    random: SessionRandom(7),
  );
}

/// Builds the Run/S&P handler with every dependency replaced by a test double.
Future<_Rig> _rig({
  required SingleCallRunState initialState,
  bool searchAndPounce = false,
  AudioLoader? audioLoader,
  AppDatabase? database,
  AnswerSource? answerSource,
  CallsignLoader? callsignLoader,
  void Function(String reason)? onAnswersExhausted,
  TransitionListener<SingleCallRunState, SingleCallRunEvent, Null>?
  transitionListener,
}) async {
  final db = database ?? AppDatabase(NativeDatabase.memory());
  final input = ContestInputHandler();
  final settings = AppSettings(
    prefs: await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(),
    ),
  )..stationCallsign = 'A1AAA';

  final machine = searchAndPounce
      ? initSearchAndPounceRunStateMachine(
          initialState: initialState as SpListeningCq,
          transitionListener: transitionListener ?? (_) {},
        )
      : initSingleCallRunStateMachine(
          initialState: initialState,
          transitionListener: transitionListener ?? (_) {},
        );

  final contestType = _FixedContestType();
  final answers = _FixedAnswerSource(_answers());
  final dataManager = ContestDataManager(
    audioLoader: audioLoader ?? _SilentAudioLoader(),
    audioPlayer: AudioPlayer(engine: _SilentAudioEngine()),
    appSettings: settings,
    appDatabase: db,
    callsignLoader: callsignLoader ?? CallsignLoader(),
    dxccManager: DxccManager(database: db),
    inputHandler: input,
  );
  final timer = ContestTimer(onContestEnd: () {});

  final handler = ContestStateChangeHandler(
    contestRunId: 'run-1',
    contestTimer: timer,
    contestType: contestType,
    contestDataManager: dataManager,
    stateMachine: machine,
    scoreManager: ScoreManager(
      contestId: 'run-1',
      stationCallsign: 'A1AAA',
      scoreCalculator: _FixedScoreCalculator(),
    ),
    contestAnswerGenerator: answerSource ?? answers,
    onAnswersExhausted: onAnswersExhausted,
    accentPolicy: const AccentPolicy(IncomingAccent.auto),
  );

  return _Rig(
    dataManager: dataManager,
    database: db,
    input: input,
    answers: answers,
    machine: machine,
    handler: handler,
    operationHandler: ContestOperationEventHandler(
      contestRunId: 'run-1',
      contestDataManager: dataManager,
      contestType: contestType,
      stateMachine: machine,
      inputHandler: input,
    ),
  );
}

List<ContestAnswer> _answers() => [
  ContestAnswer(
    callSign: 'B100IARU',
    exchange: '59 001',
    pileupCallsigns: const ['B100IARU'],
    mode: TrainingMode.pileup,
  ),
  ContestAnswer(
    callSign: 'C3CCC',
    exchange: '59 002',
    pileupCallsigns: const ['C3CCC'],
    mode: TrainingMode.pileup,
  ),
];

class _Rig {
  _Rig({
    required this.dataManager,
    required this.database,
    required this.input,
    required this.answers,
    required this.machine,
    required this.handler,
    required this.operationHandler,
  });

  final AppDatabase database;
  final ContestDataManager dataManager;
  final ContestInputHandler input;
  final _FixedAnswerSource answers;
  final StateMachine<SingleCallRunState, SingleCallRunEvent, Null> machine;
  final ContestStateChangeHandler handler;
  final ContestOperationEventHandler operationHandler;

  Future<void> dispose() async {
    handler.dispose();
    try {
      await database.close();
    } catch (_) {
      // The failing-insert test closes it early on purpose.
    }
  }
}

class _FixedAnswerSource implements AnswerSource {
  _FixedAnswerSource(this._answers);

  final List<ContestAnswer> _answers;

  /// How many questions were generated. Entry 0 of [_answers] is the one being
  /// worked on, so the first call hands out the question after it.
  int calls = 0;

  /// The abandoned callsign handed over by the last call, if any.
  String? lastRequeueCallsign;

  @override
  ContestAnswer generateAnswer({String? requeueCallsign}) {
    calls++;
    lastRequeueCallsign = requeueCallsign;
    return _answers[calls];
  }
}

/// Returns no asset bytes: audio is presentation only, and an empty buffer is
/// dropped by [AudioPlayer] before it reaches any engine.
class _SilentAudioLoader extends AudioLoader {
  @override
  Future<Uint8List> loadAudio(
    String accentDir,
    AudioPayload audioPayload,
  ) async => Uint8List(0);
}

/// Proves that an operation event (e.g. Wipe) never even asks for audio.
class _CountingAudioLoader extends _SilentAudioLoader {
  int calls = 0;

  @override
  Future<Uint8List> loadAudio(
    String accentDir,
    AudioPayload audioPayload,
  ) async {
    calls++;
    return super.loadAudio(accentDir, audioPayload);
  }
}

/// Holds every [AudioLoader.loadAudio] call until [release], which reproduces
/// the window between entering `QsoEnd` and reading its input.
class _GatedAudioLoader extends _SilentAudioLoader {
  final Completer<void> _gate = Completer<void>();

  void release() {
    if (!_gate.isCompleted) {
      _gate.complete();
    }
  }

  @override
  Future<Uint8List> loadAudio(
    String accentDir,
    AudioPayload audioPayload,
  ) async {
    if (!_gate.isCompleted) {
      await _gate.future;
    }
    return super.loadAudio(accentDir, audioPayload);
  }
}

class _SilentAudioEngine implements AudioEngine {
  @override
  bool get isInitialized => false;

  @override
  AudioSegment? createSegment(Uint8List pcm) => null;

  @override
  Future<bool> startNoiseBed(Uint8List pcm, {double volume = 0.0}) async =>
      false;

  @override
  void setNoiseBedVolume(double volume) {}

  @override
  void fadeNoiseBedVolume(double volume, Duration time) {}

  @override
  Future<void> stopNoiseBed() async {}
}

class _FixedContestType implements ContestType {
  final _exchange = _FixedExchangeManager();

  @override
  RegExp get allowExchangeRegex => RegExp('[0-9]');

  @override
  ExchangeManager get exchangeManager => _exchange;

  @override
  ScoreCalculator get scoreCalculator => _FixedScoreCalculator();

  @override
  String buildMyExchange(int qsoNumber) => qsoNumber.toString();

  @override
  String formatExchangeForAudio(String exchange) => exchange;
}

class _FixedExchangeManager implements ExchangeManager {
  @override
  String generateExchange(
    SessionRandom random, {
    required String callerCallsign,
  }) => random.nextExchange(3000).toString();

  @override
  String processExchange(String exchange) => exchange;
}

class _FixedScoreCalculator implements ScoreCalculator {
  @override
  String get stationCallsign => 'A1AAA';

  @override
  CorrectnessType calculateCorrectness(QsoTableData submitQso) => Correct();

  @override
  ScoreData calculateScore(List<QsoTableData> qsos) => ScoreData.initial();
}
