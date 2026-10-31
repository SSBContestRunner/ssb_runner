import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/callsign/callsign_loader.dart';
import 'package:ssb_runner/contest_run/new/contest_answer_generator.dart';
import 'package:ssb_runner/contest_type/contest_type.dart';
import 'package:ssb_runner/contest_type/exchange_manager.dart';
import 'package:ssb_runner/contest_type/score_calculator.dart';
import 'package:ssb_runner/training/replay_answer_source.dart';
import 'package:ssb_runner/training/session_random.dart';
import 'package:ssb_runner/training/session_review.dart';
import 'package:ssb_runner/training/training_profile.dart';

void main() {
  test('the same question seed reproduces the whole question sequence', () {
    final first = _generate(_loader(), 4242);
    final second = _generate(_loader(), 4242);

    expect(first.length, second.length);
    for (var index = 0; index < first.length; index++) {
      expect(first[index].callSign, second[index].callSign);
      expect(first[index].exchange, second[index].exchange);
      expect(first[index].pileupCallsigns, second[index].pileupCallsigns);
    }
  });

  test('changing the audio seed leaves the question sequence untouched', () {
    final profileA = AudioTrainingEffects(
      const AudioTrainingProfile(
        difficulty: TrainingDifficulty.standard,
        volume: 1,
        questionSeed: 3,
        audioSeed: 3,
      ),
    ).apply(_pcm());
    final profileB = AudioTrainingEffects(
      const AudioTrainingProfile(
        difficulty: TrainingDifficulty.standard,
        volume: 1,
        questionSeed: 3,
        audioSeed: 999,
      ),
    ).apply(_pcm());

    expect(profileA, isNot(equals(profileB)));
  });

  test('recorded answers replay in order without recomputation', () {
    final events = <TrainingRunEvent>[
      const TrainingRunEvent(
        elapsedMs: 0,
        type: 'answer',
        callsign: 'A1AAA',
        exchange: '12',
        pileupCallsigns: ['A1AAA', 'B2BBB'],
        modeId: 'pileup',
      ),
      const TrainingRunEvent(
        elapsedMs: 1000,
        type: 'answer',
        callsign: 'C3CCC',
        exchange: '7',
        pileupCallsigns: ['C3CCC'],
        modeId: 'search-and-pounce',
      ),
    ];

    final source = ReplayAnswerSource.fromEvents(events);

    final first = source.generateAnswer();
    expect(first.callSign, 'A1AAA');
    expect(first.exchange, '12');
    expect(first.pileupCallsigns, ['A1AAA', 'B2BBB']);
    expect(first.mode, TrainingMode.pileup);

    final second = source.generateAnswer();
    expect(second.callSign, 'C3CCC');
    expect(second.isSearchAndPounce, isTrue);
  });

  test('recording source captures every served answer', () {
    final loader = _loader();
    final served = <String>[];
    final source = RecordingAnswerSource(
      _generator(loader, 11),
      (answer) => served.add(answer.callSign),
    );

    final generated = [
      for (var index = 0; index < 5; index++) source.generateAnswer(),
    ];

    expect(served, generated.map((answer) => answer.callSign).toList());
  });

  test('replay ends at the recording boundary without restarting the seed', () {
    final first = _generator(_loader(), 42).generateAnswer();
    final replay = ReplayAnswerSource([first]);
    expect(replay.generateAnswer(), same(first));
    expect(replay.isExhausted, isTrue);
    for (var i = 0; i < 2; i++) {
      expect(
        replay.generateAnswer,
        throwsA(
          isA<AnswerSourceExhausted>().having(
            (end) => end.reason,
            'reason',
            'replay_completed',
          ),
        ),
      );
    }
  });

  test('historical duplicate answers remain exact during replay', () {
    final first = _generator(_loader(), 42).generateAnswer();
    final replay = ReplayAnswerSource([first, first]);
    expect(replay.generateAnswer(), same(first));
    expect(replay.generateAnswer(), same(first));
    expect(replay.generateAnswer, throwsA(isA<AnswerSourceExhausted>()));
  });

  for (final mode in TrainingMode.values) {
    test('${mode.id} draws normalized targets without replacement', () {
      final loader = CallsignLoader()
        ..callSigns.addAll(['4X6ZM', ' 4x6zm ', '', 'K1ABC', 'JA1XYZ']);
      final source = ContestAnswerGenerator(
        callsignLoader: loader,
        contestType: _contestType(),
        mode: mode,
        difficulty: TrainingDifficulty.advanced,
        random: SessionRandom(42),
      );
      final seen = <String>{};
      for (var i = 0; i < 3; i++) {
        final answer = source.generateAnswer();
        expect(seen.intersection(answer.pileupCallsigns.toSet()), isEmpty);
        expect(
          answer.pileupCallsigns.toSet().length,
          answer.pileupCallsigns.length,
        );
        expect(seen.add(answer.callSign), isTrue);
      }
      expect(seen, {'4X6ZM', 'K1ABC', 'JA1XYZ'});
      expect(source.generateAnswer, throwsA(isA<AnswerSourceExhausted>()));
    });
  }

  test('small and empty callsign pools terminate instead of looping', () {
    for (final calls in <List<String>>[
      [],
      ['ONLY1'],
      ['ONLY1', 'ONLY2'],
    ]) {
      final source = _generator(CallsignLoader()..callSigns.addAll(calls), 1);
      for (var i = 0; i < calls.length; i++) {
        expect(
          source.generateAnswer().pileupCallsigns.length,
          calls.length - i,
        );
      }
      expect(source.generateAnswer, throwsA(isA<AnswerSourceExhausted>()));
    }
  });

  group('F1 归还被放弃的台', () {
    test('池非空时旧目标留在 PILE-UP 中但不是主音', () {
      final source = _generator(_loader(), 7);
      final abandoned = source.generateAnswer();

      final next = source.generateAnswer(requeueCallsign: abandoned.callSign);

      expect(next.callSign, isNot(abandoned.callSign));
      expect(next.pileupCallsigns.first, next.callSign);
      expect(
        next.pileupCallsigns.indexOf(abandoned.callSign),
        greaterThanOrEqualTo(1),
      );
      expect(next.pileupCallsigns.toSet().length, next.pileupCallsigns.length);
    });

    test('归还后可在后续轮次重新成为主目标', () {
      final source = _generator(
        CallsignLoader()..callSigns.addAll(['ONLY1', 'ONLY2']),
        7,
      );
      final abandoned = source.generateAnswer();

      final second = source.generateAnswer(requeueCallsign: abandoned.callSign);
      expect(second.callSign, 'ONLY2');
      expect(second.pileupCallsigns, ['ONLY2', 'ONLY1']);

      // The pool now holds only the requeued station again.
      final third = source.generateAnswer();
      expect(third.callSign, 'ONLY1');
      expect(source.generateAnswer, throwsA(isA<AnswerSourceExhausted>()));
    });

    test('池耗尽时归还者降级为主音，而不是结束序列', () {
      final source = _generator(CallsignLoader()..callSigns.add('ONLY1'), 7);
      final abandoned = source.generateAnswer();

      final next = source.generateAnswer(requeueCallsign: abandoned.callSign);

      expect(next.callSign, 'ONLY1');
      expect(next.pileupCallsigns, ['ONLY1']);
      // Without a requeue the pool is still exhausted.
      expect(source.generateAnswer, throwsA(isA<AnswerSourceExhausted>()));
    });

    test('Run 模式下归还只回池，不进入本轮混音列表', () {
      final source = ContestAnswerGenerator(
        callsignLoader: _loader(),
        contestType: _contestType(),
        mode: TrainingMode.run,
        difficulty: TrainingDifficulty.advanced,
        random: SessionRandom(7),
      );
      final abandoned = source.generateAnswer();

      final next = source.generateAnswer(requeueCallsign: abandoned.callSign);
      expect(next.callSign, isNot(abandoned.callSign));
      expect(next.pileupCallsigns, [next.callSign]);

      final later = [
        for (var i = 0; i < 4; i++) source.generateAnswer().callSign,
      ];
      expect(later, contains(abandoned.callSign));
      expect(later.toSet(), hasLength(4));
      expect(source.generateAnswer, throwsA(isA<AnswerSourceExhausted>()));
    });

    test('连续放弃：每次只归还当前目标，列表无重复', () {
      final source = _generator(_loader(), 7);
      final first = source.generateAnswer();
      final second = source.generateAnswer(requeueCallsign: first.callSign);

      final third = source.generateAnswer(requeueCallsign: second.callSign);

      expect(third.callSign, isNot(second.callSign));
      expect(third.pileupCallsigns.first, third.callSign);
      expect(third.pileupCallsigns.skip(1), contains(second.callSign));
      expect(
        third.pileupCallsigns.toSet().length,
        third.pileupCallsigns.length,
      );
    });

    test('归还呼号先归一化再比较与回池', () {
      final source = _generator(_loader(), 7);
      final abandoned = source.generateAnswer();

      final next = source.generateAnswer(
        requeueCallsign: ' ${abandoned.callSign.toLowerCase()} ',
      );

      expect(next.pileupCallsigns.skip(1), contains(abandoned.callSign));
    });

    test('回放忽略归还参数，按录制内容原样播放', () {
      final recorded = ContestAnswer(
        callSign: 'A1AAA',
        exchange: '12',
        pileupCallsigns: const ['A1AAA', 'B2BBB'],
        mode: TrainingMode.pileup,
      );
      final source = ReplayAnswerSource([recorded]);

      final served = source.generateAnswer(requeueCallsign: 'ZZ9ZZZ');

      expect(served.callSign, 'A1AAA');
      expect(served.pileupCallsigns, ['A1AAA', 'B2BBB']);
    });
  });

  test('legacy review json without dual seeds still decodes', () {
    final legacy = jsonEncode({
      'runId': 'run-1',
      'contestId': 'CQ-WPX',
      'contestName': 'CQ WPX SSB',
      'modeId': 'run',
      'difficultyId': 'standard',
      'seed': 7,
      'startedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
      'endedAt': DateTime.utc(2026, 1, 1, 1).toIso8601String(),
      'qsoCount': 3,
      'correctCount': 2,
      'callsignErrors': 1,
      'exchangeErrors': 0,
      'score': 10,
    });

    final review = TrainingRunReview.decode(legacy);
    expect(review.metadata.questionSeed, 7);
    expect(review.metadata.audioSeed, 7);
    expect(review.metadata.appVersion, '');
    expect(review.accuracy, closeTo(2 / 3, 0.0001));
  });
}

