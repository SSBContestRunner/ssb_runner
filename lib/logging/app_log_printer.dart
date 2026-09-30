import 'package:logger/logger.dart';

/// Structured payload carried through a [Logger] instance.
///
/// Rendering lives in [AppLogPrinter] so that every output (file, console,
/// ring buffer) receives identical, machine-readable content.
class LogMessage {
  const LogMessage({
    required this.tag,
    required this.text,
    this.fields = const <String, Object?>{},
  });

  final String tag;
  final String text;
  final Map<String, Object?> fields;
}

/// Formats records as single-line logfmt with a UTC ISO-8601 timestamp.
///
/// Example:
/// `2026-09-30T04:15:03.123Z INFO  boot      msg="app_ready" durMs=412`
///
/// Errors and stack traces are appended as indented follow-up lines so the
/// first line of every record stays greppable.
class AppLogPrinter extends LogPrinter {
  AppLogPrinter();

  static const Map<Level, String> _levelNames = <Level, String>{
    Level.trace: 'TRACE',
    Level.debug: 'DEBUG',
    Level.info: 'INFO',
    Level.warning: 'WARN',
    Level.error: 'ERROR',
    Level.fatal: 'FATAL',
  };

  @override
  List<String> log(LogEvent event) {
    final message = event.message;
    final tag = message is LogMessage ? message.tag : 'app';
    final text = message is LogMessage ? message.text : '$message';
    final fields = message is LogMessage
        ? message.fields
        : const <String, Object?>{};

    final buffer = StringBuffer()
      ..write(event.time.toUtc().toIso8601String())
      ..write(' ')
      ..write((_levelNames[event.level] ?? event.level.name).padRight(5))
      ..write(' ')
      ..write(tag.padRight(10))
      ..write('msg="${_escape(text)}"');

    for (final entry in fields.entries) {
      final value = entry.value;
      if (value == null) {
        continue;
      }
      if (value is num || value is bool) {
        buffer.write(' ${entry.key}=$value');
      } else {
        buffer.write(' ${entry.key}="${_escape('$value')}"');
      }
    }

    final lines = <String>[buffer.toString()];

    if (event.error != null) {
      lines.add('    error: ${event.error}');
    }

    final stackTrace = event.stackTrace;
    if (stackTrace != null) {
      for (final line in '$stackTrace'.trim().split('\n')) {
        lines.add('    $line');
      }
    }

    return lines;
  }

  static String _escape(String value) {
    return value
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\r', '')
        .replaceAll('\n', '\\n');
  }
}
