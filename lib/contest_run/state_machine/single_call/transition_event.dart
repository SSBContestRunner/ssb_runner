sealed class TransitionEvent {}

class NoCopy extends TransitionEvent {}

class WorkedBefore extends TransitionEvent {}

class SubmitCall extends TransitionEvent {
  SubmitCall({required this.call});
  final String call;
}

class Retry extends TransitionEvent {}

class SubmitExchange extends TransitionEvent {
  SubmitExchange({required this.exchange});
  final String exchange;
}

class NextCall extends TransitionEvent {
  NextCall({required this.callAnswer, required this.exchangeAnswer});
  final String callAnswer;
  final String exchangeAnswer;
}