CallsignLoader _loader() =>
    CallsignLoader()
      ..callSigns.addAll(const ['A1AAA', 'B2BBB', 'C3CCC', 'D4DDD', 'E5EEE']);

_FixedContestType _contestType() => _FixedContestType();

ContestAnswerGenerator _generator(CallsignLoader loader, int seed) =>
    ContestAnswerGenerator(
      callsignLoader: loader,
      contestType: _contestType(),
      mode: TrainingMode.pileup,
      difficulty: TrainingDifficulty.advanced,
      random: SessionRandom(seed),
    );

List<ContestAnswer> _generate(CallsignLoader loader, int seed) {
  final generator = _generator(loader, seed);
  return [
    for (var index = 0; index < loader.callSigns.length; index++)
      generator.generateAnswer(),
  ];
}

Uint8List _pcm() {
  final bytes = Uint8List(60 * 2);
  final data = ByteData.sublistView(bytes);
  for (var index = 0; index < 60; index++) {
    data.setInt16(index * 2, (index * 300) - 9000, Endian.little);
  }
  return bytes;
}

class _FixedExchangeManager implements ExchangeManager {
  @override
  String generateExchange(
    SessionRandom random, {
    required String callerCallsign,
  }) => random.nextExchange(3000).toString();

  @override
  String processExchange(String exchange) => exchange;
}

class _FixedContestType implements ContestType {
  final _exchange = _FixedExchangeManager();

  @override
  RegExp get allowExchangeRegex => RegExp('[0-9]');

  @override
  ExchangeManager get exchangeManager => _exchange;

  @override
  ScoreCalculator get scoreCalculator => throw UnimplementedError();

  @override
  String buildMyExchange(int qsoNumber) => qsoNumber.toString();

  @override
  String formatExchangeForAudio(String exchange) => exchange;
}
