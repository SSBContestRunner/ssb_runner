import 'package:drift/drift.dart';

class QsoTable extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get utcInSeconds => integer()();
  TextColumn get runId => text()();
  TextColumn get stationCallsign => text()();

  TextColumn get callsign => text()();
  TextColumn get callsignCorrect => text()();
  TextColumn get exchange => text()();
  TextColumn get exchangeCorrect => text()();
}
