import 'dart:async';

import 'package:drift/drift.dart';
import 'package:ssb_runner/audio/audio_loader.dart';
import 'package:ssb_runner/audio/audio_player.dart';
import 'package:ssb_runner/audio/payload_to_audio.dart';
import 'package:ssb_runner/common/calculate_list_diff.dart';
import 'package:ssb_runner/common/concat_bytes.dart';
import 'package:ssb_runner/common/constants.dart';
import 'package:ssb_runner/contest_run/new/contest_answer_generator.dart';
import 'package:ssb_runner/contest_run/new/contest_data_manager.dart';
import 'package:ssb_runner/contest_run/new/contest_input_handler.dart';
import 'package:ssb_runner/contest_run/new/contest_timer.dart';
import 'package:ssb_runner/contest_run/score_manager.dart';
import 'package:ssb_runner/contest_run/state_machine/single_call/audio_play_type.dart';
import 'package:ssb_runner/contest_run/state_machine/single_call/single_call_run_event.dart';
import 'package:ssb_runner/contest_run/state_machine/single_call/single_call_run_state.dart';
import 'package:ssb_runner/contest_type/contest_type.dart';
import 'package:ssb_runner/db/app_database.dart';
import 'package:ssb_runner/main.dart';
import 'package:ssb_runner/state_machine/state_machine.dart';

const _timeoutDuration = Duration(seconds: 10);

class ContestStateChangeHandler {
  final String _contestRunId;
  final ContestTimer _contestTimer;
  final ContestType _contestType;
  final ContestDataManager _contestDataManager;
  final StateMachine<SingleCallRunState, SingleCallRunEvent, Null>
  _stateMachine;
  final ContestInputHandler _inputHandler;
  final ScoreManager _scoreManager;
  final ContestAnswerGenerator _answerGenerator;

  late final AudioLoader _audioLoader;
  late final AudioPlayer _audioPlayer;
  late final String _stationCallsign;
  late final AppDatabase _appDatabase;

  Timer? _retryTimer;

  ContestStateChangeHandler({
    required String contestRunId,
    required ContestTimer contestTimer,
    required ContestType contestType,
    required ContestDataManager contestDataManager,
    required StateMachine<SingleCallRunState, SingleCallRunEvent, Null>
    stateMachine,
    required ContestInputHandler inputHandler,
    required ScoreManager scoreManager,
    required ContestAnswerGenerator contestAnswerGenerator,
  }) : _contestRunId = contestRunId,
       _contestTimer = contestTimer,
       _contestType = contestType,
       _contestDataManager = contestDataManager,
       _stateMachine = stateMachine,
       _inputHandler = inputHandler,
       _scoreManager = scoreManager,
       _answerGenerator = contestAnswerGenerator {
    _audioLoader = _contestDataManager.audioLoader;

    _audioPlayer = _contestDataManager.audioPlayer;

    _stationCallsign = _contestDataManager.appSettings.stationCallsign;

    _appDatabase = _contestDataManager.appDatabase;
  }

  // region state change handler
  Future<void> handleToState(
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
            await payloadToAudioData(_stationCallsign, isMe: false),
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
          _stateMachine.transition(Retry());
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

    final currentState = _stateMachine.currentState;
    logger.d('currentState: $currentState');
    if (_stateMachine.currentState is! ReportMyExchange) {
      return;
    }

    await Future.delayed(Duration(milliseconds: 500));

    final misMatchCallsignLength = calculateMismatch(
      answer: toState.currentCallAnswer,
      submit: toState.submitCall,
    );

    if (misMatchCallsignLength >= callsignMismatchThreadshold) {
      _stateMachine.transition(CallsignInvalid());
    } else {
      _stateMachine.transition(ReceiveExchange());
    }
  }

  Future<void> _waitAudioNotPlaying() async {
    while (_audioPlayer.isPlaying()) {
      await Future.delayed(Duration(milliseconds: 100));
    }
  }

  Future<void> _handleQsoEnd(QsoEnd toState) async {
    final callsign = _inputHandler.hisCall;
    final exchange = _inputHandler.exchange;

    if (callsign.isEmpty || exchange.isEmpty) {
      return;
    }

    final submitQso = await _appDatabase.qsoTable.insertReturningOrNull(
      QsoTableCompanion.insert(
        utcInSeconds: _contestTimer.elapseTime.inSeconds,
        runId: _contestRunId,
        stationCallsign: _stationCallsign,
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

    _scoreManager.addQso(latestQsos, submitQso);

    final contestAnswer = _answerGenerator.generateAnswer();

    _inputHandler.clear();

    await _waitAudioNotPlaying();
    _stateMachine.transition(
      NextCall(
        callAnswer: contestAnswer.callSign,
        exchangeAnswer: contestAnswer.exchange,
      ),
    );
  }

  // endregion
}
