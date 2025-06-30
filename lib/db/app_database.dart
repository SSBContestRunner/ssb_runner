import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:ssb_contest_runner/db/table/prefix_table.dart';
import 'package:ssb_contest_runner/db/table/qso_table.dart';

part 'app_database.g.dart';

const _schemaVerion = 1;

@DriftDatabase(tables: [PrefixTable, QsoTable])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => _schemaVerion;

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'scr_database');
  }
}
