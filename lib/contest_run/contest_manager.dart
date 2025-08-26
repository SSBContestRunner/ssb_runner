import 'dart:async';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart';
import 'package:ssb_runner/audio/audio_loader.dart';
import 'package:ssb_runner/audio/audio_player.dart';
import 'package:ssb_runner/audio/payload_to_audio.dart';
import 'package:ssb_runner/callsign/callsign_loader.dart';
import 'package:ssb_runner/common/calculate_list_diff.dart';
import 'package:ssb_runner/common/concat_bytes.dart';
import 'package:ssb_runner/common/constants.dart';
import 'package:ssb_runner/contest_run/key_event_handler.dart';
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
const switchCallsignAndExchange = 10003;

class ContestManager {
  Timer? _contestTimer;
  Timer? _retryTimer;

  String _contestRunId = '';
  final _contestRunIdStreamController = StreamController<String>.broadcast();

  Stream<String> get contestRunIdStream => _contestRunIdStreamController.stream;

  Duration _elapseTime = Duration.zero;
  final _elapseTimeStreamController = StreamController<Duration>.broadcast();

  Stream<Duration> get elapseTimeStream => _elapseTimeStreamController.stream;

  bool isContestRunning = false;
  final _isContestRunningStreamController = StreamController<bool>.broadcast();

  Stream<bool> get isContestRunningStream =>
      _isContestRunningStreamController.stream;

  ScoreManager? scoreManager;

  final _inputControlStreamController = StreamController<int>();

  Stream<int> get inputControlStream => _inputControlStreamController.stream;

  final _keyEventManager = KeyEventHandler();

  StateMachine<SingleCallRunState, SingleCallRunEvent, Null>? _stateMachine;

  final AppSettings _appSettings;
  final AppDatabase _appDatabase;
  final AudioPlayer _audioPlayer;
  final AudioLoader _audioLoader;
  final CallsignLoader _callsignLoader;
  final DxccManager _dxccManager;

  late ContestType _contestType;

  ContestManager({
    required CallsignLoader callsignLoader,
    required AppSettings appSettings,
    required AppDatabase appDatabase,
    required AudioPlayer audioPlayer,
    required AudioLoader audioLoader,
    required DxccManager dxccManager,
  }) : _appSettings = appSettings,
       _appDatabase = appDatabase,
       _audioPlayer = audioPlayer,
       _audioLoader = audioLoader,
       _callsignLoader = callsignLoader,
       _dxccManager = dxccManager {
    _initKeyEventHandling();
  }

  void _initKeyEventHandling() {
    _keyEventManager.operationEventStream.listen((event) {
      handleOperationEvent(event);
    });

    _keyEventManager.inputAreaEventStream.listen((event) {
      _handleInputAreaEvent(event);
    });

    ServicesBinding.instance.keyboard.addHandler((event) {
      _keyEventManager.onKeyEvent(event);
      return false;
    });
  }

  // region operation event handler
  Future<void> handleOperationEvent(OperationEvent event) async {
    if (!isContestRunning) {
      return;
    }
    await _playAudioByOperationEvent(event);
    await _handleOperationEventBusiness(event);
  }

