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
  /// Runs an operation event and reports whether it did anything.
  ///
  /// `false` means the key was recognised but the current phase has nothing to
  /// do with it; the console turns that into a short hint instead of leaving a
  /// dead key press that looks like a broken keyboard.
  Future<bool> handleOperationEvent(OperationEvent event) async {
    // Paused runs are frozen: report the key as handled so it never reaches the
    // "ignored shortcut" hint, and change no state.
    if (_isPaused) {
      return true;
    }
    log.debug('operation event', tag: 'contest', fields: {'event': event.name});

    // The combined "his call + my serial" clip is part of the dispatch: it may
    // only go out when the current state accepts the shortcut. Playing it
    // unconditionally used to transmit audio the simulation never answered.
    if (event == OperationEvent.hisCallAndMyExchange) {
      return _handleHisCallAndMyExchange();
    }

    await _playAudioByOperationEvent(event);
    await _handleOperationEventBusiness(event);
    return true;
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
        // Audio and state change are dispatched together in
        // _handleHisCallAndMyExchange; playing here as well would double it.
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

    if (currentState is WaitingSubmitCall ||
        currentState is HeRepeatCorrectCallAnswer) {
      await _submitCallAndMyExchange(isOperateInput: isOperateInput);
      return;
    }

    if (currentState is WaitingSubmitMyExchange) {
      // Nothing copied for his serial yet: replay it instead of emitting a
      // `SubmitCallAndHisExchange` this state has no handler for, which used
      // to lose the key press behind a dropped-event warning.
      if (_exchange.isEmpty) {
        transition(Retry());
        return;
      }

      transition(SubmitMyExchange(exchange: _exchange, call: _hisCall));
      return;
    }

    // ReportMyExchange / QsoEnd / SpQsoEnd accept no submission: Enter is a
    // no-op there, recorded instead of dropped silently.
    log.debug(
      'submit ignored',
      tag: 'contest',
      fields: {'state': '${currentState.runtimeType}'},
    );
  }

  /// Sends his call and our serial as one transmission. Both states that owe
  /// it (`WaitingSubmitCall` and `HeRepeatCorrectCallAnswer`) handle the same
  /// `SubmitCallAndHisExchange`, so the event cannot be dropped; an empty
  /// copy asks him to repeat instead of staying mute.
  Future<void> _submitCallAndMyExchange({required bool isOperateInput}) async {
    if (_hisCall.isEmpty) {
      transition(Retry());
      return;
    }

    transition(
      SubmitCallAndHisExchange(
        call: _hisCall,
        myExchange: await _myExchange(),
        isOperateInput: isOperateInput,
      ),
    );
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

  /// The `;` shortcut: one transmission with his call and our serial.
  ///
  /// Audio and the state change are decided together here. It used to play the
  /// combined clip in every state while only two states advanced, so pressing
  /// it mid-QSO transmitted audio the run never answered. Every state is listed
  /// explicitly, in the same layout as [_handleHisCall], so a state that is
  /// added later cannot be swallowed silently.
  ///
  /// Returns false only where the shortcut is deliberately ignored, so the
  /// console can say so instead of leaving the operator wondering.
  Future<bool> _handleHisCallAndMyExchange() async {
    final currentState = _stateMachine.currentState;

    switch (currentState) {
      case WaitingSubmitCall():
      case HeRepeatCorrectCallAnswer():
        if (_hisCall.isEmpty) {
          // Nothing copied yet: ask him to repeat instead of staying mute.
          log.debug(
            'his call + my exchange: no call copied, repeating',
            tag: 'contest',
            fields: {'state': '${currentState.runtimeType}'},
          );
          transition(Retry());
          return true;
        }

        await _playHisCallAndMyExchange(_hisCall);
        transition(
          SubmitCallAndHisExchange(
            call: _hisCall,
            myExchange: await _myExchange(),
            isOperateInput: false,
          ),
        );
        return true;
      case WaitingSubmitMyExchange():
        // Already sent our report: the shortcut asks him to repeat his serial.
        if (_hisCall.isNotEmpty) {
          await _playHisCallAndMyExchange(_hisCall);
        }
        transition(Retry());
        return true;
      case HeAskForExchange():
        // He is asking for our serial; the combined clip would talk over him.
        transition(Retry());
        return true;
      case SpListeningCq():
      case SpWaitingHisExchange():
        // S&P keeps its two-Enter model: `;` is another Enter, no combined clip.
        await _handleSubmit(isOperateInput: false);
        return true;
      case ReportMyExchange():
      case QsoEnd():
      case SpQsoEnd():
        log.debug(
          'his call + my exchange ignored',
          tag: 'contest',
          fields: {'state': '${currentState.runtimeType}'},
        );
        return false;
    }
  }

  Future<void> _playHisCallAndMyExchange(String hisCall) async {
    final pcmData = await obtainHisCallAndMyExchange(hisCall);
    _audioPlayer.addAudioData(
      pcmData,
      isResetCurrentStream: true,
      isMyAudio: true,
    );
  }

  Future<void> _handleExchEvent() async {
    log.debug('exch event', tag: 'contest');
    _stateMachine.transition(SubmitHisExchange(exchange: await _myExchange()));
  }

  void handleInputAreaEvent() {
    if (_isPaused) {
      return;
    }
    _isRstFilled = true;
  }

  // endregion

  void transition(SingleCallRunEvent event) {
    _stateMachine.transition(event);
  }

  bool _isPaused = false;

  /// Freezes the operation-side wait chain for the training pause.
  void pause() {
    _isPaused = true;
  }

  void resume() {
    _isPaused = false;
  }

  /// Parks the caller while the session is paused.
  Future<void> _waitUntilResumed() async {
    while (_isPaused) {
      await Future.delayed(Duration(milliseconds: 50));
    }
  }

  Future<void> _waitAudioNotPlaying() async {
    await _waitUntilResumed();
    while (_audioPlayer.isPlaying()) {
      await _waitUntilResumed();
      await Future.delayed(Duration(milliseconds: 100));
    }
  }
}
