import 'package:flutter/services.dart';
import 'package:ssb_runner/audio/accent_policy.dart';
import 'package:ssb_runner/contest_run/key_event_handler.dart';
import 'package:ssb_runner/contest_run/new/contest_answer_generator.dart';
import 'package:ssb_runner/contest_run/new/contest_data_manager.dart';
import 'package:ssb_runner/contest_run/new/contest_input_handler.dart';
import 'package:ssb_runner/contest_run/new/contest_operation_event_handler.dart';
import 'package:ssb_runner/contest_run/new/contest_state_change_handler.dart';
import 'package:ssb_runner/contest_run/new/contest_timer.dart';
import 'package:ssb_runner/contest_run/score_manager.dart';
import 'package:ssb_runner/contest_run/state_machine/single_call/search_and_pounce_run_state_machine.dart';
import 'package:ssb_runner/contest_run/state_machine/single_call/single_call_run_event.dart';
import 'package:ssb_runner/contest_run/state_machine/single_call/single_call_run_state.dart';
import 'package:ssb_runner/contest_run/state_machine/single_call/single_call_run_state_machine.dart';
import 'package:ssb_runner/contest_type/contest_type.dart';
import 'package:ssb_runner/contest_type/score_calculator.dart';
import 'package:ssb_runner/state_machine/state_machine.dart';
import 'package:ssb_runner/training/replay_answer_source.dart';
import 'package:ssb_runner/training/session_random.dart';
import 'package:ssb_runner/training/training_profile.dart';

class ContestRunningManager {
  final String runId;
  final ContestType _contestType;
  final ContestDataManager _contestDataManager;
  final ContestTimer _contestTimer;
  final ScoreCalculator _scoreCalculator;
  final TrainingMode _mode;
  final TrainingDifficulty _difficulty;
  final AnswerSource? _answerSourceOverride;
  final void Function(ContestAnswer answer)? _onAnswerGenerated;
  final void Function(String reason)? _onAnswersExhausted;
  final AccentPolicy _accentPolicy;
  late final SessionRandom _sessionRandom = SessionRandom(_seed);
  final int _seed;

  late final ContestInputHandler _inputHandler =
      _contestDataManager.inputHandler;

  late final StateMachine<SingleCallRunState, SingleCallRunEvent, Null>
  _stateMachine;

  late final ScoreManager scoreManager = ScoreManager(
    contestId: runId,
    stationCallsign: _contestDataManager.appSettings.stationCallsign,
    scoreCalculator: _scoreCalculator,
  );

  late final AnswerSource _answerGenerator = RecordingAnswerSource(
    _answerSourceOverride ??
        ContestAnswerGenerator(
          contestType: _contestType,
          callsignLoader: _contestDataManager.callsignLoader,
          mode: _mode,
          difficulty: _difficulty,
          random: _sessionRandom,
        ),
    _onAnswerGenerated,
  );

  late final ContestStateChangeHandler _contestStateChangeHandler =
      ContestStateChangeHandler(
        contestRunId: runId,
        contestTimer: _contestTimer,
        contestType: _contestType,
        contestDataManager: _contestDataManager,
        stateMachine: _stateMachine,
        scoreManager: scoreManager,
        contestAnswerGenerator: _answerGenerator,
        onAnswersExhausted: _onAnswersExhausted,
        accentPolicy: _accentPolicy,
      );

  late final ContestOperationEventHandler contestOperationEventHandler =
      ContestOperationEventHandler(
        contestRunId: runId,
        contestDataManager: _contestDataManager,
        contestType: _contestType,
        stateMachine: _stateMachine,
        inputHandler: _inputHandler,
      );

  late final _keyEventManager = KeyEventHandler(
    functionKeys: functionKeysFromSettings(_contestDataManager.appSettings),
  );

  late final KeyEventCallback _keyEventCallback = _onKeyEvent;

  bool _onKeyEvent(KeyEvent event) {
    _keyEventManager.onKeyEvent(event);
    return false;
  }

  ContestRunningManager({
    required this.runId,
    required ContestTimer contestTimer,
    required ContestType contestType,
    required ContestDataManager contestDataManager,
    required ScoreCalculator scoreCalculator,
    required TrainingMode mode,
    required TrainingDifficulty difficulty,
    required int seed,
    AnswerSource? answerSource,
    required AccentPolicy accentPolicy,
    void Function(ContestAnswer answer)? onAnswerGenerated,
    void Function(String reason)? onAnswersExhausted,
  }) : _contestType = contestType,
       _contestTimer = contestTimer,
       _contestDataManager = contestDataManager,
       _scoreCalculator = scoreCalculator,
       _mode = mode,
       _difficulty = difficulty,
       _seed = seed,
       _answerSourceOverride = answerSource,
       _onAnswerGenerated = onAnswerGenerated,
       _onAnswersExhausted = onAnswersExhausted,
       _accentPolicy = accentPolicy {
    _contestDataManager.audioLoader.setSessionRandom(_sessionRandom);
    _setupStateMachine();
    _setupKeyboardListener();
  }

  void _setupStateMachine() {
    final contestAnswer = _answerGenerator.generateAnswer();

    void transitionListener(
      Transition<SingleCallRunState, SingleCallRunEvent, Null> transition,
    ) {
      if (transition
          is! TransitionValid<SingleCallRunState, SingleCallRunEvent, Null>) {
        return;
      }

      final toState = transition.to;
      _contestStateChangeHandler.handleToState(
        toState,
        event: transition.event,
      );

      if (toState is WaitingSubmitMyExchange &&
          toState.isOperateInput &&
          !_inputHandler.isRstFilled) {
        _inputHandler.onRstFilled(true);
      } else if (toState is SpWaitingHisExchange &&
          !_inputHandler.isRstFilled) {
        // S&P copies the runner's serial into the exchange field, so prefill
        // the report and move focus there to start copying.
        _inputHandler.onRstFilled(true);
      }
    }

    if (contestAnswer.isSearchAndPounce) {
      // S&P drives its own state machine: Enter pounces with our callsign, the
      // second Enter sends our exchange and commits, his TU closes the QSO.
      final initialState = SpListeningCq(
        currentCallAnswer: contestAnswer.callSign,
        currentExchangeAnswer: contestAnswer.exchange,
      );
      _stateMachine = initSearchAndPounceRunStateMachine(
        initialState: initialState,
        transitionListener: transitionListener,
      );
      _contestStateChangeHandler.handleToState(initialState);
      return;
    }

    final initialState = WaitingSubmitCall(
      currentCallAnswer: contestAnswer.callSign,
      currentExchangeAnswer: contestAnswer.exchange,
      pileupCallsigns: contestAnswer.pileupCallsigns,
    );

    _stateMachine = initSingleCallRunStateMachine(
      initialState: initialState,
      transitionListener: transitionListener,
    );

    _contestStateChangeHandler.handleToState(initialState);
  }

  void _setupKeyboardListener() {
    _keyEventManager.operationEventStream.listen((event) {
      contestOperationEventHandler.handleOperationEvent(event);
    });

    _keyEventManager.inputAreaEventStream.listen((event) {
      contestOperationEventHandler.handleInputAreaEvent();
      _inputHandler.onSwitchCallsignAndExchange();
    });

    ServicesBinding.instance.keyboard.addHandler(_keyEventCallback);
  }

  void stop() {
    _contestStateChangeHandler.dispose();
    _contestDataManager.audioLoader.setSessionRandom(null);
    _stateMachine.dispose();
    ServicesBinding.instance.keyboard.removeHandler(_keyEventCallback);
  }
}
