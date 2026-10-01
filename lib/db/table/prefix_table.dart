import 'package:drift/drift.dart';

class PrefixTable extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get call => text()();
  IntColumn get dxccId => integer()();
  TextColumn get continent => text()();

  /// CQ zone from the cty database; used to default the CQ WW / JIDX exchange.
  IntColumn get cqz => integer().nullable()();

  /// ITU zone (reserved; the bundled cty asset has no ituz field yet).
  IntColumn get ituz => integer().nullable()();
}