  Future<void> _playAudioByOperationEvent(OperationEvent event) async {
    Uint8List? pcmData;

    switch (event) {
      case OperationEvent.cq:
        pcmData = await obtainMyCqAudioData();
        break;
      case OperationEvent.exch:
        pcmData = await obtainMySentExchangeAudioData();
        break;
      case OperationEvent.tu:
        pcmData = await _audioLoader.loadAudio(
          myAudioAccentDir,
          CommonPayload(fileName: 'TU_QRZ.wav'),
        );
        break;
      case OperationEvent.myCall:
        pcmData = await _audioLoader.loadAudio(
          myAudioAccentDir,
          CallsignPayload(
            callsign: _appSettings.stationCallsign,
            phonicType: PhonicType.standard,
          ),
        );
        break;
      case OperationEvent.hisCall:
        pcmData = _hisCall.isNotEmpty
            ? await _audioLoader.loadAudio(
                myAudioAccentDir,
                CallsignPayload(
                  callsign: _hisCall,
                  phonicType: PhonicType.standard,
                ),
              )
            : null;
        break;
      case OperationEvent.b4:
        pcmData = await _audioLoader.loadAudio(
          myAudioAccentDir,
          CommonPayload(fileName: 'BEFORE.wav'),
        );
        break;
      case OperationEvent.agn:
        pcmData = await _audioLoader.loadAudio(
          myAudioAccentDir,
          CommonPayload(fileName: 'AGN.wav'),
        );
        break;
      case OperationEvent.nil:
        pcmData = await _audioLoader.loadAudio(
          myAudioAccentDir,
          CommonPayload(fileName: 'NO_COPY.wav'),
        );
        break;
      case OperationEvent.hisCallAndMyExchange:
        final hisCall = _hisCall;
        if (hisCall.isEmpty) {
          break;
        }
        pcmData = await obtainHisCallAndMyExchange(hisCall);
        break;
      case OperationEvent.submit:
      case OperationEvent.cancel:
        break;
    }

    final pcmDataVal = pcmData;
    if (pcmDataVal != null) {
      _audioPlayer.addAudioData(
        pcmDataVal,
        isResetCurrentStream: true,
        isMyAudio: true,
      );
    }
  }

  Future<Uint8List> obtainMyCqAudioData() async {
    final cqAudio = await _audioLoader.loadAudio(
      myAudioAccentDir,
      CommonPayload(fileName: 'CQ.wav'),
    );
    final myCallSign = _appSettings.stationCallsign;
    final myCallSignAudio = await _audioLoader.loadAudio(
      myAudioAccentDir,
      CallsignPayload(callsign: myCallSign, phonicType: PhonicType.standard),
    );
    return await concatUint8List([cqAudio, myCallSignAudio]);
  }

  Future<Uint8List> obtainMySentExchangeAudioData() async {
    return _audioLoader.loadAudio(
      myAudioAccentDir,
      CallsignPayload(
        callsign: await _obtainHisExchange(),
        phonicType: PhonicType.standard,
      ),
    );
  }

  Future<Uint8List> obtainHisCallAndMyExchange(String hisCall) async {
    final hisCallPcmData = await _audioLoader.loadAudio(
      myAudioAccentDir,
      CallsignPayload(callsign: hisCall, phonicType: PhonicType.standard),
    );
    final myExchangePcmData = await _audioLoader.loadAudio(
      myAudioAccentDir,
      CallsignPayload(
        callsign: await _obtainHisExchange(),
        phonicType: PhonicType.standard,
      ),
    );
    return await concatUint8List([hisCallPcmData, myExchangePcmData]);
  }

  Future<void> _handleOperationEventBusiness(OperationEvent event) async {
    switch (event) {
      case OperationEvent.cq:
      case OperationEvent.agn:
        transition(Retry());
        break;
      case OperationEvent.submit:
        _handleSubmit();
        break;
      case OperationEvent.cancel:
        _handleCancel();
        break;
      case OperationEvent.hisCall:
        _handleHisCall();
        break;
      case OperationEvent.hisCallAndMyExchange:
        _handleHisCallAndMyExchange();
        break;
      case OperationEvent.exch:
        _handleExchEvent();
        break;
      default:
        break;
    }
  }

  String _hisCall = '';
  String _exchange = '';
  bool _isRstFilled = false;

  Future<void> _handleSubmit({bool isOperateInput = true}) async {
    if (_hisCall.isEmpty && _exchange.isEmpty) {
      transition(Retry());
      return;
    }

    if (_hisCall.isNotEmpty && _exchange.isNotEmpty) {
      transition(SubmitMyExchange(exchange: _exchange));
      return;
    }

    if (_hisCall.isNotEmpty) {
      transition(
        SubmitCallAndHisExchange(
          call: _hisCall,
          hisExchange: await _obtainHisExchange(),
          isOperateInput: isOperateInput,
        ),
      );
      return;
    }
  }

