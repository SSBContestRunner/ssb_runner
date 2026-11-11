import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:ssb_runner/platform/database/database_bootstrap_native.dart';

/// Opens the database in the directory resolved by [ensureDatabaseReady], or
/// in memory when no writable directory exists.
DatabaseConnection openPlatformDatabaseConnection() =>
    DatabaseConnection.delayed(_connect());

Future<DatabaseConnection> _connect() async {
  final bootstrap = await ensureDatabaseReady();
  final path = bootstrap.path;

  if (path == null) {
    return DatabaseConnection(NativeDatabase.memory());
  }

  return driftDatabase(
    name: 'ssb_runner_database',
    native: DriftNativeOptions(databasePath: () async => path),
  );
}
