import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/contest_type/contest_definition.dart';
import 'package:ssb_runner/db/app_database.dart';
import 'package:ssb_runner/dxcc/dxcc_manager.dart';
import 'package:ssb_runner/training/session_random.dart';

/// Avoids loading the real DXCC table (and the SQLite/asset plumbing behind
/// it); the definitions only need the two lookups below.
class _FakeDxccManager extends DxccManager {
  _FakeDxccManager() : super(database: AppDatabase());

  @override
  int findCallsignDxccId(String callsign) => 0;

  @override
  String findCallSignContinent(String callsign) => 'AS';
}

void main() {
  test('registry exposes the five common SSB training templates', () {
    expect(
      ContestRegistry.all.map((item) => item.id),
      containsAll(<String>[
        'CQ-WPX',
        'CQ-WW-SSB',
        'ARRL-DX',
        'IARU-HF',
        'JIDX-SSB',
      ]),
    );
    expect(ContestRegistry.all, hasLength(5));
  });

  test('byId falls back to CQ-WPX for unknown ids', () {
    expect(ContestRegistry.byId('missing').id, 'CQ-WPX');
    expect(ContestRegistry.byId(null).id, 'CQ-WPX');
  });

  test('every definition creates a usable contest type', () {
    final dxccManager = _FakeDxccManager();

    for (final definition in ContestRegistry.all) {
      final contestType = definition.create(
        stationCallsign: 'BI1ABC',
        dxccManager: dxccManager,
      );

      expect(contestType.scoreCalculator, isNotNull);
      expect(contestType.exchangeManager, isNotNull);
      expect(contestType.allowExchangeRegex, isNotNull);
      expect(
        contestType.exchangeManager.generateExchange(SessionRandom(1)),
        isNotEmpty,
        reason: '${definition.id} must generate an exchange',
      );
    }
  });
}
