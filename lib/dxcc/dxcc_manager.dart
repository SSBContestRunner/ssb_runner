import 'package:drift/drift.dart' show Value;
import 'package:ssb_runner/db/app_database.dart';
import 'package:ssb_runner/dxcc/generated/prefix_data.g.dart';
import 'package:ssb_runner/dxcc/prefix_data.dart';
import 'package:ssb_runner/dxcc/prefix_row.dart';
import 'package:ssb_runner/logging/app_logger.dart';

class DxccManager {
  final AppDatabase database;

  DxccManager({required this.database});

  /// Prefix lookup table; empty until [loadDxcc] succeeds.
  Map<String, PrefixRow> _prefixByCall = const <String, PrefixRow>{};

  int findCallsignDxccId(String callsign) =>
      _findMatch(callsign)?.dxccId ?? -1;

  /// CQ zone for a callsign, or null when the cty data has no match.
  int? findCallsignCqZone(String callsign) => _findMatch(callsign)?.cqz;

  /// ITU zone for a callsign, or null when the cty data has no match.
  int? findCallsignItuZone(String callsign) => _findMatch(callsign)?.ituz;

  String findCallSignContinent(String callsign) =>
      _findMatch(callsign)?.continent ?? '';

  /// Slash-aware lookup; the rule itself lives in
  /// [lookupCallsignPrefix] so tools can reuse it without a database.
  PrefixRow? _findMatch(String callsign) =>
      lookupCallsignPrefix(_prefixByCall, callsign);

  Future<void> loadDxcc() async {
    final snapshot = await _loadSnapshot();
    if (snapshot.isNotEmpty) {
      _assign(snapshot);
      log.info(
        'dxcc loaded',
        tag: 'dxcc',
        fields: <String, Object?>{'source': 'db', 'rows': snapshot.length},
      );
      return;
    }

    final bundled = parsePrefixRows(dxccPrefixTsv);
    try {
      await replacePrefixes(bundled);
    } catch (error, stackTrace) {
      // The cache only saves the next launch some parsing; lookups still work
      // from the in-memory rows.
      log.warn(
        'dxcc cache write failed, continuing without cache',
        tag: 'dxcc',
        error: error,
        stackTrace: stackTrace,
      );
    }
    _assign(bundled);
    log.info(
      'dxcc loaded',
      tag: 'dxcc',
      fields: <String, Object?>{
        'source': 'bundled',
        'rows': bundled.length,
        'dataVersion': dxccBundledDataVersion,
      },
    );
  }

  /// The only database read path; empty when the database is unusable.
  Future<List<PrefixRow>> _loadSnapshot() async {
    try {
      final rows = await database.select(database.prefixTable).get();
      return <PrefixRow>[
        for (final row in rows)
          PrefixRow(
            call: row.call,
            dxccId: row.dxccId,
            continent: row.continent,
            cqz: row.cqz,
            ituz: row.ituz,
          ),
      ];
    } catch (error, stackTrace) {
      log.warn(
        'dxcc cache read failed, loading bundled data',
        tag: 'dxcc',
        error: error,
        stackTrace: stackTrace,
      );
      return const <PrefixRow>[];
    }
  }

  /// Atomically replaces the whole prefix table, so a failure leaves the
  /// previous snapshot (or an empty table) intact.
  ///
  /// Shared by the first-run seed and, later, by hot updates.
  Future<void> replacePrefixes(List<PrefixRow> prefixes) async {
    if (prefixes.isEmpty) {
      return;
    }

    await database.transaction(() async {
      await database.delete(database.prefixTable).go();
      await database.batch((batch) {
        batch.insertAll(database.prefixTable, <PrefixTableCompanion>[
          for (final prefix in prefixes)
            PrefixTableCompanion.insert(
              call: prefix.call,
              dxccId: prefix.dxccId,
              continent: prefix.continent,
              cqz: Value(prefix.cqz),
              ituz: Value(prefix.ituz),
            ),
        ]);
      });
    });
  }

  /// Replaces the in-memory rows, independent of where they came from.
  void reload(List<PrefixRow> prefixes) => _assign(prefixes);

  void _assign(List<PrefixRow> prefixes) {
    final byCall = <String, PrefixRow>{};
    for (final prefix in prefixes) {
      if (byCall.containsKey(prefix.call)) {
        log.warn(
          'duplicate dxcc prefix',
          tag: 'dxcc',
          fields: <String, Object?>{'call': prefix.call},
        );
        continue;
      }
      byCall[prefix.call] = prefix;
    }
    _prefixByCall = byCall;
  }
}
