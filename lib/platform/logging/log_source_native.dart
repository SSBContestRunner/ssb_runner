import 'dart:io';

import 'package:ssb_runner/logging/log_paths.dart';
import 'package:ssb_runner/logging/log_session.dart';
import 'package:ssb_runner/logging/log_source.dart';

/// Reads the rotating file written by the native logging backend.
const LogSource logSource = _FileLogSource();

class _FileLogSource implements LogSource {
  const _FileLogSource();

  Future<LogLocation> _location() async =>
      LogSession.location ?? await resolveLogDirectory();

  @override
  Future<List<String>> latestLogLines() async {
    final location = await _location();
    final latest = File('${location.path}/latest.log');
    if (!latest.existsSync()) {
      return const <String>[];
    }
    return latest.readAsLines();
  }

  @override
  Future<List<LogFileContents>> logFiles() async {
    final location = await _location();
    final directory = Directory(location.path);
    if (!directory.existsSync()) {
      return const <LogFileContents>[];
    }

    final files =
        directory
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.log'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    return <LogFileContents>[
      for (final file in files)
        LogFileContents(
          name: file.uri.pathSegments.last,
          bytes: await file.readAsBytes(),
        ),
    ];
  }
}
