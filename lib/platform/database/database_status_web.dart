import 'package:ssb_runner/platform/database/database_bootstrap_web.dart';
import 'package:ssb_runner/platform/database/web_database_state.dart';
import 'package:ssb_runner/platform/web/browser_storage.dart';

import 'database_status.dart';

export 'database_status.dart';

/// Reads the persistence grant and a fresh quota estimate for the Settings row.
Future<DatabaseStorageStatus> readDatabaseStorageStatus() async {
  final bootstrap = await ensureDatabaseReady();
  final estimate = await browserStorageEstimate();

  return DatabaseStorageStatus(
    applicable: true,
    persistent: bootstrap.persistent,
    implementation: webDatabaseImplementation ?? bootstrap.implementation,
    quota: estimate?.quota,
    usage: estimate?.usage,
  );
}
