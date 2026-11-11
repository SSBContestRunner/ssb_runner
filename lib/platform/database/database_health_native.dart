import 'package:ssb_runner/db/app_database.dart';

import 'database_status.dart';

export 'database_status.dart';

/// Probes the database once during startup.
Future<DatabaseHealth> verifyDatabaseHealth(AppDatabase database) async {
  try {
    await database.customSelect('SELECT 1').getSingle();
    return const DatabaseHealth(implementation: 'native-file');
  } catch (error) {
    return DatabaseHealth(error: '$error', persistent: false);
  }
}
