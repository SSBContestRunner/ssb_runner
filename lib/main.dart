import 'dart:async';

import 'package:catcher_2/catcher_2.dart';
import 'package:flutter/material.dart';
import 'package:ssb_runner/error_handling.dart';
import 'package:ssb_runner/logging/app_logger.dart';
import 'package:ssb_runner/logging/boot_trace.dart';
import 'package:ssb_runner/ui/main_app/main_app.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();

      // Starts the boot stopwatch as close to the entry point as possible.
      boot.start();

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
