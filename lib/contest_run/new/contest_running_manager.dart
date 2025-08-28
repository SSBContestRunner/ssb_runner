import 'package:flutter/services.dart';
import 'package:ssb_runner/contest_run/key_event_handler.dart';
import 'package:ssb_runner/contest_run/new/contest_answer_generator.dart';
import 'package:ssb_runner/contest_run/new/contest_data_manager.dart';
import 'package:ssb_runner/contest_run/new/contest_input_handler.dart';
import 'package:ssb_runner/contest_run/new/contest_operation_event_handler.dart';
import 'package:ssb_runner/contest_run/new/contest_state_change_handler.dart';
import 'package:ssb_runner/contest_run/new/contest_timer.dart';
import 'package:ssb_runner/contest_run/score_manager.dart';
import 'package:ssb_runner/contest_run/state_machine/single_call/single_call_run_event.dart';
import 'package:ssb_runner/contest_run/state_machine/single_call/single_call_run_state.dart';
import 'package:ssb_runner/contest_run/state_machine/single_call/single_call_run_state_machine.dart';
import 'package:ssb_runner/contest_type/contest_type.dart';
import 'package:ssb_runner/contest_type/score_calculator.dart';
import 'package:ssb_runner/state_machine/state_machine.dart';

class ContestRunningManager {
  final String runId;
  final ContestType _contestType;
  final ContestDataManager _contestDataManager;
  final ContestTimer _contestTimer;
  final ScoreCalculator _scoreCalculator;

  late final ContestInputHandler _inputHandler =
      _contestDataManager.inputHandler;

  late final StateMachine<SingleCallRunState, SingleCallRunEvent, Null>
  _stateMachine;

  late final ScoreManager scoreManager = ScoreManager(
    contestId: runId,
    stationCallsign: _contestDataManager.appSettings.stationCallsign,
    scoreCalculator: _scoreCalculator,
  );

  late final ContestAnswerGenerator _answerGenerator = ContestAnswerGenerator(
    contestType: _contestType,
    callsignLoader: _contestDataManager.callsignLoader,
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
      );

  late final ContestOperationEventHandler _contestOperationEventHandler =
      ContestOperationEventHandler(
        contestRunId: runId,
        contestDataManager: _contestDataManager,
        stateMachine: _stateMachine,
        inputHandler: _inputHandler,
      );

  final _keyEventManager = KeyEventHandler();

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
  }) : _contestType = contestType,
       _contestTimer = contestTimer,
       _contestDataManager = contestDataManager,
       _scoreCalculator = scoreCalculator {
    _setupStateMachine();
    _setupKeyboardListener();
  }

  void _setupStateMachine() async {
    final contestAnswer = _answerGenerator.generateAnswer();

    final waitingSubmitCall = WaitingSubmitCall(
      currentCallAnswer: contestAnswer.callSign,
      currentExchangeAnswer: contestAnswer.exchange,
    );

    _stateMachine = initSingleCallRunStateMachine(
      initialState: waitingSubmitCall,
      transitionListener: (transition) {
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
        }
      },
    );

    _contestStateChangeHandler.handleToState(waitingSubmitCall);
  }

  void _setupKeyboardListener() {
    _keyEventManager.operationEventStream.listen((event) {
      _contestOperationEventHandler.handleOperationEvent(event);
    });

    _keyEventManager.inputAreaEventStream.listen((event) {
      _contestOperationEventHandler.handleInputAreaEvent(event);
    });

    ServicesBinding.instance.keyboard.addHandler(_keyEventCallback);
  }

  void stop() {
    _stateMachine.dispose();
    ServicesBinding.instance.keyboard.removeHandler(_keyEventCallback);
  }
}
