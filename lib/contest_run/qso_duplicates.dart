import 'package:ssb_runner/common/normalize_callsign.dart';
import 'package:ssb_runner/db/app_database.dart';

/// Training currently has a single band and operating mode per run. Keep the
/// first logged contact for each station; exchanges do not identify stations.
String qsoDuplicateKey(QsoTableData qso) =>
    '${qso.runId}\u0000${normalizeCallsign(qso.callsign)}';

List<QsoTableData> uniqueQsos(List<QsoTableData> qsos) {
  final ordered = [...qsos]..sort((a, b) => a.id.compareTo(b.id));
  final seen = <String>{};
  return ordered.where((qso) => seen.add(qsoDuplicateKey(qso))).toList();
}

bool isDuplicateQso(List<QsoTableData> qsos, QsoTableData qso) => qsos.any(
  (previous) =>
      previous.id < qso.id && qsoDuplicateKey(previous) == qsoDuplicateKey(qso),
);
