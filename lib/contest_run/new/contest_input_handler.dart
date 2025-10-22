import 'dart:async';

const fillRst = 10001;
const switchCallsignAndExchange = 10003;
const clearInput = 10002;

class ContestInputHandler {
  String _hisCall = '';

  String get hisCall => _hisCall;

  String _exchange = '';

  String get exchange => _exchange;

  bool isRstFilled = false;
  final _isRstFilledStreamController = StreamController<bool>.broadcast();

  Stream<bool> get isRstFilledStream => _isRstFilledStreamController.stream;

  final _inputControlStreamController = StreamController<int>();

  Stream<int> get inputControlStream => _inputControlStreamController.stream;

  void onCallEdit(String call) {
    _hisCall = call;
  }

  void onExchangeEdit(String exchange) {
    _exchange = exchange;
  }

  void onRstFilled(bool isRstFilledVal) {
    isRstFilled = isRstFilledVal;
    _inputControlStreamController.sink.add(fillRst);
  }

  void onSwitchCallsignAndExchange() {
    _inputControlStreamController.sink.add(switchCallsignAndExchange);
  }

  void clear() {
    _hisCall = '';
    _exchange = '';
    isRstFilled = false;
    _isRstFilledStreamController.add(false);
    _inputControlStreamController.sink.add(clearInput);
  }
}
