import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:ssb_contest_runner/audio/audio_player.dart';
import 'package:ssb_contest_runner/audio/payload_to_audio.dart';
import 'package:ssb_contest_runner/contest_run/score_manager.dart';
import 'package:ssb_contest_runner/contest_run/state_machine/single_call/audio_play_type.dart';
import 'package:ssb_contest_runner/contest_run/state_machine/single_call/single_call_run_event.dart';
import 'package:ssb_contest_runner/contest_run/state_machine/single_call/single_call_run_state.dart';
import 'package:ssb_contest_runner/contest_run/state_machine/single_call/single_call_run_state_machine.dart';
import 'package:ssb_contest_runner/db/app_database.dart';
import 'package:ssb_contest_runner/dxcc/dxcc_manager.dart';
import 'package:ssb_contest_runner/settings/app_settings.dart';
import 'package:ssb_contest_runner/state_machine/state_machine.dart';
import 'package:uuid/uuid.dart';

const _timeoutDuration = Duration(seconds: 10);

class ContestManager {
  Timer? _contestTimer;
  Timer? _retryTimer;

  String _contestRunId = '';
  final _contestRunIdStreamController = StreamController<String>();
  Stream<String> get contestRunIdStream => _contestRunIdStreamController.stream;

  Duration _elapseTime = Duration.zero;
  final _elapseTimeStreamController = StreamController<Duration>();
  Stream<Duration> get elapseTimeStream => _elapseTimeStreamController.stream;

  final _isContestRunningStreamController = StreamController<bool>.broadcast();
  Stream<bool> get isContestRunningStream =>
      _isContestRunningStreamController.stream;

  ScoreManager? _scoreManager;
  final _scoreManagerStreamController = StreamController<ScoreManager?>();
  Stream<ScoreManager?> get scoreManagerStream =>
      _scoreManagerStreamController.stream;

  final _audioPlayer = AudioPlayer();

  late final StateMachine<SingleCallRunState, SingleCallRunEvent, Null>
  _stateMachine;

  final AppSettings _appSettings;
  final AppDatabase _appDatabase;

  ContestManager({
    required AppSettings appSettings,
    required AppDatabase appDatabase,
  }) : _appSettings = appSettings,
       _appDatabase = appDatabase {
    _stateMachine = initSingleCallRunStateMachine(
      initialState: WaitingSubmitCall(
        currentCallAnswer: 'BI1QJQ',
        currentExchangeAnswer: '230',
      ),
      transitionListener: (transition) {
        if (transition
            is! TransitionValid<SingleCallRunState, SingleCallRunEvent, Null>) {
          return;
        }

        final toState = transition.to;
        _playAudio(toState);
        _setupRetryTimer(toState);

        if (toState is QsoEnd) {
          _handleQsoEnd(toState);
        }
      },
    );
  }

  Future<void> _playAudio(SingleCallRunState toState) async {
    switch (toState) {
      case WaitingSubmitCall():
        final pcmData = await payloadToAudioData(toState.currentCallAnswer);
        await _playAudioInternal(pcmData);
        break;
      case WaitingSubmitExchange():
        _playAudioByPlayType(toState.audioPlayType);
        break;
      case QsoEnd():
        // TODO: Play TU QRZ
        break;
    }
  }

  Future<void> _playAudioByPlayType(AudioPlayType playType) async {
    switch (playType) {
      case NoPlay():
        _audioPlayer.stopPlay();
      case PlayExchange():
        final pcmData = await payloadToAudioData(playType.exchange);
        await _playAudioInternal(pcmData);
      case PlayCallExchange():
        final payload = playType.call + playType.exchange;
        final pcmData = await payloadToAudioData(payload);
        await _playAudioInternal(pcmData);
    }
  }

  Future<void> _playAudioInternal(Uint8List pcmData) async {
    if (!_audioPlayer.isStarted) {
      await _audioPlayer.startPlay();
    }

    _audioPlayer.addPcmData(pcmData);
  }

  void _setupRetryTimer(SingleCallRunState toState) {
    _retryTimer?.cancel();

    switch (toState) {
      case WaitingSubmitCall():
      case WaitingSubmitExchange():
        _retryTimer = Timer(_timeoutDuration, () {
          _stateMachine.transition(Retry());
        });
        break;
      case QsoEnd():
        break;
    }
  }

  void _handleQsoEnd(QsoEnd toState) async {
    final submitQso = await _appDatabase.qsoTable.insertReturningOrNull(
      QsoTableCompanion.insert(
        utcInSeconds: _elapseTime.inSeconds,
        runId: _contestRunId,
        stationCallsign: _appSettings.stationCallsign,
        callsign: toState.submitCall,
        callsignCorrect: toState.currentCallAnswer,
        exchange: toState.submitExchange,
        exchangeCorrect: toState.currentExchangeAnswer,
        rst: 59,
        rstCorrect: 59,
      ),
    );

    if (submitQso == null) {
      return;
    }

    final latestQsos = await _appDatabase.qsoTable.all().get();

    _scoreManager?.addQso(latestQsos, submitQso);
  }

  void startContest(Duration duration) {
    final contestRunId = Uuid().v4();
    _contestRunId = contestRunId;
    _contestRunIdStreamController.sink.add(contestRunId);

    _contestTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      final elapseTime = Duration(seconds: timer.tick);
      _elapseTime = elapseTime;
      _elapseTimeStreamController.sink.add(elapseTime);

      if (elapseTime >= duration) {
        _isContestRunningStreamController.sink.add(false);
        timer.cancel();
      }
    });

    final elapseTime = Duration.zero;
    _elapseTimeStreamController.sink.add(elapseTime);

    _isContestRunningStreamController.sink.add(true);

    final scoreManager = _createScoreManager();
    _scoreManager = scoreManager;
    _scoreManagerStreamController.sink.add(scoreManager);

    _audioPlayer.startPlay();
  }

  ScoreManager _createScoreManager() {
    final dxccManager = DxccManager(database: _appDatabase);

    return ScoreManager(
      contestId: _appSettings.contestId,
      stationCallsign: _appSettings.stationCallsign,
      dxccManager: dxccManager,
    );
  }

  void stopContest() {
    _contestTimer?.cancel();
    _isContestRunningStreamController.sink.add(false);
    _scoreManager = null;
    _scoreManagerStreamController.sink.add(null);
  }

  void transition(SingleCallRunEvent event) {
    _stateMachine.transition(event);
  }
}
