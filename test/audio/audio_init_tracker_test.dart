import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/audio/audio_init_tracker.dart';

void main() {
  group('AudioInitTracker', () {
    test('is settled before start() was called', () async {
      final tracker = AudioInitTracker();

      expect(tracker.state, AudioInitState.neverStarted);
      await tracker.settled;
      expect(await tracker.settledWithin(Duration.zero), isTrue);
    });

    test('is not settled while the initialisation is running', () async {
      final tracker = AudioInitTracker();
      final initialise = Completer<void>();

      final started = tracker.start(() => initialise.future);

      expect(tracker.state, AudioInitState.running);
      expect(await tracker.settledWithin(Duration.zero), isFalse);

      initialise.complete();
      await started;

      expect(tracker.state, AudioInitState.completed);
      expect(await tracker.settledWithin(Duration.zero), isTrue);
    });

    test('settles after a failed initialisation and rethrows', () async {
      final tracker = AudioInitTracker();

      final started = tracker.start(() async => throw StateError('boom'));

      expect(tracker.state, AudioInitState.running);
      await expectLater(started, throwsStateError);
      expect(tracker.state, AudioInitState.failed);
      // A failed init is not a hang: the exit path must continue.
      expect(await tracker.settledWithin(Duration.zero), isTrue);
    });

    test(
      'reports a timeout when the initialisation outlives the budget',
      () async {
        final tracker = AudioInitTracker();
        final initialise = Completer<void>();
        unawaited(tracker.start(() => initialise.future));

        expect(
          await tracker.settledWithin(const Duration(milliseconds: 10)),
          isFalse,
        );

        initialise.complete();
        await tracker.settled;
        expect(tracker.state, AudioInitState.completed);
        expect(await tracker.settledWithin(Duration.zero), isTrue);
      },
    );
  });
}