  Future<String> _obtainHisExchange() async {
    final count = await _appDatabase.qsoTable
        .count(
          where: (row) {
            return row.runId.equals(_contestRunId);
          },
        )
        .getSingle();

    return '${count + 1}';
  }

  void _handleCancel() {
    if (_audioPlayer.isMePlaying()) {
      _stateMachine?.transition(Cancel());
      _audioPlayer.resetStream();
    }
  }

  Future<void> _handleHisCall() async {
    await _waitAudioNotPlaying();

    if (_hisCall.isEmpty) {
      return;
    }

    if (_stateMachine?.currentState is WaitingSubmitCall) {
      _stateMachine?.transition(SubmitCall(call: _hisCall));
      return;
    }

    if (_stateMachine?.currentState is HeAskForExchange) {
      transition(Retry());
      return;
    }
  }

  void _handleHisCallAndMyExchange() {
    if (_stateMachine?.currentState is WaitingSubmitCall) {
      _handleSubmit(isOperateInput: false);
      return;
    }

    if (_stateMachine?.currentState is WaitingSubmitMyExchange) {
      transition(Retry());
      return;
    }
  }

  Future<void> _handleExchEvent() async {
    logger.d('exch event');
    _stateMachine?.transition(
      SubmitHisExchange(exchange: await _obtainHisExchange()),
    );
  }

  void _handleInputAreaEvent(InputAreaEvent event) {
    switch (event) {
      case InputAreaEvent.switchCallsignAndExchange:
        _inputControlStreamController.sink.add(switchCallsignAndExchange);
        _isRstFilled = true;
        break;
    }
  }

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

  // endregion

  void startContest() async {
    _audioPlayer.startPlay();
    await _startContestInternal();
  }

  Future<void> _startContestInternal() async {
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

    final contestRunId = Uuid().v4();
    _contestRunId = contestRunId;
    _contestRunIdStreamController.sink.add(contestRunId);

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
    _contestType = CqWpxContestType(
      stationCallsign: _appSettings.stationCallsign,
      dxccManager: _dxccManager,
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
        _handleToState(toState, event: transition.event);

        if (toState is WaitingSubmitMyExchange &&
            toState.isOperateInput &&
            !_isRstFilled) {
          _isRstFilled = true;
          _inputControlStreamController.sink.add(fillRst);
        }
      },
    );

