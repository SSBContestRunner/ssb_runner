import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:ssb_runner/contest_run/key_event_handler.dart';
import 'package:ssb_runner/settings/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('fresh install uses the N1MM-aligned default table', () async {
    final harness = await _createHarness();
    final bindings = harness.settings.functionKeyBindings;

    expect(bindings, hasLength(12));
    expect(bindings.map((binding) => binding.key), FunctionKey.values);

    expect(bindings[0].action, OperationAction.cq);
    expect(bindings[1].action, OperationAction.exchange);
    expect(bindings[2].action, OperationAction.tu);
    expect(bindings[3].action, OperationAction.myCall);
    expect(bindings[4].action, OperationAction.hisCall);
    expect(bindings[5].action, OperationAction.before);
    expect(bindings[6].action, OperationAction.again);
    expect(bindings[7].action, OperationAction.noCopy);
    expect(bindings[8].action, isNull);
    expect(bindings[9].action, isNull);
    expect(bindings[10].action, isNull);
    expect(bindings[11].action, OperationAction.wipe);
  });

  test('all keys can be Spare without falling back to the defaults', () async {
    final harness = await _createHarness();

    await harness.settings.setFunctionKeyBindings([
      for (final key in FunctionKey.values) FunctionKeyBinding(key, null),
    ]);

    final bindings = harness.settings.functionKeyBindings;
    expect(bindings, hasLength(12));
    expect(bindings.every((binding) => binding.isSpare), isTrue);
  });

  test(
    'partial new settings fill the missing keys from the defaults',
    () async {
      final harness = await _createHarness();
      await harness.prefs.setString('setting_function_key_F12', 'spare');

      final bindings = harness.settings.functionKeyBindings;
      expect(bindings[0].action, OperationAction.cq);
      expect(bindings[8].action, isNull);
      expect(bindings[11].action, isNull);
    },
  );

  test(
    'legacy action bindings migrate on top of the new default table',
    () async {
      final harness = await _createHarness();
      await harness.prefs.setString('setting_key_binding_cq', 'F2');
      await harness.prefs.setString('setting_key_binding_exchange', 'F1');

      final bindings = harness.settings.functionKeyBindings;

      // The operator's swap wins; untouched actions keep their new defaults.
      expect(bindings[0].key, FunctionKey.f1);
      expect(bindings[0].action, OperationAction.exchange);
      expect(bindings[1].key, FunctionKey.f2);
      expect(bindings[1].action, OperationAction.cq);
      expect(bindings[2].action, OperationAction.tu);
      expect(bindings[11].action, OperationAction.wipe);

      // Migration is persisted once, so a later read must not recompute it.
      expect(
        harness.prefs.getString('setting_function_key_F1'),
        OperationAction.exchange.id,
      );
      expect(
        harness.prefs.getString('setting_function_key_F12'),
        OperationAction.wipe.id,
      );
      // Every new key is written, and the old settings stay for rollback.
      for (final key in FunctionKey.values) {
        expect(
          harness.prefs.getString('setting_function_key_${key.label}'),
          isNotNull,
        );
      }
      expect(harness.prefs.getString('setting_key_binding_cq'), 'F2');
      expect(harness.prefs.getString('setting_key_binding_exchange'), 'F1');

      // Re-reading must not re-migrate on top of the written settings.
      final reread = harness.settings.functionKeyBindings;
      expect(reread[0].action, OperationAction.exchange);
      expect(reread[1].action, OperationAction.cq);
      expect(
        harness.prefs.getString('setting_function_key_F1'),
        OperationAction.exchange.id,
      );
    },
  );

  test(
    'dirty legacy conflict keeps customisation and spares the loser',
    () async {
      final harness = await _createHarness();
      // Both actions claim F2: the later action wins, the earlier becomes Spare.
      await harness.prefs.setString('setting_key_binding_cq', 'F2');
      await harness.prefs.setString('setting_key_binding_exchange', 'F2');

      final bindings = harness.settings.functionKeyBindings;
      expect(bindings[0].isSpare, isTrue);
      expect(bindings[1].action, OperationAction.exchange);
      expect(
        bindings.where((binding) => binding.action == OperationAction.cq),
        isEmpty,
      );

      final assigned = bindings
          .where((binding) => !binding.isSpare)
          .map((binding) => binding.action)
          .toList();
      expect(assigned.toSet(), hasLength(assigned.length));
    },
  );

  test('all F1-F12 keys are recognised, Spare keys stay silent', () async {
    final handler = KeyEventHandler();
    final events = <OperationEvent>[];
    handler.operationEventStream.listen(events.add);

    for (final key in FunctionKey.values) {
      await _press(handler, key.logicalKey, _physicalFunctionKeys[key.index]);
    }

    expect(events, [
      OperationEvent.cq,
      OperationEvent.exch,
      OperationEvent.tu,
      OperationEvent.myCall,
      OperationEvent.hisCall,
      OperationEvent.b4,
      OperationEvent.agn,
      OperationEvent.nil,
      // F9–F11 are Spare: no event.
      OperationEvent.wipe,
    ]);
  });

  test('F12 emits Wipe while Spare keys emit nothing', () async {
    final handler = KeyEventHandler();
    final events = <OperationEvent>[];
    handler.operationEventStream.listen(events.add);

    await _press(handler, LogicalKeyboardKey.f12, PhysicalKeyboardKey.f12);
    expect(events, [OperationEvent.wipe]);

    await _press(handler, LogicalKeyboardKey.f9, PhysicalKeyboardKey.f9);
    expect(events, [OperationEvent.wipe]);

    await _press(handler, LogicalKeyboardKey.f1, PhysicalKeyboardKey.f1);
    expect(events, [OperationEvent.wipe, OperationEvent.cq]);
  });

  test('a held function key fires once until it is released', () async {
    final handler = KeyEventHandler();
    final events = <OperationEvent>[];
    handler.operationEventStream.listen(events.add);

    handler.onKeyEvent(
      const KeyDownEvent(
        logicalKey: LogicalKeyboardKey.f12,
        physicalKey: PhysicalKeyboardKey.f12,
        timeStamp: Duration.zero,
      ),
    );
    handler.onKeyEvent(
      const KeyDownEvent(
        logicalKey: LogicalKeyboardKey.f12,
        physicalKey: PhysicalKeyboardKey.f12,
        timeStamp: Duration.zero,
      ),
    );
    await pumpEventQueue();
    expect(events, [OperationEvent.wipe]);

    handler.onKeyEvent(
      const KeyUpEvent(
        logicalKey: LogicalKeyboardKey.f12,
        physicalKey: PhysicalKeyboardKey.f12,
        timeStamp: Duration.zero,
      ),
    );
    await _press(handler, LogicalKeyboardKey.f12, PhysicalKeyboardKey.f12);
    expect(events, [OperationEvent.wipe, OperationEvent.wipe]);
  });

  testWidgets('F12 is handled globally while a text field has focus', (
    tester,
  ) async {
    final handler = KeyEventHandler();
    final events = <OperationEvent>[];
    handler.operationEventStream.listen(events.add);

    bool onKeyEvent(KeyEvent event) {
      handler.onKeyEvent(event);
      return false;
    }

    ServicesBinding.instance.keyboard.addHandler(onKeyEvent);
    addTearDown(
      () => ServicesBinding.instance.keyboard.removeHandler(onKeyEvent),
    );

    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Material(child: TextField(focusNode: focusNode)),
      ),
    );
    focusNode.requestFocus();
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.f12);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.f12);
    // Widget tests run in fake async, so pump instead of pumpEventQueue().
    await tester.pump();

    expect(events, [OperationEvent.wipe]);
    expect(focusNode.hasFocus, isTrue);
  });

  test('custom bindings are honoured by the keyboard handler', () async {
    final harness = await _createHarness();
    await harness.settings.setFunctionKeyBindings([
      for (final key in FunctionKey.values)
        FunctionKeyBinding(
          key,
          key == FunctionKey.f9 ? OperationAction.cq : null,
        ),
    ]);

    final handler = KeyEventHandler(
      bindings: functionKeysFromSettings(harness.settings),
    );
    final events = <OperationEvent>[];
    handler.operationEventStream.listen(events.add);

    await _press(handler, LogicalKeyboardKey.f9, PhysicalKeyboardKey.f9);
    expect(events, [OperationEvent.cq]);

    await _press(handler, LogicalKeyboardKey.f1, PhysicalKeyboardKey.f1);
    expect(events, [OperationEvent.cq]);
  });
}

