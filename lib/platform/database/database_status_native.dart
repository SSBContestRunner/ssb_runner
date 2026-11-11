import 'database_status.dart';

export 'database_status.dart';

/// Desktop history is a normal file, so there is no browser storage control to
/// show in Settings.
Future<DatabaseStorageStatus> readDatabaseStorageStatus() async {
  return const DatabaseStorageStatus();
}
