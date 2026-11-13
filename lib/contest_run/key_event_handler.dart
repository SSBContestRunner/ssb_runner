import 'dart:async';

import 'package:flutter/services.dart';
import 'package:ssb_runner/logging/app_logger.dart';
import 'package:ssb_runner/settings/app_settings.dart';

/// The default F1–F12 bindings, derived from [FunctionKey] so the keys and the
/// settings share one source.
List<FunctionKeyBinding> get defaultFunctionKeyBindings => [
  for (final key in FunctionKey.values)
    FunctionKeyBinding(key, key.defaultAction),
];

class KeyEventHandler {
  KeyEventHandler({List<FunctionKeyBinding>? bindings, this.isPaused})
    : _bindings = bindings ?? defaultFunctionKeyBindings;

  /// Gates every shortcut while the session is paused. Pause and resume are
  /// button-only, and a paused run must not react to Enter/Esc/Space/`;`/F-keys.
  final bool Function()? isPaused;

  final List<FunctionKeyBinding> _bindings;

  late final Map<LogicalKeyboardKey, OperationAction?> _actionByKey = {
    for (final binding in _bindings) binding.key.logicalKey: binding.action,
  };

  bool _isFunctionKeyPressed = false;

  final StreamController<OperationEvent> _operationEventController =
      StreamController.broadcast(sync: false);
  Stream<OperationEvent> get operationEventStream =>
      _operationEventController.stream;

  final StreamController<InputAreaEvent> _inputAreaEventController =
      StreamController.broadcast(sync: false);
  Stream<InputAreaEvent> get inputAreaEventStream =>
      _inputAreaEventController.stream;

  /// Any modifier held counts as a combination, not as the shortcut itself.
  ///
  /// This is read from [HardwareKeyboard] rather than tracked here: the
  /// framework updates its pressed state before calling the handlers, so it
  /// cannot go stale if a key-up is missed (e.g. released while the window was
  /// inactive), which used to disable `;`, Enter, Esc and Space silently.
  /// Any modifier turns a function key into someone else's shortcut, so the
  /// F1–F12 branch stays silent while Shift, Ctrl, Alt or Meta is held and only
  /// a bare function key dispatches. Fixed shortcuts keep their own rules
  /// below; in particular `;` still accepts Shift.
  bool get _hasModifierPressed =>
      HardwareKeyboard.instance.isShiftPressed ||
      HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isAltPressed ||
      HardwareKeyboard.instance.isMetaPressed;

  /// Modifier names for the key log, so a "dead" `;` can be diagnosed from the
  /// file without reproducing it.
  String get _modifierLabel => [
    if (HardwareKeyboard.instance.isMetaPressed) 'meta',
    if (HardwareKeyboard.instance.isControlPressed) 'control',
    if (HardwareKeyboard.instance.isAltPressed) 'alt',
    if (HardwareKeyboard.instance.isShiftPressed) 'shift',
  ].join('+');

  void onKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      _handleKeyPressed(event);
      return;
    }

    if (event is KeyUpEvent) {
      _handleFunctionKeyReleased(event.logicalKey);
    }
  }

  /// Drops the "a function key is still held" latch.
  ///
  /// Called when the window stops being active: the key-up can be delivered
  /// somewhere else, and a stuck latch would make every F-key dead until one is
  /// pressed and released again in this window.
  void resetPressedKeys() {
    _isFunctionKeyPressed = false;
  }

  /// [KeyRepeatEvent] is deliberately not handled: holding a shortcut down
  /// sends a key once, and auto-repeat must not storm the state machine.
  void _handleKeyPressed(KeyEvent event) {
    // Swallow the key entirely rather than letting it fall through: an event
    // that reaches the manager could still surface as an ignored shortcut.
    if (isPaused?.call() ?? false) {
      return;
    }

    final key = event.logicalKey;

    if (_actionByKey.containsKey(key)) {
      if (_hasModifierPressed) {
        log.debug(
          'function key ignored: modifier held',
          tag: 'key',
          fields: {'key': key.debugName, 'modifiers': _modifierLabel},
        );
      } else {
        _handleFunctionKeyPressed(key);
      }
    }

    _checkSingleKeyPressed(event, LogicalKeyboardKey.enter, () {
      _operationEventController.add(OperationEvent.submit);
    });

    _checkSingleKeyPressed(event, LogicalKeyboardKey.escape, () {
      _operationEventController.add(OperationEvent.cancel);
    });

    // Only a bare `;` counts. The physical key is still accepted so a layout
    // that reports `:` for the same key keeps working, but Shift is treated as
    // a modifier like everywhere else and suppresses the shortcut.
    _checkSingleKeyPressed(event, LogicalKeyboardKey.semicolon, () {
      _operationEventController.add(OperationEvent.hisCallAndMyExchange);
    }, referencePhysicalKey: PhysicalKeyboardKey.semicolon);

    _checkSingleKeyPressed(event, LogicalKeyboardKey.space, () {
      _inputAreaEventController.add(InputAreaEvent.switchCallsignAndExchange);
    });
  }

  void _checkSingleKeyPressed(
    KeyEvent event,
    LogicalKeyboardKey referenceKey,
    void Function() block, {
    PhysicalKeyboardKey? referencePhysicalKey,
  }) {
    final matches =
        event.logicalKey == referenceKey ||
        (referencePhysicalKey != null &&
            event.physicalKey == referencePhysicalKey);
    if (!matches) {
      return;
    }

    if (_hasModifierPressed) {
      log.debug(
        'shortcut ignored: modifier held',
        tag: 'key',
        fields: {'key': referenceKey.debugName, 'modifiers': _modifierLabel},
      );
      return;
    }

    log.debug(
      'shortcut',
      tag: 'key',
      fields: {'key': referenceKey.debugName, 'modifiers': _modifierLabel},
    );
    block();
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
