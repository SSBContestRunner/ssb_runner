import 'package:ssb_contest_runner/contest_run/state_machine/single_call/audio_play_type.dart';
import 'package:ssb_contest_runner/contest_run/state_machine/single_call/single_call_run_state.dart';
import 'package:ssb_contest_runner/contest_run/state_machine/single_call/single_call_run_event.dart';
import 'package:ssb_contest_runner/state_machine/state_machine.dart';

StateMachine<SingleCallRunState, SingleCallRunEvent, Null>
initSingleCallRunStateMachine() {
  return StateMachine.create((builder) {
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

        definition.transitionTo(
          WaitingSubmitExchange(
            currentCallAnswer: currentCallAnswer,
            currentExchangeAnswer: currentExchangeAnswer,
            submitCall: submitCall,
            // FIXME: determine the audio play type
            audioPlayType: NoPlay(),
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
  });
}
