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
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/state_machine/state_machine.dart';

import '../../dxcc/dxcc_manager.dart';

const _timeoutDuration = Duration(seconds: 10);

class ContestStateChangeHandler {
  final String _contestRunId;
  final ContestTimer _contestTimer;
  final ContestType _contestType;
  final ContestDataManager _contestDataManager;
  final StateMachine<SingleCallRunState, SingleCallRunEvent, Null>
  _stateMachine;
  final ScoreManager _scoreManager;
  final ContestAnswerGenerator _answerGenerator;

  late final AudioLoader _audioLoader = _contestDataManager.audioLoader;
  late final AudioPlayer _audioPlayer = _contestDataManager.audioPlayer;
  late final String _stationCallsign =
      _contestDataManager.appSettings.stationCallsign;
  late final AppDatabase _appDatabase = _contestDataManager.appDatabase;
  late final ContestInputHandler _inputHandler =
      _contestDataManager.inputHandler;

  late final DxccManager _dxccManager = _contestDataManager.dxccManager;
  late final AppSettings _appSettings = _contestDataManager.appSettings;

  Timer? _retryTimer;

  ContestStateChangeHandler({
    required String contestRunId,
    required ContestTimer contestTimer,
    required ContestType contestType,
    required ContestDataManager contestDataManager,
    required StateMachine<SingleCallRunState, SingleCallRunEvent, Null>
    stateMachine,
    required ScoreManager scoreManager,
    required ContestAnswerGenerator contestAnswerGenerator,
  }) : _contestRunId = contestRunId,
       _contestTimer = contestTimer,
       _contestType = contestType,
       _contestDataManager = contestDataManager,
       _stateMachine = stateMachine,
       _scoreManager = scoreManager,
       _answerGenerator = contestAnswerGenerator;

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
        final dxccId = _dxccManager.findCallsignDxccId(
          toState.currentCallAnswer,
        );
        await _playAudioByPlayType(toState.audioPlayType, dxccId);
        break;
      case WaitingSubmitMyExchange():
        final dxccId = _dxccManager.findCallsignDxccId(
          toState.currentCallAnswer,
        );
        await _playAudioByPlayType(
          toState.audioPlayType,
          dxccId,
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
        final dxccId = _dxccManager.findCallsignDxccId(
          toState.currentCallAnswer,
        );
        await _playAudioByPlayType(
          toState.audioPlayType,
          dxccId,
          isResetAudioStream: true,
        );
        break;
      case HeAskForExchange():
        final dxccId = _dxccManager.findCallsignDxccId(
          toState.currentCallAnswer,
        );
        final accent = obtainAccentByDxccId(dxccId);
        final list = [
          if (toState.isPlayMyCall)
            await _audioLoader.loadAudio(
              obtainAccentByDxccId(dxccId),
              CallsignPayload(
                callsign: _stationCallsign,
                phonicType: _appSettings.phonicType,
              ),
            ),
          await loadAssetsWavPcmData('$accent/Common/NR.wav'),
        ];

        final pcmData = await concatUint8List(list);
        _audioPlayer.addAudioData(pcmData);
        break;
      case HeRepeatCorrectCallAnswer():
        final dxccId = _dxccManager.findCallsignDxccId(
          toState.currentCallAnswer,
        );

        final pcmData = await _audioLoader.loadAudio(
          obtainAssetDir(false, dxccId),
          CallsignPayload(
            callsign: toState.currentCallAnswer,
            phonicType: _appSettings.phonicType,
          ),
        );

        _audioPlayer.addAudioData(pcmData);
        break;
    }
  }

  Future<void> _playAudioByPlayType(
    AudioPlayType playType,
    int dxccId, {
    bool isResetAudioStream = false,
  }) async {
    switch (playType) {
      case NoPlay():
        // play nothing
        break;
      case PlayExchange():
        final assetDir = obtainAssetDir(playType.isMe, dxccId);
        final rstAudioFileName = obtainRstAudioFileName(playType.isMe);

        final rstPcmData = await _audioLoader.loadAudio(
          assetDir,
          CommonPayload(fileName: rstAudioFileName),
        );

        final exchangePcmData = await _audioLoader.loadAudio(
          assetDir,
          CallsignPayload(
            callsign: playType.exchangeToPlay,
            phonicType: _appSettings.phonicType,
          ),
        );

        final pcmData = await concatUint8List([rstPcmData, exchangePcmData]);

        _audioPlayer.addAudioData(
          pcmData,
          isResetCurrentStream: isResetAudioStream,
          isMyAudio: playType.isMe,
        );
        break;
      case PlayCallExchange():
        final callSignPcmData = await _audioLoader.loadAudio(
          obtainAssetDir(playType.isMe, dxccId),
          CallsignPayload(
            callsign: playType.call,
            phonicType: _appSettings.phonicType,
          ),
        );

        final rstPcmData = await _audioLoader.loadAudio(
          obtainAssetDir(playType.isMe, dxccId),
          CommonPayload(
            fileName: obtainRstAudioFileName(
              playType.isMe,
              isCallsignCorrect: false,
            ),
          ),
        );

        final exchangePcmData = await _audioLoader.loadAudio(
          obtainAssetDir(playType.isMe, dxccId),
          CallsignPayload(
            callsign: playType.exchangeToPlay,
            phonicType: _appSettings.phonicType,
          ),
        );

        final pcmData = await concatUint8List([
          callSignPcmData,
          rstPcmData,
          exchangePcmData,
        ]);

        _audioPlayer.addAudioData(
          pcmData,
          isResetCurrentStream: isResetAudioStream,
          isMyAudio: playType.isMe,
        );
        break;
      case PlayCall():
        final pcmData = await _audioLoader.loadAudio(
          obtainAssetDir(playType.isMe, dxccId),
          CallsignPayload(
            callsign: playType.callToPlay,
            phonicType: _appSettings.phonicType,
          ),
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
