import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:ssb_runner/audio/audio_player.dart';
import 'package:ssb_runner/contest_run/state_machine/single_call/single_call_run_event.dart';
import 'package:ssb_runner/contest_run/state_machine/single_call/single_call_run_state.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/state_machine/state_machine.dart';

import '../audio/audio_loader.dart';
import '../common/concat_bytes.dart';
import '../db/app_database.dart';
import '../main.dart';
import 'key_event_handler.dart';

class OperationEventHandler {
  final AudioLoader _audioLoader;
  final AppDatabase _appDatabase;
  final AppSettings _appSettings;
  final AudioPlayer _audioPlayer;

  final String _contestRunId;

  final StateMachine<SingleCallRunState, SingleCallRunEvent, Null>?
  _stateMachine;

  String _hisCall = '';
  String _exchange = '';
  bool _isRstFilled = false;

  OperationEventHandler({
    required String contestRunId,
    required AudioLoader audioLoader,
    required AudioPlayer audioPlayer,
    required AppDatabase appDatabase,
    required AppSettings appSettings,
    required StateMachine<SingleCallRunState, SingleCallRunEvent, Null>?
    stateMachine,
  }) : _contestRunId = contestRunId,
       _audioLoader = audioLoader,
       _audioPlayer = audioPlayer,
       _appDatabase = appDatabase,
       _appSettings = appSettings,
       _stateMachine = stateMachine;

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

  void transition(SingleCallRunEvent event) {
    _stateMachine?.transition(event);
  }

  Future<void> _waitAudioNotPlaying() async {
    while (_audioPlayer.isPlaying()) {
      await Future.delayed(Duration(milliseconds: 100));
    }
  }
}
