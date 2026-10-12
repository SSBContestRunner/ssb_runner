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
  });
  final String callAnswer;
  final String exchangeAnswer;
  final List<String> pileupCallsigns;
}

class Cancel extends SingleCallRunEvent {}

// region Search & Pounce events

/// Operator pressed Enter while listening to a CQ: pounce with our callsign.
class SpPounce extends SingleCallRunEvent {}

/// Operator copied the runner's serial and pressed Enter: send our exchange.
/// The QSO commits on this event — there is no separate confirmation step.
class SpSubmitHisExchange extends SingleCallRunEvent {
  SpSubmitHisExchange({required this.exchange, required this.myExchange});

  /// The runner's serial the operator copied.
  final String exchange;

  /// The exchange we transmit.
  final String myExchange;
}
// endregion
