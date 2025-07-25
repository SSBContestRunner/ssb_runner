import 'package:drift/drift.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ssb_runner/common/streams.dart';
import 'package:ssb_runner/common/time_format.dart';
import 'package:ssb_runner/contest_run/contest_manager.dart';
import 'package:ssb_runner/db/app_database.dart';
import 'package:ssb_runner/main.dart';
import 'package:ssb_runner/ui/qso_result_table/qso_result_list/qso_result.dart';

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
    final flatten = _contestManager.obtainCurrentRunQsoStream();

    flatten.listen((qsos) {
      final qsoResults = qsos.map((qso) {
        return QsoResult(
          call: QsoResultField(
            data: qso.callsign,
            isCorrect: qso.callsignCorrect == qso.callsign,
          ),
          exchange: QsoResultField(
            data: qso.exchange,
            isCorrect: qso.exchange == qso.exchangeCorrect,
          ),
          utc: _utcTimeToString(qso.utcInSeconds),
          corrections: _calculateCorrection(qso),
        );
      }).toList();

      emit(qsoResults);
    });
  }

  String _calculateCorrection(QsoTableData qso) {
    final stringBuffer = StringBuffer();

    if (qso.callsign != qso.callsignCorrect) {
      stringBuffer.write(qso.callsignCorrect);
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
