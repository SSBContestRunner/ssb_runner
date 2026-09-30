import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:ssb_runner/common/dirs.dart';
import 'package:ssb_runner/db/table/event_log_table.dart';
import 'package:ssb_runner/db/table/prefix_table.dart';
import 'package:ssb_runner/db/table/qso_table.dart';

part 'app_database.g.dart';

const _schemaVersion = 2;

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
    },
  );

  static DatabaseConnection _openConnection() {
    return driftDatabase(
      name: 'ssb_runner_database',
      native: DriftNativeOptions(
        databaseDirectory: () async {
          return '${await getAppDirectory()}/$dirDb';
        },
      ),
    );
  }
}
