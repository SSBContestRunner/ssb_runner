import 'package:drift/drift.dart';

class QsoTable extends Table {

  IntColumn get id => integer().autoIncrement()();
  TextColumn get runId => text()();
  TextColumn get callsign => text()();
  TextColumn get stationCallsign=> text()();
  TextColumn get exchangeRecv => text()();
  TextColumn get exchangeSent => text()();
  IntColumn get rstSent => integer()();
  IntColumn get rstRecv => integer()();
}