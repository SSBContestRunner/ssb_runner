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

  /// Accent directory the incoming station was heard in. Null on rows logged
  /// before v7, which makes the QSO voice replay unavailable.
  TextColumn get accentDir => text().nullable()();

  /// Phonic mode used when the QSO was played (standard / location / mixed).
  TextColumn get phonicType => text().nullable()();

  /// Resolved phonic directory per callsign character, so a mixed-mode replay
  /// reproduces the exact letters that were heard.
  TextColumn get callPhonicDirs => text().nullable()();

  /// Resolved phonic directory per exchange character.
  TextColumn get exchangePhonicDirs => text().nullable()();
}
