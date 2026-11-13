typedef AsyncAction = Future<void> Function();

typedef ExitCleanupErrorHandler = void Function(
  String step,
  Object error,
  StackTrace stackTrace,
);

/// Runs one exit step with a hard time bound.
///
/// Returns `true` when [action] completed before [timeout] without throwing.
/// The future never completes with an error, so the caller can always decide
/// what to do next instead of leaving the process behind.
Future<bool> runBoundedExitStep({
  required String step,
  required AsyncAction action,
  Duration timeout = const Duration(seconds: 2),
  ExitCleanupErrorHandler? onError,
}) async {
  try {
    await action().timeout(timeout);
    return true;
  } catch (error, stackTrace) {
    onError?.call(step, error, stackTrace);
    return false;
  }
}

/// Runs the desktop exit cleanup with a hard time bound per step.
///
/// Each step either completes, times out, or fails; a failure is reported
/// through [onError] and never stops the steps that follow.
///
/// Returns `true` when the audio deinit completed. A `false` answer means the
/// native engine may still be tearing down, so the caller must not answer the
/// platform's exit request: `ExitProcess` would run the plugin's DLL detach
/// while that teardown is still in flight.
Future<bool> runBoundedExitCleanup({
  required AsyncAction deinitAudio,
  required AsyncAction flushLogs,
  Duration deinitTimeout = const Duration(seconds: 2),
  Duration flushTimeout = const Duration(milliseconds: 1500),
  ExitCleanupErrorHandler? onError,
}) async {
  final disposed = await runBoundedExitStep(
    step: 'audio deinit',
    action: deinitAudio,
    timeout: deinitTimeout,
    onError: onError,
  );

  await runBoundedExitStep(
    step: 'log flush',
    action: flushLogs,
    timeout: flushTimeout,
    onError: onError,
  );

  return disposed;
}
