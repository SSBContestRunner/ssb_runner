import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:ssb_runner/db/database_bootstrap.dart';
import 'package:ssb_runner/db/table/event_log_table.dart';
import 'package:ssb_runner/db/table/prefix_table.dart';
import 'package:ssb_runner/db/table/qso_table.dart';

part 'app_database.g.dart';

const _schemaVersion = 5;

@DriftDatabase(tables: [PrefixTable, QsoTable, EventLogTable])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => _schemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
    },
    onUpgrade: (migrator, from, to) async {
      // v2 added the training event log; keep existing QSO/prefix rows.
      if (from < 2) {
        await migrator.createTable(eventLogTable);
      }
      // v3 adds the cty zone columns. Drop the cached prefixes so the next
      // loadDxcc() re-parses the asset and fills them.
      if (from < 3) {
        await migrator.addColumn(prefixTable, prefixTable.cqz);
        await migrator.addColumn(prefixTable, prefixTable.ituz);
        await delete(prefixTable).go();
      }
      // v4 ships ITU zones in the cty asset; drop the cached prefixes so the
      // next loadDxcc() re-parses them.
      if (from < 4) {
        await delete(prefixTable).go();
      }
      // v5 rebuilds the cty asset from cty.dat (correct entity ids); same
      // reload applies.
      if (from < 5) {
        await delete(prefixTable).go();
      }
    },
  );

  static DatabaseConnection _openConnection() {
    return DatabaseConnection.delayed(_connect());
  }

  /// Opens the database in the directory resolved by [ensureDatabaseReady],
  /// or in memory when no writable directory exists.
  static Future<DatabaseConnection> _connect() async {
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
}
