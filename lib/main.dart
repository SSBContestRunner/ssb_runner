import 'dart:async';

import 'package:catcher_2/catcher_2.dart';
import 'package:flutter/material.dart';
import 'package:ssb_runner/error_handling.dart';
import 'package:ssb_runner/logging/app_logger.dart';
import 'package:ssb_runner/logging/logging_bootstrap.dart';
import 'package:ssb_runner/ui/main_app/main_app.dart';
import 'package:window_manager/window_manager.dart';

const seedColor = Color(0xFF0059BA);

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Logging first: everything after this point is persisted to disk.
      await bootstrapLogging();
      await _hideWindowUntilFirstFrame();

      final (debugOptions, releaseOptions) = await initErrorHandling();

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
/// `ensureInitialized` must come first: every other method dereferences the
/// native window, which macOS only binds to the plugin during that call.
Future<void> _hideWindowUntilFirstFrame() async {
  try {
    await windowManager.ensureInitialized();
    await windowManager.setOpacity(0);
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
