import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ssb_runner/common/time_format.dart';
import 'package:ssb_runner/contest_run/new/contest_manager.dart';
import 'package:ssb_runner/db/app_database.dart';
import 'package:ssb_runner/ui/qso_result_table/qso_result_list/qso_result.dart';

class QsoRecordListCubit extends Cubit<List<QsoResult>> {
  final AppDatabase _appDatabase;
  final ContestManager _contestManager;

  StreamSubscription<List<QsoTableData>>? _qsoTableDataStream;

  QsoRecordListCubit({
    required AppDatabase appDatabase,
    required ContestManager contestManager,
  }) : _appDatabase = appDatabase,
       _contestManager = contestManager,
       super([]) {
    _contestManager.contestRunIdStream.listen((id) {
      if (id.isEmpty) {
        return;
      }

      _qsoTableDataStream?.cancel();

      final qsoStream =
          (_appDatabase.qsoTable.select()..where((qso) {
                return qso.runId.equals(id);
              }))
              .watch();

      _qsoTableDataStream = qsoStream.listen((qsos) {
        _onQsosUpdate(qsos);
      });
    });
  }

  void _onQsosUpdate(List<QsoTableData> qsos) {
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
  }

  String _calculateCorrection(QsoTableData qso) {
    final stringBuffer = StringBuffer();

    if (qso.callsign != qso.callsignCorrect) {
      stringBuffer.write(qso.callsignCorrect);
    }

    if (qso.exchange != qso.exchangeCorrect) {
      if (stringBuffer.isNotEmpty) {
        stringBuffer.write(' ');
      }
      stringBuffer.write(qso.exchangeCorrect);
    }

    return stringBuffer.toString();
  }

  String _utcTimeToString(int utcInSeconds) {
    final duration = Duration(seconds: utcInSeconds);
    return formatDuration(duration);
  }
}
