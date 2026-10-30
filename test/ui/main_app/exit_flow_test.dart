import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/ui/main_app/exit_flow.dart';

const Duration _shortTimeout = Duration(milliseconds: 50);

void main() {
  group('runBoundedExitCleanup', () {
    test('runs the audio deinit before the log flush', () async {
      final steps = <String>[];

      await runBoundedExitCleanup(
        deinitAudio: () async => steps.add('audio'),
        flushLogs: () async => steps.add('logs'),
      );

      expect(steps, <String>['audio', 'logs']);
    });

    test('moves on to the log flush when the audio deinit hangs', () async {
      final steps = <String>[];

      await runBoundedExitCleanup(
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

      await runBoundedExitCleanup(
        deinitAudio: () async => throw StateError('boom'),
        flushLogs: () async => steps.add('logs'),
        deinitTimeout: _shortTimeout,
        flushTimeout: _shortTimeout,
        onError: (step, error, stackTrace) => steps.add('error:$step'),
      );

      expect(steps, <String>['error:audio deinit', 'logs']);
    });
  });
}
