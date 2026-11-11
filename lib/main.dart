import 'dart:async';

import 'package:catcher_2/catcher_2.dart';
import 'package:flutter/material.dart';
import 'package:ssb_runner/error_handling.dart';
import 'package:ssb_runner/logging/app_logger.dart';
import 'package:ssb_runner/logging/boot_trace.dart';
import 'package:ssb_runner/platform/diagnostics/boot_diagnostics.dart';
import 'package:ssb_runner/platform/window/window_port.dart';
import 'package:ssb_runner/ui/main_app/main_app.dart';

void main(List<String> args) {
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();

      // Starts the boot stopwatch as close to the entry point as possible.
      boot.start();

      // Native startup timeline and the UI-isolate heartbeat; a no-op on the
      // web, where the browser owns the process.
      configureBootDiagnostics(args);

      // Hide the window before anything else: this is native FFI with no IO,
      // and the macOS runner already made the window visible at this point.
      // The browser owns its window, so the port is a no-op there.
      unawaited(hideWindowUntilFirstFrame());

      // Memory only. The platform sink is installed after the first frame, so
      // the first-frame path never waits on a directory, a platform channel or
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

void _reportToCatcher(Object error, StackTrace stackTrace) {
  try {
    Catcher2.reportCheckedError(error, stackTrace);
  } catch (_) {
    // Catcher2 may not be initialised yet; the file log already holds the
    // error and its stack trace.
    return;
  }
}
