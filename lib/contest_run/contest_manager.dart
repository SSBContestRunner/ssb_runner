import 'dart:async';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart' hide KeyEventManager;
import 'package:ssb_runner/audio/audio_player.dart';
import 'package:ssb_runner/audio/operation_event_audio.dart';
import 'package:ssb_runner/audio/payload_to_audio.dart';
import 'package:ssb_runner/callsign/callsign_loader.dart';
import 'package:ssb_runner/common/concat_bytes.dart';
import 'package:ssb_runner/contest_run/key_event_manager.dart';
import 'package:ssb_runner/contest_run/score_manager.dart';
import 'package:ssb_runner/contest_run/state_machine/single_call/audio_play_type.dart';
import 'package:ssb_runner/contest_run/state_machine/single_call/single_call_run_event.dart';
import 'package:ssb_runner/contest_run/state_machine/single_call/single_call_run_state.dart';
import 'package:ssb_runner/contest_run/state_machine/single_call/single_call_run_state_machine.dart';
import 'package:ssb_runner/contest_type/contest_type.dart';
import 'package:ssb_runner/contest_type/cq_wpx/cq_wpx.dart';
import 'package:ssb_runner/db/app_database.dart';
import 'package:ssb_runner/dxcc/dxcc_manager.dart';
import 'package:ssb_runner/main.dart';
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

  late ContestType _contestType;

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
        await _handleSubmit();
        break;
    }

    final pcmDataVal = pcmData;
    if (pcmDataVal != null) {
      _audioPlayer.addAudioData(pcmDataVal);
    }
  }

  Future<void> _handleSubmit() async {
    if (_hisCall.isEmpty && _exchange.isEmpty) {
      transition(Retry());
      return;
    }

    if (_hisCall.isNotEmpty && _exchange.isNotEmpty) {
      transition(SubmitExchange(exchange: _exchange));
      return;
    }

    if (_hisCall.isNotEmpty) {
      transition(
        SubmitCall(call: _hisCall, myExchange: await _obtainMyExchange()),
      );
      return;
    }
  }

  Future<String> _obtainMyExchange() async {
    final count = await _appDatabase.qsoTable
        .count(
          where: (row) {
            return row.runId.equals(_contestRunId);
          },
        )
        .getSingle();

    return '${count + 1}';
  }

  String _hisCall = '';
  String _exchange = '';
  bool _isRstFilled = false;

  void onCallInput(String callSign) {
    _hisCall = callSign;
  }

  void onExchangeInput(String exchange) {
    _exchange = exchange;
  }

  void _clearInput() {
    _hisCall = '';
    _exchange = '';
    _isRstFilled = false;
    _inputControlStreamController.sink.add(clearInput);
  }

  void startContest() {
    final contestRunId = Uuid().v4();

    _contestRunId = contestRunId;
    _contestRunIdStreamController.sink.add(contestRunId);

    _audioPlayer.startPlay();

    _startContestInternal();
  }

  void _startContestInternal() async {
    await _createContestType();

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
        stopContest();
      }
    });

    final elapseTime = Duration.zero;
    _elapseTimeStreamController.sink.add(elapseTime);

    isContestRunning = true;
    _isContestRunningStreamController.sink.add(true);

    _clearInput();
    final (callSign, exchange) = _generateAnswer();
    final initialState = WaitingSubmitCall(
      currentCallAnswer: callSign,
      currentExchangeAnswer: exchange,
    );

    _setupStateMachine(initialState);
  }

  Future<void> _createContestType() async {
    final dxccManager = DxccManager(database: _appDatabase);
    await dxccManager.loadDxcc();

    _contestType = CqWpxContestType(
      stationCallsign: _appSettings.stationCallsign,
      dxccManager: dxccManager,
    );
  }

  Future<ScoreManager> _createScoreManager() async {
    return ScoreManager(
      contestId: _appSettings.contestId,
      stationCallsign: _appSettings.stationCallsign,
      scoreCalculator: _contestType.scoreCalculator,
    );
  }

  (String, String) _generateAnswer() {
    List<String> callSigns = _callsignLoader.callSigns;

    final random = Random();
    final index = random.nextInt(callSigns.length);
    final callSign = callSigns[index];

    final exchangManager = _contestType.exchangeManager;
    final exchange = exchangManager.generateExchange();

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

        if (toState is WaitingSubmitExchange && !_isRstFilled) {
          _isRstFilled = true;
          _inputControlStreamController.sink.add(fillRst);
        }
      },
    );

    _handleToState(waitingSubmitCall);
  }

  Future<void> _handleToState(SingleCallRunState toState) async {
    _setupRetryTimer(toState);

    await _playAudio(toState);

    switch (toState) {
      case ReportMyExchange():
        await _handleReportMyExchange(toState);
        break;
      case QsoEnd():
        await _handleQsoEnd(toState);
        break;
      default:
        break;
    }
  }

  Future<void> _playAudio(SingleCallRunState toState) async {
    switch (toState) {
      case WaitingSubmitCall():
        final currentCallAnswer = toState.currentCallAnswer;
        logger.i('play audio!!: $currentCallAnswer');
        final pcmData = await payloadToAudioData(toState.currentCallAnswer);
        await _playAudioInternal(pcmData);
        break;
      case WaitingSubmitExchange():
        await _playAudioByPlayType(toState.audioPlayType);
        break;
      case QsoEnd():
        final pcmData = await loadAssetsWavPcmData('$globalRunPath/TU QRZ.wav');
        _audioPlayer.addAudioData(pcmData);
        break;
      case ReportMyExchange():
        await _playAudioByPlayType(toState.audioPlayType);
        break;
    }
  }

  Future<void> _playAudioByPlayType(AudioPlayType playType) async {
    switch (playType) {
      case NoPlay():
        _audioPlayer.stopPlay();
        break;
      case PlayExchange():
        final pcmData = await exchangeToAudioData(
          playType.exchangeToPlay,
          isMe: playType.isMe,
        );
        await _playAudioInternal(pcmData);
        break;
      case PlayCallExchange():
        final callSignPcmData = await payloadToAudioData(
          playType.call,
          isMe: playType.isMe,
        );
        final exchangePcmData = await exchangeToAudioData(
          playType.exchange,
          isMe: playType.isMe,
        );
        final pcmData = concatUint8List([callSignPcmData, exchangePcmData]);
        await _playAudioInternal(pcmData);
        break;
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
      case ReportMyExchange():
        break;
    }
  }

  Future<void> _handleReportMyExchange(ReportMyExchange toState) async {
    await _waitAudioNotPlaying();
    await Future.delayed(Duration(milliseconds: 500));
    _stateMachine?.transition(ReceiveExchange());
  }

  Future<void> _waitAudioNotPlaying() async {
    while (_audioPlayer.isPlaying()) {
      await Future.delayed(Duration(milliseconds: 100));
    }
  }

  Future<void> _handleQsoEnd(QsoEnd toState) async {
    final submitQso = await _appDatabase.qsoTable.insertReturningOrNull(
      QsoTableCompanion.insert(
        utcInSeconds: _elapseTime.inSeconds,
        runId: _contestRunId,
        stationCallsign: _appSettings.stationCallsign,
        callsign: toState.submitCall,
        callsignCorrect: toState.currentCallAnswer,
        exchange: _contestType.exchangeManager.processExchange(
          toState.submitExchange,
        ),
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
      NextCall(callAnswer: callSign, exchangeAnswer: exchange),
    );

    _clearInput();
  }

  void stopContest() {
    final contestTimer = _contestTimer;

    if (contestTimer != null && contestTimer.isActive) {
      contestTimer.cancel();
      _contestTimer = null;
    }

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
