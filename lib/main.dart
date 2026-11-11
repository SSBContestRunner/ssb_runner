import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:catcher_2/catcher_2.dart';
import 'package:flutter/material.dart';
import 'package:ssb_runner/error_handling.dart';
import 'package:ssb_runner/logging/app_logger.dart';
import 'package:ssb_runner/logging/boot_beat.dart';
import 'package:ssb_runner/logging/boot_trace.dart';
import 'package:ssb_runner/ui/main_app/main_app.dart';
import 'package:window_manager/window_manager.dart';

const String _bootTraceDirPrefix = '--boot-trace-dir=';
const String _bootStallEnv = 'SSB_RUNNER_TEST_BOOT_STALL_MS';

void main(List<String> args) {
  final nativeTraceDirectory = _bootTraceDirectory(args);

  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();

      // Starts the boot stopwatch as close to the entry point as possible.
      boot.start();

      if (nativeTraceDirectory != null) {
        boot.nativeTraceDirectory = nativeTraceDirectory;
        _startBootBeat();
      }

      _maybeStallForTest();

      // Hide the window before anything else: this is native FFI with no IO,
      // and the macOS runner already made the window visible at this point.
      _hideWindowUntilFirstFrame();

      // Memory only. The file sink is installed after the first frame, so the
      // first-frame path never waits on a directory, a platform channel or
      // `PackageInfo`.
      installLogger(AppLogger.buffered());

      // No real IO, so stay synchronous instead of handing the event loop
      // back before `runApp`.
      final (debugOptions, releaseOptions) = initErrorHandling();

      Catcher2(
        rootWidget: MainApp(),
        debugConfig: debugOptions,
        releaseConfig: releaseOptions,
      );
    },
    (error, stackTrace) {
      log.fatal(
        'Uncaught asynchronous error',
        tag: 'crash',
        error: error,
        stackTrace: stackTrace,
      );
      _reportToCatcher(error, stackTrace);
    },
    zoneSpecification: appZoneSpecification(),
  );
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

/// Keeps the window invisible until the first frame is painted.
///
/// This does not call `windowManager.hide()`: on macOS the window is the only
/// one, and the runner's `applicationShouldTerminateAfterLastWindowClosed`
/// returns true, so ordering it out quits the app. A fully transparent window
/// stays "visible" and therefore does not terminate, while still drawing no
/// white frame. [MainApp] makes it opaque again after the first frame.
///
/// `WindowManager.instance.getCurrent()` resolves the app's own window from the
/// native window manager (macOS enumerates `[NSApplication windows]`), so there
/// is no initialisation step to wait for before touching it.
void _hideWindowUntilFirstFrame() {
  try {
    final window = WindowManager.instance.getCurrent();
    window?.opacity = 0;
  } catch (error, stackTrace) {
    log.warn(
      'window hide failed',
      tag: 'boot',
      error: error,
      stackTrace: stackTrace,
    );
  }
}

void _reportToCatcher(Object error, StackTrace stackTrace) {
  try {
    Catcher2.reportCheckedError(error, stackTrace);
  } catch (_) {
    // Catcher2 may not be initialised yet; the file log already holds the
    // error and its stack trace.
    return;
  }
}
