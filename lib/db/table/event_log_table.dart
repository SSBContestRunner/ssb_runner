import 'package:drift/drift.dart';

/// Append-only record of the answers served in one training run. The replay
/// engine reads this log first, so history stays replayable even if the answer
/// generator changes later (design §5.5).
class EventLogTable extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get runId => text()();
  IntColumn get elapsedMs => integer()();

  /// answer / submit / nocopy / worked-before
  TextColumn get eventType => text()();

  /// JSON: callsign / exchange / pileupCallsigns / mode
  TextColumn get payload => text()();
  IntColumn get createdAtUtc => integer()();
}
