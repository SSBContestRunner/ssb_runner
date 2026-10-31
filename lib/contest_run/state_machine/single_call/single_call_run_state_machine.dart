import 'package:ssb_runner/common/calculate_list_diff.dart';
import 'package:ssb_runner/contest_run/state_machine/single_call/audio_play_type.dart';
import 'package:ssb_runner/contest_run/state_machine/single_call/single_call_run_event.dart';
import 'package:ssb_runner/contest_run/state_machine/single_call/single_call_run_state.dart';
import 'package:ssb_runner/logging/app_logger.dart';
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
      definition.on(WorkedBefore, (state, event) {
        final eventVal = event as WorkedBefore;
        final currentCallAnswer = eventVal.nextCallAnswer;
        final currentExchangeAnswer = eventVal.nextExchangeAnswer;

        return definition.transitionTo(
          WaitingSubmitCall(
            currentCallAnswer: currentCallAnswer,
            currentExchangeAnswer: currentExchangeAnswer,
            pileupCallsigns: eventVal.pileupCallsigns,
          ),
        );
      });

      definition.on(Retry, (state, event) {
        final stateVal = state as WaitingSubmitCall;

        // Rebuild from the answer rather than copying `audioPlayType`: a
        // mis-copied or invalid submission may have left a silent state behind,
        // and copying it would leave every CQ/AGN/timeout retry silent too.
        return definition.transitionTo(
          WaitingSubmitCall(
            currentCallAnswer: stateVal.currentCallAnswer,
            currentExchangeAnswer: stateVal.currentExchangeAnswer,
            pileupCallsigns: stateVal.pileupCallsigns,
          ),
        );
      });

      definition.on(SubmitCallAndHisExchange, (state, event) {
        final stateVal = state as WaitingSubmitCall;
        final currentCallAnswer = stateVal.currentCallAnswer;
        final currentExchangeAnswer = stateVal.currentExchangeAnswer;

        final eventVal = event as SubmitCallAndHisExchange;
        final submitCall = eventVal.call;
        final myExchange = eventVal.myExchange;

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
            pileupCallsigns: eventVal.pileupCallsigns,
          ),
        );
      });

      definition.on(SubmitCall, (state, event) {
        final stateVal = state as WaitingSubmitCall;
        final submitCall = (event as SubmitCall).call;
        final currentCallAnswer = stateVal.currentCallAnswer;

        if (submitCall == currentCallAnswer) {
          return definition.transitionTo(
            HeAskForExchange(
              currentCallAnswer: currentCallAnswer,
              currentExchangeAnswer: stateVal.currentExchangeAnswer,
              submitCall: submitCall,
              isPlayMyCall: false,
            ),
          );
        }

        if (shouldRepeatCallsign(
          answer: currentCallAnswer,
          submit: submitCall,
        )) {
          return definition.transitionTo(
            HeRepeatCorrectCallAnswer(
              currentCallAnswer: currentCallAnswer,
              currentExchangeAnswer: stateVal.currentExchangeAnswer,
              submitCall: submitCall,
              pileupCallsigns: stateVal.pileupCallsigns,
            ),
          );
        }

        // A wildly wrong copy keeps him calling: replay the pileup (or the
        // single call) with the default audio for this answer instead of
        // silencing the round.
        return definition.transitionTo(
          WaitingSubmitCall(
            currentCallAnswer: currentCallAnswer,
            currentExchangeAnswer: stateVal.currentExchangeAnswer,
            pileupCallsigns: stateVal.pileupCallsigns,
          ),
        );
      });
    });

    builder.state(HeAskForExchange, (definition) {
      definition.on(Retry, (state, event) {
        state as HeAskForExchange;
        return definition.transitionTo(state.copyWith(isPlayMyCall: true));
      });

      definition.on(AbandonQso, (state, event) {
        return definition.transitionTo(_abandonedRound(event as AbandonQso));
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

      definition.on(AbandonQso, (state, event) {
        return definition.transitionTo(_abandonedRound(event as AbandonQso));
      });

      definition.on(SubmitCall, (state, event) {
        final stateVal = state as HeRepeatCorrectCallAnswer;
        final submitCall = (event as SubmitCall).call;

        if (submitCall == stateVal.currentCallAnswer) {
          return definition.transitionTo(
            HeAskForExchange(
              currentCallAnswer: stateVal.currentCallAnswer,
              currentExchangeAnswer: stateVal.currentExchangeAnswer,
              submitCall: submitCall,
              isPlayMyCall: false,
            ),
          );
        }

        if (shouldRepeatCallsign(
          answer: stateVal.currentCallAnswer,
          submit: submitCall,
        )) {
          return definition.transitionTo(
            HeRepeatCorrectCallAnswer(
              currentCallAnswer: stateVal.currentCallAnswer,
              currentExchangeAnswer: stateVal.currentExchangeAnswer,
              submitCall: submitCall,
              pileupCallsigns: stateVal.pileupCallsigns,
            ),
          );
        }

        return definition.transitionTo(
          WaitingSubmitCall(
            currentCallAnswer: stateVal.currentCallAnswer,
            currentExchangeAnswer: stateVal.currentExchangeAnswer,
            pileupCallsigns: stateVal.pileupCallsigns,
          ),
        );
      });

      definition.on(SubmitCallAndHisExchange, (state, event) {
        final stateVal = state as HeRepeatCorrectCallAnswer;
        final eventVal = event as SubmitCallAndHisExchange;

        return definition.transitionTo(
          ReportMyExchange(
            currentCallAnswer: stateVal.currentCallAnswer,
            currentExchangeAnswer: stateVal.currentExchangeAnswer,
            submitCall: eventVal.call,
            myExchange: eventVal.myExchange,
            audioPlayType: PlayCallExchange(
              call: eventVal.call,
              exchange: eventVal.myExchange,
              isMe: true,
            ),
            isOperateInput: eventVal.isOperateInput,
          ),
        );
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
      definition.on(AbandonQso, (state, event) {
        return definition.transitionTo(_abandonedRound(event as AbandonQso));
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

        // The copy was rejected: go back to a listening state that replays the
        // answer instead of one that can never make a sound again.
        return definition.transitionTo(
          WaitingSubmitCall(
            currentCallAnswer: state.currentCallAnswer,
            currentExchangeAnswer: state.currentExchangeAnswer,
          ),
        );
      });
    });

    builder.state(WaitingSubmitMyExchange, (definition) {
      definition.on(AbandonQso, (state, event) {
        return definition.transitionTo(_abandonedRound(event as AbandonQso));
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

        // The operator may correct the callsign while copying the exchange;
        // only then is the corrected call announced before signing off.
        final correctedCall =
            eventVal.call.isNotEmpty && eventVal.call != stateVal.submitCall
            ? eventVal.call
            : null;

        return definition.transitionTo(
          QsoEnd(
            currentCallAnswer: stateVal.currentCallAnswer,
            currentExchangeAnswer: stateVal.currentExchangeAnswer,
            submitCall: stateVal.submitCall,
            submitExchange: eventVal.exchange,
            correctedCall: correctedCall,
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
            pileupCallsigns: eventVal.pileupCallsigns,
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
            pileupCallsigns: eventVal.pileupCallsigns,
          ),
        );
      });
    });

    builder.onTransition((transition) {
      if (transition
          is TransitionValid<SingleCallRunState, SingleCallRunEvent, Null>) {
        log.info(
          'onTransition: from=${transition.from.runtimeType} to=${transition.to.runtimeType} event=${transition.event.runtimeType}',
          tag: 'contest.state',
          fields: _transitionFields(transition.to),
        );
      } else {
        log.warn(
          'dropped: no handler for ${transition.event.runtimeType} in ${transition.from.runtimeType}',
          tag: 'contest.state',
        );
      }
      transitionListener(transition);
    });
  });
}

WaitingSubmitCall _abandonedRound(AbandonQso event) {
  return WaitingSubmitCall(
    currentCallAnswer: event.nextCallAnswer,
    currentExchangeAnswer: event.nextExchangeAnswer,
    pileupCallsigns: event.pileupCallsigns,
  );
}

/// Copy carried into the transition log so a stuck round can be diagnosed
/// without reproducing it: what was asked, what was submitted, and whose
/// callsign was being announced.
Map<String, Object?> _transitionFields(SingleCallRunState value) {
  return switch (value) {
    WaitingSubmitCall state => {
      'call': state.currentCallAnswer,
      'exchange': state.currentExchangeAnswer,
      'pileupCallsigns': state.pileupCallsigns,
    },
    ReportMyExchange state => {
      'call': state.currentCallAnswer,
      'exchange': state.currentExchangeAnswer,
      'submitCall': state.submitCall,
      'isOperateInput': state.isOperateInput,
    },
    WaitingSubmitMyExchange state => {
      'call': state.currentCallAnswer,
      'exchange': state.currentExchangeAnswer,
      'submitCall': state.submitCall,
      'isOperateInput': state.isOperateInput,
    },
    HeAskForExchange state => {
      'call': state.currentCallAnswer,
      'exchange': state.currentExchangeAnswer,
      'submitCall': state.submitCall,
      'isPlayMyCall': state.isPlayMyCall,
    },
    HeRepeatCorrectCallAnswer state => {
      'call': state.currentCallAnswer,
      'exchange': state.currentExchangeAnswer,
      'submitCall': state.submitCall,
    },
    QsoEnd state => {
      'call': state.currentCallAnswer,
      'exchange': state.currentExchangeAnswer,
      'submitCall': state.submitCall,
      'submitExchange': state.submitExchange,
    },
    SpListeningCq state => {'call': state.currentCallAnswer},
    SpWaitingHisExchange state => {'call': state.currentCallAnswer},
    SpQsoEnd state => {'call': state.currentCallAnswer},
  };
}

AudioPlayType _calcuateSingleCallAudioPlayType(
  String submitCall,
  String answerCall,
  String answerExchange,
) {
  if (answerCall == submitCall) {
    return PlayExchange(exchange: answerExchange, isMe: false);
  }

  if (shouldRepeatCallsign(answer: answerCall, submit: submitCall)) {
    return PlayCallExchange(
      call: answerCall,
      exchange: answerExchange,
      isMe: false,
    );
  }

  return NoPlay();
}
