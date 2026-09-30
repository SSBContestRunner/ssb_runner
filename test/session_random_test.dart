import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/training/session_random.dart';

void main() {
  test('the same seed produces identical draws', () {
    final first = SessionRandom(1234);
    final second = SessionRandom(1234);

    for (var index = 0; index < 100; index++) {
      expect(first.nextCallsignIndex(1000), second.nextCallsignIndex(1000));
      expect(first.nextExchange(3000), second.nextExchange(3000));
      expect(first.nextPhonicType(3), second.nextPhonicType(3));
      expect(first.nextAudioUnit(), second.nextAudioUnit());
    }
  });

  test('different seeds diverge', () {
    final first = SessionRandom(1);
    final second = SessionRandom(2);

    final firstDraws = List.generate(50, (_) => first.nextCallsignIndex(1000));
    final secondDraws = List.generate(50, (_) => second.nextCallsignIndex(1000));

    expect(firstDraws, isNot(equals(secondDraws)));
  });

  test('audio draws do not shift the question sequence', () {
    final baseline = SessionRandom(99);
    final disturbed = SessionRandom(99);

    for (var index = 0; index < 10; index++) {
      disturbed.nextAudioUnit();
    }

    for (var index = 0; index < 100; index++) {
      expect(
        disturbed.nextCallsignIndex(1000),
        baseline.nextCallsignIndex(1000),
      );
    }
  });

  test('question draws do not shift the audio sequence', () {
    final baseline = SessionRandom(7);
    final disturbed = SessionRandom(7);

    for (var index = 0; index < 10; index++) {
      disturbed.nextCallsignIndex(50);
      disturbed.nextExchange(50);
      disturbed.nextPhonicType(3);
    }

    for (var index = 0; index < 100; index++) {
      expect(disturbed.nextAudioUnit(), baseline.nextAudioUnit());
    }
  });
}
