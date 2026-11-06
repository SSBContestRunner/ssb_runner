import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/db/app_database.dart';

const _replayColumns = [
  'accent_dir',
  'phonic_type',
  'call_phonic_dirs',
  'exchange_phonic_dirs',
];

/// Builds an in-memory database with the schema of [version] and sets
/// `user_version`, so opening it with [AppDatabase] exercises `onUpgrade`.
QueryExecutor _legacyDatabase(
  int version, {
  bool withPrefixRows = true,
  bool withQsoRow = true,
}) {
  return NativeDatabase.memory(
    setup: (db) {
      db.execute(
        'CREATE TABLE "prefix_table" ('
        '"id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
        '"call" TEXT NOT NULL, '
        '"dxcc_id" INTEGER NOT NULL, '
        '"continent" TEXT NOT NULL'
        '${version >= 3 ? ', "cqz" INTEGER, "ituz" INTEGER' : ''}'
        ')',
      );
      db.execute(
        'CREATE TABLE "qso_table" ('
        '"id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
        '"utc_in_seconds" INTEGER NOT NULL, '
        '"run_id" TEXT NOT NULL, '
        '"station_callsign" TEXT NOT NULL, '
        '"callsign" TEXT NOT NULL, '
        '"callsign_correct" TEXT NOT NULL, '
        '"exchange" TEXT NOT NULL, '
        '"exchange_correct" TEXT NOT NULL'
        ')',
      );
      db.execute(
        'CREATE TABLE "event_log_table" ('
        '"id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
        '"run_id" TEXT NOT NULL, '
        '"elapsed_ms" INTEGER NOT NULL, '
        '"event_type" TEXT NOT NULL, '
        '"payload" TEXT NOT NULL, '
        '"created_at_utc" INTEGER NOT NULL'
        ')',
      );

      if (withPrefixRows) {
        db.execute(
          version >= 3
              ? "INSERT INTO prefix_table "
                    "(call, dxcc_id, continent, cqz, ituz) "
                    "VALUES ('K', 291, 'NA', 5, 8)"
              : "INSERT INTO prefix_table (call, dxcc_id, continent) "
                    "VALUES ('K', 291, 'NA')",
        );
      }
      if (withQsoRow) {
        db.execute(
          'INSERT INTO qso_table '
          '(utc_in_seconds, run_id, station_callsign, callsign, '
          'callsign_correct, exchange, exchange_correct) '
          "VALUES (10, 'run-1', 'MYCALL', 'K1ABC', 'K1ABC', '001', '001')",
        );
      }

      db.execute('PRAGMA user_version = $version');
    },
  );
}

Future<List<QueryRow>> _qsoTableInfo(AppDatabase db) =>
    db.customSelect('PRAGMA table_info("qso_table")').get();

void main() {
  test('fresh install uses schema 7 with nullable replay columns', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    expect(db.schemaVersion, 7);
    expect(await db.qsoTable.select().get(), isEmpty);

    final info = await _qsoTableInfo(db);
    for (final name in _replayColumns) {
      final column = info.firstWhere((row) => row.data['name'] == name);
      expect(column.data['type'], 'TEXT');
      expect(column.data['notnull'], 0);
    }
  });

  test('v6 -> v7 keeps rows and adds the four nullable columns', () async {
    final db = AppDatabase(_legacyDatabase(6));
    addTearDown(db.close);

    final qsos = await db.qsoTable.select().get();
    expect(qsos, hasLength(1));
    expect(qsos.single.callsign, 'K1ABC');
    expect(qsos.single.accentDir, isNull);
    expect(qsos.single.phonicType, isNull);
    expect(qsos.single.callPhonicDirs, isNull);
    expect(qsos.single.exchangePhonicDirs, isNull);

    final info = await _qsoTableInfo(db);
    for (final name in _replayColumns) {
      final column = info.firstWhere((row) => row.data['name'] == name);
      expect(column.data['notnull'], 0);
    }
  });

  test('v6 -> v7 does not clear prefix_table', () async {
    final db = AppDatabase(_legacyDatabase(6));
    addTearDown(db.close);

    expect(await db.prefixTable.select().get(), hasLength(1));
  });

  test('v5 -> v7 clears the prefix cache but keeps QSOs', () async {
    final db = AppDatabase(_legacyDatabase(5));
    addTearDown(db.close);

    expect(await db.prefixTable.select().get(), isEmpty);
    expect(await db.qsoTable.select().get(), hasLength(1));
  });

  test('v2 -> v7 upgrade smoke test', () async {
    final db = AppDatabase(_legacyDatabase(2));
    addTearDown(db.close);

    expect(await db.prefixTable.select().get(), isEmpty);
    expect(await db.qsoTable.select().get(), hasLength(1));

    final info = await _qsoTableInfo(db);
    for (final name in _replayColumns) {
      final column = info.firstWhere((row) => row.data['name'] == name);
      expect(column.data['notnull'], 0);
    }
  });

  test('replay metadata round-trips through insert and read', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await db
        .into(db.qsoTable)
        .insert(
          QsoTableCompanion.insert(
            utcInSeconds: 12,
            runId: 'run-2',
            stationCallsign: 'MYCALL',
            callsign: 'JA1ABC',
            callsignCorrect: 'JA1ABC',
            exchange: '028',
            exchangeCorrect: '028',
            accentDir: const Value('JP'),
            phonicType: const Value('mixed'),
            callPhonicDirs: const Value(
              'ICAO,Location,ICAO,Alphabet,ICAO,Number',
            ),
            exchangePhonicDirs: const Value('Number,Number,Number'),
          ),
        );

    final row = (await db.qsoTable.select().get()).single;
    expect(row.accentDir, 'JP');
    expect(row.phonicType, 'mixed');
    expect(row.callPhonicDirs, 'ICAO,Location,ICAO,Alphabet,ICAO,Number');
    expect(row.exchangePhonicDirs, 'Number,Number,Number');
  });
}
