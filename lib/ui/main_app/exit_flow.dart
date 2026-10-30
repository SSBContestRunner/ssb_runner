typedef AsyncAction = Future<void> Function();

typedef ExitCleanupErrorHandler =
    void Function(String step, Object error, StackTrace stackTrace);

/// Runs the desktop exit cleanup with a hard time bound per step.
///
/// Each step either completes, times out, or fails; a failure is reported
/// through [onError] and never stops the steps that follow. The function
/// therefore never throws, so the caller can always answer the platform's
/// exit request instead of leaving the process behind.
Future<void> runBoundedExitCleanup({
  required AsyncAction deinitAudio,
  required AsyncAction flushLogs,
  Duration deinitTimeout = const Duration(seconds: 2),
  Duration flushTimeout = const Duration(milliseconds: 1500),
  ExitCleanupErrorHandler? onError,
}) async {
  Future<void> run(String step, AsyncAction action, Duration timeout) async {
    try {
      await action().timeout(timeout);
    } catch (error, stackTrace) {
      onError?.call(step, error, stackTrace);
    }
  }

  await run('audio deinit', deinitAudio, deinitTimeout);
  await run('log flush', flushLogs, flushTimeout);
}
