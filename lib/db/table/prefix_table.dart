import 'package:drift/drift.dart';

class PrefixTable extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get call => text()();
  IntColumn get dxccId => integer()();
}