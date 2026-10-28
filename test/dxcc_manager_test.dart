import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/db/app_database.dart';
import 'package:ssb_runner/dxcc/dxcc_manager.dart';
import 'package:ssb_runner/dxcc/prefix_row.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('seeds from bundled data, then reuses the db snapshot', () async {
    final first = DxccManager(database: db);
    await first.loadDxcc();
    expect(await db.select(db.prefixTable).get(), isNotEmpty);

    final second = DxccManager(database: db);
    await second.loadDxcc();

    expect(second.findCallsignDxccId('K1ABC'), 291);
    expect(second.findCallsignCqZone('K1ABC'), 5);
    expect(second.findCallsignItuZone('K1ABC'), 8);
    expect(second.findCallSignContinent('K1ABC'), 'NA');
    expect(
      second.findCallsignDxccId('K1ABC'),
      first.findCallsignDxccId('K1ABC'),
    );
  });

  test('falls back to shorter prefixes and reports misses', () async {
    final dxcc = DxccManager(database: db);
    await dxcc.loadDxcc();

    // The `K1` prefix has no own row, so the walk back to `K` answers.
    expect(dxcc.findCallsignDxccId('K1ABC'), 291);
    expect(dxcc.findCallsignDxccId('QQQQQ'), -1);
    expect(dxcc.findCallsignCqZone('QQQQQ'), isNull);
    expect(dxcc.findCallsignItuZone('QQQQQ'), isNull);
    expect(dxcc.findCallSignContinent('QQQQQ'), '');
  });

  test('a populated database is used instead of bundled data', () async {
    await DxccManager(database: db).replacePrefixes(const <PrefixRow>[
      PrefixRow(call: 'ZZ', dxccId: 999, continent: 'AF'),
    ]);

    final dxcc = DxccManager(database: db);
    await dxcc.loadDxcc();

    expect(dxcc.findCallsignDxccId('ZZ1ABC'), 999);
    expect(dxcc.findCallsignDxccId('K1ABC'), -1);
    // The snapshot is not overwritten by the bundled seed.
    expect((await db.select(db.prefixTable).get()).length, 1);
  });

  test('replacePrefixes rolls back when a row fails', () async {
    final dxcc = DxccManager(database: db);
    await dxcc.replacePrefixes(const <PrefixRow>[
      PrefixRow(call: 'K', dxccId: 291, continent: 'NA', cqz: 5, ituz: 8),
    ]);
    expect((await db.select(db.prefixTable).get()).length, 1);

    await db.customStatement(
      'CREATE TRIGGER fail_bad_call BEFORE INSERT ON prefix_table '
      "WHEN NEW.call = 'BAD' BEGIN SELECT RAISE(ABORT, 'boom'); END;",
    );

    await expectLater(
      dxcc.replacePrefixes(const <PrefixRow>[
        PrefixRow(call: 'AA', dxccId: 1, continent: 'NA'),
        PrefixRow(call: 'BAD', dxccId: 2, continent: 'NA'),
      ]),
      throwsA(anything),
    );

    final rows = await db.select(db.prefixTable).get();
    expect(rows.map((row) => row.call), <String>['K']);
  });

  test('an unusable database still resolves from bundled data', () async {
    final closed = AppDatabase(NativeDatabase.memory());
    await closed.close();

    final dxcc = DxccManager(database: closed);
    await dxcc.loadDxcc();

    expect(dxcc.findCallsignDxccId('K1ABC'), 291);
  });
}
