import 'dart:async';

import 'package:flutter/services.dart';

final functionKeysMap =  {
  LogicalKeyboardKey.f1: OperationEvent.cq,
  LogicalKeyboardKey.f2: OperationEvent.exch,
  LogicalKeyboardKey.f3: OperationEvent.tu,
  LogicalKeyboardKey.f4: OperationEvent.myCall,
  LogicalKeyboardKey.f5: OperationEvent.hisCall,
  LogicalKeyboardKey.f6: OperationEvent.b4,
  LogicalKeyboardKey.f7: OperationEvent.agn,
  LogicalKeyboardKey.f8: OperationEvent.nil,
};

class KeyEventManager {
  bool _isFunctionKeyPressed = false;

  final StreamController<OperationEvent> _operationEventController =
      StreamController.broadcast(sync: false);

  late final Stream<OperationEvent> operationEventStream;

  KeyEventManager() {
    operationEventStream = _operationEventController.stream;
  }

  void onKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      _handleKeyPressed(event.logicalKey);
    }

    if (event is KeyUpEvent) {
      _handleFunctionKeyReleased(event.logicalKey);
    }
  }

  void _handleKeyPressed(LogicalKeyboardKey key) {
    if (functionKeysMap.keys.contains(key)) {
      _handleFunctionKeyPressed(key);
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

enum OperationEvent { cq, exch, tu, myCall, hisCall, b4, agn, nil }
