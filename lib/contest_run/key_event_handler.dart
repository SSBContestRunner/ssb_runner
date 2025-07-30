import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

final functionKeysMap = {
  LogicalKeyboardKey.f1: OperationEvent.cq,
  LogicalKeyboardKey.f2: OperationEvent.exch,
  LogicalKeyboardKey.f3: OperationEvent.tu,
  LogicalKeyboardKey.f4: OperationEvent.myCall,
  LogicalKeyboardKey.f5: OperationEvent.hisCall,
  LogicalKeyboardKey.f6: OperationEvent.b4,
  LogicalKeyboardKey.f7: OperationEvent.agn,
  LogicalKeyboardKey.f8: OperationEvent.nil,
};

class KeyEventHandler {
  bool _isFunctionKeyPressed = false;

  final Set<LogicalKeyboardKey> _pressedKeys = {};

  final StreamController<OperationEvent> _operationEventController =
      StreamController.broadcast(sync: false);
  Stream<OperationEvent> get operationEventStream =>
      _operationEventController.stream;

  final StreamController<InputAreaEvent> _inputAreaEventController =
      StreamController.broadcast(sync: false);
  Stream<InputAreaEvent> get inputAreaEventStream =>
      _inputAreaEventController.stream;

  void onKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      _pressedKeys.add(event.logicalKey);
      _handleKeyPressed(event.logicalKey);
    }

    if (event is KeyUpEvent) {
      _pressedKeys.remove(event.logicalKey);
      _handleFunctionKeyReleased(event.logicalKey);
    }
  }

  void _handleKeyPressed(LogicalKeyboardKey key) {
    if (functionKeysMap.keys.contains(key)) {
      _handleFunctionKeyPressed(key);
    }

    _checkOnlyKeyPressed(key, LogicalKeyboardKey.enter, () {
      _operationEventController.add(OperationEvent.submit);
    });

    _checkOnlyKeyPressed(key, LogicalKeyboardKey.escape, () {
      _operationEventController.add(OperationEvent.cancel);
    });

    _checkOnlyKeyPressed(key, LogicalKeyboardKey.space, () {
      _inputAreaEventController.add(InputAreaEvent.switchCallsignAndExchange);
    });
  }

  void _checkOnlyKeyPressed(
    LogicalKeyboardKey key,
    LogicalKeyboardKey referenceKey,
    void Function() block,
  ) {
    if (key == referenceKey && _pressedKeys.length == 1) {
      block();
    }
  }

  void _handleFunctionKeyPressed(LogicalKeyboardKey key) {
    if (_isFunctionKeyPressed) {
      return;
    }

    _isFunctionKeyPressed = true;

    final operationEvent = functionKeysMap[key];
    if (operationEvent != null) {
      _operationEventController.add(operationEvent);
    }
  }

  void _handleFunctionKeyReleased(LogicalKeyboardKey key) {
    if (functionKeysMap.keys.contains(key)) {
      _isFunctionKeyPressed = false;
    }
  }
}

enum OperationEvent {
  cq(btnText: 'CQ'),
  exch(btnText: 'EXCH'),
  tu(btnText: 'TU'),
  myCall(btnText: '<my>'),
  hisCall(btnText: '<his>'),
  b4(btnText: 'B4'),
  agn(btnText: 'AGN'),
  nil(btnText: 'NIL'),
  submit(btnText: ''),
  cancel(btnText: '');

  final String btnText;

  const OperationEvent({required this.btnText});
}

enum InputAreaEvent { switchCallsignAndExchange }
