import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

import 'app_log_printer.dart';
import 'log_paths.dart';

/// Tag used when no subsystem is given.
const String defaultTag = 'app';

const int _contextBufferSize = 200;
const int _maxLogFileSizeKb = 5 * 1024;
const int _maxRotatedFileCount = 10;
const String _latestLogFileName = 'latest.log';

final Level _defaultLevel = kReleaseMode ? Level.info : Level.debug;

AppLogger? _current;

/// Global logging entry point.
///
/// Safe to call at any time: before [installLogger] it lazily falls back to a
/// console-only logger so early startup failures are never lost.
AppLogger get log => _current ??= AppLogger.consoleOnly();

/// Installs the process-wide logger.
void installLogger(AppLogger appLogger) => _current = appLogger;

bool _suppressPrintCapture = false;

/// Zone hook that routes `print` output into the log stream.
///
/// A Windows release build runs as a GUI process with no console, so anything a
/// plugin writes through `print` would otherwise be discarded.
ZoneSpecification appZoneSpecification() {
  return ZoneSpecification(
    print: (self, parent, zone, line) {
      if (_suppressPrintCapture) {
        // Output produced by the logging pipeline itself: send it straight to
        // the real stdout to avoid an infinite loop.
        parent.print(zone, line);
        return;
      }

      _suppressPrintCapture = true;
      try {
        log.debug(line, tag: 'stdout');
      } finally {
        _suppressPrintCapture = false;
      }
    },
  );
}

/// Application logging facade.
///
/// Wraps `package:logger` with tag/field support, path redaction and a
/// context dump that is written into the log file whenever an error is
/// recorded.
class AppLogger {
  AppLogger._(
    this._primary,
    this._console,
    this._filters,
    this._ring,
    this._file,
  );

  /// Console-only logger used before the file sink is available.
  factory AppLogger.consoleOnly() {
    final filter = ProductionFilter()..level = _defaultLevel;
    final logger = Logger(
      filter: filter,
      output: ConsoleOutput(),
      printer: PrettyPrinter(methodCount: 5),
    );

    return AppLogger._(logger, null, <LogFilter>[filter], null, null);
  }

  /// Logger backed by a rotating file sink and an in-memory context buffer.
  factory AppLogger.fileBacked({
    required String directory,
    required String header,
  }) {
    final primaryFilter = ProductionFilter()..level = _defaultLevel;
    final ring = MemoryOutput(bufferSize: _contextBufferSize);
    final file = AdvancedFileOutput(
      path: directory,
      maxFileSizeKB: _maxLogFileSizeKb,
      maxRotatedFilesCount: _maxRotatedFileCount,
      latestFileName: _latestLogFileName,
      fileHeader: header,
    );

    final primary = Logger(
      filter: primaryFilter,
      output: MultiOutput(<LogOutput>[file, ring]),
      printer: AppLogPrinter(),
    );

    final filters = <LogFilter>[primaryFilter];
    Logger? console;
    if (!kReleaseMode) {
      final consoleFilter = ProductionFilter()..level = _defaultLevel;
      filters.add(consoleFilter);
      console = Logger(
        filter: consoleFilter,
        output: ConsoleOutput(),
        printer: PrettyPrinter(methodCount: 5),
      );
    }

    return AppLogger._(primary, console, filters, ring, file);
  }

  final Logger _primary;
  final Logger? _console;
  final List<LogFilter> _filters;
  final MemoryOutput? _ring;
  final AdvancedFileOutput? _file;

