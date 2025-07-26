sealed class SingleCallRunEvent {}

class NoCopy extends SingleCallRunEvent {
  final String nextCallAnswer;
  final String nextExchangeAnswer;

  NoCopy({required this.nextCallAnswer, required this.nextExchangeAnswer});
}

class WorkedBefore extends SingleCallRunEvent {
  final String nextCallAnswer;
  final String nextExchangeAnswer;

  WorkedBefore({
    required this.nextCallAnswer,
    required this.nextExchangeAnswer,
  });
}

class SubmitCall extends SingleCallRunEvent {
  SubmitCall({required this.call, required this.myExchange});
  final String call;
  final String myExchange;
}

class ReceiveExchange extends SingleCallRunEvent {
  ReceiveExchange();
}

class Retry extends SingleCallRunEvent {}

class SubmitExchange extends SingleCallRunEvent {
  SubmitExchange({required this.exchange});
  final String exchange;
}

class NextCall extends SingleCallRunEvent {
  NextCall({required this.callAnswer, required this.exchangeAnswer});
  final String callAnswer;
  final String exchangeAnswer;
}
