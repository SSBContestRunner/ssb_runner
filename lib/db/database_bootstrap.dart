import 'dart:io';

import 'package:ssb_runner/common/dirs.dart';
import 'package:ssb_runner/logging/app_logger.dart';

const String _databaseFileName = 'ssb_runner_database.sqlite';

/// Database location written by older versions, relative to Documents.
const String _legacyRelativeDirectory = 'ssb_runner/db';

/// What drift needs to open the database, plus anything the UI should tell the
/// user about history not being where they expect it.
class DatabaseBootstrap {
  const DatabaseBootstrap({
    required this.directory,
    required this.path,
    required this.fallbackIndex,
    this.migratedFrom,
    this.warning,
  });

  const DatabaseBootstrap.inMemory({required this.warning})
    : directory = null,
      path = null,
      fallbackIndex = -1,
      migratedFrom = null;

  /// Directory holding the database file; `null` for an in-memory database.
  final String? directory;

  /// Full path of the database file; `null` for an in-memory database.
  final String? path;

  /// Index of the storage root that was used, 0 being the preferred one.
  final int fallbackIndex;

  /// Legacy database copied into [directory], when a migration ran.
  final String? migratedFrom;

  /// User-facing message. Startup is never blocked on it.
  final String? warning;
}

Future<DatabaseBootstrap>? _pending;

/// Prepares the database directory, once per process.
///
/// The directory lives next to the logs in the application support folder, so
/// the path cannot be redirected by OneDrive the way Documents can. The
/// database older versions wrote to Documents is copied over once.
///
/// Never throws: when no directory is usable the result asks drift for an
/// in-memory database and carries a warning for the UI.
Future<DatabaseBootstrap> ensureDatabaseReady() => _pending ??= _prepare();

Future<DatabaseBootstrap> _prepare() async {
  final roots = await appDataRoots();

  for (var index = 0; index < roots.length; index++) {
    final candidate = '${roots[index]}/$dirDb';
    final location = await prepareDirectory(candidate, index);

    if (location == null) {
      log.warn(
        'database directory unavailable',
        tag: 'db',
        fields: describeDirectory(candidate),
      );
      continue;
    }

    final path = '${location.path}/$_databaseFileName';
    final migration = await _migrateLegacyDatabase(path);

    if (migration.error != null) {
      log.warn(
        'legacy database migration failed',
        tag: 'db',
        fields: <String, Object?>{
          'from': migration.source,
          'to': path,
          'error': migration.error,
        },
      );
    }

    final warnings = <String>[
      if (index > 0) 'History is stored in a fallback folder: ${location.path}',
      if (migration.error != null)
        'Could not migrate the existing history: ${migration.error}',
    ];

    final bootstrap = DatabaseBootstrap(
      directory: location.path,
      path: path,
      fallbackIndex: index,
      migratedFrom: migration.source,
      warning: warnings.isEmpty ? null : warnings.join('\n'),
    );

    log.info(
      'database directory resolved',
      tag: 'db',
      fields: <String, Object?>{
        'db_dir': bootstrap.directory,
        'fallback_index': bootstrap.fallbackIndex,
        'migrated_from': bootstrap.migratedFrom,
        'warning': bootstrap.warning,
      },
    );

    return bootstrap;
  }

  log.error(
    'no writable database directory, using an in-memory database',
    tag: 'db',
    fields: <String, Object?>{'roots': roots},
  );

  return const DatabaseBootstrap.inMemory(
    warning: 'History is unavailable: no writable data folder was found.',
  );
}

class _Migration {
  const _Migration({this.source, this.error});

  final String? source;
  final String? error;
}

/// Copies the legacy Documents database into [targetPath] when the target does
/// not exist yet.
Future<_Migration> _migrateLegacyDatabase(String targetPath) async {
  if (File(targetPath).existsSync()) {
    return const _Migration();
  }

  final documents = await documentsPath();
  if (documents == null) {
    return const _Migration();
  }

  final source = File(
    '$documents/$_legacyRelativeDirectory/$_databaseFileName',
  );
  if (!source.existsSync()) {
    return const _Migration();
  }

  try {
    source.copySync(targetPath);
    for (final suffix in const <String>['-wal', '-shm']) {
      final companion = File('${source.path}$suffix');
      if (companion.existsSync()) {
        companion.copySync('$targetPath$suffix');
      }
    }
  } on FileSystemException catch (error) {
    return _Migration(
      source: source.path,
      error: error.osError?.message ?? error.message,
    );
  }

  log.info(
    'legacy database migrated',
    tag: 'db',
    fields: <String, Object?>{'from': source.path, 'to': targetPath},
  );

  return _Migration(source: source.path);
}
