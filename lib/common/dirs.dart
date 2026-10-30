import 'dart:io';

import 'package:path_provider/path_provider.dart';

const dirDb = 'db';

/// A directory that was created and proven writable.
class WritableDirectory {
  const WritableDirectory({required this.path, required this.fallbackIndex});

  final String path;

  /// Position in the candidate list, 0 being the preferred location.
  final int fallbackIndex;
}

/// App-owned storage roots, most preferred first: application support,
/// temporary directory, then the directory holding the executable.
///
/// The support directory is the same base the log files use. Unlike the
/// user-visible Documents folder it is not redirected by OneDrive and cannot be
/// moved by the user, which is what breaks the database on Windows.
Future<List<String>> appDataRoots() async {
  final roots = <String>[];

  final support = await _providerPath(getApplicationSupportDirectory);
  if (support != null) {
    roots.add(support);
  }

  final temp = await _providerPath(getTemporaryDirectory);
  if (temp != null) {
    roots.add(temp);
  }

  roots.add(File(Platform.resolvedExecutable).parent.path);

  return roots;
}

/// The user-visible Documents folder, or `null` when the provider fails.
///
/// Only used to look for data written by older versions; nothing new is stored
/// there.
Future<String?> documentsPath() =>
    _providerPath(getApplicationDocumentsDirectory);

Future<String?> _providerPath(Future<Directory> Function() provider) async {
  try {
    final directory = await provider();
    return directory.path;
  } on Exception {
    return null;
  }
}

/// Creates [path] and proves the process can write into it.
///
/// Returns `null` when the directory cannot be created or used, so the caller
/// can move on to the next candidate. A probe file is required because
/// directory creation reports the wrong thing on redirected locations: on the
/// Windows machine that motivated this, the Documents folder reported as
/// existing but every write below it failed with `ERROR_PATH_NOT_FOUND`.
Future<WritableDirectory?> prepareDirectory(String path, int index) async {
  try {
    final directory = Directory(path);
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }

    final probe = File('$path/.write_probe');
    probe.writeAsStringSync('ok');
    probe.deleteSync();

    return WritableDirectory(path: path, fallbackIndex: index);
  } on FileSystemException {
    return null;
  }
}

/// Filesystem facts about [path], for the diagnostic summary.
///
/// [FileSystemEntity.typeSync] without following links reports `link` for a
/// Windows junction, and `followed_type` reports `notFound` when that link is
/// broken. That combination is how a redirected Documents folder whose target
/// is gone shows up in a log.
Map<String, Object?> describeDirectory(String path) {
  final description = <String, Object?>{
    'path': path,
    'type': _typeOf(path, followLinks: false),
    'followed_type': _typeOf(path, followLinks: true),
  };

  try {
    description['resolved'] = Directory(path).resolveSymbolicLinksSync();
  } on FileSystemException catch (error) {
    description['resolve_error'] = error.osError?.message ?? error.message;
  }

  return description;
}

String _typeOf(String path, {required bool followLinks}) {
  try {
    return switch (FileSystemEntity.typeSync(path, followLinks: followLinks)) {
      FileSystemEntityType.file => 'file',
      FileSystemEntityType.directory => 'directory',
      FileSystemEntityType.link => 'link',
      _ => 'notFound',
    };
  } on FileSystemException {
    return 'error';
  }
}
