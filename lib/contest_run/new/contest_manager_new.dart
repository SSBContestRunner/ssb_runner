import 'dart:async';

import 'package:ssb_runner/contest_run/new/contest_data_manager.dart';
import 'package:ssb_runner/contest_run/new/contest_input_handler.dart';
import 'package:ssb_runner/contest_run/new/contest_running_manager.dart';
import 'package:ssb_runner/contest_run/new/contest_timer.dart';
import 'package:ssb_runner/contest_type/cq_wpx/cq_wpx.dart';
import 'package:ssb_runner/contest_type/cq_wpx/cq_wpx_score_calculator.dart';
import 'package:uuid/uuid.dart';

class ContestManagerNew {
  final ContestDataManager _contestDataManager;

  ContestManagerNew({required ContestDataManager contestDataManager})
    : _contestDataManager = contestDataManager;

  late final ContestTimer _contestTimer = ContestTimer(
    onContestEnd: () {
      stopContest();
    },
  );

  ContestRunningManager? contestRunningManager;

  bool _isContestRunning = false;
  final _isContestRunningStreamController = StreamController<bool>.broadcast();

  Stream<bool> get isContestRunningStream =>
      _isContestRunningStreamController.stream;

  bool get isContestRunning => _isContestRunning;

  void startContest() {
    contestRunningManager = _createContestRunningManager();
    final durationInMinutes = _contestDataManager.appSettings.contestDuration;
    _contestTimer.start(durationInMinutes);

    _isContestRunning = true;
    _isContestRunningStreamController.sink.add(true);
  }

  ContestRunningManager _createContestRunningManager() {
    final stationCallSign = _contestDataManager.appSettings.stationCallsign;
    final dxccManager = _contestDataManager.dxccManager;

    return ContestRunningManager(
      runId: Uuid().v4(),
      contestTimer: _contestTimer,
      contestType: CqWpxContestType(
        stationCallsign: _contestDataManager.appSettings.stationCallsign,
        dxccManager: dxccManager,
      ),
      contestDataManager: _contestDataManager,
      inputHandler: ContestInputHandler(),
      scoreCalculator: WpxScoreCalculator(
        stationCallsign: stationCallSign,
        dxccManager: dxccManager,
      ),
    );
  }

  void stopContest() {
    _contestTimer.stop();
    contestRunningManager?.stop();

    _isContestRunning = false;
    _isContestRunningStreamController.sink.add(false);
  }
}
