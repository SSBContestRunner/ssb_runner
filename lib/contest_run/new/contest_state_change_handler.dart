import 'dart:async';

import 'package:drift/drift.dart';
import 'package:ssb_runner/audio/accent_policy.dart';
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

const _defaultTimeoutDuration = Duration(seconds: 10);

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
  final Duration _retryTimeout;
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

  /// Fixed for the whole run: built by [ContestManager.startContest].
  final AccentPolicy _accentPolicy;

  Timer? _retryTimer;
  bool _isAbandoning = false;

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
    required AccentPolicy accentPolicy,
    Duration retryTimeout = _defaultTimeoutDuration,
  }) : _retryTimeout = retryTimeout,
       _contestRunId = contestRunId,
       _contestTimer = contestTimer,
       _contestType = contestType,
       _contestDataManager = contestDataManager,
       _stateMachine = stateMachine,
       _scoreManager = scoreManager,
       _answerGenerator = contestAnswerGenerator,
       _onAnswersExhausted = onAnswersExhausted,
       _accentPolicy = accentPolicy {
    _inputHandler.onInputChanged = _resetRetryTimer;
  }

  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _inputHandler.onInputChanged = null;
  }

  // region state change handler
  Future<void> handleToState(
    SingleCallRunState toState, {
    SingleCallRunEvent? event,
  }) async {
    if (_disposed) return;
    _setupRetryTimer(toState, event);

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

  /// F1 in the middle of a QSO: drop the round without logging it, then start
  /// a fresh question. The abandoned station goes back into the pool and, in
  /// pile-up mode, stays audible as an interferer. The operator's input is left
  /// untouched — F12 is the explicit "clear input" key.
  Future<void> abandonRound() async {
    if (_disposed || _isAbandoning) return;
    _isAbandoning = true;

    try {
      final abandonedState = _stateMachine.currentState;
      _retryTimer?.cancel();
      _retryTimer = null;

      // Let the CQ the operator just sent finish before announcing the new
      // pile-up. If the round moved on meanwhile, the newer state wins.
      await _waitAudioNotPlaying();
      if (_disposed || !identical(_stateMachine.currentState, abandonedState)) {
        return;
      }

      final requeuedCallsign = _abandonedCallsign(abandonedState);
      log.info(
        'round abandoned',
        tag: 'contest.state',
        fields: <String, Object?>{
          'runId': _contestRunId,
          'reason': 'cq',
          'from': '${abandonedState.runtimeType}',
          'requeuedCallsign': requeuedCallsign,
        },
      );

      final contestAnswer = await _generateNextAnswer(
        requeueCallsign: requeuedCallsign,
      );
      if (contestAnswer == null || _disposed) return;

      _stateMachine.transition(
        AbandonQso(
          nextCallAnswer: contestAnswer.callSign,
          nextExchangeAnswer: contestAnswer.exchange,
          pileupCallsigns: contestAnswer.pileupCallsigns,
        ),
      );
    } finally {
      _isAbandoning = false;
    }
  }

  /// The station being worked on in an in-flight QSO, or null outside one.
  String? _abandonedCallsign(SingleCallRunState state) => switch (state) {
    HeRepeatCorrectCallAnswer s => s.currentCallAnswer,
    HeAskForExchange s => s.currentCallAnswer,
    WaitingSubmitMyExchange s => s.currentCallAnswer,
    ReportMyExchange s => s.currentCallAnswer,
    _ => null,
  };

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
        final accent = _accentPolicy.resolve(isMe: false, dxccId: dxccId);
        final list = [
          if (toState.isPlayMyCall)
            await _audioLoader.loadAudio(
              accent,
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
        // Replace whatever is playing so "press once = hear once": queuing
        // would let a retry stack another clip behind the operator's CQ.
        _audioPlayer.addAudioData(pcmData, isResetCurrentStream: true);
        break;
      case HeRepeatCorrectCallAnswer():
        final dxccId = _dxccManager.findCallsignDxccId(
          toState.currentCallAnswer,
        );

        final pcmData = await _audioLoader.loadAudio(
          _accentPolicy.resolve(isMe: false, dxccId: dxccId),
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
        final assetDir = _accentPolicy.resolve(
          isMe: playType.isMe,
          dxccId: dxccId,
        );
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
        final assetDir = _accentPolicy.resolve(
          isMe: playType.isMe,
          dxccId: dxccId,
        );
        final callSignPcmData = await _audioLoader.loadAudio(
          assetDir,
          CallsignPayload(
            callsign: playType.call,
            phonicType: _appSettings.phonicType,
          ),
        );

        final rstPcmData = await _audioLoader.loadAudio(
          assetDir,
          CommonPayload(
            fileName: obtainRstAudioFileName(
              playType.isMe,
              isCallsignCorrect: false,
            ),
          ),
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
          _accentPolicy.resolve(isMe: playType.isMe, dxccId: dxccId),
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
              _accentPolicy.resolve(isMe: false, dxccId: dxccId),
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
        final assetDir = _accentPolicy.resolve(isMe: false, dxccId: dxccId);
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

  void _setupRetryTimer(SingleCallRunState toState, SingleCallRunEvent? event) {
    _retryTimer?.cancel();
    _retryTimer = null;

    switch (toState) {
      case WaitingSubmitCall():
      case SpListeningCq():
      case SpWaitingHisExchange():
        _armRetryTimer();
        break;
      case WaitingSubmitMyExchange():
      case HeAskForExchange():
      case HeRepeatCorrectCallAnswer():
        // An in-flight QSO is replayed automatically once after the first
        // silence. A Retry that already replayed must not arm the timer again,
        // or the round would repeat itself every 10 s forever.
        if (event is! Retry) {
          _armRetryTimer();
        }
        break;
      case QsoEnd():
      case ReportMyExchange():
      case SpQsoEnd():
        break;
    }
  }

  void _armRetryTimer() {
    _retryTimer = Timer(_retryTimeout, () {
      _stateMachine.transition(Retry());
    });
  }

  /// Restarts the listening timeout for the current state. Typing must not be
  /// interrupted by an automatic re-send.
  void _resetRetryTimer() {
    if (_disposed) return;
    _setupRetryTimer(_stateMachine.currentState, null);
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
    final contestAnswer = await _generateNextAnswer();
    if (contestAnswer == null) return;
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

  /// Produces the next question, or `null` once the answer sequence is
  /// exhausted (in which case the run is finished and the review is shown).
  /// [requeueCallsign] is passed only from the abandon path.
  Future<ContestAnswer?> _generateNextAnswer({String? requeueCallsign}) async {
    try {
      return _answerGenerator.generateAnswer(requeueCallsign: requeueCallsign);
    } on AnswerSourceExhausted catch (end) {
      // Finish the final sign-off before stopping audio and saving the review.
      await _waitAudioNotPlaying();
      if (_disposed) return null;
      log.info(
        'Answer sequence completed',
        tag: 'contest',
        fields: {'runId': _contestRunId, 'reason': end.reason},
      );
      _onAnswersExhausted?.call(end.reason);
      return null;
    }
  }

  // endregion
}
