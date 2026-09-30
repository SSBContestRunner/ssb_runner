import 'dart:async';

import 'package:catcher_2/catcher_2.dart';
import 'package:flutter/material.dart';
import 'package:ssb_runner/error_handling.dart';
import 'package:ssb_runner/logging/app_logger.dart';
import 'package:ssb_runner/logging/logging_bootstrap.dart';
import 'package:ssb_runner/ui/main_app/main_app.dart';

const seedColor = Color(0xFF0059BA);

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Logging first: everything after this point is persisted to disk.
      await bootstrapLogging();

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

void _reportToCatcher(Object error, StackTrace stackTrace) {
  try {
    Catcher2.reportCheckedError(error, stackTrace);
  } catch (_) {
    // Catcher2 may not be initialised yet; the file log already holds the
    // error and its stack trace.
    return;
  }
}