    _handleToState(waitingSubmitCall);
  }

  // region state change handler
  Future<void> _handleToState(
    SingleCallRunState toState, {
    SingleCallRunEvent? event,
  }) async {
    _setupRetryTimer(toState);

    await _playAudioByStateChange(toState, event);

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

  Future<void> _playAudioByStateChange(
    SingleCallRunState toState,
    SingleCallRunEvent? event,
  ) async {
    switch (toState) {
      case WaitingSubmitCall():
        await _playAudioByPlayType(toState.audioPlayType);
        break;
      case WaitingSubmitMyExchange():
        await _playAudioByPlayType(
          toState.audioPlayType,
          isResetAudioStream: event is SubmitCallAndHisExchange,
        );
        break;
      case QsoEnd():
        final pcmData = await _audioLoader.loadAudio(
          myAudioAccentDir,
          CommonPayload(fileName: 'TU_QRZ.wav'),
        );
        _audioPlayer.addAudioData(
          pcmData,
          isResetCurrentStream: true,
          isMyAudio: true,
        );
        break;
      case ReportMyExchange():
        await _playAudioByPlayType(
          toState.audioPlayType,
          isResetAudioStream: true,
        );
        break;
      case HeAskForExchange():
        final list = [
          if (toState.isPlayMyCall)
            await payloadToAudioData(_appSettings.stationCallsign, isMe: false),
          await loadAssetsWavPcmData('English-US/Common/NR.wav'),
        ];

        final pcmData = await concatUint8List(list);
        _audioPlayer.addAudioData(pcmData);
        break;
      case HeRepeatCorrectCallAnswer():
        final pcmData = await payloadToAudioData(toState.currentCallAnswer);
        _audioPlayer.addAudioData(pcmData);
        break;
    }
  }

  Future<void> _playAudioByPlayType(
    AudioPlayType playType, {
    bool isResetAudioStream = false,
  }) async {
    switch (playType) {
      case NoPlay():
        // play nothing
        break;
      case PlayExchange():
        final pcmData = await exchangeToAudioData(
          playType.exchangeToPlay,
          isMe: playType.isMe,
        );
        _audioPlayer.addAudioData(
          pcmData,
          isResetCurrentStream: isResetAudioStream,
          isMyAudio: playType.isMe,
        );
        break;
      case PlayCallExchange():
        final callSignPcmData = await payloadToAudioData(
          playType.call,
          isMe: playType.isMe,
        );
        final exchangePcmData = await exchangeToAudioData(
          playType.exchangeToPlay,
          isMe: playType.isMe,
          isCallsignCorrect: false,
        );

        final pcmData = await concatUint8List([
          callSignPcmData,
          exchangePcmData,
        ]);

        _audioPlayer.addAudioData(
          pcmData,
          isResetCurrentStream: isResetAudioStream,
          isMyAudio: playType.isMe,
        );
        break;
      case PlayCall():
        final pcmData = await payloadToAudioData(
          playType.callToPlay,
          isMe: playType.isMe,
        );
        _audioPlayer.addAudioData(
          pcmData,
          isResetCurrentStream: isResetAudioStream,
          isMyAudio: playType.isMe,
        );
        break;
    }
  }

  void _setupRetryTimer(SingleCallRunState toState) {
    _retryTimer?.cancel();

    switch (toState) {
      case WaitingSubmitCall():
      case WaitingSubmitMyExchange():
      case HeAskForExchange():
      case HeRepeatCorrectCallAnswer():
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
    logger.d('_handleReportMyExchange!');
    await _waitAudioNotPlaying();

    final currentState = _stateMachine?.currentState;
    logger.d('currentState: $currentState');
    if (_stateMachine?.currentState is! ReportMyExchange) {
      return;
    }

    await Future.delayed(Duration(milliseconds: 500));

    final misMatchCallsignLength = calculateMismatch(
      answer: toState.currentCallAnswer,
      submit: toState.submitCall,
    );

    if (misMatchCallsignLength >= callsignMismatchThreadshold) {
      _stateMachine?.transition(CallsignInvalid());
    } else {
      _stateMachine?.transition(ReceiveExchange());
    }
  }

  Future<void> _waitAudioNotPlaying() async {
    while (_audioPlayer.isPlaying()) {
      await Future.delayed(Duration(milliseconds: 100));
    }
  }

  Future<void> _handleQsoEnd(QsoEnd toState) async {
    final callsign = _hisCall;
    final exchange = _exchange;

    if (callsign.isEmpty || exchange.isEmpty) {
      return;
    }

    final submitQso = await _appDatabase.qsoTable.insertReturningOrNull(
      QsoTableCompanion.insert(
        utcInSeconds: _elapseTime.inSeconds,
        runId: _contestRunId,
        stationCallsign: _appSettings.stationCallsign,
        callsign: callsign,
        callsignCorrect: toState.currentCallAnswer,
        exchange: _contestType.exchangeManager.processExchange(exchange),
        exchangeCorrect: toState.currentExchangeAnswer,
      ),
    );

    if (submitQso == null) {
      return;
    }

    final latestQsos =
        await (_appDatabase.qsoTable.select()..where((qsoTable) {
              return qsoTable.runId.equals(_contestRunId);
            }))
            .get();
    scoreManager?.addQso(latestQsos, submitQso);

    final (callSignAnswer, exchangeAnswer) = _generateAnswer();
    _clearInput();

    await _waitAudioNotPlaying();
    _stateMachine?.transition(
      NextCall(callAnswer: callSignAnswer, exchangeAnswer: exchangeAnswer),
    );
  }

  // endregion

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

  Future<int> countCurrentRunQso() async {
    return await _appDatabase.qsoTable
            .count(
              where: (row) {
                return row.runId.equals(_contestRunId);
              },
            )
            .getSingleOrNull() ??
        0;
  }
}
