import 'dart:async';

import 'package:drift/drift.dart';
import 'package:ssb_runner/audio/audio_loader.dart';
import 'package:ssb_runner/audio/audio_player.dart';
import 'package:ssb_runner/audio/mix_pileup.dart';
import 'package:ssb_runner/audio/payload_to_audio.dart';
import 'package:ssb_runner/common/calculate_list_diff.dart';
import 'package:ssb_runner/common/concat_bytes.dart';
import 'package:ssb_runner/contest_run/new/contest_answer_generator.dart';
import 'package:ssb_runner/contest_run/new/contest_data_manager.dart';
import 'package:ssb_runner/contest_run/new/contest_input_handler.dart';
import 'package:ssb_runner/contest_run/new/contest_timer.dart';
import 'package:ssb_runner/contest_run/score_manager.dart';
import 'package:ssb_runner/contest_run/qso_duplicates.dart';
import 'package:ssb_runner/contest_run/state_machine/single_call/audio_play_type.dart';
import 'package:ssb_runner/contest_run/state_machine/single_call/single_call_run_event.dart';
import 'package:ssb_runner/contest_run/state_machine/single_call/single_call_run_state.dart';
import 'package:ssb_runner/contest_type/contest_type.dart';
import 'package:ssb_runner/db/app_database.dart';
import 'package:ssb_runner/logging/app_logger.dart';
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
  final AnswerSource _answerGenerator;
  final void Function(String reason)? _onAnswersExhausted;
  bool _disposed = false;

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
    required AnswerSource contestAnswerGenerator,
    void Function(String reason)? onAnswersExhausted,
  }) : _contestRunId = contestRunId,
       _contestTimer = contestTimer,
       _contestType = contestType,
       _contestDataManager = contestDataManager,
       _stateMachine = stateMachine,
       _scoreManager = scoreManager,
       _answerGenerator = contestAnswerGenerator,
       _onAnswersExhausted = onAnswersExhausted;

  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
  }

  // region state change handler
  Future<void> handleToState(
    SingleCallRunState toState, {
    SingleCallRunEvent? event,
  }) async {
    if (_disposed) return;
    _setupRetryTimer(toState);

    try {
      await _playAudioByStateChange(toState, event);
    } catch (error, stackTrace) {
      // Audio is presentation only: a failed clip must never block QSO
      // logging or the state-machine follow-up below.
      log.error(
        'Failed to play audio for state change',
        tag: 'contest.state',
        fields: <String, Object?>{'to': '$toState', 'event': '$event'},
        error: error,
        stackTrace: stackTrace,
      );
    }

    if (_disposed) return;
    switch (toState) {
      case ReportMyExchange():
        await _handleReportMyExchange(toState);
        break;
      case QsoEnd():
        // Commit from the state snapshot rather than the live input: this
        // state's sign-off audio loads asynchronously, and the operator may
        // still be editing the fields while it does.
        await _logQsoAndAdvance(
          correctCall: toState.currentCallAnswer,
          correctExchange: toState.currentExchangeAnswer,
          submitCall: toState.correctedCall ?? toState.submitCall,
          submitExchange: toState.submitExchange,
        );
        break;
      case SpQsoEnd():
        // The second Enter commits the QSO; his TU and the next CQ follow.
        // SpQsoEnd carries no copy of the runner's call, so read it here; the
        // submit handler already refuses to enter without it.
        await _logQsoAndAdvance(
          correctCall: toState.currentCallAnswer,
          correctExchange: toState.currentExchangeAnswer,
          submitCall: _inputHandler.hisCall,
          submitExchange: _inputHandler.exchange,
        );
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
        // When the operator fixed the callsign while copying the exchange, read
        // the corrected call before signing off so both sides agree on it.
        final correctedCall = toState.correctedCall;
        final list = [
          if (correctedCall != null)
            await _audioLoader.loadAudio(
              myAudioAccentDir,
              CallsignPayload(
                callsign: correctedCall,
                phonicType: _appSettings.phonicType,
              ),
            ),
          await _audioLoader.loadAudio(
            myAudioAccentDir,
            CommonPayload(fileName: 'TU_QRZ.wav'),
          ),
        ];
        final pcmData = await concatUint8List(list);
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
          await _audioLoader.loadAudio(
            accent,
            CommonPayload(fileName: 'NR.wav'),
          ),
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
      case SpListeningCq():
        // A runner calling CQ; pressing Enter pounces with our callsign. On a
        // Retry (the operator pressed AGN/CQ for a repeat) our own clip is
        // already playing, so the runner's CQ is queued behind it instead of
        // resetting the stream — otherwise the AGN is cut off unheard. Entering
        // the state fresh replaces whatever came before.
        await _playAudioByPlayType(
          PlaySearchAndPounce(call: toState.currentCallAnswer),
          _dxccManager.findCallsignDxccId(toState.currentCallAnswer),
          isResetAudioStream: event is! Retry,
        );
        break;
      case SpWaitingHisExchange():
        final dxccId = _dxccManager.findCallsignDxccId(
          toState.currentCallAnswer,
        );
        // On the initial pounce, send our callsign before the runner answers;
        // on Retry the callsign has already been sent, so replay only the answer.
        if (event is SpPounce) {
          final myCallPcmData = await _audioLoader.loadAudio(
            myAudioAccentDir,
            CallsignPayload(
              callsign: _stationCallsign,
              phonicType: _appSettings.phonicType,
            ),
          );
          _audioPlayer.addAudioData(
            myCallPcmData,
            isResetCurrentStream: true,
            isMyAudio: true,
          );
        }
        // The runner answers with our call + his exchange.
        await _playAudioByPlayType(
          PlayCallExchange(
            call: _stationCallsign,
            exchange: toState.currentExchangeAnswer,
            isMe: false,
          ),
          dxccId,
        );
        break;
      case SpQsoEnd():
        final dxccId = _dxccManager.findCallsignDxccId(
          toState.currentCallAnswer,
        );
        // Step 4: we send "Roger + our serial", interrupting whatever is still
        // playing since the operator sent it with Enter.
        await _playAudioByPlayType(
          PlayExchange(exchange: toState.myExchange, isMe: true),
          dxccId,
          isResetAudioStream: true,
        );
        // Step 5: he signs off with TU. No received-TU clip exists, so the
        // operator's own TU clip is reused as a received signal.
        final tuPcmData = await _audioLoader.loadAudio(
          myAudioAccentDir,
          CommonPayload(fileName: 'TU_QRZ.wav'),
        );
        _audioPlayer.addAudioData(tuPcmData);
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
            callsign: _contestType.formatExchangeForAudio(
              playType.exchangeToPlay,
            ),
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
            callsign: _contestType.formatExchangeForAudio(
              playType.exchangeToPlay,
            ),
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
      case PlayPileup():
        final clips = await Future.wait(
          playType.calls.map(
            (callsign) => _audioLoader.loadAudio(
              obtainAssetDir(false, dxccId),
              CallsignPayload(
                callsign: callsign,
                phonicType: _appSettings.phonicType,
              ),
            ),
          ),
        );
        final difficulty = _appSettings.difficulty;
        final mixed = clips.length <= 1
            ? clips.first
            : mixPileup(
                clips.first,
                clips.skip(1).toList(),
                interfererGain: 0.5,
                offsetSamples: difficulty.pileupOffsetSamples,
              );
        _audioPlayer.addAudioData(
          mixed,
          isResetCurrentStream: isResetAudioStream,
        );
        break;
      case PlaySearchAndPounce():
        final assetDir = obtainAssetDir(false, dxccId);
        final cq = await _audioLoader.loadAudio(
          myAudioAccentDir,
          CommonPayload(fileName: 'CQ.wav'),
        );
        final call = await _audioLoader.loadAudio(
          assetDir,
          CallsignPayload(
            callsign: playType.call,
            phonicType: _appSettings.phonicType,
          ),
        );
        _audioPlayer.addAudioData(
          await concatUint8List([cq, call]),
          isResetCurrentStream: isResetAudioStream,
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
      case SpListeningCq():
      case SpWaitingHisExchange():
        _retryTimer = Timer(_timeoutDuration, () {
          _stateMachine.transition(Retry());
        });
        break;
      case QsoEnd():
      case ReportMyExchange():
      case SpQsoEnd():
        break;
    }
  }

  Future<void> _handleReportMyExchange(ReportMyExchange toState) async {
    log.debug('_handleReportMyExchange!', tag: 'contest');
    await _waitAudioNotPlaying();

    final currentState = _stateMachine.currentState;
    log.debug('currentState: $currentState', tag: 'contest');
    if (_disposed || !identical(_stateMachine.currentState, toState)) {
      return;
    }

    await Future.delayed(Duration(milliseconds: 500));
    if (_disposed || !identical(_stateMachine.currentState, toState)) return;

    final answer = toState.currentCallAnswer;
    final submit = toState.submitCall;

    if (submit == answer ||
        shouldRepeatCallsign(answer: answer, submit: submit)) {
      _stateMachine.transition(ReceiveExchange());
    } else {
      _stateMachine.transition(CallsignInvalid());
    }
  }

  Future<void> _waitAudioNotPlaying() async {
    while (!_disposed && _audioPlayer.isPlaying()) {
      await Future.delayed(Duration(milliseconds: 100));
    }
  }

  /// Commits the QSO and rolls into the next one. Run mode (`QsoEnd`) and S&P
  /// (`SpQsoEnd`) share this; only the sign-off audio differs.
  ///
  /// Committing is best effort, advancing is not: an empty copy, a failed
  /// insert or a scoring error must never leave the machine parked in the
  /// sign-off state, which handles nothing but `NextCall` and arms no retry
  /// timer.
  Future<void> _logQsoAndAdvance({
    required String correctCall,
    required String correctExchange,
    required String submitCall,
    required String submitExchange,
  }) async {
    if (submitCall.isEmpty || submitExchange.isEmpty) {
      log.warn(
        'QSO skipped: his call or exchange is empty',
        tag: 'contest.state',
        fields: <String, Object?>{
          'call': submitCall,
          'exchange': submitExchange,
        },
      );
    } else {
      try {
        final submitQso = await _appDatabase.qsoTable.insertReturningOrNull(
          QsoTableCompanion.insert(
            utcInSeconds: _contestTimer.elapseTime.inSeconds,
            runId: _contestRunId,
            stationCallsign: _stationCallsign,
            callsign: submitCall,
            callsignCorrect: correctCall,
            exchange: _contestType.exchangeManager.processExchange(
              submitExchange,
            ),
            exchangeCorrect: correctExchange,
          ),
        );

        if (submitQso == null) {
          log.warn('QSO was not inserted', tag: 'contest.state');
        } else {
          final latestQsos =
              await (_appDatabase.qsoTable.select()..where((qsoTable) {
                    return qsoTable.runId.equals(_contestRunId);
                  }))
                  .get();

          final duplicate = isDuplicateQso(latestQsos, submitQso);
          log.info(
            'QSO logged',
            tag: 'contest.qso',
            fields: {
              'runId': _contestRunId,
              'qsoId': submitQso.id,
              'elapsedSeconds': submitQso.utcInSeconds,
              'call': submitCall,
              'exchange': submitQso.exchange,
              'correctCall': correctCall,
              'correctExchange': correctExchange,
              'duplicate': duplicate,
            },
          );
          _scoreManager.addQso(latestQsos, submitQso);
        }
      } catch (error, stackTrace) {
        log.error(
          'failed to log the QSO, advancing anyway',
          tag: 'contest.state',
          fields: <String, Object?>{'call': submitCall},
          error: error,
          stackTrace: stackTrace,
        );
      }
    }

    if (_disposed) return;
    _inputHandler.clear();
    final ContestAnswer contestAnswer;
    try {
      contestAnswer = _answerGenerator.generateAnswer();
    } on AnswerSourceExhausted catch (end) {
      // Finish the final sign-off before stopping audio and saving the review.
      await _waitAudioNotPlaying();
      if (_disposed) return;
      log.info(
        'Answer sequence completed',
        tag: 'contest',
        fields: {'runId': _contestRunId, 'reason': end.reason},
      );
      _onAnswersExhausted?.call(end.reason);
      return;
    }
    await _waitAudioNotPlaying();
    if (_disposed) return;
    _stateMachine.transition(
      NextCall(
        callAnswer: contestAnswer.callSign,
        exchangeAnswer: contestAnswer.exchange,
        pileupCallsigns: contestAnswer.pileupCallsigns,
      ),
    );
  }

  // endregion
}
