import 'package:drift/drift.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ssb_contest_runner/common/streams.dart';
import 'package:ssb_contest_runner/common/time_format.dart';
import 'package:ssb_contest_runner/contest_run/contest_manager.dart';
import 'package:ssb_contest_runner/db/app_database.dart';
import 'package:ssb_contest_runner/ui/qso_result_table/qso_result_list/qso_result.dart';

class QsoRecordListCubit extends Cubit<List<QsoResult>> {
  final AppDatabase _appDatabase;
  final ContestManager _contestManager;

  QsoRecordListCubit({
    required AppDatabase appDatabase,
    required ContestManager contestManager,
  }) : _appDatabase = appDatabase,
       _contestManager = contestManager,
       super([]) {
    _listenQsoUpdate();
  }

  void _listenQsoUpdate() {
    final streams = _contestManager.contestRunIdStream.stream.map((id) {
      if (id.isEmpty) {
        return Stream<List<QsoTableData>>.empty();
      }

      return (_appDatabase.qsoTable.select()..where((qso) {
            return qso.runId.equals(id);
          }))
          .watch();
    });

    final flatten = flattenStreams(streams);

    flatten.listen((qsos) {
      qsos.map((qso) {
        QsoResult(
          call: QsoResultField(
            data: qso.callsign,
            isCorrect: qso.callsignCorrect == qso.callsign,
          ),
          rst: QsoResultField(
            data: qso.rst.toString(),
            isCorrect: qso.rst == qso.rstCorrect,
          ),
          exchange: QsoResultField(
            data: qso.exchange,
            isCorrect: qso.exchange == qso.exchangeCorrect,
          ),
          utc: _utcTimeToString(qso.utcInSeconds),
          corrections: _calculateCorrection(qso),
        );
      });
    });
  }

  String _calculateCorrection(QsoTableData qso) {
    final stringBuffer = StringBuffer();

    if (qso.callsign != qso.callsignCorrect) {
      stringBuffer.write(qso.callsignCorrect);
    }

    if (qso.rst != qso.rstCorrect) {
      stringBuffer.write(qso.rstCorrect);
    }

    if (qso.exchange != qso.exchangeCorrect) {
      stringBuffer.write(qso.exchangeCorrect);
    }

    return stringBuffer.toString();
  }

  String _utcTimeToString(int utcInSeconds) {
    final duration = Duration(seconds: utcInSeconds);
    return formatDuration(duration);
  }
}
