import 'package:ssb_runner/contest_run/state_machine/single_call/audio_play_type.dart';

sealed class SingleCallRunState {}

class WaitingSubmitCall extends SingleCallRunState {
  WaitingSubmitCall({
    required this.currentCallAnswer,
    required this.currentExchangeAnswer,
  });
  final String currentCallAnswer;
  final String currentExchangeAnswer;
}

class ReportMyExchange extends SingleCallRunState {
  ReportMyExchange({
    required this.currentCallAnswer,
    required this.currentExchangeAnswer,
    required this.submitCall,
    required this.myExchange,
    required this.audioPlayType,
  });
  final String currentCallAnswer;
  final String currentExchangeAnswer;
  final String submitCall;
  final String myExchange;
  final AudioPlayType audioPlayType;
}

class WaitingSubmitExchange extends SingleCallRunState {
  WaitingSubmitExchange({
    required this.currentCallAnswer,
    required this.currentExchangeAnswer,
    required this.submitCall,
    required this.audioPlayType,
  });
  final String currentCallAnswer;
  final String currentExchangeAnswer;

  final String submitCall;
  final AudioPlayType audioPlayType;
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
