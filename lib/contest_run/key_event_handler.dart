import 'dart:async';

import 'package:flutter/services.dart';
import 'package:ssb_runner/settings/app_settings.dart';

/// The default F1–F12 bindings, derived from [FunctionKey] so the keys and the
/// settings share one source.
List<FunctionKeyBinding> get defaultFunctionKeyBindings => [
  for (final key in FunctionKey.values)
    FunctionKeyBinding(key, key.defaultAction),
];

class KeyEventHandler {
  KeyEventHandler({List<FunctionKeyBinding>? bindings})
    : _bindings = bindings ?? defaultFunctionKeyBindings;

  final List<FunctionKeyBinding> _bindings;

  late final Map<LogicalKeyboardKey, OperationAction?> _actionByKey = {
    for (final binding in _bindings) binding.key.logicalKey: binding.action,
  };

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
    if (_actionByKey.containsKey(key)) {
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

    // Spare keys are recognised as function keys but dispatch nothing.
    final action = _actionByKey[key];
    if (action != null) {
      _operationEventController.add(operationEventFor(action));
    }
  }

  void _handleFunctionKeyReleased(LogicalKeyboardKey key) {
    if (_actionByKey.containsKey(key)) {
      _isFunctionKeyPressed = false;
    }
  }
}

List<FunctionKeyBinding> functionKeysFromSettings(AppSettings settings) =>
    settings.functionKeyBindings;

OperationEvent operationEventFor(OperationAction action) => switch (action) {
  OperationAction.cq => OperationEvent.cq,
  OperationAction.exchange => OperationEvent.exch,
  OperationAction.tu => OperationEvent.tu,
  OperationAction.myCall => OperationEvent.myCall,
  OperationAction.hisCall => OperationEvent.hisCall,
  OperationAction.before => OperationEvent.b4,
  OperationAction.again => OperationEvent.agn,
  OperationAction.noCopy => OperationEvent.nil,
  OperationAction.wipe => OperationEvent.wipe,
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
  wipe(btnText: 'Wipe'),
  submit(btnText: ''),
  cancel(btnText: ''),
  hisCallAndMyExchange(btnText: '');

  final String btnText;

  const OperationEvent({required this.btnText});
}

enum InputAreaEvent { switchCallsignAndExchange }
