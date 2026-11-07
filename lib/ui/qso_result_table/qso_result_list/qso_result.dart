import 'package:ssb_runner/common/time_format.dart';
import 'package:ssb_runner/contest_run/qso_duplicates.dart';
import 'package:ssb_runner/db/app_database.dart';

List<QsoResult> qsoResultsFromRecords(
  List<QsoTableData> qsos, {
  bool sessionIdle = true,
}) {
  final countedIds = uniqueQsos(qsos).map((qso) => qso.id).toSet();
  return qsos.map((qso) {
    final isDupe = !countedIds.contains(qso.id);
    final callWrong = qso.callsign != qso.callsignCorrect;
    final exchangeWrong = qso.exchange != qso.exchangeCorrect;
    final hasCorrection = callWrong || exchangeWrong;
    final isLegacy =
        qso.accentDir == null ||
        qso.phonicType == null ||
        qso.callPhonicDirs == null ||
        qso.exchangePhonicDirs == null ||
        qso.callsignCorrect.trim().isEmpty ||
        qso.exchangeCorrect.trim().isEmpty;

    return QsoResult(
      id: qso.id,
      call: QsoResultField(data: qso.callsign, isCorrect: !callWrong),
      exchange: QsoResultField(data: qso.exchange, isCorrect: !exchangeWrong),
      utc: formatDuration(Duration(seconds: qso.utcInSeconds)),
      corrections: [
        if (isDupe) 'DUPE',
        if (callWrong) qso.callsignCorrect,
        if (exchangeWrong) qso.exchangeCorrect,
      ].join(' '),
      correctCall: qso.callsignCorrect,
      correctExchange: qso.exchangeCorrect,
      accentDir: qso.accentDir,
      phonicTypeId: qso.phonicType,
      callPhonicDirs: _parsePhonicDirs(qso.callPhonicDirs),
      exchangePhonicDirs: _parsePhonicDirs(qso.exchangePhonicDirs),
      hasCorrection: hasCorrection,
      isPureDupe: isDupe && !hasCorrection,
      isLegacy: isLegacy,
      canReplay: sessionIdle && hasCorrection && !isLegacy,
    );
  }).toList();
}

List<String>? _parsePhonicDirs(String? raw) {
  if (raw == null || raw.isEmpty) {
    return null;
  }
  return raw.split(',');
}

class QsoResult {
  final QsoResultField call;
  final QsoResultField exchange;
  final String utc;
  final String corrections;

  final String rst = '59';

  final int id;
  final String correctCall;
  final String correctExchange;
  final String? accentDir;
  final String? phonicTypeId;
  final List<String>? callPhonicDirs;
  final List<String>? exchangePhonicDirs;
  final bool hasCorrection;
  final bool isPureDupe;
  final bool isLegacy;
  final bool canReplay;

  QsoResult({
    required this.call,
    required this.exchange,
    required this.utc,
    required this.corrections,
    this.id = 0,
    this.correctCall = '',
    this.correctExchange = '',
    this.accentDir,
    this.phonicTypeId,
    this.callPhonicDirs,
    this.exchangePhonicDirs,
    this.hasCorrection = false,
    this.isPureDupe = false,
    this.isLegacy = false,
    this.canReplay = false,
  });

  /// Serial number announced by the station (correct value when known).
  String get serial =>
      correctExchange.isNotEmpty ? correctExchange : exchange.data;

  /// Callsign used by the replay; empty when the row predates the replay
  /// metadata.
  String get replayCallsign => correctCall;
}

class QsoResultField {
  final String data;
  final bool isCorrect;

  QsoResultField({required this.data, required this.isCorrect});
}
