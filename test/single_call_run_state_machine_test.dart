import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/contest_run/state_machine/single_call/single_call_run_event.dart';
import 'package:ssb_runner/contest_run/state_machine/single_call/single_call_run_state.dart';
import 'package:ssb_runner/contest_run/state_machine/single_call/single_call_run_state_machine.dart';
import 'package:ssb_runner/state_machine/state_machine.dart';

void main() {
  group('HeRepeatCorrectCallAnswer 收到 SubmitCall', () {
    test('只抄到对方呼号前缀时，继续重放呼号', () {
      // 2 字母 -> 删到 1 字母，仍然满足 startsWith，对方应再次重放。
      final machine = _machineInRepeatState('B100IARU', submitCall: 'B10');

      final toState = machine.transition(SubmitCall(call: 'B'));

      expect(toState, isA<HeRepeatCorrectCallAnswer>());
    });

    test('抄全呼号后进入索要交换信息阶段', () {
      final machine = _machineInRepeatState('B100IARU', submitCall: 'B10');

      final toState = machine.transition(SubmitCall(call: 'B100IARU'));

      expect(toState, isA<HeAskForExchange>());
    });

    test('抄错且差异超过阈值时不再重放', () {
      final machine = _machineInRepeatState('B100IARU', submitCall: 'B10');

      final toState = machine.transition(SubmitCall(call: 'X9ZZZZ'));

      expect(toState, isA<WaitingSubmitCall>());
    });
  });
}

StateMachine<SingleCallRunState, SingleCallRunEvent, Null> _machineInRepeatState(
  String answer, {
  required String submitCall,
}) {
  return initSingleCallRunStateMachine(
    initialState: HeRepeatCorrectCallAnswer(
      currentCallAnswer: answer,
      currentExchangeAnswer: '59 001',
      submitCall: submitCall,
    ),
    transitionListener: (_) {},
  );
}