import 'package:ssb_runner/common/calculate_list_diff.dart';
import 'package:ssb_runner/contest_run/state_machine/single_call/audio_play_type.dart';
import 'package:ssb_runner/contest_run/state_machine/single_call/single_call_run_event.dart';
import 'package:ssb_runner/contest_run/state_machine/single_call/single_call_run_state.dart';
import 'package:ssb_runner/state_machine/state_machine.dart';

StateMachine<SingleCallRunState, SingleCallRunEvent, Null>
initSingleCallRunStateMachine({
  required SingleCallRunState initialState,
  required TransitionListener<SingleCallRunState, SingleCallRunEvent, Null>
  transitionListener,
}) {
  return StateMachine.create((builder) {
    builder.initialState(initialState);

    builder.state(Init, (definition) {
      definition.on(NextCall, (state, event) {
        return definition.transitionTo(
          WaitingSubmitCall(
            currentCallAnswer: (event as NextCall).callAnswer,
            currentExchangeAnswer: event.exchangeAnswer,
          ),
        );
      });
    });

    builder.state(WaitingSubmitCall, (definition) {
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

      definition.on(SubmitCall, (state, event) {
        final stateVal = state as WaitingSubmitCall;
        final currentCallAnswer = stateVal.currentCallAnswer;
        final currentExchangeAnswer = stateVal.currentExchangeAnswer;

        final eventVal = event as SubmitCall;
        final submitCall = eventVal.call;

        return definition.transitionTo(
          WaitingSubmitExchange(
            currentCallAnswer: currentCallAnswer,
            currentExchangeAnswer: currentExchangeAnswer,
            submitCall: submitCall,
            audioPlayType: _calcuateSingleCallAudioPlayType(
              submitCall,
              currentCallAnswer,
              currentExchangeAnswer,
            ),
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

    builder.state(WaitingSubmitExchange, (definition) {
      definition.on(Retry, (state, event) {
        final stateVal = state as WaitingSubmitExchange;

        return definition.transitionTo(
          WaitingSubmitExchange(
            currentCallAnswer: stateVal.currentCallAnswer,
            currentExchangeAnswer: stateVal.currentExchangeAnswer,
            submitCall: stateVal.submitCall,
            audioPlayType: stateVal.audioPlayType,
          ),
        );
      });

      definition.on(SubmitExchange, (state, event) {
        final stateVal = state as WaitingSubmitExchange;
        final eventVal = event as SubmitExchange;

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
      print(
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

  if (diff >= 3) {
    return NoPlay();
  }

  if (diff > 0) {
    return PlayCallExchange(call: submitCall, exchange: answerExchange);
  }

  return PlayExchange(exchange: answerExchange);
}
