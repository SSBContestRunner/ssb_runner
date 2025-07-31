import 'package:ssb_runner/contest_run/state_machine/single_call/audio_play_type.dart';

sealed class SingleCallRunState {}

class WaitingSubmitCall extends SingleCallRunState {
  WaitingSubmitCall({
    required this.currentCallAnswer,
    required this.currentExchangeAnswer,
    AudioPlayType? audioPlayType,
  }) : audioPlayType = audioPlayType ?? PlayCall(callToPlay: currentCallAnswer);

  final String currentCallAnswer;
  final String currentExchangeAnswer;
  final AudioPlayType audioPlayType;

  // copy with
  WaitingSubmitCall copyWith({
    String? currentCallAnswer,
    String? currentExchangeAnswer,
    AudioPlayType? audioPlayType,
  }) {
    return WaitingSubmitCall(
      currentCallAnswer: currentCallAnswer ?? this.currentCallAnswer,
      currentExchangeAnswer:
          currentExchangeAnswer ?? this.currentExchangeAnswer,
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

class WaitingSubmitExchange extends SingleCallRunState {
  WaitingSubmitExchange({
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

  WaitingSubmitExchange copyWith({
    String? currentCallAnswer,
    String? currentExchangeAnswer,
    String? submitCall,
    AudioPlayType? audioPlayType,
    bool? isOperateInput,
  }) {
    return WaitingSubmitExchange(
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
  });

  final String currentCallAnswer;
  final String currentExchangeAnswer;

  final String submitCall;
  final String submitExchange;
}
