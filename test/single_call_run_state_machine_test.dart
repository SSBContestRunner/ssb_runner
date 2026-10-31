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

    test('抄错且差异超过阈值时回到重发，仍保留堆叠与音频', () {
      final machine = _machineInRepeatState(
        'B100IARU',
        submitCall: 'B10',
        pileupCallsigns: ['B100IARU', 'K1ABC', 'N0XYZ'],
      );

      final toState = machine.transition(SubmitCall(call: 'X9ZZZZ'));

      expect(toState, isA<WaitingSubmitCall>());
      final waiting = toState as WaitingSubmitCall;
      expect(waiting.pileupCallsigns, ['B100IARU', 'K1ABC', 'N0XYZ']);
      expect(waiting.audioPlayType, isNot(isA<NoPlay>()));
      expect(waiting.audioPlayType, isA<PlayPileup>());
    });
  });

  group('WaitingSubmitCall 抄错呼号', () {
    test('差异超过阈值时回到重发，不再静音', () {
      final machine = _machineInWaitingSubmitCall(pileupCallsigns: _pileup);

      final toState = machine.transition(SubmitCall(call: 'X9ZZZZ'));

      expect(toState, isA<WaitingSubmitCall>());
      final waiting = toState as WaitingSubmitCall;
      expect(waiting.pileupCallsigns, _pileup);
      expect(waiting.audioPlayType, isA<PlayPileup>());
    });

    test('重试重建默认音频，能从静音状态恢复', () {
      // 模拟历史遗留的坏状态：本轮音频已被 NoPlay 覆盖。
      final machine = _machineInWaitingSubmitCall(
        pileupCallsigns: _pileup,
        audioPlayType: NoPlay(),
      );

      final toState = machine.transition(Retry());

      expect(toState, isA<WaitingSubmitCall>());
      expect((toState as WaitingSubmitCall).audioPlayType, isA<PlayPileup>());
    });

    test('只有一台时重试重放该台呼号', () {
      final machine = _machineInWaitingSubmitCall();

      final toState = machine.transition(Retry());

      expect(toState, isA<WaitingSubmitCall>());
      final waiting = toState as WaitingSubmitCall;
      expect(waiting.audioPlayType, isA<PlayCall>());
      expect((waiting.audioPlayType as PlayCall).callToPlay, 'B100IARU');
    });
  });

  group('ReportMyExchange 收到 CallsignInvalid', () {
    test('回到可重听的等待提交状态，重试仍有音频', () {
      final machine = _machineInReportMyExchange();

      final toState = machine.transition(CallsignInvalid());

      expect(toState, isA<WaitingSubmitCall>());
      expect((toState as WaitingSubmitCall).audioPlayType, isA<PlayCall>());

      final retried = machine.transition(Retry());

      expect(retried, isA<WaitingSubmitCall>());
      expect((retried as WaitingSubmitCall).audioPlayType, isA<PlayCall>());
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

    test('收到 Retry 原地重播他的序号', () {
      final machine = initSingleCallRunStateMachine(
        initialState: WaitingSubmitMyExchange(
          currentCallAnswer: 'B100IARU',
          currentExchangeAnswer: '59 001',
          submitCall: 'B100IARU',
          audioPlayType: PlayExchange(exchange: '59 001', isMe: false),
          isOperateInput: false,
        ),
        transitionListener: (_) {},
      );

      final toState = machine.transition(Retry());

      expect(toState, isA<WaitingSubmitMyExchange>());
      final waiting = toState as WaitingSubmitMyExchange;
      expect(waiting.audioPlayType, isA<PlayExchange>());
      expect((waiting.audioPlayType as PlayExchange).isMe, isFalse);
    });
  });

  group('在途 QSO 放弃本轮', () {
    test('HeAskForExchange 收到 Retry 仍原地重播我的呼号', () {
      final machine = _machineInHeAskForExchange();

      final toState = machine.transition(Retry());

      expect(toState, isA<HeAskForExchange>());
      expect((toState as HeAskForExchange).isPlayMyCall, isTrue);
    });

    test('HeAskForExchange 收到 AbandonQso：换新题并回到等待提交呼号', () {
      final machine = _machineInHeAskForExchange();

      final toState = machine.transition(
        AbandonQso(
          nextCallAnswer: 'C3CCC',
          nextExchangeAnswer: '59 002',
          pileupCallsigns: const ['C3CCC'],
        ),
      );

      expect(toState, isA<WaitingSubmitCall>());
      final waiting = toState as WaitingSubmitCall;
      expect(waiting.currentCallAnswer, 'C3CCC');
      expect(waiting.currentExchangeAnswer, '59 002');
      expect(waiting.audioPlayType, isA<PlayCall>());
    });

    test('HeAskForExchange 收到 SubmitHisExchange：进入发送我的序号阶段', () {
      final machine = _machineInHeAskForExchange(submitCall: 'B10');

      final toState = machine.transition(SubmitHisExchange(exchange: '59 001'));

      expect(toState, isA<WaitingSubmitMyExchange>());
      expect((toState as WaitingSubmitMyExchange).submitCall, 'B10');
    });

    test('WaitingSubmitMyExchange 收到 AbandonQso：换新题', () {
      final machine = _machineInSubmitExchangeState(submitCall: 'B100IARU');

      final toState = machine.transition(
        AbandonQso(nextCallAnswer: 'C3CCC', nextExchangeAnswer: '59 002'),
      );

      expect(toState, isA<WaitingSubmitCall>());
      expect((toState as WaitingSubmitCall).currentCallAnswer, 'C3CCC');
    });

    test('HeRepeatCorrectCallAnswer 收到 AbandonQso：换新题', () {
      final machine = _machineInRepeatState('B100IARU', submitCall: 'B10');

      final toState = machine.transition(
        AbandonQso(nextCallAnswer: 'C3CCC', nextExchangeAnswer: '59 002'),
      );

      expect(toState, isA<WaitingSubmitCall>());
      expect((toState as WaitingSubmitCall).currentCallAnswer, 'C3CCC');
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

const _pileup = ['B100IARU', 'K1ABC', 'N0XYZ'];

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
_machineInRepeatState(
  String answer, {
  required String submitCall,
  List<String> pileupCallsigns = const [],
}) {
  return initSingleCallRunStateMachine(
    initialState: HeRepeatCorrectCallAnswer(
      currentCallAnswer: answer,
      currentExchangeAnswer: '59 001',
      submitCall: submitCall,
      pileupCallsigns: pileupCallsigns,
    ),
    transitionListener: (_) {},
  );
}

StateMachine<SingleCallRunState, SingleCallRunEvent, Null>
_machineInWaitingSubmitCall({
  List<String> pileupCallsigns = const [],
  AudioPlayType? audioPlayType,
}) {
  return initSingleCallRunStateMachine(
    initialState: WaitingSubmitCall(
      currentCallAnswer: 'B100IARU',
      currentExchangeAnswer: '59 001',
      pileupCallsigns: pileupCallsigns,
      audioPlayType: audioPlayType,
    ),
    transitionListener: (_) {},
  );
}

StateMachine<SingleCallRunState, SingleCallRunEvent, Null>
_machineInReportMyExchange() {
  return initSingleCallRunStateMachine(
    initialState: ReportMyExchange(
      currentCallAnswer: 'B100IARU',
      currentExchangeAnswer: '59 001',
      submitCall: 'B10',
      myExchange: '59 001',
      audioPlayType: NoPlay(),
      isOperateInput: true,
    ),
    transitionListener: (_) {},
  );
}

StateMachine<SingleCallRunState, SingleCallRunEvent, Null>
_machineInHeAskForExchange({
  String submitCall = 'B100IARU',
  bool isPlayMyCall = false,
}) {
  return initSingleCallRunStateMachine(
    initialState: HeAskForExchange(
      currentCallAnswer: 'B100IARU',
      currentExchangeAnswer: '59 001',
      submitCall: submitCall,
      isPlayMyCall: isPlayMyCall,
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
