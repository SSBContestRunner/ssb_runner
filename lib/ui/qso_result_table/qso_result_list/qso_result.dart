import 'package:ssb_runner/common/time_format.dart';
import 'package:ssb_runner/contest_run/qso_duplicates.dart';
import 'package:ssb_runner/db/app_database.dart';

List<QsoResult> qsoResultsFromRecords(List<QsoTableData> qsos) {
  final countedIds = uniqueQsos(qsos).map((qso) => qso.id).toSet();
  return qsos.map((qso) {
    return QsoResult(
      call: QsoResultField(
        data: qso.callsign,
        isCorrect: qso.callsignCorrect == qso.callsign,
      ),
      exchange: QsoResultField(
        data: qso.exchange,
        isCorrect: qso.exchange == qso.exchangeCorrect,
      ),
      utc: formatDuration(Duration(seconds: qso.utcInSeconds)),
      corrections: [
        if (!countedIds.contains(qso.id)) 'DUPE',
        if (qso.callsign != qso.callsignCorrect) qso.callsignCorrect,
        if (qso.exchange != qso.exchangeCorrect) qso.exchangeCorrect,
      ].join(' '),
    );
  }).toList();
}

class QsoResult {
  final QsoResultField call;
  final QsoResultField exchange;
  final String utc;
  final String corrections;

  final String rst = '59';

  QsoResult({
    required this.call,
    required this.exchange,
    required this.utc,
    required this.corrections,
  });
}

class QsoResultField {
  final String data;
  final bool isCorrect;

  QsoResultField({required this.data, required this.isCorrect});
}
