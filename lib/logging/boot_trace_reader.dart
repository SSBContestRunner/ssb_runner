import 'dart:io';

import 'app_logger.dart';

/// Native startup timeline written by `windows/runner/startup_trace.cpp`.
///
/// All durations are relative to `entry` and come from the native performance
/// counter, so they are immune to system clock changes. Missing or partially
/// written files yield null or absent fields instead of an exception.
class NativeBootTrace {
  const NativeBootTrace({
    this.state,
    this.entryUtcMs,
    this.elapsedUs,
    this.phasesUs = const <String, int>{},
    this.lastPhase,
    this.timedOut = false,
    this.dartStalled = false,
    this.dartPhase,
    this.dartStep,
    this.dartGapMs,
  });

  /// Last `state` seen: `entry`, `timeout`, `shown` or `dart_stalled`.
  final String? state;

  /// Wall clock time of the first instruction in the runner, for aligning with
  /// Dart's `DateTime.now()`.
  final int? entryUtcMs;

  /// Duration of the last record, relative to `entry`.
  final int? elapsedUs;

  /// Completed native phases in microseconds, keyed by `window`, `controller`,
  /// `plugins` and `first_frame`.
  final Map<String, int> phasesUs;

  /// Last native phase reached.
  final String? lastPhase;

  /// True when any record carries `state=timeout`.
  final bool timedOut;

  /// True when any record carries `state=dart_stalled`.
  final bool dartStalled;

  /// Last heartbeat phase reported before the stall.
  final String? dartPhase;

  /// Last BOOT step index reported before the stall.
  final int? dartStep;

  /// Milliseconds between the last heartbeat and the stall record.
  final int? dartGapMs;
}

const Map<String, String> _phaseKeys = <String, String>{
  'window_us': 'window',
  'controller_us': 'controller',
  'plugins_us': 'plugins',
  'first_frame_us': 'first_frame',
};

/// Path of the trace file owned by the current process.
String bootTraceFilePath(String directory) {
  final separator = directory.endsWith(Platform.pathSeparator)
      ? ''
      : Platform.pathSeparator;
  return '$directory${separator}boot_$pid.log';
}

/// Reads and merges the native timeline of the current process.
///
/// Returns null when the file is absent, unreadable or empty.
Future<NativeBootTrace?> readBootTrace(String directory) async {
  final file = File(bootTraceFilePath(directory));
  List<String> lines;
  try {
    if (!await file.exists()) {
      return null;
    }
    lines = await file.readAsLines();
  } on FileSystemException {
    return null;
  }
  if (lines.isEmpty) {
    return null;
  }

  String? state;
  int? entryUtcMs;
  int? elapsedUs;
  String? lastPhase;
  String? dartPhase;
  int? dartStep;
  int? dartGapMs;
  var timedOut = false;
  var dartStalled = false;
  var recognised = false;
  final phasesUs = <String, int>{};

  for (final line in lines) {
    final values = _parseLine(line);
    if (values.isEmpty) {
      continue;
    }
    recognised = true;

    final lineState = values['state'];
    if (lineState == 'timeout') {
      timedOut = true;
    }
    if (lineState == 'dart_stalled') {
      dartStalled = true;
    }
    state = lineState ?? state;

    entryUtcMs = _toInt(values['entry_utc_ms']) ?? entryUtcMs;
    elapsedUs = _toInt(values['elapsed_us']) ?? elapsedUs;
    lastPhase = values['phase'] ?? lastPhase;
    dartPhase = values['dart_phase'] ?? dartPhase;
    dartStep = _toInt(values['dart_step']) ?? dartStep;
    dartGapMs = _toInt(values['dart_gap_ms']) ?? dartGapMs;

    for (final entry in _phaseKeys.entries) {
      final value = _toInt(values[entry.key]);
      if (value == null) {
        continue;
      }
      final previous = phasesUs[entry.value];
      if (previous == null || value > previous) {
        phasesUs[entry.value] = value;
      }
    }
  }

  if (!recognised) {
    return null;
  }

  return NativeBootTrace(
    state: state,
    entryUtcMs: entryUtcMs,
    elapsedUs: elapsedUs,
    phasesUs: phasesUs,
    lastPhase: lastPhase,
    timedOut: timedOut,
    dartStalled: dartStalled,
    dartPhase: dartPhase,
    dartStep: dartStep,
    dartGapMs: dartGapMs,
  );
}

/// Deletes the trace file of the current process. Best effort.
Future<void> deleteBootTrace(String directory) async {
  try {
    final file = File(bootTraceFilePath(directory));
    if (await file.exists()) {
      await file.delete();
    }
  } on FileSystemException catch (error) {
    log.debug(
      'boot trace cleanup failed',
      tag: 'boot',
      fields: <String, Object?>{'error': '$error'},
    );
  }
}

Map<String, String> _parseLine(String line) {
  final values = <String, String>{};
  for (final token in line.split(' ')) {
    final separator = token.indexOf('=');
    if (separator <= 0 || separator == token.length - 1) {
      continue;
    }
    values[token.substring(0, separator)] = token.substring(separator + 1);
  }
  return values;
}

int? _toInt(String? value) => value == null ? null : int.tryParse(value);
