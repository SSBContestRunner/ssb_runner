import 'dart:ffi';
import 'dart:io';

import 'package:ssb_runner/logging/app_logger.dart';
import 'package:ssb_runner/logging/boot_beat.dart';
import 'package:ssb_runner/logging/boot_trace.dart';

const String _bootTraceDirPrefix = '--boot-trace-dir=';
const String _bootStallEnv = 'SSB_RUNNER_TEST_BOOT_STALL_MS';

/// Wires the native startup timeline and the UI-isolate heartbeat.
///
/// The Windows runner passes `--boot-trace-dir`; the heartbeat symbol only
/// exists on that platform, so every other native target continues unchanged.
void configureBootDiagnostics(List<String> args) {
  final nativeTraceDirectory = _bootTraceDirectory(args);
  if (nativeTraceDirectory != null) {
    boot.nativeTraceDirectory = nativeTraceDirectory;
    _startBootBeat();
  }

  _maybeStallForTest();
}

/// Directory the Windows runner writes its native timeline to, if provided.
String? _bootTraceDirectory(List<String> args) {
  for (final arg in args) {
    if (arg.startsWith(_bootTraceDirPrefix)) {
      return arg.substring(_bootTraceDirPrefix.length);
    }
  }
  return null;
}

/// Reports UI-isolate liveness to the native startup watchdog.
///
/// Fundamentally optional: when the symbol is missing (macOS/Linux) startup
/// continues unchanged.
void _startBootBeat() {
  final beat = loadBootBeat(DynamicLibrary.process());
  if (beat == null) {
    log.debug(
      'boot beat unavailable',
      tag: 'boot',
      fields: <String, Object?>{'reason': 'symbol'},
    );
    return;
  }

  BootBeat(
    beat: beat,
    phase: () => boot.phase,
    step: () => boot.stepIndex,
  ).start();
}

/// CI only: stalls the UI isolate so the native watchdog's `dart_stalled`
/// detection can be exercised.
void _maybeStallForTest() {
  final millis = int.tryParse(Platform.environment[_bootStallEnv] ?? '');
  if (millis == null || millis <= 0) {
    return;
  }
  sleep(Duration(milliseconds: millis));
}
