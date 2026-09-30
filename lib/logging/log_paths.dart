import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// A resolved, writable location for log files.
class LogLocation {
  const LogLocation({required this.path, required this.fallbackIndex});

  final String path;
  final int fallbackIndex;
}

Future<String?> _tryDirectory(Future<Directory> Function() provider) async {
  try {
    final directory = await provider();
    return directory.path;
  } on Exception {
    return null;
  }
}

Future<List<String>> _candidateDirectories() async {
  final candidates = <String>[];

  final support = await _tryDirectory(getApplicationSupportDirectory);
  if (support != null) {
    candidates.add('$support/log');
  }

  final temp = await _tryDirectory(getTemporaryDirectory);
  if (temp != null) {
    candidates.add('$temp/ssb_runner/log');
  }

  candidates.add('${File(Platform.resolvedExecutable).parent.path}/log');

  return candidates;
}

/// Resolves the first writable log directory, creating it when missing.
///
/// The order is: application support, temporary directory, then next to the
/// executable (portable installs). The index of the directory that was used is
/// reported so it can be recorded in the session header.
Future<LogLocation> resolveLogDirectory() async {
  final candidates = await _candidateDirectories();

  for (var index = 0; index < candidates.length; index++) {
    final path = candidates[index];
    try {
      final directory = Directory(path);
      if (!directory.existsSync()) {
        directory.createSync(recursive: true);
      }

      // Prove writability with a probe file: a directory can exist yet be
      // read-only, for example when installed under Program Files.
      final probe = File('$path/.write_probe');
      probe.writeAsStringSync('ok');
      probe.deleteSync();

      return LogLocation(path: path, fallbackIndex: index);
    } on FileSystemException {
      continue;
    }
  }

  return LogLocation(
    path: '${Directory.current.path}/log',
    fallbackIndex: candidates.length,
  );
}

/// Replaces the user home directory prefix with a tilde.
String redactPath(String path) {
  if (path.isEmpty) {
    return path;
  }

  final home =
      Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
  if (home == null || home.isEmpty) {
    return path;
  }

  return path.replaceAll(home.replaceAll('\\', '/'), '~').replaceAll(home, '~');
}
