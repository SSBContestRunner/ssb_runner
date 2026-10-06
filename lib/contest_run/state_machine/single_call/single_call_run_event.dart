sealed class SingleCallRunEvent {}

class NoCopy extends SingleCallRunEvent {
  final String nextCallAnswer;
  final String nextExchangeAnswer;
  final List<String> pileupCallsigns;

  NoCopy({
    required this.nextCallAnswer,
    required this.nextExchangeAnswer,
    this.pileupCallsigns = const [],
  });
}

class WorkedBefore extends SingleCallRunEvent {
  final String nextCallAnswer;
  final String nextExchangeAnswer;
  final List<String> pileupCallsigns;

  WorkedBefore({
    required this.nextCallAnswer,
    required this.nextExchangeAnswer,
    this.pileupCallsigns = const [],
  });
}

class SubmitCallAndHisExchange extends SingleCallRunEvent {
  SubmitCallAndHisExchange({
    required this.call,
    required this.myExchange,
    required this.isOperateInput,
  });
  final String call;
  final String myExchange;
  final bool isOperateInput;
}

class SubmitCall extends SingleCallRunEvent {
  SubmitCall({required this.call});
  final String call;
}

class CallsignInvalid extends SingleCallRunEvent {
  CallsignInvalid();
}

class ReceiveExchange extends SingleCallRunEvent {
  ReceiveExchange();
}

class Retry extends SingleCallRunEvent {}

class SubmitMyExchange extends SingleCallRunEvent {
  SubmitMyExchange({required this.exchange, required this.call});
  final String exchange;

  /// Callsign currently in the input, so a correction made while copying the
  /// exchange can be announced when the QSO is signed off.
  final String call;
}

class SubmitHisExchange extends SingleCallRunEvent {
  SubmitHisExchange({required this.exchange});
  final String exchange;
}

class NextCall extends SingleCallRunEvent {
  NextCall({
    required this.callAnswer,
    required this.exchangeAnswer,
    this.pileupCallsigns = const [],
    this.isSearchAndPounce = false,
  });
  final String callAnswer;
  final String exchangeAnswer;
  final List<String> pileupCallsigns;
  final bool isSearchAndPounce;
}

class Cancel extends SingleCallRunEvent {}