Future<void> _press(
  KeyEventHandler handler,
  LogicalKeyboardKey logicalKey,
  PhysicalKeyboardKey physicalKey,
) async {
  handler.onKeyEvent(
    KeyDownEvent(
      logicalKey: logicalKey,
      physicalKey: physicalKey,
      timeStamp: Duration.zero,
    ),
  );
  handler.onKeyEvent(
    KeyUpEvent(
      logicalKey: logicalKey,
      physicalKey: physicalKey,
      timeStamp: Duration.zero,
    ),
  );
  await pumpEventQueue();
}

const _physicalFunctionKeys = [
  PhysicalKeyboardKey.f1,
  PhysicalKeyboardKey.f2,
  PhysicalKeyboardKey.f3,
  PhysicalKeyboardKey.f4,
  PhysicalKeyboardKey.f5,
  PhysicalKeyboardKey.f6,
  PhysicalKeyboardKey.f7,
  PhysicalKeyboardKey.f8,
  PhysicalKeyboardKey.f9,
  PhysicalKeyboardKey.f10,
  PhysicalKeyboardKey.f11,
  PhysicalKeyboardKey.f12,
];

Future<({AppSettings settings, SharedPreferencesWithCache prefs})>
_createHarness() async {
  final prefs = await SharedPreferencesWithCache.create(
    cacheOptions: const SharedPreferencesWithCacheOptions(),
  );
  return (settings: AppSettings(prefs: prefs), prefs: prefs);
}
