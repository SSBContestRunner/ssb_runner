import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart';
import 'package:ssb_runner/db/app_database.dart';
import 'package:ssb_runner/training/session_review.dart';

const String _format = 'ssb-runner-history';
const int _formatVersion = 1;
const String _historyEntryName = 'history.json';

/// Oldest schema a backup may come from. v2 is the first version with the
/// training event log, which replay needs.
const int _minSupportedSchemaVersion = 2;

/// Raised when a file is not a backup this build can import.
class HistoryBackupException implements Exception {
  const HistoryBackupException(
    this.message, {
    this.createdByNewerVersion = false,
  });

  final String message;

  /// True when the file is well-formed but written by a newer build.
  final bool createdByNewerVersion;

  @override
  String toString() => message;
}

/// In-memory backup produced for the save dialog.
class HistoryBackupExport {
  const HistoryBackupExport({
    required this.fileName,
    required this.bytes,
    required this.qsoCount,
    required this.eventCount,
  });

  final String fileName;
  final List<int> bytes;
  final int qsoCount;
  final int eventCount;
}

/// Validated contents of a history backup.
class HistoryBackup {
  const HistoryBackup({
    required this.schemaVersion,
    required this.appVersion,
    required this.buildNumber,
    required this.exportedAt,
    required this.qsos,
    required this.events,
    required this.sessionReviews,
  });

  final int schemaVersion;
  final String appVersion;
  final String buildNumber;
  final DateTime exportedAt;
  final List<QsoTableData> qsos;
  final List<EventLogTableData> events;
  final List<TrainingRunReview> sessionReviews;

  int get qsoCount => qsos.length;
  int get eventCount => events.length;
  int get sessionReviewCount => sessionReviews.length;
}

/// Reads the whole history and wraps it in a zip with a JSON manifest.
Future<HistoryBackupExport> createHistoryBackup(
  AppDatabase database, {
  required List<TrainingRunReview> sessionReviews,
  required String appVersion,
  required String buildNumber,
}) async {
  final qsos = await (database.select(
    database.qsoTable,
  )..orderBy([(row) => OrderingTerm.asc(row.id)])).get();
  final events = await (database.select(
    database.eventLogTable,
  )..orderBy([(row) => OrderingTerm.asc(row.id)])).get();

  final payload = <String, Object?>{
    'format': _format,
    'formatVersion': _formatVersion,
    'schemaVersion': appDatabaseSchemaVersion,
    'appVersion': appVersion,
    'buildNumber': buildNumber,
    'exportedAt': DateTime.now().toUtc().toIso8601String(),
    'counts': <String, int>{
      'qso': qsos.length,
      'eventLog': events.length,
      'sessionReview': sessionReviews.length,
    },
    'qso': [for (final row in qsos) _qsoToJson(row)],
    'eventLog': [for (final row in events) _eventToJson(row)],
    'sessionReviews': [for (final review in sessionReviews) review.encode()],
  };

  final archive = Archive()
    ..addFile(ArchiveFile.string(_historyEntryName, jsonEncode(payload)));

  return HistoryBackupExport(
    fileName: 'ssb-runner-history-${_timestamp()}.zip',
    bytes: ZipEncoder().encode(archive),
    qsoCount: qsos.length,
    eventCount: events.length,
  );
}

