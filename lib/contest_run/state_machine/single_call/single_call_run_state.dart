import 'package:ssb_runner/contest_run/state_machine/single_call/audio_play_type.dart';

sealed class SingleCallRunState {}

class WaitingSubmitCall extends SingleCallRunState {
  WaitingSubmitCall({
    required this.currentCallAnswer,
    required this.currentExchangeAnswer,
    this.pileupCallsigns = const [],
    AudioPlayType? audioPlayType,
  }) : audioPlayType =
           audioPlayType ??
           (pileupCallsigns.length > 1
               ? PlayPileup(calls: pileupCallsigns)
               : PlayCall(callToPlay: currentCallAnswer));

  final String currentCallAnswer;
  final String currentExchangeAnswer;
  final List<String> pileupCallsigns;
  final AudioPlayType audioPlayType;

  // copy with
  WaitingSubmitCall copyWith({
    String? currentCallAnswer,
    String? currentExchangeAnswer,
    List<String>? pileupCallsigns,
    AudioPlayType? audioPlayType,
  }) {
    return WaitingSubmitCall(
      currentCallAnswer: currentCallAnswer ?? this.currentCallAnswer,
      currentExchangeAnswer:
          currentExchangeAnswer ?? this.currentExchangeAnswer,
      pileupCallsigns: pileupCallsigns ?? this.pileupCallsigns,
      audioPlayType: audioPlayType ?? this.audioPlayType,
    );
  }
}

class ReportMyExchange extends SingleCallRunState {
  ReportMyExchange({
    required this.currentCallAnswer,
    required this.currentExchangeAnswer,
    required this.submitCall,
    required this.myExchange,
    required this.audioPlayType,
    required this.isOperateInput,
  });
  final String currentCallAnswer;
  final String currentExchangeAnswer;
  final String submitCall;
  final String myExchange;
  final AudioPlayType audioPlayType;
  final bool isOperateInput;
}

class WaitingSubmitMyExchange extends SingleCallRunState {
  WaitingSubmitMyExchange({
    required this.currentCallAnswer,
    required this.currentExchangeAnswer,
    required this.submitCall,
    required this.audioPlayType,
    required this.isOperateInput,
  });
  final String currentCallAnswer;
  final String currentExchangeAnswer;

  final String submitCall;
  final AudioPlayType audioPlayType;
  final bool isOperateInput;

  WaitingSubmitMyExchange copyWith({
    String? currentCallAnswer,
    String? currentExchangeAnswer,
    String? submitCall,
    AudioPlayType? audioPlayType,
    bool? isOperateInput,
  }) {
    return WaitingSubmitMyExchange(
      currentCallAnswer: currentCallAnswer ?? this.currentCallAnswer,
      currentExchangeAnswer:
          currentExchangeAnswer ?? this.currentExchangeAnswer,
      submitCall: submitCall ?? this.submitCall,
      audioPlayType: audioPlayType ?? this.audioPlayType,
      isOperateInput: isOperateInput ?? this.isOperateInput,
    );
  }
}

class QsoEnd extends SingleCallRunState {
  QsoEnd({
    required this.currentCallAnswer,
    required this.currentExchangeAnswer,
    required this.submitCall,
    required this.submitExchange,
    this.correctedCall,
  });

  final String currentCallAnswer;
  final String currentExchangeAnswer;

  final String submitCall;
  final String submitExchange;

  /// Callsign the operator fixed while copying the exchange, announced before
  /// signing off. Null when the first submission already stood.
  final String? correctedCall;
}

class HeAskForExchange extends SingleCallRunState {
  HeAskForExchange({
    required this.currentCallAnswer,
    required this.currentExchangeAnswer,
    required this.submitCall,
    required this.isPlayMyCall,
  });

  final String currentCallAnswer;
  final String currentExchangeAnswer;

  final String submitCall;
  final bool isPlayMyCall;

  HeAskForExchange copyWith({
    String? currentCallAnswer,
    String? currentExchangeAnswer,
    String? submitCall,
    bool? isPlayMyCall,
  }) {
    return HeAskForExchange(
      currentCallAnswer: currentCallAnswer ?? this.currentCallAnswer,
      currentExchangeAnswer:
          currentExchangeAnswer ?? this.currentExchangeAnswer,
      submitCall: submitCall ?? this.submitCall,
      isPlayMyCall: isPlayMyCall ?? this.isPlayMyCall,
    );
  }
}

class HeRepeatCorrectCallAnswer extends SingleCallRunState {
  HeRepeatCorrectCallAnswer({
    required this.currentCallAnswer,
    required this.currentExchangeAnswer,
    required this.submitCall,
    this.pileupCallsigns = const [],
  }) {
    audioPlayType = PlayCall(callToPlay: currentCallAnswer);
  }

  final String currentCallAnswer;
  final String currentExchangeAnswer;

  final String submitCall;

  /// Carried through so a failed re-submit can return to a pileup state
  /// without losing the pileup.
  final List<String> pileupCallsigns;
  late final AudioPlayType audioPlayType;
}

// region Search & Pounce states
//
// S&P drives its own state machine (see search_and_pounce_run_state_machine.dart)
// with a two-Enter QSO, matching N1MM's ESM behaviour:
//   SpListeningCq        hear "CQ <his call>"; the operator copies his callsign
//     → Enter 1, send our callsign
//   SpWaitingHisExchange he answers with our call + his serial; the operator
//                        copies the serial
//     → Enter 2, send our exchange; the QSO commits here
//   SpQsoEnd             we send "Roger + our serial", he answers TU, then the
//                        next CQ follows — no third Enter

/// Listening to a station calling CQ. The operator copies his callsign, then
/// Enter pounces with our callsign.
class SpListeningCq extends SingleCallRunState {
  SpListeningCq({
    required this.currentCallAnswer,
    required this.currentExchangeAnswer,
  });

  final String currentCallAnswer;
  final String currentExchangeAnswer;
}

/// We pounced with our callsign; he answers with our call and his serial. The
/// operator copies the serial, then Enter sends our exchange and commits.
class SpWaitingHisExchange extends SingleCallRunState {
  SpWaitingHisExchange({
    required this.currentCallAnswer,
    required this.currentExchangeAnswer,
  });

  final String currentCallAnswer;
  final String currentExchangeAnswer;
}

/// Signing off: we transmit our exchange, he answers TU, then the next CQ
/// follows. Entering this state is what commits the QSO.
class SpQsoEnd extends SingleCallRunState {
  SpQsoEnd({
    required this.currentCallAnswer,
    required this.currentExchangeAnswer,
    required this.myExchange,
  });

  final String currentCallAnswer;
  final String currentExchangeAnswer;

  /// The exchange we transmit, used for the "send our exchange" playback.
  final String myExchange;
}
// endregion
