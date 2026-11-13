import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/ui/main_app/exit_flow.dart';

const Duration _shortTimeout = Duration(milliseconds: 50);

void main() {
  group('runBoundedExitCleanup', () {
    test('runs the audio deinit before the log flush', () async {
      final steps = <String>[];

      final disposed = await runBoundedExitCleanup(
        deinitAudio: () async => steps.add('audio'),
        flushLogs: () async => steps.add('logs'),
      );

      expect(steps, <String>['audio', 'logs']);
      expect(disposed, isTrue);
    });

    test('reports an unfinished deinit when the audio deinit hangs', () async {
      final steps = <String>[];

      final disposed = await runBoundedExitCleanup(
        deinitAudio: () async {
          steps.add('audio');
          await Completer<void>().future;
        },
        flushLogs: () async => steps.add('logs'),
        deinitTimeout: _shortTimeout,
        flushTimeout: _shortTimeout,
        onError: (step, error, stackTrace) => steps.add('error:$step'),
      );

      expect(steps, <String>['audio', 'error:audio deinit', 'logs']);
      // The exit path must not answer the request in this case.
      expect(disposed, isFalse);
    });

    test('returns when the log flush hangs', () async {
      final steps = <String>[];

      await runBoundedExitCleanup(
        deinitAudio: () async => steps.add('audio'),
        flushLogs: () async {
          steps.add('logs');
          await Completer<void>().future;
        },
        deinitTimeout: _shortTimeout,
        flushTimeout: _shortTimeout,
        onError: (step, error, stackTrace) => steps.add('error:$step'),
      );

      expect(steps, <String>['audio', 'logs', 'error:log flush']);
    });

    test('reports a failing step and still runs the next one', () async {
      final steps = <String>[];

      final disposed = await runBoundedExitCleanup(
        deinitAudio: () async => throw StateError('boom'),
        flushLogs: () async => steps.add('logs'),
        deinitTimeout: _shortTimeout,
        flushTimeout: _shortTimeout,
        onError: (step, error, stackTrace) => steps.add('error:$step'),
      );

      expect(steps, <String>['error:audio deinit', 'logs']);
      // A failed init still created the native player, so its teardown did not
      // complete either.
      expect(disposed, isFalse);
    });
  });

  group('runBoundedExitStep', () {
    test('returns true when the action completes in time', () async {
      expect(
        await runBoundedExitStep(
          step: 'log flush',
          action: () async {},
          timeout: _shortTimeout,
        ),
        isTrue,
      );
    });

    test('returns false and reports the step when the action hangs', () async {
      final errors = <String>[];

      final completed = await runBoundedExitStep(
        step: 'log flush',
        action: () => Completer<void>().future,
        timeout: _shortTimeout,
        onError: (step, error, stackTrace) => errors.add(step),
      );

      expect(completed, isFalse);
      expect(errors, <String>['log flush']);
    });
  });
}