/// Parses and validates [bytes] without touching the database.
///
/// Every field is checked before anything is written, so a malformed file can
/// never leave a half-restored history behind.
HistoryBackup parseHistoryBackup(List<int> bytes) {
  if (bytes.isEmpty) {
    throw const HistoryBackupException('empty file');
  }

  final jsonBytes = _extractJsonBytes(bytes);
  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(jsonBytes));
  } on Object {
    throw const HistoryBackupException('history.json is not valid JSON');
  }

  final root = _requireMap(decoded, 'root');
  if (root['format'] != _format) {
    throw const HistoryBackupException('unknown backup format');
  }

  final formatVersion = _requireInt(root['formatVersion'], 'formatVersion');
  if (formatVersion > _formatVersion) {
    throw const HistoryBackupException(
      'backup format is newer than this build',
      createdByNewerVersion: true,
    );
  }
  if (formatVersion != _formatVersion) {
    throw const HistoryBackupException('unsupported backup format version');
  }

  final schemaVersion = _requireInt(root['schemaVersion'], 'schemaVersion');
  if (schemaVersion > appDatabaseSchemaVersion) {
    throw const HistoryBackupException(
      'backup schema is newer than this build',
      createdByNewerVersion: true,
    );
  }
  if (schemaVersion < _minSupportedSchemaVersion) {
    throw const HistoryBackupException('backup schema is too old');
  }

  final exportedAt = _requireDate(root['exportedAt'], 'exportedAt');
  final appVersion = _optionalString(root['appVersion']) ?? '';
  final buildNumber = _optionalString(root['buildNumber']) ?? '';

  final qsoJson = _requireList(root['qso'], 'qso');
  final eventJson = _requireList(root['eventLog'], 'eventLog');
  final reviewJson = _requireList(root['sessionReviews'], 'sessionReviews');

  final qsos = <QsoTableData>[
    for (var index = 0; index < qsoJson.length; index++)
      _qsoFromJson(qsoJson[index], index),
  ];
  final events = <EventLogTableData>[
    for (var index = 0; index < eventJson.length; index++)
      _eventFromJson(eventJson[index], index),
  ];
  final reviews = <TrainingRunReview>[
    for (final item in reviewJson) _reviewFromJson(item),
  ];

  _validateUniqueIds(qsos.map((row) => row.id), 'qso');
  _validateUniqueIds(events.map((row) => row.id), 'eventLog');

  final counts = root['counts'];
  if (counts != null) {
    final map = _requireMap(counts, 'counts');
    _validateCount(map['qso'], qsos.length, 'qso');
    _validateCount(map['eventLog'], events.length, 'eventLog');
    _validateCount(map['sessionReview'], reviews.length, 'sessionReview');
  }

  return HistoryBackup(
    schemaVersion: schemaVersion,
    appVersion: appVersion,
    buildNumber: buildNumber,
    exportedAt: exportedAt,
    qsos: qsos,
    events: events,
    sessionReviews: reviews,
  );
}

/// Replaces the database rows and the session list with [backup].
///
/// The prefix table is a cache rebuilt from the bundled cty data, so it is
/// cleared instead of restored.
Future<void> restoreHistoryBackup(
  AppDatabase database,
  HistoryBackup backup, {
  required Future<void> Function(List<TrainingRunReview>) replaceSessionHistory,
}) async {
  await database.transaction(() async {
    await database.delete(database.qsoTable).go();
    await database.delete(database.eventLogTable).go();
    await database.delete(database.prefixTable).go();

    await database.batch((batch) {
      batch.insertAll(database.qsoTable, [
        for (final row in backup.qsos)
          QsoTableCompanion.insert(
            id: Value(row.id),
            utcInSeconds: row.utcInSeconds,
            runId: row.runId,
            stationCallsign: row.stationCallsign,
            callsign: row.callsign,
            callsignCorrect: row.callsignCorrect,
            exchange: row.exchange,
            exchangeCorrect: row.exchangeCorrect,
            accentDir: Value(row.accentDir),
            phonicType: Value(row.phonicType),
            callPhonicDirs: Value(row.callPhonicDirs),
            exchangePhonicDirs: Value(row.exchangePhonicDirs),
          ),
      ]);
      batch.insertAll(database.eventLogTable, [
        for (final row in backup.events)
          EventLogTableCompanion.insert(
            id: Value(row.id),
            runId: row.runId,
            elapsedMs: row.elapsedMs,
            eventType: row.eventType,
            payload: row.payload,
            createdAtUtc: row.createdAtUtc,
          ),
      ]);
    });
  });

  await replaceSessionHistory(backup.sessionReviews);
}

List<int> _extractJsonBytes(List<int> bytes) {
  final isZip =
      bytes.length >= 4 &&
      bytes[0] == 0x50 &&
      bytes[1] == 0x4B &&
      bytes[2] == 0x03 &&
      bytes[3] == 0x04;
  if (!isZip) {
    return bytes;
  }

  try {
    final archive = ZipDecoder().decodeBytes(bytes);
    for (final file in archive.files) {
      if (file.name == _historyEntryName && file.isFile) {
        return file.content;
      }
    }
  } on Object {
    throw const HistoryBackupException('zip archive is unreadable');
  }

  throw const HistoryBackupException('history.json is missing from the zip');
}

Map<String, Object?> _qsoToJson(QsoTableData row) => <String, Object?>{
  'id': row.id,
  'utcInSeconds': row.utcInSeconds,
  'runId': row.runId,
  'stationCallsign': row.stationCallsign,
  'callsign': row.callsign,
  'callsignCorrect': row.callsignCorrect,
  'exchange': row.exchange,
  'exchangeCorrect': row.exchangeCorrect,
  'accentDir': row.accentDir,
  'phonicType': row.phonicType,
  'callPhonicDirs': row.callPhonicDirs,
  'exchangePhonicDirs': row.exchangePhonicDirs,
};

