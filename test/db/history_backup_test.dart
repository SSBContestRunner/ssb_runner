import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/db/app_database.dart';
import 'package:ssb_runner/db/history_backup.dart';
import 'package:ssb_runner/training/session_review.dart';
import 'package:ssb_runner/training/training_profile.dart';

Map<String, Object?> _minimalBackup({
  int schemaVersion = 7,
  String format = 'ssb-runner-history',
  Map<String, int>? counts,
}) {
  return <String, Object?>{
    'format': format,
    'formatVersion': 1,
    'schemaVersion': schemaVersion,
    'appVersion': '0.3.0',
    'buildNumber': '300001',
    'exportedAt': DateTime.utc(2026, 11, 10).toIso8601String(),
    'counts':
        counts ?? <String, int>{'qso': 0, 'eventLog': 0, 'sessionReview': 0},
    'qso': <Object?>[],
    'eventLog': <Object?>[],
    'sessionReviews': <Object?>[],
  };
}

TrainingRunReview _review() {
  final metadata = TrainingRunMetadata(
    runId: 'run-1',
    contestId: 'CQ-WPX',
    contestName: 'CQ WPX SSB',
    modeId: TrainingMode.run.id,
    difficultyId: TrainingDifficulty.standard.id,
    questionSeed: 7,
    audioSeed: 7,
    startedAt: DateTime.utc(2026, 11, 10, 10),
  );
  return TrainingRunReview.fromQsos(
    metadata: metadata,
    qsos: const <QsoTableData>[],
    score: 0,
    endReason: 'stopped',
  );
}

void main() {
  test('history backup round-trips rows and session reviews', () async {
    final source = AppDatabase(NativeDatabase.memory());
    addTearDown(source.close);

    await source
        .into(source.qsoTable)
        .insert(
          QsoTableCompanion.insert(
            id: const Value(7),
            utcInSeconds: 12,
            runId: 'run-1',
            stationCallsign: 'MYCALL',
            callsign: 'K1ABC',
            callsignCorrect: 'K1ABC',
            exchange: '001',
            exchangeCorrect: '001',
            accentDir: const Value('US'),
            phonicType: const Value('standard'),
          ),
        );
    await source
        .into(source.eventLogTable)
        .insert(
          EventLogTableCompanion.insert(
            id: const Value(3),
            runId: 'run-1',
            elapsedMs: 100,
            eventType: 'answer',
            payload: '{"callsign":"K1ABC"}',
            createdAtUtc: 1234,
          ),
        );

    final exported = await createHistoryBackup(
      source,
      sessionReviews: <TrainingRunReview>[_review()],
      appVersion: '0.3.0',
      buildNumber: '300001',
    );
    expect(exported.qsoCount, 1);
    expect(exported.eventCount, 1);

    final parsed = parseHistoryBackup(exported.bytes);
    expect(parsed.qsoCount, 1);
    expect(parsed.eventCount, 1);
    expect(parsed.sessionReviewCount, 1);
    expect(parsed.qsos.single.callsign, 'K1ABC');
    expect(parsed.qsos.single.accentDir, 'US');
    expect(parsed.events.single.runId, 'run-1');

    final target = AppDatabase(NativeDatabase.memory());
    addTearDown(target.close);
    List<TrainingRunReview>? restoredReviews;

    await restoreHistoryBackup(
      target,
      parsed,
      replaceSessionHistory: (reviews) async {
        restoredReviews = reviews;
      },
    );

    final qsos = await target.qsoTable.select().get();
    expect(qsos.single.id, 7);
    expect(qsos.single.callsign, 'K1ABC');
    final events = await target.eventLogTable.select().get();
    expect(events.single.id, 3);
    expect(events.single.eventType, 'answer');
    expect(restoredReviews, hasLength(1));
    expect(restoredReviews!.single.metadata.runId, 'run-1');
  });

  test('restore replaces existing history instead of appending', () async {
    final target = AppDatabase(NativeDatabase.memory());
    addTearDown(target.close);

    await target
        .into(target.qsoTable)
        .insert(
          QsoTableCompanion.insert(
            utcInSeconds: 1,
            runId: 'old-run',
            stationCallsign: 'MYCALL',
            callsign: 'OLD',
            callsignCorrect: 'OLD',
            exchange: '1',
            exchangeCorrect: '1',
          ),
        );

    final backup = parseHistoryBackup(
      utf8.encode(jsonEncode(_minimalBackup())),
    );
    await restoreHistoryBackup(
      target,
      backup,
      replaceSessionHistory: (_) async {},
    );

    expect(await target.qsoTable.select().get(), isEmpty);
  });

  test('raw JSON backups are accepted', () {
    final backup = parseHistoryBackup(
      utf8.encode(jsonEncode(_minimalBackup())),
    );
    expect(backup.schemaVersion, 7);
    expect(backup.qsoCount, 0);
  });

  test('rejects a backup written by a newer schema', () {
    expect(
      () => parseHistoryBackup(
        utf8.encode(jsonEncode(_minimalBackup(schemaVersion: 99))),
      ),
      throwsA(
        isA<HistoryBackupException>().having(
          (error) => error.createdByNewerVersion,
          'createdByNewerVersion',
          isTrue,
        ),
      ),
    );
  });

  test('rejects an unknown format and a count mismatch', () {
    expect(
      () => parseHistoryBackup(
        utf8.encode(jsonEncode(_minimalBackup(format: 'something-else'))),
      ),
      throwsA(isA<HistoryBackupException>()),
    );
    expect(
      () => parseHistoryBackup(
        utf8.encode(
          jsonEncode(
            _minimalBackup(
              counts: <String, int>{
                'qso': 3,
                'eventLog': 0,
                'sessionReview': 0,
              },
            ),
          ),
        ),
      ),
      throwsA(isA<HistoryBackupException>()),
    );
  });

  test('rejects garbage instead of writing a partial history', () {
    expect(
      () => parseHistoryBackup(utf8.encode('not a backup')),
      throwsA(isA<HistoryBackupException>()),
    );
    expect(
      () => parseHistoryBackup(const <int>[0x50, 0x4B, 0x03, 0x04, 0x00]),
      throwsA(isA<HistoryBackupException>()),
    );
  });
}
