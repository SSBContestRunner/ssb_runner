import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/contest_run/key_event_handler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    HardwareKeyboard.instance.clearState();
  });

  group('单键快捷', () {
    test('分号键发出 hisCallAndMyExchange', () async {
      final handler = KeyEventHandler();
      final operations = <OperationEvent>[];
      handler.operationEventStream.listen(operations.add);

      _press(handler, LogicalKeyboardKey.semicolon, PhysicalKeyboardKey.semicolon);
      await pumpEventQueue();

      expect(operations, [OperationEvent.hisCallAndMyExchange]);
    });

    test('回车提交、Esc 停止、空格切换输入框', () async {
      final handler = KeyEventHandler();
      final operations = <OperationEvent>[];
      final inputs = <InputAreaEvent>[];
      handler.operationEventStream.listen(operations.add);
      handler.inputAreaEventStream.listen(inputs.add);

      _press(handler, LogicalKeyboardKey.enter, PhysicalKeyboardKey.enter);
      _press(handler, LogicalKeyboardKey.escape, PhysicalKeyboardKey.escape);
      _press(handler, LogicalKeyboardKey.space, PhysicalKeyboardKey.space);
      await pumpEventQueue();

      expect(operations, [OperationEvent.submit, OperationEvent.cancel]);
      expect(inputs, [InputAreaEvent.switchCallsignAndExchange]);
    });
  });

  group('修饰键', () {
    test('分号键按住 Shift 时不派发', () async {
      final handler = KeyEventHandler();
      final operations = <OperationEvent>[];
      handler.operationEventStream.listen(operations.add);

      _holdModifier(LogicalKeyboardKey.shiftLeft, PhysicalKeyboardKey.shiftLeft);
      _press(handler, LogicalKeyboardKey.semicolon, PhysicalKeyboardKey.semicolon);
      await pumpEventQueue();

      expect(operations, isEmpty);
      HardwareKeyboard.instance.clearState();
    });

    test('逻辑键为冒号时按物理键识别', () async {
      // 某些布局把同一个物理键报成 `:`；无修饰键时物理键兜底仍表示分号。
      HardwareKeyboard.instance.clearState();
      final handler = KeyEventHandler();
      final operations = <OperationEvent>[];
      handler.operationEventStream.listen(operations.add);

      _press(handler, LogicalKeyboardKey.colon, PhysicalKeyboardKey.semicolon);
      await pumpEventQueue();

      expect(operations, [OperationEvent.hisCallAndMyExchange]);
    });

    test('Ctrl / Cmd / Alt + 分号键被忽略', () async {
      for (final modifier in [
        (LogicalKeyboardKey.controlLeft, PhysicalKeyboardKey.controlLeft),
        (LogicalKeyboardKey.metaLeft, PhysicalKeyboardKey.metaLeft),
        (LogicalKeyboardKey.altLeft, PhysicalKeyboardKey.altLeft),
      ]) {
        final handler = KeyEventHandler();
        final operations = <OperationEvent>[];
        handler.operationEventStream.listen(operations.add);

        _holdModifier(modifier.$1, modifier.$2);
        _press(
          handler,
          LogicalKeyboardKey.semicolon,
          PhysicalKeyboardKey.semicolon,
        );
        await pumpEventQueue();

        expect(operations, isEmpty, reason: '${modifier.$1.debugName} + ;');
        HardwareKeyboard.instance.clearState();
      }
    });

    test('Shift + 回车不提交', () async {
      final handler = KeyEventHandler();
      final operations = <OperationEvent>[];
      handler.operationEventStream.listen(operations.add);

      _holdModifier(LogicalKeyboardKey.shiftLeft, PhysicalKeyboardKey.shiftLeft);
      _press(handler, LogicalKeyboardKey.enter, PhysicalKeyboardKey.enter);
      await pumpEventQueue();

      expect(operations, isEmpty);
    });
  });

  test('长按产生的 KeyRepeatEvent 不再派发', () async {
    final handler = KeyEventHandler();
    final operations = <OperationEvent>[];
    handler.operationEventStream.listen(operations.add);

    _press(handler, LogicalKeyboardKey.semicolon, PhysicalKeyboardKey.semicolon);
    handler.onKeyEvent(
      const KeyRepeatEvent(
        logicalKey: LogicalKeyboardKey.semicolon,
        physicalKey: PhysicalKeyboardKey.semicolon,
        timeStamp: Duration.zero,
      ),
    );
    await pumpEventQueue();

    expect(operations, [OperationEvent.hisCallAndMyExchange]);
  });

  test('失焦复位后功能键不会卡住', () async {
    final handler = KeyEventHandler();
    final operations = <OperationEvent>[];
    handler.operationEventStream.listen(operations.add);

    // 按住 F1：第二次 KeyDown 被抑制。
    _keyDown(handler, LogicalKeyboardKey.f1, PhysicalKeyboardKey.f1);
    _keyDown(handler, LogicalKeyboardKey.f1, PhysicalKeyboardKey.f1);
    await pumpEventQueue();
    expect(operations, [OperationEvent.cq]);

    // 窗口失焦时 KeyUp 可能被别的应用吃掉，复位后必须能再次触发。
    handler.resetPressedKeys();
    _keyDown(handler, LogicalKeyboardKey.f1, PhysicalKeyboardKey.f1);
    await pumpEventQueue();
    expect(operations, [OperationEvent.cq, OperationEvent.cq]);
  });
}

void _keyDown(
  KeyEventHandler handler,
  LogicalKeyboardKey logicalKey,
  PhysicalKeyboardKey physicalKey,
) {
  handler.onKeyEvent(
    KeyDownEvent(
      logicalKey: logicalKey,
      physicalKey: physicalKey,
      timeStamp: Duration.zero,
    ),
  );
}

void _press(
  KeyEventHandler handler,
  LogicalKeyboardKey logicalKey,
  PhysicalKeyboardKey physicalKey,
) {
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
}

/// Feeds the framework's own pressed state, which is what the handler reads to
/// tell a shortcut from a modifier combination.
void _holdModifier(LogicalKeyboardKey logicalKey, PhysicalKeyboardKey physicalKey) {
  HardwareKeyboard.instance.handleKeyEvent(
    KeyDownEvent(
      logicalKey: logicalKey,
      physicalKey: physicalKey,
      timeStamp: Duration.zero,
    ),
  );
}