Map<String, Object?> _eventToJson(EventLogTableData row) => <String, Object?>{
  'id': row.id,
  'runId': row.runId,
  'elapsedMs': row.elapsedMs,
  'eventType': row.eventType,
  'payload': row.payload,
  'createdAtUtc': row.createdAtUtc,
};

QsoTableData _qsoFromJson(Object? value, int index) {
  try {
    final json = _requireMap(value, 'qso[$index]');
    return QsoTableData(
      id: _requirePositiveInt(json['id'], 'qso[$index].id'),
      utcInSeconds: _requireInt(
        json['utcInSeconds'],
        'qso[$index].utcInSeconds',
      ),
      runId: _requireString(json['runId'], 'qso[$index].runId'),
      stationCallsign: _requireString(
        json['stationCallsign'],
        'qso[$index].stationCallsign',
      ),
      callsign: _requireString(json['callsign'], 'qso[$index].callsign'),
      callsignCorrect: _requireString(
        json['callsignCorrect'],
        'qso[$index].callsignCorrect',
      ),
      exchange: _requireString(json['exchange'], 'qso[$index].exchange'),
      exchangeCorrect: _requireString(
        json['exchangeCorrect'],
        'qso[$index].exchangeCorrect',
      ),
      accentDir: _optionalString(json['accentDir']),
      phonicType: _optionalString(json['phonicType']),
      callPhonicDirs: _optionalString(json['callPhonicDirs']),
      exchangePhonicDirs: _optionalString(json['exchangePhonicDirs']),
    );
  } on HistoryBackupException {
    rethrow;
  } on Object {
    throw HistoryBackupException('qso[$index] is malformed');
  }
}

EventLogTableData _eventFromJson(Object? value, int index) {
  try {
    final json = _requireMap(value, 'eventLog[$index]');
    return EventLogTableData(
      id: _requirePositiveInt(json['id'], 'eventLog[$index].id'),
      runId: _requireString(json['runId'], 'eventLog[$index].runId'),
      elapsedMs: _requireInt(json['elapsedMs'], 'eventLog[$index].elapsedMs'),
      eventType: _requireString(
        json['eventType'],
        'eventLog[$index].eventType',
      ),
      payload: _requireString(json['payload'], 'eventLog[$index].payload'),
      createdAtUtc: _requireInt(
        json['createdAtUtc'],
        'eventLog[$index].createdAtUtc',
      ),
    );
  } on HistoryBackupException {
    rethrow;
  } on Object {
    throw HistoryBackupException('eventLog[$index] is malformed');
  }
}

TrainingRunReview _reviewFromJson(Object? value) {
  final source = _requireString(value, 'sessionReviews[]');
  try {
    return TrainingRunReview.decode(source);
  } on Object {
    throw const HistoryBackupException('session review is malformed');
  }
}

Map<String, Object?> _requireMap(Object? value, String path) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, item) => MapEntry<String, Object?>('$key', item));
  }
  throw HistoryBackupException('$path is not an object');
}

List<Object?> _requireList(Object? value, String path) {
  if (value is List) {
    return value;
  }
  throw HistoryBackupException('$path is not a list');
}

int _requireInt(Object? value, String path) {
  if (value is int) {
    return value;
  }
  if (value is num && value == value.truncate()) {
    return value.toInt();
  }
  throw HistoryBackupException('$path is not an integer');
}

int _requirePositiveInt(Object? value, String path) {
  final parsed = _requireInt(value, path);
  if (parsed <= 0) {
    throw HistoryBackupException('$path must be positive');
  }
  return parsed;
}

String _requireString(Object? value, String path) {
  if (value is String) {
    return value;
  }
  throw HistoryBackupException('$path is not a string');
}

String? _optionalString(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is String) {
    return value;
  }
  throw HistoryBackupException('optional string has the wrong type');
}

DateTime _requireDate(Object? value, String path) {
  final text = _requireString(value, path);
  final parsed = DateTime.tryParse(text);
  if (parsed == null) {
    throw HistoryBackupException('$path is not a timestamp');
  }
  return parsed.toUtc();
}

void _validateCount(Object? value, int actual, String name) {
  if (_requireInt(value, 'counts.$name') != actual) {
    throw HistoryBackupException('counts.$name does not match the rows');
  }
}

void _validateUniqueIds(Iterable<int> ids, String name) {
  final seen = <int>{};
  for (final id in ids) {
    if (!seen.add(id)) {
      throw HistoryBackupException('$name contains duplicate ids');
    }
  }
}

String _timestamp() {
  final now = DateTime.now();
  String two(int value) => value.toString().padLeft(2, '0');

  return '${now.year}${two(now.month)}${two(now.day)}'
      '-${two(now.hour)}${two(now.minute)}${two(now.second)}';
}
