import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:ssb_runner/common/app_info.dart';
import 'package:ssb_runner/common/dirs.dart';

import 'app_logger.dart';
import 'boot_trace.dart';
import 'log_paths.dart';
import 'log_session.dart';

const List<String> _libraryExtensions = <String>['.dll', '.so', '.dylib'];

/// Upgrades the pre-frame in-memory logger to the file-backed one and records
/// the environment snapshot.
///
/// Must only run after the first frame: before that every step here would keep
/// the splash off screen on a slow disk or under a virus scanner.
Future<void> bootstrapLoggingAfterFirstFrame() async {
  final location = await resolveLogDirectory();
  // Read the metadata once and share it with the session header and the UI.
  final packageInfo = await readPackageInfo();
  final headerLines = await buildSessionHeader(
    location: location,
    packageInfo: packageInfo,
  );
  AppInfo.apply(packageInfo);

  final pending = log.bufferedEvents;
  installLogger(
    await AppLogger.restoreFileBacked(
      directory: location.path,
      header: headerLines.map((line) => '# $line').join('\n'),
      pending: pending,
    ),
  );

  log.info(
    'log sink upgraded',
    tag: 'boot',
    fields: <String, Object?>{
      'log_dir': redactPath(location.path),
      'fallback_index': location.fallbackIndex,
      'replayed': pending.length,
    },
  );

  await boot.step('log_ready', () async {
    log.info(
      'log directory resolved',
      tag: 'boot',
      fields: <String, Object?>{
        'log_dir': redactPath(location.path),
        'fallback_index': location.fallbackIndex,
        'mode': kReleaseMode ? 'release' : 'debug',
      },
    );
  });

  await boot.step('platform', () async {
    log.info(
      'platform snapshot',
      tag: 'boot',
      fields: <String, Object?>{
        'os': Platform.operatingSystem,
        'os_version': Platform.operatingSystemVersion,
        'dart': Platform.version.split(' ').first,
        'locale': Platform.localeName,
        'processors': Platform.numberOfProcessors,
      },
    );
  });

  // Diagnostics only: they must not delay `application ready`.
  unawaited(boot.step('runtime_env_probe', probeRuntimeEnvironment));
  unawaited(boot.step('storage_probe', probeStorageRoots));
}

/// Records the native libraries shipped next to the executable.
///
/// The directory listing runs in an isolate: every entry may trigger a virus
/// scanner scan, and enumerating them on the UI isolate stalls the splash.
Future<void> probeRuntimeEnvironment() async {
  final fields = await Isolate.run(_listRuntimeLibraries);
  log.info('runtime environment probe', tag: 'env', fields: fields);
}

Map<String, Object?> _listRuntimeLibraries() {
  final executableDirectory = File(Platform.resolvedExecutable).parent;
  final libraries = <String>[];

  if (executableDirectory.existsSync()) {
    for (final entity in executableDirectory.listSync()) {
      if (entity is! File) {
        continue;
      }

      final name = entity.uri.pathSegments.last.toLowerCase();
      if (_libraryExtensions.any(name.endsWith)) {
        libraries.add(name);
      }
    }
  }
  libraries.sort();

  return <String, Object?>{
    'exe_dir': redactPath(executableDirectory.path),
    'library_count': libraries.length,
    'libraries': libraries.join(','),
  };
}

/// Records whether the folders the app writes to are usable.
///
/// Windows reports the Documents folder as existing even when it is a redirect
/// whose target is gone, and every write below it then fails with "path not
/// found". The type/link details recorded here make that visible in the
/// diagnostics summary instead of only showing up as an opaque errno.
Future<void> probeStorageRoots() async {
  final documents = await documentsPath();
  final roots = await appDataRoots();

  final descriptions = <Map<String, Object?>>[];
  if (documents != null) {
    descriptions.add(await describeDirectory(documents));
  }
  for (final root in roots) {
    descriptions.add(await describeDirectory(root));
  }

  log.info(
    'storage probe',
    tag: 'env',
    fields: <String, Object?>{'roots': descriptions},
  );
}

/// Flushes pending log records. Call this on app exit.
Future<void> flushLogs() => log.flush();
