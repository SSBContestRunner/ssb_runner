import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:ssb_runner/common/dirs.dart';
import 'package:ssb_runner/db/table/prefix_table.dart';
import 'package:ssb_runner/db/table/qso_table.dart';

part 'app_database.g.dart';

const _schemaVersion = 1;

@DriftDatabase(tables: [PrefixTable, QsoTable])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => _schemaVersion;

  static QueryExecutor _openConnection() {
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
