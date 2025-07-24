import 'dart:async';
import 'dart:developer';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart' hide KeyEventManager;
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

const fillRst = 10001;
const clearInput = 10002;

class ContestManager {
  Timer? _contestTimer;
  Timer? _retryTimer;

  String _contestRunId = '';
  final _contestRunIdStreamController = StreamController<String>();
  Stream<String> get contestRunIdStream => _contestRunIdStreamController.stream;

  Duration _elapseTime = Duration.zero;
  final _elapseTimeStreamController = StreamController<Duration>();
  Stream<Duration> get elapseTimeStream => _elapseTimeStreamController.stream;

  bool isContestRunning = false;
  final _isContestRunningStreamController = StreamController<bool>.broadcast();
  Stream<bool> get isContestRunningStream =>
      _isContestRunningStreamController.stream;

  ScoreManager? scoreManager;

  final _inputControlStreamController = StreamController<int>();
  Stream<int> get inputControlStream => _inputControlStreamController.stream;

  final _keyEventManager = KeyEventManager();

  StateMachine<SingleCallRunState, SingleCallRunEvent, Null>? _stateMachine;

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
    _initKeyEventHandling();
  }

  void _initKeyEventHandling() {
    _keyEventManager.operationEventStream.listen((event) {
      handleOperationEvent(event);
    });

    ServicesBinding.instance.keyboard.addHandler((event) {
      _keyEventManager.onKeyEvent(event);
      return false;
    });
  }

  Future<void> handleOperationEvent(OperationEvent event) async {
    Uint8List? pcmData;

    switch (event) {
      case OperationEvent.cq:
        pcmData = await cqAudioData(_appSettings.stationCallsign);
        break;
      case OperationEvent.exch:
        pcmData = _exchange.isNotEmpty
            ? await exchangeAudioData(_exchange)
            : null;
        break;
      case OperationEvent.tu:
        pcmData = await loadAssetsWavPcmData('$globalRunPath/TU QRZ.wav');
        break;
      case OperationEvent.myCall:
        pcmData = await payloadToAudioData(_appSettings.stationCallsign);
        break;
      case OperationEvent.hisCall:
        pcmData = _hisCall.isNotEmpty
            ? await payloadToAudioData(_hisCall)
            : null;
        break;
      case OperationEvent.b4:
        pcmData = await loadAssetsWavPcmData('$globalRunPath/TU QRZ.wav');
        break;
      case OperationEvent.agn:
        pcmData = await loadAssetsWavPcmData('$globalRunPath/AGN.wav');
        break;
      case OperationEvent.nil:
        pcmData = await loadAssetsWavPcmData('$globalRunPath/TU QRZ.wav');
        break;
      case OperationEvent.submit:
        _handleSubmit();
        break;
    }

    final pcmDataVal = pcmData;
    if (pcmDataVal != null) {
      _audioPlayer.addAudioData(pcmDataVal);
    }
  }

  void _handleSubmit() {
    if (_hisCall.isEmpty && _exchange.isEmpty) {
      transition(Retry());
      return;
    }

    if (_hisCall.isNotEmpty && _exchange.isNotEmpty) {
      transition(SubmitExchange(exchange: _exchange));
      return;
    }

    if (_hisCall.isNotEmpty) {
      transition(SubmitCall(call: _hisCall));
      return;
    }
  }

  String _hisCall = '';
  String _exchange = '';

  void onCallInput(String callSign) {
    _hisCall = callSign;
  }

  void onExchangeInput(String exchange) {
    _exchange = exchange;
  }

  void startContest() {
    final contestRunId = Uuid().v4();

    _contestRunId = contestRunId;
    _contestRunIdStreamController.sink.add(contestRunId);

    _audioPlayer.startPlay();

    _startContestInternal();
  }

  void _startContestInternal() async {
    final scoreManager = await _createScoreManager();
    this.scoreManager = scoreManager;

    if (_callsignLoader.callSigns.isEmpty) {
      await _callsignLoader.loadCallsigns();
    }

    final duration = Duration(minutes: _appSettings.contestDuration);

    _contestTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      final elapseTime = Duration(seconds: timer.tick);
      _elapseTime = elapseTime;
      _elapseTimeStreamController.sink.add(elapseTime);

      if (elapseTime >= duration) {
        isContestRunning = false;
        _isContestRunningStreamController.sink.add(false);
        timer.cancel();
      }
    });

    final elapseTime = Duration.zero;
    _elapseTimeStreamController.sink.add(elapseTime);

    isContestRunning = true;
    _isContestRunningStreamController.sink.add(true);

    final (callSign, exchange) = _generateAnswer();
    final initialState = WaitingSubmitCall(
      currentCallAnswer: callSign,
      currentExchangeAnswer: exchange,
    );

    _setupStateMachine(initialState);
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

  (String, String) _generateAnswer() {
    List<String> callSigns = _callsignLoader.callSigns;

    final random = Random();
    final index = random.nextInt(callSigns.length);
    final callSign = callSigns[index];
    final exchange = random.nextInt(3000) + 1;

    return (callSign, exchange.toString());
  }

  void _setupStateMachine(WaitingSubmitCall waitingSubmitCall) async {
    _stateMachine = initSingleCallRunStateMachine(
      initialState: waitingSubmitCall,
      transitionListener: (transition) {
        if (transition
            is! TransitionValid<SingleCallRunState, SingleCallRunEvent, Null>) {
          return;
        }

        final toState = transition.to;
        _handleToState(toState);

        if (transition.from is WaitingSubmitCall &&
            toState is WaitingSubmitExchange) {
          _inputControlStreamController.sink.add(fillRst);
        }
      },
    );

    _handleToState(waitingSubmitCall);
  }

  void _handleToState(SingleCallRunState toState) {
    _playAudio(toState);
    _setupRetryTimer(toState);

    if (toState is QsoEnd) {
      _handleQsoEnd(toState);
    }
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
        _audioPlayer.addAudioData(pcmData);
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

    _audioPlayer.addAudioData(pcmData);
  }

  void _setupRetryTimer(SingleCallRunState toState) {
    _retryTimer?.cancel();

    switch (toState) {
      case WaitingSubmitCall():
      case WaitingSubmitExchange():
        _retryTimer = Timer(_timeoutDuration, () {
          _stateMachine?.transition(Retry());
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
      ),
    );

    if (submitQso == null) {
      return;
    }

    final latestQsos = await _appDatabase.qsoTable.all().get();
    scoreManager?.addQso(latestQsos, submitQso);

    final (callSign, exchange) = _generateAnswer();
    _stateMachine?.transition(
      NextCall(callAnswer: callSign, exchangeAnswer: '0$exchange'),
    );

    _inputControlStreamController.sink.add(clearInput);
  }

  void stopContest() {
    _contestTimer?.cancel();
    isContestRunning = false;
    _isContestRunningStreamController.sink.add(false);
    scoreManager = null;
    _stateMachine?.dispose();
    _stateMachine = null;
    _audioPlayer.stopPlay();
  }

  void transition(SingleCallRunEvent event) {
    _stateMachine?.transition(event);
  }
}
