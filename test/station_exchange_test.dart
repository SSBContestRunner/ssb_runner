import 'package:drift/drift.dart' show LazyDatabase;
import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/contest_type/station_exchange.dart';
import 'package:ssb_runner/db/app_database.dart';
import 'package:ssb_runner/dxcc/dxcc_manager.dart';

/// Shared by every fake so the process only ever holds one database instance.
final AppDatabase _unusedDatabase = AppDatabase(
  LazyDatabase(
    () async => throw StateError('The DXCC table must not be touched here.'),
  ),
);

class _FakeDxccManager extends DxccManager {
  _FakeDxccManager() : super(database: _unusedDatabase);

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

    final missing = validateStationExchange(
      plan: plan,
      config: StationExchangeConfig.empty,
      stationCallsign: 'BI1QJQ',
      dxccManager: dxcc,
    );
    expect(missing, isA<StationExchangeMissing>());
    expect(missing!.field.id, 'cqZone');

    final outOfRange = validateStationExchange(
      plan: plan,
      config: const StationExchangeConfig({'cqZone': '99'}),
      stationCallsign: 'BI1QJQ',
      dxccManager: dxcc,
    );
    expect(outOfRange, isA<StationExchangeOutOfRange>());
    expect((outOfRange! as StationExchangeOutOfRange).min, _cqZoneField.min);
    expect((outOfRange as StationExchangeOutOfRange).max, _cqZoneField.max);
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

  test('buildMyExchangeText matches each contest spoken form', () {
    final dxcc = _FakeDxccManager();

    expect(
      buildMyExchangeText(
        plan: const MyExchangePlan(fields: [], sendsSerial: true),
        config: StationExchangeConfig.empty,
        stationCallsign: '',
        dxccManager: dxcc,
        qsoNumber: 7,
      ),
      '007',
      reason: 'CQ WPX serial',
    );
    expect(
      buildMyExchangeText(
        plan: MyExchangePlan(fields: [_cqZoneField], sendsSerial: false),
        config: const StationExchangeConfig({'cqZone': '5'}),
        stationCallsign: 'BI1QJQ',
        dxccManager: dxcc,
        qsoNumber: 1,
      ),
      '05',
      reason: 'CQ WW / JIDX: configured 5 is read as zero-five',
    );
    expect(
      buildMyExchangeText(
        plan: MyExchangePlan(
          fields: [
            StationExchangeField(
              id: 'ituZone',
              label: 'ITU Zone',
              min: 1,
              max: 90,
              audioDigits: 2,
            ),
          ],
          sendsSerial: false,
        ),
        config: StationExchangeConfig.empty,
        stationCallsign: 'DL1ABC',
        dxccManager: dxcc,
        qsoNumber: 1,
      ),
      '',
      reason: 'IARU without an explicit or derivable zone',
    );
    expect(
      buildMyExchangeText(
        plan: MyExchangePlan(
          fields: [
            StationExchangeField(
              id: 'power',
              label: 'Power',
              min: 1,
              max: 1500,
              audioDigits: 0,
            ),
          ],
          sendsSerial: false,
        ),
        config: const StationExchangeConfig({'power': '100'}),
        stationCallsign: 'W1ABC',
        dxccManager: dxcc,
        qsoNumber: 1,
      ),
      '100',
      reason: 'ARRL DX: power is read as entered',
    );
    expect(
      buildMyExchangeText(
        plan: MyExchangePlan(
          fields: [
            StationExchangeField(
              id: 'stateProvince',
              label: 'State/Province',
              numeric: false,
            ),
          ],
          sendsSerial: false,
        ),
        config: const StationExchangeConfig({'stateProvince': 'TX'}),
        stationCallsign: 'K1ABC',
        dxccManager: dxcc,
        qsoNumber: 1,
      ),
      'TX',
      reason: 'ARRL DX: letters pass through',
    );
    expect(
      buildMyExchangeText(
        plan: MyExchangePlan(
          fields: [
            StationExchangeField(
              id: 'prefecture',
              label: 'Prefecture',
              min: 1,
              max: 50,
              audioDigits: 2,
            ),
          ],
          sendsSerial: false,
        ),
        config: const StationExchangeConfig({'prefecture': '10'}),
        stationCallsign: 'JA1ABC',
        dxccManager: dxcc,
        qsoNumber: 1,
      ),
      '10',
    );
  });

  test('StationExchangeBuilder delegates to buildMyExchangeText', () {
    final dxcc = _FakeDxccManager();
    const plan = MyExchangePlan(fields: [_cqZoneField], sendsSerial: false);
    const config = StationExchangeConfig({'cqZone': '5'});
    final builder = StationExchangeBuilder(
      plan: plan,
      config: config,
      stationCallsign: 'BI1QJQ',
      dxccManager: dxcc,
      exchangeAudioDigits: 2,
    );

    expect(
      builder.buildMyExchange(1),
      buildMyExchangeText(
        plan: plan,
        config: config,
        stationCallsign: 'BI1QJQ',
        dxccManager: dxcc,
        qsoNumber: 1,
      ),
    );
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
