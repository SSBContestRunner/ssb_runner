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

  test('the leading segment wins for portable calls', () async {
    final dxcc = DxccManager(database: db);
    await dxcc.loadDxcc();

    expect(dxcc.findCallsignDxccId('9A/DF2AJ'), 497);
    expect(dxcc.findCallsignCqZone('9A/DF2AJ'), 15);
    expect(dxcc.findCallsignItuZone('9A/DF2AJ'), 28);

    expect(dxcc.findCallsignDxccId('F/DL3HAH'), 227);
    expect(dxcc.findCallsignDxccId('4W/K7CO'), 511);
    expect(dxcc.findCallsignDxccId('ZA/F4GFE'), 7);
    expect(dxcc.findCallsignDxccId('OZ/DJ1XT'), 221);
    expect(dxcc.findCallsignDxccId('OH/G1UZD'), 224);

    // PY0F is its own table token; it must not be truncated to PY0 / PY.
    expect(dxcc.findCallsignDxccId('PY0F/AA4NC'), 56);
    expect(dxcc.findCallsignCqZone('PY0F/AA4NC'), 11);
    expect(dxcc.findCallsignItuZone('PY0F/AA4NC'), 13);

    // A /digit area suffix still follows the leading segment, which carries
    // the Russian call area (R9XC -> R9X -> European Russia).
    expect(dxcc.findCallsignDxccId('R9XC/1'), 54);
  });

  test('portable suffixes do not change the leading segment result', () async {
    final dxcc = DxccManager(database: db);
    await dxcc.loadDxcc();

    final base = dxcc.findCallsignDxccId('DL0AB');
    for (final suffix in <String>['P', 'M', 'MM', 'QRP', '1']) {
      expect(dxcc.findCallsignDxccId('DL0AB/$suffix'), base);
    }

    expect(dxcc.findCallsignDxccId('W1ABC/7'), 291);
    expect(dxcc.findCallsignDxccId('K1ABC/M'), 291);

    // /P must not drag an Asiatic Russian call into European Russia.
    expect(dxcc.findCallsignDxccId('R9GM/P'), 15);
    expect(dxcc.findCallsignCqZone('R9GM/P'), 17);
    expect(dxcc.findCallsignItuZone('R9GM/P'), 30);
  });

  test('an unresolvable call falls back to the longest table token', () async {
    final dxcc = DxccManager(database: db);
    await dxcc.loadDxcc();

    // The regex reads VP2EAD as VP2, which has no row; VP2E is a token of its
    // own and must win over the shorter VP2.
    expect(dxcc.findCallsignDxccId('VP2EAD'), 12);
    expect(dxcc.findCallsignCqZone('VP2EAD'), 8);
    expect(dxcc.findCallsignItuZone('VP2EAD'), 11);
    expect(dxcc.findCallsignDxccId('VP2MAA'), 96);
    expect(dxcc.findCallsignDxccId('VP2VGG'), 65);

    // Bare entity prefixes were misses too.
    expect(dxcc.findCallsignDxccId('VP2E'), 12);
    expect(dxcc.findCallsignDxccId('VP2M'), 96);
    expect(dxcc.findCallsignDxccId('VP2E/W1ABC'), 12);
  });

  test('a resolved call never takes the token fallback', () async {
    final dxcc = DxccManager(database: db);
    await dxcc.loadDxcc();

    // 4U1U is the longer token, yet 4U1UN already answers from the regex path.
    expect(dxcc.findCallsignDxccId('4U1UN'), 248);
    // The slash rule and the legacy rule are untouched by the new branch.
    expect(dxcc.findCallsignDxccId('9A/DF2AJ'), 497);
    expect(dxcc.findCallsignDxccId('K1ABC'), 291);
  });

  test('a call that equals a table token is answered exactly', () async {
    final dxcc = DxccManager(database: db);
    await dxcc.loadDxcc();

    // Bare PY0F is the table token, not the PY0 regex match (Brazil).
    expect(dxcc.findCallsignDxccId('PY0F'), 56);
    expect(dxcc.findCallsignCqZone('PY0F'), 11);
    expect(dxcc.findCallsignItuZone('PY0F'), 13);
    expect(dxcc.findCallsignDxccId('PW0F'), 56);
  });

  test(
    'the token fallback ignores tokens shorter than three characters',
    () async {
      final dxcc = DxccManager(database: db);
      await dxcc.loadDxcc();

      // 4G and 7Q are table tokens, but too short to identify these calls.
      expect(dxcc.findCallsignDxccId('4GRID'), -1);
      expect(dxcc.findCallsignDxccId('7QAA'), -1);
      expect(dxcc.findCallsignDxccId('7QNL'), -1);
    },
  );

  test(
    'falls back to the legacy whole-call lookup when the main call misses',
    () async {
      final dxcc = DxccManager(database: db);
      await dxcc.loadDxcc();

      // QQQQ has no row, so the old whole-call extraction answers with K1.
      expect(dxcc.findCallsignDxccId('QQQQ/K1ABC'), 291);
      expect(dxcc.findCallsignDxccId('QQQQQ'), -1);
    },
  );
}
