import 'package:ssb_runner/db/app_database.dart';
import 'package:ssb_runner/platform/database/web_database_state.dart';

import 'database_status.dart';

export 'database_status.dart';

/// Forces the WASM connection open and rejects a silent in-memory fallback.
///
/// A memory database would "work" until the tab closes, so it must become a
/// retryable startup error instead of quietly losing the user's history.
Future<DatabaseHealth> verifyDatabaseHealth(AppDatabase database) async {
  try {
    await database.customSelect('SELECT 1').getSingle();
  } catch (error) {
    return DatabaseHealth(error: '$error', persistent: false);
  }

  final implementation = webDatabaseImplementation;
  if (implementation == null) {
    return const DatabaseHealth(
      error: 'database did not report a storage implementation',
      persistent: false,
    );
  }
  if (!webDatabasePersistent) {
    return DatabaseHealth(
      error: 'database fell back to in-memory storage',
      implementation: implementation,
      persistent: false,
    );
  }

  return DatabaseHealth(implementation: implementation);
}
