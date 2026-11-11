import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/logging/boot_trace_reader.dart';

Future<Directory> _traceDirectory() async {
  final directory = await Directory.systemTemp.createTemp('ssb_boot_trace');
  addTearDown(() => directory.delete(recursive: true));
  return directory;
}

Future<File> _writeTrace(Directory directory, String contents) {
  return File(bootTraceFilePath(directory.path)).writeAsString(contents);
}

void main() {
  test('parses a complete timeline', () async {
    final directory = await _traceDirectory();
    await _writeTrace(
      directory,
      'trace=1 state=entry pid=1 entry_utc_ms=1762836000123 elapsed_us=0 '
      'phase=entry\n'
      'trace=1 state=shown pid=1 entry_utc_ms=1762836000123 '
      'elapsed_us=12400310 phase=shown window_us=180022 '
      'controller_us=9210030 plugins_us=11004400 first_frame_us=12310010\n',
    );

    final trace = await readBootTrace(directory.path);

    expect(trace, isNotNull);
    expect(trace!.state, 'shown');
    expect(trace.entryUtcMs, 1762836000123);
    expect(trace.elapsedUs, 12400310);
    expect(trace.lastPhase, 'shown');
    expect(trace.timedOut, isFalse);
    expect(trace.dartStalled, isFalse);
    expect(trace.phasesUs, <String, int>{
      'window': 180022,
      'controller': 9210030,
      'plugins': 11004400,
      'first_frame': 12310010,
    });
  });

  test('accepts a file that only has the entry record', () async {
    final directory = await _traceDirectory();
    await _writeTrace(
      directory,
      'trace=1 state=entry pid=1 entry_utc_ms=1762836000123 elapsed_us=0 '
      'phase=entry\n',
    );

    final trace = await readBootTrace(directory.path);

    expect(trace?.state, 'entry');
    expect(trace?.timedOut, isFalse);
    expect(trace?.phasesUs, isEmpty);
  });

  test('marks a timeout and keeps the last elapsed value', () async {
    final directory = await _traceDirectory();
    await _writeTrace(
      directory,
      'trace=1 state=entry pid=1 entry_utc_ms=1762836000123 elapsed_us=0 '
      'phase=entry\n'
      'trace=1 state=timeout pid=1 entry_utc_ms=1762836000123 '
      'elapsed_us=10000231 phase=plugins_registered window_us=180022 '
      'controller_us=9210030 plugins_us=11004400 dart_phase=booting '
      'dart_step=05 dart_gap_ms=10020\n'
      'trace=1 state=shown pid=1 entry_utc_ms=1762836000123 '
      'elapsed_us=12400310 phase=shown first_frame_us=12310010\n',
    );

    final trace = await readBootTrace(directory.path);

    expect(trace?.timedOut, isTrue);
    expect(trace?.state, 'shown');
    expect(trace?.elapsedUs, 12400310);
    expect(trace?.dartStep, 5);
    expect(trace?.dartGapMs, 10020);
    expect(trace?.phasesUs['plugins'], 11004400);
  });

  test('parses a dart_stalled record', () async {
    final directory = await _traceDirectory();
    await _writeTrace(
      directory,
      'trace=1 state=entry pid=1 entry_utc_ms=1762836000123 elapsed_us=0 '
      'phase=entry\n'
      'trace=1 state=dart_stalled pid=1 entry_utc_ms=1762836000123 '
      'elapsed_us=11004312 phase=plugins_registered dart_phase=booting '
      'dart_step=05 dart_gap_ms=10020\n',
    );

    final trace = await readBootTrace(directory.path);

    expect(trace?.dartStalled, isTrue);
    expect(trace?.lastPhase, 'plugins_registered');
    expect(trace?.dartPhase, 'booting');
    expect(trace?.dartStep, 5);
    expect(trace?.dartGapMs, 10020);
  });

  test('ignores unknown keys and tolerates a truncated line', () async {
    final directory = await _traceDirectory();
    await _writeTrace(
      directory,
      'trace=1 state=entry pid=1 entry_utc_ms=1762836000123 unknown=1 '
      'elapsed_us=0 phase=entry\n'
      'trace=1 state=shown pid=1 trunc',
    );

    final trace = await readBootTrace(directory.path);

    expect(trace?.state, 'shown');
    expect(trace?.entryUtcMs, 1762836000123);
  });

  test('returns null for a missing or empty file', () async {
    final directory = await _traceDirectory();
    expect(await readBootTrace(directory.path), isNull);

    await _writeTrace(directory, '');
    expect(await readBootTrace(directory.path), isNull);
  });

  test('deleteBootTrace removes only the current pid file', () async {
    final directory = await _traceDirectory();
    final own = await _writeTrace(directory, 'trace=1 state=entry\n');
    final other = await File('${directory.path}/boot_other.log')
        .writeAsString('trace=1 state=entry\n');

    await deleteBootTrace(directory.path);

    expect(await own.exists(), isFalse);
    expect(await other.exists(), isTrue);
  });
}
