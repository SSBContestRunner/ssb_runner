import 'dart:async';

import 'package:flutter/services.dart';

const _functionKeys = [
  LogicalKeyboardKey.f1,
  LogicalKeyboardKey.f2,
  LogicalKeyboardKey.f3,
  LogicalKeyboardKey.f4,
  LogicalKeyboardKey.f5,
  LogicalKeyboardKey.f6,
  LogicalKeyboardKey.f7,
  LogicalKeyboardKey.f8,
];

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
    if (_functionKeys.contains(key)) {
      _handleFunctionKeyPressed(key);
    }
  }

  void _handleFunctionKeyPressed(LogicalKeyboardKey key) {
    if (_isFunctionKeyPressed) {
      return;
    }

    _isFunctionKeyPressed = true;

    switch (key) {
      case LogicalKeyboardKey.f1:
        _operationEventController.add(OperationEvent.cq);
        break;
      case LogicalKeyboardKey.f2:
        _operationEventController.add(OperationEvent.exch);
        break;
      case LogicalKeyboardKey.f3:
        _operationEventController.add(OperationEvent.tu);
        break;
      case LogicalKeyboardKey.f4:
        _operationEventController.add(OperationEvent.myCall);
        break;
      case LogicalKeyboardKey.f5:
        _operationEventController.add(OperationEvent.hisCall);
        break;
      case LogicalKeyboardKey.f6:
        _operationEventController.add(OperationEvent.b4);
        break;
      case LogicalKeyboardKey.f7:
        _operationEventController.add(OperationEvent.agn);
        break;
      case LogicalKeyboardKey.f8:
        _operationEventController.add(OperationEvent.nil);
        break;
    }
  }

  void _handleFunctionKeyReleased(LogicalKeyboardKey key) {
    if (_functionKeys.contains(key)) {
      _isFunctionKeyPressed = false;
    }
  }
}

enum OperationEvent { cq, exch, tu, myCall, hisCall, b4, agn, nil }
