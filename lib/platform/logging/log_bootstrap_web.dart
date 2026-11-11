import 'package:flutter/foundation.dart';
import 'package:ssb_runner/common/app_info.dart';
import 'package:ssb_runner/logging/app_logger.dart';
import 'package:ssb_runner/logging/boot_trace.dart';
import 'package:ssb_runner/logging/log_location.dart';
import 'package:ssb_runner/logging/log_session.dart';
import 'package:ssb_runner/platform/environment/environment.dart';

/// Installs the in-memory logger and records the browser environment snapshot.
///
/// Nothing is persisted: the log would otherwise compete with the database for
/// the origin's storage quota. The pre-frame records are replayed into the
/// buffer so the web diagnostics still show what happened before the first
/// frame.
Future<void> installPlatformLogging() async {
  final packageInfo = await readPackageInfo();
  final environment = await captureEnvironment();
  await buildSessionHeader(
    location: const LogLocation(path: 'browser-memory', fallbackIndex: -1),
    packageInfo: packageInfo,
    environment: environment,
  );
  AppInfo.apply(packageInfo);

  installLogger(AppLogger.memoryBacked(pending: log.bufferedEvents));

  await boot.step('log_ready', () async {
    log.info(
      'log backend ready',
      tag: 'boot',
      fields: <String, Object?>{
        'backend': 'memory',
        'max_lines': 5000,
        'mode': kReleaseMode ? 'release' : 'debug',
      },
    );
  });

  await boot.step('platform', () async {
    log.info('platform snapshot', tag: 'boot', fields: environment.fields);
  });
}
