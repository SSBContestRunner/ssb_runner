import 'package:drift/drift.dart';
import 'package:ssb_runner/db/table/event_log_table.dart';
import 'package:ssb_runner/db/table/prefix_table.dart';
import 'package:ssb_runner/db/table/qso_table.dart';
import 'package:ssb_runner/platform/database/database_connection.dart';

part 'app_database.g.dart';

/// Current on-disk schema version.
///
/// History backups carry it so an import can reject a file written by a newer
/// build instead of silently dropping columns.
const int appDatabaseSchemaVersion = 7;

@DriftDatabase(tables: [PrefixTable, QsoTable, EventLogTable])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? openPlatformDatabaseConnection());

  @override
  int get schemaVersion => appDatabaseSchemaVersion;

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
      // v6 ships the 20261102 cty.dat update; drop the cached prefixes so the
      // next loadDxcc() re-parses the new asset.
      if (from < 6) {
        await delete(prefixTable).go();
      }
      // v7 adds the QSO voice replay metadata. The columns are nullable so
      // rows logged before this version stay readable and are marked as
      // legacy (not replayable) by the UI.
      if (from < 7) {
        await migrator.addColumn(qsoTable, qsoTable.accentDir);
        await migrator.addColumn(qsoTable, qsoTable.phonicType);
        await migrator.addColumn(qsoTable, qsoTable.callPhonicDirs);
        await migrator.addColumn(qsoTable, qsoTable.exchangePhonicDirs);
      }
    },
  );
}
