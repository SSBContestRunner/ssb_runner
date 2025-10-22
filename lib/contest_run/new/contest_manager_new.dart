import 'dart:async';

import 'package:drift/drift.dart';
import 'package:ssb_runner/audio/audio_player.dart';
import 'package:ssb_runner/contest_run/new/contest_data_manager.dart';
import 'package:ssb_runner/contest_run/new/contest_input_handler.dart';
import 'package:ssb_runner/contest_run/new/contest_running_manager.dart';
import 'package:ssb_runner/contest_run/new/contest_timer.dart';
import 'package:ssb_runner/contest_type/contest_type.dart';
import 'package:ssb_runner/contest_type/cq_wpx/cq_wpx.dart';
import 'package:ssb_runner/contest_type/cq_wpx/cq_wpx_score_calculator.dart';
import 'package:ssb_runner/db/app_database.dart';
import 'package:uuid/uuid.dart';

class ContestManagerNew {
  final ContestDataManager _contestDataManager;

  ContestManagerNew({required ContestDataManager contestDataManager})
    : _contestDataManager = contestDataManager;

  late final ContestTimer contestTimer = ContestTimer(
    onContestEnd: () {
      stopContest();
    },
  );

  String _currentContestRunId = '';
  final _contestRunIdStreamController = StreamController<String>.broadcast();

  Stream<String> get contestRunIdStream => _contestRunIdStreamController.stream;

  late final AppDatabase _appDatabase = _contestDataManager.appDatabase;

  ContestRunningManager? contestRunningManager;

  bool _isContestRunning = false;
  final _isContestRunningStreamController = StreamController<bool>.broadcast();

  Stream<bool> get isContestRunningStream =>
      _isContestRunningStreamController.stream;

  bool get isContestRunning => _isContestRunning;

  late final AudioPlayer _audioPlayer = _contestDataManager.audioPlayer;
  late final ContestInputHandler _contestInputHandler =
      _contestDataManager.inputHandler;

  final _contestTypeStreamController =
      StreamController<ContestType>.broadcast();

  Stream<ContestType> get contestTypeStream =>
      _contestTypeStreamController.stream;

  void startContest() {
    final runId = Uuid().v4();
    _currentContestRunId = runId;
    _contestRunIdStreamController.sink.add(runId);

    _audioPlayer.startPlay();
    _contestInputHandler.clear();

    final dxccManager = _contestDataManager.dxccManager;
    final contestType = CqWpxContestType(
      stationCallsign: _contestDataManager.appSettings.stationCallsign,
      dxccManager: dxccManager,
    );

    _contestTypeStreamController.sink.add(contestType);
    contestRunningManager = _createContestRunningManager(runId, contestType);

    final durationInMinutes = _contestDataManager.appSettings.contestDuration;
    contestTimer.start(durationInMinutes);

    _isContestRunning = true;
    _isContestRunningStreamController.sink.add(true);
  }

  ContestRunningManager _createContestRunningManager(
    String runId,
    ContestType contestType,
  ) {
    final stationCallSign = _contestDataManager.appSettings.stationCallsign;
    final dxccManager = _contestDataManager.dxccManager;

    return ContestRunningManager(
      runId: runId,
      contestTimer: contestTimer,
      contestType: contestType,
      contestDataManager: _contestDataManager,
      scoreCalculator: WpxScoreCalculator(
        stationCallsign: stationCallSign,
        dxccManager: dxccManager,
      ),
    );
  }

  void stopContest() {
    contestTimer.stop();
    contestRunningManager?.stop();

    _audioPlayer.stopPlay();

    _isContestRunning = false;
    _isContestRunningStreamController.sink.add(false);
  }

  Future<int> countCurrentRunQso() async {
    return await _appDatabase.qsoTable
            .count(
              where: (row) {
                return row.runId.equals(_currentContestRunId);
              },
            )
            .getSingleOrNull() ??
        0;
  }
}
