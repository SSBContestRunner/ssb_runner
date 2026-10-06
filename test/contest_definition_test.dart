import 'package:drift/drift.dart' show LazyDatabase;
import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/contest_type/contest_definition.dart';
import 'package:ssb_runner/contest_type/contest_type.dart';
import 'package:ssb_runner/contest_type/received_exchange.dart';
import 'package:ssb_runner/contest_type/station_exchange.dart';
import 'package:ssb_runner/db/app_database.dart';
import 'package:ssb_runner/dxcc/dxcc_manager.dart';
import 'package:ssb_runner/training/session_random.dart';

/// Avoids loading the real DXCC table; the definitions only need the lookups
/// below.
class _FakeDxccManager extends DxccManager {
  _FakeDxccManager({this.dxccId = 0, this.cqZone = 24, this.ituZone})
    : super(database: AppDatabase(_unusedExecutor()));

  final int dxccId;
  final int? cqZone;
  final int? ituZone;

  @override
  int findCallsignDxccId(String callsign) => dxccId;

  @override
  String findCallSignContinent(String callsign) => 'AS';

  @override
  int? findCallsignCqZone(String callsign) => cqZone;

  @override
  int? findCallsignItuZone(String callsign) => ituZone;
}

ContestType _type(
  String id, {
  StationExchangeConfig config = StationExchangeConfig.empty,
  _FakeDxccManager? dxccManager,
  String stationCallsign = 'BI1QJQ',
}) => ContestRegistry.byId(id).create(
  stationCallsign: stationCallsign,
  dxccManager: dxccManager ?? _FakeDxccManager(),
  stationExchange: config,
);

