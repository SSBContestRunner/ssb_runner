import 'dart:async';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter/widgets.dart';
import 'package:ssb_runner/audio/audio_player.dart';
import 'package:ssb_runner/audio/operation_event_audio.dart';
import 'package:ssb_runner/audio/payload_to_audio.dart';
import 'package:ssb_runner/callsign/callsign_loader.dart';
import 'package:ssb_runner/contest_run/key_event_manager.dart';
import 'package:ssb_runner/contest_run/score_manager.dart';
import 'package:ssb_runner/contest_run/state_machine/single_call/audio_play_type.dart';
import 'package:ssb_runner/contest_run/state_machine/single_call/single_call_run_event.dart';
import 'package:ssb_runner/contest_run/state_machine/single_call/single_call_run_state.dart';
import 'package:ssb_runner/contest_run/state_machine/single_call/single_call_run_state_machine.dart';
import 'package:ssb_runner/db/app_database.dart';
import 'package:ssb_runner/dxcc/dxcc_manager.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/state_machine/state_machine.dart';
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

  final _fillCallAndRstStreamController = StreamController<int>();
  Stream<int> get fillCallAndRstStream =>
      _fillCallAndRstStreamController.stream;

  final _keyEventManager = KeyEventManager();

  late final StateMachine<SingleCallRunState, SingleCallRunEvent, Null>
  _stateMachine;

  final AppSettings _appSettings;
  final AppDatabase _appDatabase;
  final AudioPlayer _audioPlayer;
  final CallsignLoader _callsignLoader;

  ContestManager({
    required CallsignLoader callsignLoader,
    required AppSettings appSettings,
    required AppDatabase appDatabase,
    required AudioPlayer audioPlayer,
  }) : _appSettings = appSettings,
       _appDatabase = appDatabase,
       _audioPlayer = audioPlayer,
       _callsignLoader = callsignLoader {
    _stateMachine = initSingleCallRunStateMachine(
      initialState: Init(),
      transitionListener: (transition) {
        if (transition
            is! TransitionValid<SingleCallRunState, SingleCallRunEvent, Null>) {
          return;
        }

        final toState = transition.to;
        _playAudio(toState);
        _setupRetryTimer(toState);

        if (transition.from is WaitingSubmitCall &&
            toState is WaitingSubmitExchange) {
          _fillCallAndRstStreamController.sink.add(Random(null).nextInt(12093));
        }

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
        final pcmData = await loadAssetsWavPcmData('$globalRunPath/TU QRZ.wav');
        _audioPlayer.resetAndPlay(pcmData);
        break;
      case Init():
        // don't play audio in init
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

    _audioPlayer.resetAndPlay(pcmData);
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
      case Init():
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
      ),
    );

    if (submitQso == null) {
      return;
    }

    final latestQsos = await _appDatabase.qsoTable.all().get();
    _scoreManager?.addQso(latestQsos, submitQso);

    _generateAnswerAndNextCall();
  }

  void startContest() {
    final duration = Duration(minutes: _appSettings.contestDuration);
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

    _audioPlayer.startPlay();

    _startContestInternal();
  }

  void _startContestInternal() async {
    final scoreManager = await _createScoreManager();
    _scoreManager = scoreManager;
    _scoreManagerStreamController.sink.add(scoreManager);

    if (_callsignLoader.callSigns.isEmpty) {
      await _callsignLoader.loadCallsigns();
    }

    _generateAnswerAndNextCall();
  }

  Future<ScoreManager> _createScoreManager() async {
    final dxccManager = DxccManager(database: _appDatabase);

    await dxccManager.loadDxcc();

    return ScoreManager(
      contestId: _appSettings.contestId,
      stationCallsign: _appSettings.stationCallsign,
      dxccManager: dxccManager,
    );
  }

  void _generateAnswerAndNextCall() {
    List<String> callSigns = _callsignLoader.callSigns;

    final random = Random();
    final index = random.nextInt(callSigns.length);
    final callSign = callSigns[index];
    final exchange = random.nextInt(3000) + 1;

    _stateMachine.transition(
      NextCall(callAnswer: callSign, exchangeAnswer: '0$exchange'),
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

  void onKeyEvent(KeyEvent event) {
    _keyEventManager.onKeyEvent(event);
  }
}
