import 'package:ssb_runner/contest_run/state_machine/single_call/single_call_run_event.dart';
import 'package:ssb_runner/contest_run/state_machine/single_call/single_call_run_state.dart';
import 'package:ssb_runner/logging/app_logger.dart';
import 'package:ssb_runner/state_machine/state_machine.dart';

/// Search & Pounce flow, separate from Run mode (see
/// single_call_run_state_machine.dart for the Run mode machine).
///
/// Two Enter presses drive a QSO, matching N1MM's ESM behaviour; the second one
/// commits the QSO and the rest of the exchange runs without further input:
///   SpListeningCq          Enter → SpPounce,            send our callsign
///   SpWaitingHisExchange   Enter → SpSubmitHisExchange, send our exchange, log
///   SpQsoEnd               auto  → NextCall,            he answers TU
StateMachine<SingleCallRunState, SingleCallRunEvent, Null>
initSearchAndPounceRunStateMachine({
  required SpListeningCq initialState,
  required TransitionListener<SingleCallRunState, SingleCallRunEvent, Null>
  transitionListener,
}) {
  return StateMachine.create((builder) {
    builder.initialState(initialState);

    builder.state(SpListeningCq, (definition) {
      definition.on(SpPounce, (state, event) {
        final stateVal = state as SpListeningCq;
        return definition.transitionTo(
          SpWaitingHisExchange(
            currentCallAnswer: stateVal.currentCallAnswer,
            currentExchangeAnswer: stateVal.currentExchangeAnswer,
          ),
        );
      });

      definition.on(Retry, (state, event) {
        return definition.transitionTo(state);
      });

      definition.on(NextCall, (state, event) {
        final eventVal = event as NextCall;
        return definition.transitionTo(
          SpListeningCq(
            currentCallAnswer: eventVal.callAnswer,
            currentExchangeAnswer: eventVal.exchangeAnswer,
          ),
        );
      });
    });

    builder.state(SpWaitingHisExchange, (definition) {
      definition.on(SpSubmitHisExchange, (state, event) {
        final stateVal = state as SpWaitingHisExchange;
        final eventVal = event as SpSubmitHisExchange;
        return definition.transitionTo(
          SpQsoEnd(
            currentCallAnswer: stateVal.currentCallAnswer,
            currentExchangeAnswer: stateVal.currentExchangeAnswer,
            myExchange: eventVal.myExchange,
          ),
        );
      });

      definition.on(Retry, (state, event) {
        return definition.transitionTo(state);
      });

      definition.on(NextCall, (state, event) {
        final eventVal = event as NextCall;
        return definition.transitionTo(
          SpListeningCq(
            currentCallAnswer: eventVal.callAnswer,
            currentExchangeAnswer: eventVal.exchangeAnswer,
          ),
        );
      });
    });

    builder.state(SpQsoEnd, (definition) {
      definition.on(NextCall, (state, event) {
        final eventVal = event as NextCall;
        return definition.transitionTo(
          SpListeningCq(
            currentCallAnswer: eventVal.callAnswer,
            currentExchangeAnswer: eventVal.exchangeAnswer,
          ),
        );
      });
    });

    builder.onTransition((transition) {
      log.info(
        'onTransition: from=${transition.from} to=${(transition is TransitionValid<SingleCallRunState, SingleCallRunEvent, Null>) ? transition.to : null} event=${transition.event}',
        tag: 'contest.state',
      );
      transitionListener(transition);
    });
  });
}
