import 'app_logger.dart';

/// Numbered startup instrumentation.
///
/// Every step is logged before and after execution, so a startup failure can be
/// pinpointed to a single line even when the process dies early.
class BootTrace {
  int _sequence = 0;

  /// Runs [action] while recording a start/ok/fail record for [label].
  ///
  /// Failures are logged and rethrown so the caller can decide the fallback.
  Future<T> step<T>(
    String label,
    Future<T> Function() action, {
    Map<String, Object?> fields = const <String, Object?>{},
  }) async {
    final index = (++_sequence).toString().padLeft(2, '0');
    final stopwatch = Stopwatch()..start();

    log.info('BOOT $index $label start', tag: 'boot', fields: fields);

    try {
      final result = await action();
      log.info(
        'BOOT $index $label ok',
        tag: 'boot',
        fields: <String, Object?>{'durMs': stopwatch.elapsedMilliseconds},
      );
      return result;
    } catch (error, stackTrace) {
      log.error(
        'BOOT $index $label failed',
        tag: 'boot',
        fields: <String, Object?>{'durMs': stopwatch.elapsedMilliseconds},
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }
}

/// Shared boot trace used by the startup sequence.
final BootTrace boot = BootTrace();
