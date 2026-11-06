import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/db/app_database.dart';
import 'package:ssb_runner/ui/qso_result_table/qso_result_list/qso_result.dart';

QsoTableData _qso({
  required int id,
  String callsign = 'K1ABC',
  String callsignCorrect = 'K1ABC',
  String exchange = '001',
  String exchangeCorrect = '001',
  String? accentDir = 'US',
}) {
  return QsoTableData(
    id: id,
    utcInSeconds: id * 10,
    runId: 'run-1',
    stationCallsign: 'MYCALL',
    callsign: callsign,
    callsignCorrect: callsignCorrect,
    exchange: exchange,
    exchangeCorrect: exchangeCorrect,
    accentDir: accentDir,
    phonicType: accentDir == null ? null : 'standard',
    callPhonicDirs: accentDir == null ? null : 'ICAO,Number,ICAO,ICAO,ICAO',
    exchangePhonicDirs: accentDir == null ? null : 'Number,Number,Number',
  );
}

void main() {
  test('a corrected QSO is replayable only while the session is idle', () {
    final qso = _qso(id: 1, callsign: 'K1ABD', callsignCorrect: 'K1ABC');

    final idle = qsoResultsFromRecords([qso]).single;
    expect(idle.hasCorrection, isTrue);
    expect(idle.isLegacy, isFalse);
    expect(idle.canReplay, isTrue);

    final running = qsoResultsFromRecords([qso], sessionIdle: false).single;
    expect(running.canReplay, isFalse);
  });

  test('a pure DUPE is excluded from corrections and replay', () {
    final first = _qso(id: 1);
    final duplicate = _qso(id: 2);

    final rows = qsoResultsFromRecords([duplicate, first]);
    expect(rows.first.isPureDupe, isTrue);
    expect(rows.first.hasCorrection, isFalse);
    expect(rows.first.canReplay, isFalse);
    expect(rows.first.corrections, 'DUPE');
  });

  test('rows logged before v7 are legacy and not replayable', () {
    final row = qsoResultsFromRecords([
      _qso(id: 1, callsign: 'K1ABD', callsignCorrect: 'K1ABC', accentDir: null),
    ]).single;

    expect(row.isLegacy, isTrue);
    expect(row.canReplay, isFalse);
    expect(row.hasCorrection, isTrue);
    expect(row.correctCall, 'K1ABC');
  });

  test('the replay serial uses the correct exchange', () {
    final row = qsoResultsFromRecords([
      _qso(id: 1, exchange: '002', exchangeCorrect: '028'),
    ]).single;

    expect(row.serial, '028');
    expect(row.canReplay, isTrue);
  });
}
