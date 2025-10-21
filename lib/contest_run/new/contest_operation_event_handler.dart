import 'dart:async';

import 'package:drift/drift.dart';
import 'package:ssb_runner/audio/audio_loader.dart';
import 'package:ssb_runner/audio/audio_player.dart';
import 'package:ssb_runner/common/concat_bytes.dart';
import 'package:ssb_runner/contest_run/key_event_handler.dart';
import 'package:ssb_runner/contest_run/new/contest_data_manager.dart';
import 'package:ssb_runner/contest_run/new/contest_input_handler.dart';
import 'package:ssb_runner/contest_run/state_machine/single_call/single_call_run_event.dart';
import 'package:ssb_runner/contest_run/state_machine/single_call/single_call_run_state.dart';
import 'package:ssb_runner/db/app_database.dart';
import 'package:ssb_runner/main.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/state_machine/state_machine.dart';

class ContestOperationEventHandler {
  final String _contestRunId;
  final ContestDataManager _contestDataManager;
  final StateMachine<SingleCallRunState, SingleCallRunEvent, Null>
  _stateMachine;
  final ContestInputHandler _inputHandler;

  String get _hisCall => _inputHandler.hisCall;

  String get _exchange => _inputHandler.exchange;

  set _isRstFilled(bool value) => _inputHandler.isRstFilled = value;

  late final AudioLoader _audioLoader = _contestDataManager.audioLoader;
  late final AudioPlayer _audioPlayer = _contestDataManager.audioPlayer;
  late final AppSettings _appSettings = _contestDataManager.appSettings;
  late final AppDatabase _appDatabase = _contestDataManager.appDatabase;

  final _inputControlStreamController = StreamController<int>();

  Stream<int> get inputControlStream => _inputControlStreamController.stream;

  ContestOperationEventHandler({
    required String contestRunId,
    required ContestDataManager contestDataManager,
    required StateMachine<SingleCallRunState, SingleCallRunEvent, Null>
    stateMachine,
    required ContestInputHandler inputHandler,
  }) : _contestRunId = contestRunId,
       _contestDataManager = contestDataManager,
       _stateMachine = stateMachine,
       _inputHandler = inputHandler;

  // region operation event handler
  Future<void> handleOperationEvent(OperationEvent event) async {
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
            phonicType: _appSettings.phonicType,
          ),
        );
        break;
      case OperationEvent.hisCall:
        pcmData = _hisCall.isNotEmpty
            ? await _audioLoader.loadAudio(
                myAudioAccentDir,
                CallsignPayload(
                  callsign: _hisCall,
                  phonicType: _appSettings.phonicType,
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
      CallsignPayload(
        callsign: myCallSign,
        phonicType: _appSettings.phonicType,
      ),
    );
    return await concatUint8List([cqAudio, myCallSignAudio]);
  }

  Future<Uint8List> obtainMySentExchangeAudioData() async {
    return _audioLoader.loadAudio(
      myAudioAccentDir,
      CallsignPayload(
        callsign: await _obtainHisExchange(),
        phonicType: _appSettings.phonicType,
      ),
    );
  }

  Future<Uint8List> obtainHisCallAndMyExchange(String hisCall) async {
    final hisCallPcmData = await _audioLoader.loadAudio(
      myAudioAccentDir,
      CallsignPayload(callsign: hisCall, phonicType: _appSettings.phonicType),
    );
    final myExchangePcmData = await _audioLoader.loadAudio(
      myAudioAccentDir,
      CallsignPayload(
        callsign: await _obtainHisExchange(),
        phonicType: _appSettings.phonicType,
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
      _stateMachine.transition(Cancel());
      _audioPlayer.resetStream();
    }
  }

  Future<void> _handleHisCall() async {
    await _waitAudioNotPlaying();

    if (_hisCall.isEmpty) {
      return;
    }

    if (_stateMachine.currentState is WaitingSubmitCall) {
      _stateMachine.transition(SubmitCall(call: _hisCall));
      return;
    }

    if (_stateMachine.currentState is HeAskForExchange) {
      transition(Retry());
      return;
    }
  }

  void _handleHisCallAndMyExchange() {
    if (_stateMachine.currentState is WaitingSubmitCall) {
      _handleSubmit(isOperateInput: false);
      return;
    }

    if (_stateMachine.currentState is WaitingSubmitMyExchange) {
      transition(Retry());
      return;
    }
  }

  Future<void> _handleExchEvent() async {
    logger.d('exch event');
    _stateMachine.transition(
      SubmitHisExchange(exchange: await _obtainHisExchange()),
    );
  }

  void handleInputAreaEvent() {
    _isRstFilled = true;
  }

  // endregion

  void transition(SingleCallRunEvent event) {
    _stateMachine.transition(event);
  }

  Future<void> _waitAudioNotPlaying() async {
    while (_audioPlayer.isPlaying()) {
      await Future.delayed(Duration(milliseconds: 100));
    }
  }
}
