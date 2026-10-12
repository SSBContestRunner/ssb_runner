// `Retry` also exists in test_api; hide it so the state machine's event wins.
import 'package:flutter_test/flutter_test.dart' hide Retry;
import 'package:ssb_runner/contest_run/state_machine/single_call/audio_play_type.dart';
import 'package:ssb_runner/contest_run/state_machine/single_call/search_and_pounce_run_state_machine.dart';
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

  group('WaitingSubmitMyExchange 录入序号阶段提交', () {
    test('在录入序号阶段更正呼号时，签字前带上更正后的呼号', () {
      // 先前发错呼号（B10）给了信号报告，进入录入序号阶段后才改成正确呼号。
      final machine = _machineInSubmitExchangeState(submitCall: 'B10');

      final toState = machine.transition(
        SubmitMyExchange(exchange: '59 001', call: 'B100IARU'),
      );

      expect(toState, isA<QsoEnd>());
      expect((toState as QsoEnd).correctedCall, 'B100IARU');
    });

    test('呼号未改动时不朗读更正呼号', () {
      final machine = _machineInSubmitExchangeState(submitCall: 'B100IARU');

      final toState = machine.transition(
        SubmitMyExchange(exchange: '59 001', call: 'B100IARU'),
      );

      expect(toState, isA<QsoEnd>());
      expect((toState as QsoEnd).correctedCall, isNull);
    });
  });

  group('S&P 状态机', () {
    test('第 1 次回车发送本台呼号并等待对方回应', () {
      final machine = _spMachine();

      final toState = machine.transition(SpPounce());

      expect(toState, isA<SpWaitingHisExchange>());
      expect((toState as SpWaitingHisExchange).currentCallAnswer, 'A1AAA');
    });

    test('第 2 次回车直接落库，不存在第三个等待确认的状态', () {
      final machine = _spMachine();
      machine.transition(SpPounce());

      final toState = machine.transition(
        SpSubmitHisExchange(exchange: '007', myExchange: '001'),
      );

      expect(toState, isA<SpQsoEnd>());
      final qsoEnd = toState as SpQsoEnd;
      expect(qsoEnd.currentExchangeAnswer, '007');
      expect(qsoEnd.myExchange, '001');
    });

    test('对方 TU 播完后自动回到下一台 CQ', () {
      final machine = _spMachine();
      machine.transition(SpPounce());
      machine.transition(
        SpSubmitHisExchange(exchange: '007', myExchange: '001'),
      );

      final next = machine.transition(
        NextCall(callAnswer: 'B2BBB', exchangeAnswer: '002'),
      );

      expect(next, isA<SpListeningCq>());
      expect((next as SpListeningCq).currentCallAnswer, 'B2BBB');
    });

    test('未抄到序号时回车重听，不进入签字', () {
      final machine = _spMachine();
      machine.transition(SpPounce());

      final toState = machine.transition(Retry());

      expect(toState, isA<SpWaitingHisExchange>());
    });
  });
}

StateMachine<SingleCallRunState, SingleCallRunEvent, Null> _spMachine() {
  return initSearchAndPounceRunStateMachine(
    initialState: SpListeningCq(
      currentCallAnswer: 'A1AAA',
      currentExchangeAnswer: '007',
    ),
    transitionListener: (_) {},
  );
}

StateMachine<SingleCallRunState, SingleCallRunEvent, Null>
_machineInRepeatState(String answer, {required String submitCall}) {
  return initSingleCallRunStateMachine(
    initialState: HeRepeatCorrectCallAnswer(
      currentCallAnswer: answer,
      currentExchangeAnswer: '59 001',
      submitCall: submitCall,
    ),
    transitionListener: (_) {},
  );
}

StateMachine<SingleCallRunState, SingleCallRunEvent, Null>
_machineInSubmitExchangeState({required String submitCall}) {
  return initSingleCallRunStateMachine(
    initialState: WaitingSubmitMyExchange(
      currentCallAnswer: 'B100IARU',
      currentExchangeAnswer: '59 001',
      submitCall: submitCall,
      audioPlayType: NoPlay(),
      isOperateInput: true,
    ),
    transitionListener: (_) {},
  );
}