  void trace(
    String message, {
    String tag = defaultTag,
    Map<String, Object?> fields = const <String, Object?>{},
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log(
      Level.trace,
      message,
      tag: tag,
      fields: fields,
      error: error,
      stackTrace: stackTrace,
    );
  }

  void debug(
    String message, {
    String tag = defaultTag,
    Map<String, Object?> fields = const <String, Object?>{},
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log(
      Level.debug,
      message,
      tag: tag,
      fields: fields,
      error: error,
      stackTrace: stackTrace,
    );
  }

  void info(
    String message, {
    String tag = defaultTag,
    Map<String, Object?> fields = const <String, Object?>{},
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log(
      Level.info,
      message,
      tag: tag,
      fields: fields,
      error: error,
      stackTrace: stackTrace,
    );
  }

  void warn(
    String message, {
    String tag = defaultTag,
    Map<String, Object?> fields = const <String, Object?>{},
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log(
      Level.warning,
      message,
      tag: tag,
      fields: fields,
      error: error,
      stackTrace: stackTrace,
    );
  }

  void error(
    String message, {
    String tag = defaultTag,
    Map<String, Object?> fields = const <String, Object?>{},
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log(
      Level.error,
      message,
      tag: tag,
      fields: fields,
      error: error,
      stackTrace: stackTrace,
    );
    _dumpContext();
  }

  void fatal(
    String message, {
    String tag = defaultTag,
    Map<String, Object?> fields = const <String, Object?>{},
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log(
      Level.fatal,
      message,
      tag: tag,
      fields: fields,
      error: error,
      stackTrace: stackTrace,
    );
    _dumpContext();
  }

  /// Completes when the underlying outputs have been initialized.
  Future<void> get ready => _primary.init;

  /// Switches between the default level and trace-level verbose logging.
  void setVerbose(bool verbose) {
    final level = verbose ? Level.trace : _defaultLevel;
    for (final filter in _filters) {
      filter.level = level;
    }

    info(
      'log level updated',
      tag: 'boot',
      fields: <String, Object?>{'verbose': verbose, 'level': level.name},
    );
  }

  /// Flushes and closes the file sink. Call before the process exits.
  Future<void> flush() async {
    try {
      await _file?.destroy();
    } catch (_) {
      return;
    }
  }

  void _log(
    Level level,
    String message, {
    required String tag,
    required Map<String, Object?> fields,
    Object? error,
    StackTrace? stackTrace,
  }) {
    final record = LogMessage(
      tag: tag,
      text: redactPath(message),
      fields: _redactFields(fields),
    );

    _primary.log(level, record, error: error, stackTrace: stackTrace);

    final console = _console;
    if (console != null) {
      final previous = _suppressPrintCapture;
      _suppressPrintCapture = true;
      try {
        console.log(
          level,
          '[$tag] ${record.text}${_formatFields(record.fields)}',
          error: error,
          stackTrace: stackTrace,
        );
      } finally {
        _suppressPrintCapture = previous;
      }
    }
  }

  static String _formatFields(Map<String, Object?> fields) {
    if (fields.isEmpty) {
      return '';
    }
    return ' $fields';
  }

  /// Writes the buffered context into the file so a crash has a lead-up trail.
  void _dumpContext() {
    final ring = _ring;
    final file = _file;
    if (ring == null || file == null || ring.buffer.isEmpty) {
      return;
    }

    final lines = <String>[
      '--- CONTEXT DUMP (${ring.buffer.length} entries) ---',
    ];
    for (final event in ring.buffer) {
      lines.addAll(event.lines);
    }
    lines.add('--- END CONTEXT DUMP ---');
    ring.buffer.clear();

    // Level.fatal belongs to writeImmediately, so this flushes immediately.
    file.output(OutputEvent(LogEvent(Level.fatal, 'context dump'), lines));
  }

  static Map<String, Object?> _redactFields(Map<String, Object?> fields) {
    if (fields.isEmpty) {
      return fields;
    }

    return fields.map(
      (key, value) => MapEntry<String, Object?>(key, _redactValue(value)),
    );
  }

  static Object? _redactValue(Object? value) {
    if (value is String) {
      return redactPath(value);
    }
    if (value is Map) {
      return value.map(
        (key, item) => MapEntry<Object?, Object?>(key, _redactValue(item)),
      );
    }
    if (value is Iterable) {
      return value.map(_redactValue).toList();
    }
    return value;
  }
}
