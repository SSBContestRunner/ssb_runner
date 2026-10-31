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
import 'package:ssb_runner/contest_type/contest_type.dart';
import 'package:ssb_runner/db/app_database.dart';
import 'package:ssb_runner/logging/app_logger.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/state_machine/state_machine.dart';

class ContestOperationEventHandler {
  final String _contestRunId;
  final ContestDataManager _contestDataManager;
  final ContestType _contestType;
  final StateMachine<SingleCallRunState, SingleCallRunEvent, Null>
  _stateMachine;
  final ContestInputHandler _inputHandler;
  final Future<void> Function()? _onAbandonRound;

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
    required ContestType contestType,
    required StateMachine<SingleCallRunState, SingleCallRunEvent, Null>
    stateMachine,
    required ContestInputHandler inputHandler,
    Future<void> Function()? onAbandonRound,
  }) : _contestRunId = contestRunId,
       _contestDataManager = contestDataManager,
       _contestType = contestType,
       _stateMachine = stateMachine,
       _inputHandler = inputHandler,
       _onAbandonRound = onAbandonRound;

  // region operation event handler
  Future<void> handleOperationEvent(OperationEvent event) async {
    log.debug('operation event', tag: 'contest', fields: {'event': event.name});
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
      case OperationEvent.wipe:
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
        callsign: await _myExchange(),
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
        callsign: await _myExchange(),
        phonicType: _appSettings.phonicType,
      ),
    );
    return await concatUint8List([hisCallPcmData, myExchangePcmData]);
  }

  Future<void> _handleOperationEventBusiness(OperationEvent event) async {
    switch (event) {
      case OperationEvent.cq:
        await _handleCq();
        break;
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
      case OperationEvent.wipe:
        // Wipe only clears the operator's input: no state change, no audio,
        // no database write and no operation log.
        _inputHandler.clear();
        break;
      default:
        break;
    }
  }

  /// States of a QSO that has started but not been committed yet. F1 there
  /// means "give up this round", not "call CQ again".
  bool get _isInFlightQso => switch (_stateMachine.currentState) {
    HeRepeatCorrectCallAnswer() ||
    HeAskForExchange() ||
    WaitingSubmitMyExchange() ||
    ReportMyExchange() => true,
    _ => false,
  };

  Future<void> _handleCq() async {
    if (_isInFlightQso) {
      await _onAbandonRound?.call();
      return;
    }

    transition(Retry());
  }

  Future<void> _handleSubmit({bool isOperateInput = true}) async {
    // S&P drives Enter by state (N1MM style): the first Enter pounces with our
    // callsign once his call has been copied, the second sends our exchange and
    // commits. Neither step falls back to the Run-mode input heuristics.
    final currentState = _stateMachine.currentState;
    if (currentState is SpListeningCq) {
      if (_hisCall.isEmpty) {
        transition(Retry());
        return;
      }

      _stateMachine.transition(SpPounce());
      return;
    }

    if (currentState is SpWaitingHisExchange) {
      // His call is committed from the input, and SpQsoEnd handles nothing but
      // its own next call; entering it without the call would park the run.
      if (_hisCall.isEmpty || _exchange.isEmpty) {
        transition(Retry());
        return;
      }

      _stateMachine.transition(
        SpSubmitHisExchange(
          exchange: _exchange,
          myExchange: await _myExchange(),
        ),
      );
      return;
    }

    if (currentState is HeAskForExchange) {
      // He asked for his serial: Enter sends what the operator copied. With
      // nothing copied, replay the request instead of dropping the key press.
      if (_exchange.isEmpty) {
        transition(Retry());
        return;
      }

      transition(SubmitHisExchange(exchange: _exchange));
      return;
    }

    if (_hisCall.isEmpty && _exchange.isEmpty) {
      transition(Retry());
      return;
    }

    if (_hisCall.isNotEmpty && _exchange.isNotEmpty) {
      transition(SubmitMyExchange(exchange: _exchange, call: _hisCall));
      return;
    }

    if (_hisCall.isNotEmpty) {
      transition(
        SubmitCallAndHisExchange(
          call: _hisCall,
          myExchange: await _myExchange(),
          isOperateInput: isOperateInput,
        ),
      );
      return;
    }
  }

  /// The exchange the operator transmits for the current QSO. Contest-aware:
  /// CQ WPX serial, CQ WW/JIDX CQ zone, IARU ITU zone, ARRL power.
  Future<String> _myExchange() async {
    final done = await _appDatabase.qsoTable
        .count(
          where: (row) {
            return row.runId.equals(_contestRunId);
          },
        )
        .getSingle();

    return _contestType.buildMyExchange(done + 1);
  }

  /// Esc stops whatever is being sent, in Run and S&P alike: it drops the
  /// playing or queued audio immediately, as N1MM's "stop sending" does. It
  /// leaves the state machine and the operator's input untouched.
  void _handleCancel() {
    _audioPlayer.resetStream();
  }

  /// F5 (`<his>`) sends the callsign the operator copied. What that means for
  /// the round depends on where it stands, so the states are spelled out
  /// instead of inferred:
  ///
  /// - still waiting for the callsign (or he is repeating it): the copy is
  ///   submitted, as before;
  /// - the callsign is already agreed and he owes us the exchange: he repeats
  ///   his serial, exactly like F7 (AGN). Run and S&P both work this way.
  ///
  /// States outside the matrix (sign-off, report being sent) get nothing on
  /// purpose: they have no `Retry` handler, so a blanket retry would only spam
  /// the state log with dropped-event warnings.
  Future<void> _handleHisCall() async {
    await _waitAudioNotPlaying();

    if (_hisCall.isEmpty) {
      return;
    }

    switch (_stateMachine.currentState) {
      case WaitingSubmitCall():
      case HeRepeatCorrectCallAnswer():
        _stateMachine.transition(SubmitCall(call: _hisCall));
        break;
      case HeAskForExchange():
      case WaitingSubmitMyExchange():
      case SpWaitingHisExchange():
        transition(Retry());
        break;
      default:
        break;
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
    log.debug('exch event', tag: 'contest');
    _stateMachine.transition(SubmitHisExchange(exchange: await _myExchange()));
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
