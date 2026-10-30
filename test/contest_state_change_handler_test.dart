import 'dart:async';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
// `Retry` also exists in test_api; hide it so the state machine's event wins.
import 'package:flutter_test/flutter_test.dart' hide Retry;
import 'package:ssb_runner/audio/audio_engine.dart';
import 'package:ssb_runner/audio/audio_loader.dart';
import 'package:ssb_runner/audio/audio_player.dart';
import 'package:ssb_runner/callsign/callsign_loader.dart';
import 'package:ssb_runner/contest_run/data/score_data.dart';
import 'package:ssb_runner/contest_run/new/contest_answer_generator.dart';
import 'package:ssb_runner/contest_run/new/contest_data_manager.dart';
import 'package:ssb_runner/contest_run/new/contest_input_handler.dart';
import 'package:ssb_runner/contest_run/new/contest_operation_event_handler.dart';
import 'package:ssb_runner/contest_run/new/contest_state_change_handler.dart';
import 'package:ssb_runner/contest_run/new/contest_timer.dart';
import 'package:ssb_runner/contest_run/key_event_handler.dart';
import 'package:ssb_runner/contest_run/score_manager.dart';
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
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:ssb_runner/state_machine/state_machine.dart';
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

  group('QsoEnd 提交与推进', () {
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

/// Builds the Run/S&P handler with every dependency replaced by a test double.
Future<_Rig> _rig({
  required SingleCallRunState initialState,
  bool searchAndPounce = false,
  AudioLoader? audioLoader,
  AppDatabase? database,
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
          transitionListener: (_) {},
        )
      : initSingleCallRunStateMachine(
          initialState: initialState,
          transitionListener: (_) {},
        );

  final contestType = _FixedContestType();
  final answers = _FixedAnswerSource(_answers());
  final dataManager = ContestDataManager(
    audioLoader: audioLoader ?? _SilentAudioLoader(),
    audioPlayer: AudioPlayer(engine: _SilentAudioEngine()),
    appSettings: settings,
    appDatabase: db,
    callsignLoader: CallsignLoader(),
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
    contestAnswerGenerator: answers,
  );

  return _Rig(
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
    required this.database,
    required this.input,
    required this.answers,
    required this.machine,
    required this.handler,
    required this.operationHandler,
  });

  final AppDatabase database;
  final ContestInputHandler input;
  final _FixedAnswerSource answers;
  final StateMachine<SingleCallRunState, SingleCallRunEvent, Null> machine;
  final ContestStateChangeHandler handler;
  final ContestOperationEventHandler operationHandler;

  Future<void> dispose() async {
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

  @override
  ContestAnswer generateAnswer() {
    calls++;
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
