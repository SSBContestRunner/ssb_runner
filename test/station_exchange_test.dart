import 'package:drift/drift.dart' show LazyDatabase;
import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/contest_type/station_exchange.dart';
import 'package:ssb_runner/db/app_database.dart';
import 'package:ssb_runner/dxcc/dxcc_manager.dart';

class _FakeDxccManager extends DxccManager {
  _FakeDxccManager()
    : super(
        database: AppDatabase(
          LazyDatabase(
            () async =>
                throw StateError('The DXCC table must not be touched here.'),
          ),
        ),
      );

  @override
  int? findCallsignCqZone(String callsign) => 24;

  @override
  int? findCallsignItuZone(String callsign) => null;
}

const _cqZoneField = StationExchangeField(
  id: 'cqZone',
  label: 'CQ Zone',
  min: 1,
  max: 40,
  audioDigits: 2,
);

void main() {
  test('explicit config wins, then derived default, then null', () {
    final dxcc = _FakeDxccManager();
    expect(
      resolveExchangeValue(
        _cqZoneField,
        const StationExchangeConfig({'cqZone': '23'}),
        'BI1QJQ',
        dxcc,
      ),
      '23',
    );
    expect(
      resolveExchangeValue(
        _cqZoneField,
        StationExchangeConfig.empty,
        'BI1QJQ',
        dxcc,
      ),
      null,
      reason: 'no derive callback on this field',
    );

    final derived = StationExchangeField(
      id: 'cqZone',
      label: 'CQ Zone',
      min: 1,
      max: 40,
      audioDigits: 2,
      derive: (callsign, manager) =>
          manager.findCallsignCqZone(callsign)?.toString(),
    );
    expect(
      resolveExchangeValue(
        derived,
        StationExchangeConfig.empty,
        'BI1QJQ',
        dxcc,
      ),
      '24',
    );
  });

  test('validateStationExchange enforces the start gate', () {
    final dxcc = _FakeDxccManager();
    final plan = MyExchangePlan(fields: [_cqZoneField], sendsSerial: false);

    expect(
      validateStationExchange(
        plan: plan,
        config: StationExchangeConfig.empty,
        stationCallsign: 'BI1QJQ',
        dxccManager: dxcc,
      ),
      'Please set CQ Zone',
    );
    expect(
      validateStationExchange(
        plan: plan,
        config: const StationExchangeConfig({'cqZone': '99'}),
        stationCallsign: 'BI1QJQ',
        dxccManager: dxcc,
      ),
      contains('between'),
    );
    expect(
      validateStationExchange(
        plan: plan,
        config: const StationExchangeConfig({'cqZone': '5'}),
        stationCallsign: 'BI1QJQ',
        dxccManager: dxcc,
      ),
      isNull,
    );
  });

  test('serial plans need no configuration', () {
    expect(
      validateStationExchange(
        plan: const MyExchangePlan(fields: [], sendsSerial: true),
        config: StationExchangeConfig.empty,
        stationCallsign: 'BI1QJQ',
        dxccManager: _FakeDxccManager(),
      ),
      isNull,
    );
  });

  test('formatExchangeNumber strips and pads', () {
    expect(formatExchangeNumber('007', 3), '007');
    expect(formatExchangeNumber('7', 3), '007');
    expect(formatExchangeNumber('5', 2), '05');
    expect(formatExchangeNumber('100', 0), '100');
    expect(formatExchangeNumber('0100', 0), '100');
  });

  test('StationExchangeConfig JSON round-trips and drops empty values', () {
    final config = StationExchangeConfig.empty.withValue('cqZone', '24');
    final decoded = StationExchangeConfig.fromJson(config.toJson());
    expect(decoded['cqZone'], '24');

    final cleared = config.withValue('cqZone', '');
    expect(cleared['cqZone'], isNull);

    expect(StationExchangeConfig.fromJson(const {}).values, isEmpty);
  });

  test('isJapanDxcc covers Japan and its islands', () {
    expect(isJapanDxcc(339), isTrue);
    expect(isJapanDxcc(192), isTrue);
    expect(isJapanDxcc(177), isTrue);
    expect(isJapanDxcc(318), isFalse);
  });
}
