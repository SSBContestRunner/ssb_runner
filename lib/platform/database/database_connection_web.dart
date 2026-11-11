import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:ssb_runner/logging/app_logger.dart';
import 'package:ssb_runner/platform/database/database_bootstrap_web.dart';
import 'package:ssb_runner/platform/database/web_database_state.dart';

/// Opens the database through SQLite WASM, persisted by OPFS or IndexedDB.
///
/// `sqlite3.wasm` and `drift_worker.js` are served next to `index.html`; their
/// versions must match the resolved `drift` package. In particular, the
/// sqlite3 3.9.0 release wasm is not loadable by drift 2.35.3's worker, so
/// `web/sqlite3.wasm` is copied from drift's own devtools build. See the
/// dependency note in `pubspec.yaml`.
DatabaseConnection openPlatformDatabaseConnection() =>
    DatabaseConnection.delayed(_connect());

Future<DatabaseConnection> _connect() async {
  await ensureDatabaseReady();

  return driftDatabase(
    name: 'ssb_runner_database',
    web: DriftWebOptions(
      sqlite3Wasm: Uri.parse('sqlite3.wasm'),
      driftWorker: Uri.parse('drift_worker.js'),
      onResult: (result) {
        webDatabaseImplementation = result.chosenImplementation.name;
        webDatabasePersistent =
            result.chosenImplementation != WasmStorageImplementation.inMemory;

        final missing = result.missingFeatures
            .map((feature) => feature.name)
            .join(',');
        log.info(
          'database opened',
          tag: 'db',
          fields: <String, Object?>{
            'implementation': result.chosenImplementation.name,
            'missing_features': missing,
          },
        );

        if (!webDatabasePersistent) {
          log.error(
            'database has no persistent storage',
            tag: 'db',
            fields: <String, Object?>{'missing_features': missing},
          );
        }
      },
    ),
  );
}
