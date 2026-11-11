import 'package:ssb_runner/logging/app_logger.dart';
import 'package:ssb_runner/platform/logging/log_bootstrap.dart';

/// Upgrades the pre-frame in-memory logger to the platform backend and records
/// the environment snapshot.
///
/// Must only run after the first frame: before that every step here would keep
/// the splash off screen on a slow disk or under a virus scanner.
Future<void> bootstrapLoggingAfterFirstFrame() => installPlatformLogging();

/// Flushes pending log records. Call this on app exit.
Future<void> flushLogs() => log.flush();
