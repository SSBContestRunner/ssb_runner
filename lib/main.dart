import 'dart:async';

import 'package:catcher_2/catcher_2.dart';
import 'package:flutter/foundation.dart' show BindingBase;
import 'package:flutter/material.dart';
import 'package:ssb_runner/error_handling.dart';
import 'package:ssb_runner/logging/app_logger.dart';
import 'package:ssb_runner/logging/boot_trace.dart';
import 'package:ssb_runner/platform/diagnostics/boot_diagnostics.dart';
import 'package:ssb_runner/platform/window/window_port.dart';
import 'package:ssb_runner/ui/main_app/main_app.dart';

void main(List<String> args) {
  // Zone errors are only reported by default, which hides a binding that was
  // initialised in a different zone than `runApp`. Fail loudly instead; this
  // must run before the binding is initialised.
  BindingBase.debugZoneErrorsAreFatal = true;

  runZonedGuarded(
    () {
      // Starts the boot stopwatch as close to the entry point as possible.
      boot.start();

      // Native startup timeline and the UI-isolate heartbeat; a no-op on the
      // web, where the browser owns the process.
      configureBootDiagnostics(args);

      // Memory only. The platform sink is installed after the first frame, so
      // the first-frame path never waits on a directory, a platform channel or
      // `PackageInfo`.
      installLogger(AppLogger.buffered());

      // No real IO, so stay synchronous instead of handing the event loop
      // back before `runApp`.
      final (debugOptions, releaseOptions) = initErrorHandling();

      // The binding is initialised by Catcher2 on purpose: it does so inside
      // the same zone it uses for `runApp` (on the web that is its own
      // error-guarding zone), so the two always agree. Calling
      // `ensureInitialized()` here instead would tie the binding to this zone
      // and make the web build report a "Zone mismatch" during `runApp`.
      Catcher2(
        ensureInitialized: true,
        runAppFunction: () {
          // Hides the window before the first frame. This is native FFI with no
          // IO, but it still needs the binding, so it runs from here rather
          // than from the constructor path. The browser owns its window, so the
          // port is a no-op there.
          unawaited(hideWindowUntilFirstFrame());
          runApp(MainApp());
        },
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
