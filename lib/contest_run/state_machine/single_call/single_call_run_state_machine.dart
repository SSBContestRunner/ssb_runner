import 'package:ssb_runner/common/calculate_list_diff.dart';
import 'package:ssb_runner/common/constants.dart';
import 'package:ssb_runner/contest_run/state_machine/single_call/audio_play_type.dart';
import 'package:ssb_runner/contest_run/state_machine/single_call/single_call_run_event.dart';
import 'package:ssb_runner/contest_run/state_machine/single_call/single_call_run_state.dart';
import 'package:ssb_runner/main.dart';
import 'package:ssb_runner/state_machine/state_machine.dart';

StateMachine<SingleCallRunState, SingleCallRunEvent, Null>
initSingleCallRunStateMachine({
  required SingleCallRunState initialState,
  required TransitionListener<SingleCallRunState, SingleCallRunEvent, Null>
  transitionListener,
}) {
  return StateMachine.create((builder) {
    builder.initialState(initialState);

    builder.state(WaitingSubmitCall, (definition) {
      definition.on(Cancel, (state, event) {
        state as WaitingSubmitCall;
        return definition.transitionTo(state.copyWith(audioPlayType: NoPlay()));
      });

      definition.on(WorkedBefore, (state, event) {
        final eventVal = event as WorkedBefore;
        final currentCallAnswer = eventVal.nextCallAnswer;
        final currentExchangeAnswer = eventVal.nextExchangeAnswer;

        return definition.transitionTo(
          WaitingSubmitCall(
            currentCallAnswer: currentCallAnswer,
            currentExchangeAnswer: currentExchangeAnswer,
          ),
        );
      });

      definition.on(Retry, (state, event) {
        final stateVal = state as WaitingSubmitCall;
        final currentCallAnswer = stateVal.currentCallAnswer;
        final currentExchangeAnswer = stateVal.currentExchangeAnswer;

        return definition.transitionTo(
          WaitingSubmitCall(
            currentCallAnswer: currentCallAnswer,
            currentExchangeAnswer: currentExchangeAnswer,
          ),
        );
      });

      definition.on(SubmitCallAndHisExchange, (state, event) {
        final stateVal = state as WaitingSubmitCall;
        final currentCallAnswer = stateVal.currentCallAnswer;
        final currentExchangeAnswer = stateVal.currentExchangeAnswer;

        final eventVal = event as SubmitCallAndHisExchange;
        final submitCall = eventVal.call;
        final myExchange = eventVal.hisExchange;

        return definition.transitionTo(
          ReportMyExchange(
            currentCallAnswer: currentCallAnswer,
            currentExchangeAnswer: currentExchangeAnswer,
            submitCall: submitCall,
            myExchange: myExchange,
            audioPlayType: PlayCallExchange(
              call: submitCall,
              exchange: myExchange,
              isMe: true,
            ),
            isOperateInput: eventVal.isOperateInput,
          ),
        );
      });

      definition.on(NoCopy, (state, event) {
        final eventVal = event as NoCopy;
        final nextCallAnswer = eventVal.nextCallAnswer;
        final nextExchangeAnswer = eventVal.nextExchangeAnswer;

        return definition.transitionTo(
          WaitingSubmitCall(
            currentCallAnswer: nextCallAnswer,
            currentExchangeAnswer: nextExchangeAnswer,
          ),
        );
      });

      definition.on(SubmitCall, (state, event) {
        state as WaitingSubmitCall;
        event as SubmitCall;

        final submitCall = event.call;

        final diff = calculateMismatch(
          answer: state.currentCallAnswer,
          submit: submitCall,
        );

        if (diff > callsignMismatchThreadshold) {
          return definition.transitionTo(
            state.copyWith(audioPlayType: NoPlay()),
          );
        }

        if (diff > 0) {
          return definition.transitionTo(
            HeRepeatCorrectCallAnswer(
              currentCallAnswer: state.currentCallAnswer,
              currentExchangeAnswer: state.currentExchangeAnswer,
              submitCall: submitCall,
            ),
          );
        }

        return definition.transitionTo(
          HeAskForExchange(
            currentCallAnswer: state.currentCallAnswer,
            currentExchangeAnswer: state.currentExchangeAnswer,
            submitCall: event.call,
            isPlayMyCall: false,
          ),
        );
      });
    });

    builder.state(HeAskForExchange, (definition) {
      definition.on(Retry, (state, event) {
        state as HeAskForExchange;
        return definition.transitionTo(state.copyWith(isPlayMyCall: true));
      });

      definition.on(SubmitHisExchange, (state, event) {
        state as HeAskForExchange;

        return definition.transitionTo(
          WaitingSubmitMyExchange(
            currentCallAnswer: state.currentCallAnswer,
            currentExchangeAnswer: state.currentExchangeAnswer,
            submitCall: state.submitCall,
            audioPlayType: PlayExchange(
              exchange: state.currentExchangeAnswer,
              isMe: false,
            ),
            isOperateInput: false,
          ),
        );
      });
    });

    builder.state(HeRepeatCorrectCallAnswer, (definition) {
      definition.on(Retry, (state, event) {
        return definition.transitionTo(state);
      });

      definition.on(SubmitHisExchange, (state, event) {
        state as HeRepeatCorrectCallAnswer;
        return definition.transitionTo(
          WaitingSubmitMyExchange(
            currentCallAnswer: state.currentCallAnswer,
            currentExchangeAnswer: state.currentExchangeAnswer,
            submitCall: state.submitCall,
            audioPlayType: PlayExchange(
              exchange: state.currentExchangeAnswer,
              isMe: false,
            ),
            isOperateInput: false,
          ),
        );
      });
    });

    builder.state(ReportMyExchange, (definition) {
      definition.on(Cancel, (state, event) {
        state as ReportMyExchange;
        return definition.transitionTo(
          WaitingSubmitCall(
            currentCallAnswer: state.currentCallAnswer,
            currentExchangeAnswer: state.currentExchangeAnswer,
            audioPlayType: NoPlay(),
          ),
        );
      });

      definition.on(ReceiveExchange, (state, event) {
        state as ReportMyExchange;

        return definition.transitionTo(
          WaitingSubmitMyExchange(
            currentCallAnswer: state.currentCallAnswer,
            currentExchangeAnswer: state.currentExchangeAnswer,
            submitCall: state.submitCall,
            audioPlayType: _calcuateSingleCallAudioPlayType(
              state.submitCall,
              state.currentCallAnswer,
              state.currentExchangeAnswer,
            ),
            isOperateInput: state.isOperateInput,
          ),
        );
      });

      definition.on(CallsignInvalid, (state, event) {
        state as ReportMyExchange;

        return definition.transitionTo(
          WaitingSubmitCall(
            currentCallAnswer: state.currentCallAnswer,
            currentExchangeAnswer: state.currentExchangeAnswer,
            audioPlayType: NoPlay(),
          ),
        );
      });
    });

    builder.state(WaitingSubmitMyExchange, (definition) {
      definition.on(Cancel, (state, event) {
        state as WaitingSubmitMyExchange;
        return definition.transitionTo(state.copyWith(audioPlayType: NoPlay()));
      });

      definition.on(Retry, (state, event) {
        final stateVal = state as WaitingSubmitMyExchange;

        return definition.transitionTo(
          WaitingSubmitMyExchange(
            currentCallAnswer: stateVal.currentCallAnswer,
            currentExchangeAnswer: stateVal.currentExchangeAnswer,
            submitCall: stateVal.submitCall,
            audioPlayType: stateVal.audioPlayType,
            isOperateInput: stateVal.isOperateInput,
          ),
        );
      });

      definition.on(SubmitMyExchange, (state, event) {
        final stateVal = state as WaitingSubmitMyExchange;
        final eventVal = event as SubmitMyExchange;

        return definition.transitionTo(
          QsoEnd(
            currentCallAnswer: stateVal.currentCallAnswer,
            currentExchangeAnswer: stateVal.currentExchangeAnswer,
            submitCall: stateVal.submitCall,
            submitExchange: eventVal.exchange,
          ),
        );
      });

      definition.on(NoCopy, (state, event) {
        final eventVal = event as NoCopy;
        final nextCallAnswer = eventVal.nextCallAnswer;
        final nextExchangeAnswer = eventVal.nextExchangeAnswer;

        return definition.transitionTo(
          WaitingSubmitCall(
            currentCallAnswer: nextCallAnswer,
            currentExchangeAnswer: nextExchangeAnswer,
          ),
        );
      });
    });

    builder.state(QsoEnd, (definition) {
      definition.on(NextCall, (state, event) {
        final eventVal = event as NextCall;

        return definition.transitionTo(
          WaitingSubmitCall(
            currentCallAnswer: eventVal.callAnswer,
            currentExchangeAnswer: eventVal.exchangeAnswer,
          ),
        );
      });
    });

    builder.onTransition((transition) {
      logger.i(
        'onTransition: from=${transition.from} to=${(transition is TransitionValid<SingleCallRunState, SingleCallRunEvent, Null>) ? transition.to : null} event=${transition.event}',
      );
      transitionListener(transition);
    });
  });
}

AudioPlayType _calcuateSingleCallAudioPlayType(
  String submitCall,
  String answerCall,
  String answerExchange,
) {
  int diff = calculateMismatch(answer: answerCall, submit: submitCall);

  if (diff >= callsignMismatchThreadshold) {
    return NoPlay();
  }

  if (diff > 0) {
    return PlayCallExchange(
      call: answerCall,
      exchange: answerExchange,
      isMe: false,
    );
  }

  return PlayExchange(exchange: answerExchange, isMe: false);
}
