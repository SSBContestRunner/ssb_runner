import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ssb_runner/contest_run/new/contest_manager.dart';
import 'package:ssb_runner/db/app_database.dart';
import 'package:ssb_runner/ui/qso_result_table/qso_result_list/qso_result.dart';

class QsoRecordListCubit extends Cubit<List<QsoResult>> {
  final AppDatabase _appDatabase;
  final ContestManager _contestManager;

  StreamSubscription<List<QsoTableData>>? _qsoTableDataStream;
  StreamSubscription<ContestSessionPhase>? _phaseSubscription;
  List<QsoTableData> _qsos = [];
  bool _sessionIdle = true;

  QsoRecordListCubit({
    required AppDatabase appDatabase,
    required ContestManager contestManager,
  }) : _appDatabase = appDatabase,
       _contestManager = contestManager,
       super([]) {
    _sessionIdle = !contestManager.isContestRunning;
    _phaseSubscription = _contestManager.sessionPhaseStream.listen((phase) {
      final idle = phase == ContestSessionPhase.idle;
      if (_sessionIdle == idle) {
        return;
      }
      _sessionIdle = idle;
      _onQsosUpdate(_qsos);
    });
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
    _qsos = qsos;
    emit(qsoResultsFromRecords(qsos, sessionIdle: _sessionIdle));
  }

  @override
  Future<void> close() async {
    await _phaseSubscription?.cancel();
    await _qsoTableDataStream?.cancel();
    return super.close();
  }
}
