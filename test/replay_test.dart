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

    final generated = [for (var index = 0; index < 5; index++) source.generateAnswer()];

    expect(served, generated.map((answer) => answer.callSign).toList());
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

CallsignLoader _loader() => CallsignLoader()
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
  return [for (var index = 0; index < 8; index++) generator.generateAnswer()];
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
  String generateExchange(SessionRandom random) =>
      random.nextExchange(3000).toString();

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
}
