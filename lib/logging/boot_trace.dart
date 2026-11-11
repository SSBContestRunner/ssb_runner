import 'app_logger.dart';

/// Numbered startup instrumentation.
///
/// Every step is logged before and after execution, so a startup failure can be
/// pinpointed to a single line even when the process dies early.
class BootTrace {
  int _sequence = 0;

  /// Time since [start] was called, i.e. since the Dart entry point ran.
  final Stopwatch _sinceStart = Stopwatch()..start();

  DateTime? _startedAtUtc;
  DateTime? _firstFrameAtUtc;

  /// Current startup phase shared with the native watchdog heartbeat.
  ///
  /// One of `preFrame`, `booting`, `firstFrame`, `ready`.
  String phase = 'preFrame';

  /// Directory the Windows runner writes its native timeline to.
  ///
  /// Null when the runner did not pass `--boot-trace-dir`.
  String? nativeTraceDirectory;

  /// Touches the top-level [boot] instance so the stopwatch starts inside
  /// `main()` instead of on the first `boot.step` call.
  void start() {
    _startedAtUtc ??= DateTime.now().toUtc();
  }

  DateTime? get startedAtUtc => _startedAtUtc;

  DateTime? get firstFrameAtUtc => _firstFrameAtUtc;

  /// Number of the last started BOOT step, reported with the heartbeat.
  int get stepIndex => _sequence;

  int get elapsedMs => _sinceStart.elapsedMilliseconds;

  /// Time since the Dart entry point ran, measured on the same UTC clock as the
  /// native `entry_utc_ms`, so the two timelines can be reconciled.
  int? get sinceProcessMs => _startedAtUtc == null
      ? null
      : DateTime.now().toUtc().difference(_startedAtUtc!).inMilliseconds;

  void markFirstFrame() {
    _firstFrameAtUtc ??= DateTime.now().toUtc();
    phase = 'firstFrame';
  }

  /// Marks the end of the startup sequence; stops the native heartbeat.
  void markReady() {
    phase = 'ready';
  }

  /// Runs [action] while recording a start/ok/fail record for [label].
  ///
  /// Failures are logged and rethrown so the caller can decide the fallback.
  Future<T> step<T>(
    String label,
    Future<T> Function() action, {
    Map<String, Object?> fields = const <String, Object?>{},
  }) async {
    final index = (++_sequence).toString().padLeft(2, '0');
    phase = 'booting';
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
