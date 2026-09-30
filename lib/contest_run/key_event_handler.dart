import 'dart:async';

import 'package:flutter/services.dart';
import 'package:ssb_runner/settings/app_settings.dart';

final defaultFunctionKeysMap = {
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
  KeyEventHandler({Map<LogicalKeyboardKey, OperationEvent>? functionKeys})
    : _functionKeysMap = functionKeys ?? defaultFunctionKeysMap;

  final Map<LogicalKeyboardKey, OperationEvent> _functionKeysMap;

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
    if (_functionKeysMap.keys.contains(key)) {
      _handleFunctionKeyPressed(key);
    }

    _checkOnlyKeyPressed(key, LogicalKeyboardKey.enter, () {
      _operationEventController.add(OperationEvent.submit);
    });

    _checkOnlyKeyPressed(key, LogicalKeyboardKey.escape, () {
      _operationEventController.add(OperationEvent.cancel);
    });

    _checkOnlyKeyPressed(key, LogicalKeyboardKey.semicolon, () {
      _operationEventController.add(OperationEvent.hisCallAndMyExchange);
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

    final operationEvent = _functionKeysMap[key];
    if (operationEvent != null) {
      _operationEventController.add(operationEvent);
    }
  }

  void _handleFunctionKeyReleased(LogicalKeyboardKey key) {
    if (_functionKeysMap.keys.contains(key)) {
      _isFunctionKeyPressed = false;
    }
  }
}

Map<LogicalKeyboardKey, OperationEvent> functionKeysFromSettings(
  AppSettings settings,
) {
  final result = <LogicalKeyboardKey, OperationEvent>{};
  for (final action in OperationAction.values) {
    final key = _logicalFunctionKey(settings.binding(action));
    if (key != null) result[key] = _operationEventFor(action);
  }
  return result.isEmpty ? defaultFunctionKeysMap : result;
}

LogicalKeyboardKey? _logicalFunctionKey(String label) => switch (label) {
  'F1' => LogicalKeyboardKey.f1,
  'F2' => LogicalKeyboardKey.f2,
  'F3' => LogicalKeyboardKey.f3,
  'F4' => LogicalKeyboardKey.f4,
  'F5' => LogicalKeyboardKey.f5,
  'F6' => LogicalKeyboardKey.f6,
  'F7' => LogicalKeyboardKey.f7,
  'F8' => LogicalKeyboardKey.f8,
  _ => null,
};

OperationEvent _operationEventFor(OperationAction action) => switch (action) {
  OperationAction.cq => OperationEvent.cq,
  OperationAction.exchange => OperationEvent.exch,
  OperationAction.tu => OperationEvent.tu,
  OperationAction.myCall => OperationEvent.myCall,
  OperationAction.hisCall => OperationEvent.hisCall,
  OperationAction.before => OperationEvent.b4,
  OperationAction.again => OperationEvent.agn,
  OperationAction.noCopy => OperationEvent.nil,
};

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
  cancel(btnText: ''),
  hisCallAndMyExchange(btnText: '');

  final String btnText;

  const OperationEvent({required this.btnText});
}

enum InputAreaEvent { switchCallsignAndExchange }
