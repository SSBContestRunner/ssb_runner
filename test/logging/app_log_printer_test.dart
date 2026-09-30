import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:ssb_runner/logging/app_log_printer.dart';

void main() {
  test('formats a structured record as logfmt with a UTC timestamp', () {
    final event = LogEvent(
      Level.info,
      const LogMessage(
        tag: 'boot',
        text: 'app_ready',
        fields: <String, Object?>{'durMs': 12, 'path': 'a b'},
      ),
      time: DateTime.utc(2026, 9, 30, 4, 15, 3, 123),
    );

    final lines = AppLogPrinter().log(event);

    expect(lines, hasLength(1));
    expect(lines.single, startsWith('2026-09-30T04:15:03.123Z INFO  boot'));
    expect(lines.single, contains('msg="app_ready"'));
    expect(lines.single, contains('durMs=12'));
    expect(lines.single, contains('path="a b"'));
  });

  test('escapes quotes and newlines inside the message', () {
    final event = LogEvent(
      Level.warning,
      const LogMessage(tag: 'io', text: 'say "hi"\nnext'),
    );

    final line = AppLogPrinter().log(event).single;

    expect(line, contains(r'msg="say \"hi\"\nnext"'));
  });

  test('appends error and stack trace as indented lines', () {
    final event = LogEvent(
      Level.error,
      const LogMessage(tag: 'crash', text: 'boom'),
      error: 'StateError: nope',
      stackTrace: StackTrace.fromString('frame one\nframe two'),
    );

    final lines = AppLogPrinter().log(event);

    expect(lines.first, contains('ERROR crash'));
    expect(lines, contains('    error: StateError: nope'));
    expect(lines, contains('    frame one'));
    expect(lines, contains('    frame two'));
  });

  test('falls back to the app tag for plain string messages', () {
    final event = LogEvent(Level.info, 'plain');

    final line = AppLogPrinter().log(event).single;

    expect(line, contains('app'));
    expect(line, contains('msg="plain"'));
  });
}
