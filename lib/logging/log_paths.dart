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

final RegExp _posixHomePattern = RegExp(r'/(?:Users|home)/[^/\s]+');
final RegExp _windowsHomePattern = RegExp(r'[A-Za-z]:[\\/]Users[\\/][^\\/\s]+');

/// Home directory spellings that may be exposed by the current process.
///
/// Sandboxed release builds may expose a container path as `HOME`, so the
/// current user directory is also derived from `USER`/`USERNAME`.
Set<String> _homeCandidates() {
  final candidates = <String>{};
  for (final key in const <String>['HOME', 'USERPROFILE']) {
    final value = Platform.environment[key];
    if (value != null && value.isNotEmpty) {
      candidates.add(value);
    }
  }

  final user = Platform.environment['USER'] ?? Platform.environment['USERNAME'];
  if (user != null && user.isNotEmpty) {
    candidates
      ..add('/Users/$user')
      ..add('/home/$user');
    final systemDrive = Platform.environment['SystemDrive'];
    if (systemDrive != null && systemDrive.isNotEmpty) {
      candidates.add('$systemDrive\\Users\\$user');
    }
  }

  return candidates;
}

String _replaceHome(String text) {
  var redacted = text;
  for (final candidate in _homeCandidates()) {
    redacted = redacted
        .replaceAll(candidate.replaceAll('\\', '/'), '~')
        .replaceAll(candidate, '~');
  }
  return redacted;
}

/// Replaces the user home directory prefix with a tilde.
String redactPath(String path) {
  if (path.isEmpty) {
    return path;
  }

  return _replaceHome(
    path,
  ).replaceFirst(_posixHomePattern, '~').replaceFirst(_windowsHomePattern, '~');
}

/// Redacts user-home prefixes anywhere in [text], including log messages that
/// embed paths inside a field value.
String redactText(String text) {
  if (text.isEmpty) {
    return text;
  }

  return _replaceHome(
    text,
  ).replaceAll(_posixHomePattern, '~').replaceAll(_windowsHomePattern, '~');
}