/// None of these tests touch the database, so a lazy executor keeps them free
/// of platform channels and the native sqlite library.
LazyDatabase _unusedExecutor() => LazyDatabase(
  () async => throw StateError('The DXCC table must not be touched here.'),
);

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
        stationExchange: StationExchangeConfig.empty,
      );

      expect(contestType.scoreCalculator, isNotNull);
      expect(contestType.exchangeManager, isNotNull);
      expect(contestType.allowExchangeRegex, isNotNull);
      expect(
        contestType.exchangeManager.generateExchange(
          SessionRandom(1),
          callerCallsign: 'BI1ABC',
        ),
        isNotEmpty,
        reason: '${definition.id} must generate a received exchange',
      );
    }
  });

  test('the operator exchange is contest specific, not always a serial', () {
    expect(_type('CQ-WPX').buildMyExchange(7), '007');
    expect(_type('CQ-WW-SSB').buildMyExchange(7), '24');
    expect(
      _type(
        'IARU-HF',
        config: const StationExchangeConfig({'ituZone': '8'}),
      ).buildMyExchange(7),
      '08',
    );
    expect(
      _type(
        'ARRL-DX',
        config: const StationExchangeConfig({'power': '100'}),
      ).buildMyExchange(7),
      '100',
    );
    expect(_type('JIDX-SSB').buildMyExchange(7), '24');

    // Regression: the five contests must not all collapse to the WPX serial.
    final values = {
      'CQ-WPX': _type('CQ-WPX').buildMyExchange(1),
      'CQ-WW-SSB': _type('CQ-WW-SSB').buildMyExchange(1),
      'JIDX-SSB': _type('JIDX-SSB').buildMyExchange(1),
    };
    expect(values.values.toSet().length, greaterThan(1));
  });

  test('explicit station values win over derived defaults', () {
    expect(
      _type(
        'CQ-WW-SSB',
        config: const StationExchangeConfig({'cqZone': '23'}),
      ).buildMyExchange(1),
      '23',
    );
  });

  test('JIDX switches to a prefecture for JA stations', () {
    final ja = _FakeDxccManager(dxccId: 339);
    expect(
      _type(
        'JIDX-SSB',
        dxccManager: ja,
        config: const StationExchangeConfig({'prefecture': '10'}),
      ).buildMyExchange(1),
      '10',
    );
    final nonJa = _FakeDxccManager(dxccId: 318);
    expect(_type('JIDX-SSB', dxccManager: nonJa).buildMyExchange(1), '24');
  });

  test('received exchange audio padding follows the contest', () {
    expect(_type('CQ-WPX').formatExchangeForAudio('7'), '007');
    expect(_type('CQ-WW-SSB').formatExchangeForAudio('5'), '05');
    expect(_type('IARU-HF').formatExchangeForAudio('5'), '05');
    expect(_type('JIDX-SSB').formatExchangeForAudio('5'), '05');
    expect(_type('ARRL-DX').formatExchangeForAudio('100'), '100');
  });

  test('received exchange follows the caller for zone contests', () {
    expect(
      _type('CQ-WW-SSB', dxccManager: _FakeDxccManager(cqZone: 24))
          .exchangeManager
          .generateExchange(SessionRandom(1), callerCallsign: 'BI1ABC'),
      '24',
    );
    expect(
      _type('IARU-HF', dxccManager: _FakeDxccManager(ituZone: 44))
          .exchangeManager
          .generateExchange(SessionRandom(1), callerCallsign: 'BY1ABC'),
      '44',
    );
  });

  test('IARU refines US callers to their call-area ITU zone', () {
    final us = _FakeDxccManager(dxccId: 291, ituZone: 8);
    String zoneFor(String call) => _type('IARU-HF', dxccManager: us)
        .exchangeManager
        .generateExchange(SessionRandom(1), callerCallsign: call);
    expect(zoneFor('W6ABC'), '6');
    expect(zoneFor('W5ABC'), '7');
    expect(zoneFor('W4ABC'), '8');
  });

  test('JIDX received exchange uses a prefecture for JA, zone for DX', () {
    final prefecture = int.parse(
      _type('JIDX-SSB', dxccManager: _FakeDxccManager(dxccId: 339))
          .exchangeManager
          .generateExchange(SessionRandom(3), callerCallsign: 'JA1ABC'),
    );
    expect(prefecture, inInclusiveRange(10, 17));
    expect(
      _type('JIDX-SSB', dxccManager: _FakeDxccManager(cqZone: 24))
          .exchangeManager
          .generateExchange(SessionRandom(1), callerCallsign: 'BI1ABC'),
      '24',
    );
  });

  test('ARRL received exchange is a state for W/VE, power for DX', () {
    expect(
      _type('ARRL-DX', dxccManager: _FakeDxccManager(dxccId: 291))
          .exchangeManager
          .generateExchange(SessionRandom(1), callerCallsign: 'W6ABC'),
      'CA',
    );
    final power = _type('ARRL-DX', dxccManager: _FakeDxccManager(dxccId: 318))
        .exchangeManager
        .generateExchange(SessionRandom(1), callerCallsign: 'BI1ABC');
    expect(arrlPowerValues, contains(power));
  });

  test('CQ WW refines US callers to their call-area CQ zone', () {
    final us = _FakeDxccManager(dxccId: 291, cqZone: 5);
    String zoneFor(String call) => _type('CQ-WW-SSB', dxccManager: us)
        .exchangeManager
        .generateExchange(SessionRandom(1), callerCallsign: call);
    expect(zoneFor('W6ABC'), '3');
    expect(zoneFor('W0ABC'), '4');
    expect(zoneFor('W4ABC'), '5');
  });

  test('ARRL operator exchange follows the station role', () {
    final wve = _FakeDxccManager(dxccId: 291);
    final wvePlan = ContestRegistry.byId(
      'ARRL-DX',
    ).myExchangePlan(stationCallsign: 'W1ABC', dxccManager: wve);
    expect(wvePlan.fields.single.id, 'stateProvince');
    // RUN gate: a W/VE operator must configure a valid state/province.
    expect(
      validateStationExchange(
        plan: wvePlan,
        config: StationExchangeConfig.empty,
        stationCallsign: 'W1ABC',
        dxccManager: wve,
      ),
      isNotNull,
    );
    expect(
      validateStationExchange(
        plan: wvePlan,
        config: const StationExchangeConfig({'stateProvince': 'ZZ'}),
        stationCallsign: 'W1ABC',
        dxccManager: wve,
      ),
      isNotNull,
    );
    expect(
      validateStationExchange(
        plan: wvePlan,
        config: const StationExchangeConfig({'stateProvince': 'CT'}),
        stationCallsign: 'W1ABC',
        dxccManager: wve,
      ),
      isNull,
    );
    expect(
      ContestRegistry.byId('ARRL-DX')
          .create(
            stationCallsign: 'W1ABC',
            dxccManager: wve,
            stationExchange: const StationExchangeConfig({
              'stateProvince': 'CT',
            }),
          )
          .buildMyExchange(1),
      'CT',
    );

    // A DX operator must configure power instead.
    final dx = _FakeDxccManager(dxccId: 318);
    final dxPlan = ContestRegistry.byId(
      'ARRL-DX',
    ).myExchangePlan(stationCallsign: 'BI1QJQ', dxccManager: dx);
    expect(dxPlan.fields.single.id, 'power');
    expect(
      validateStationExchange(
        plan: dxPlan,
        config: StationExchangeConfig.empty,
        stationCallsign: 'BI1QJQ',
        dxccManager: dx,
      ),
      isNotNull,
    );
    expect(
      validateStationExchange(
        plan: dxPlan,
        config: const StationExchangeConfig({'power': '100'}),
        stationCallsign: 'BI1QJQ',
        dxccManager: dx,
      ),
      isNull,
    );
  });

  test('ARRL accepts letter exchanges, other contests stay numeric', () {
    expect(_type('ARRL-DX').allowExchangeRegex.hasMatch('X'), isTrue);
    expect(_type('CQ-WW-SSB').allowExchangeRegex.hasMatch('X'), isFalse);
  });

  test('JIDX constrains the operator prefecture to its JA call area', () {
    final ja = _FakeDxccManager(dxccId: 339);
    final plan = ContestRegistry.byId(
      'JIDX-SSB',
    ).myExchangePlan(stationCallsign: 'JA1ABC', dxccManager: ja);
    expect(plan.fields.single.min, 10);
    expect(plan.fields.single.max, 17);
    expect(
      validateStationExchange(
        plan: plan,
        config: const StationExchangeConfig({'prefecture': '40'}),
        stationCallsign: 'JA1ABC',
        dxccManager: ja,
      ),
      isNotNull,
    );
    expect(
      validateStationExchange(
        plan: plan,
        config: const StationExchangeConfig({'prefecture': '12'}),
        stationCallsign: 'JA1ABC',
        dxccManager: ja,
      ),
      isNull,
    );
  });
}
