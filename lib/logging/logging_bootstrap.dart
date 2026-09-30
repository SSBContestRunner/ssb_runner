import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_logger.dart';
import 'boot_trace.dart';
import 'log_paths.dart';
import 'log_session.dart';

const List<String> _libraryExtensions = <String>['.dll', '.so', '.dylib'];

/// Installs the file-backed logger and records the environment snapshot.
///
/// Call this as early as possible, before plugins and UI start up, so that
/// early failures still end up in the log file.
Future<void> bootstrapLogging() async {
  final location = await resolveLogDirectory();
  final headerLines = await buildSessionHeader(location: location);

  installLogger(
    AppLogger.fileBacked(
      directory: location.path,
      header: headerLines.map((line) => '# $line').join('\n'),
    ),
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

  await boot.step('runtime_env_probe', probeRuntimeEnvironment);
}

/// Records the native libraries shipped next to the executable.
Future<void> probeRuntimeEnvironment() async {
  final executableDirectory = File(Platform.resolvedExecutable).parent;
  if (!executableDirectory.existsSync()) {
    return;
  }

  final libraries = <String>[];
  for (final entity in executableDirectory.listSync()) {
    if (entity is! File) {
      continue;
    }

    final name = entity.uri.pathSegments.last.toLowerCase();
    if (_libraryExtensions.any(name.endsWith)) {
      libraries.add(name);
    }
  }
  libraries.sort();

  log.info(
    'runtime environment probe',
    tag: 'env',
    fields: <String, Object?>{
      'exe_dir': redactPath(executableDirectory.path),
      'library_count': libraries.length,
      'libraries': libraries.join(','),
    },
  );
}

/// Flushes pending log records. Call this on app exit.
Future<void> flushLogs() => log.flush();
