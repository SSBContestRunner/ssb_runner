import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:ssb_runner/audio/accent_policy.dart';
import 'package:ssb_runner/audio/audio_player.dart';
import 'package:ssb_runner/common/app_info.dart';
import 'package:ssb_runner/common/normalize_callsign.dart';
import 'package:ssb_runner/contest_run/new/contest_answer_generator.dart';
import 'package:ssb_runner/contest_run/new/contest_data_manager.dart';
import 'package:ssb_runner/contest_run/new/contest_input_handler.dart';
import 'package:ssb_runner/contest_run/new/contest_running_manager.dart';
import 'package:ssb_runner/contest_run/new/contest_timer.dart';
import 'package:ssb_runner/contest_run/new/run_plan.dart';
import 'package:ssb_runner/contest_run/new/run_plan_resolver.dart';
import 'package:ssb_runner/contest_run/qso_duplicates.dart';
import 'package:ssb_runner/contest_type/contest_definition.dart';
import 'package:ssb_runner/contest_type/contest_type.dart';
import 'package:ssb_runner/contest_type/station_exchange.dart';
import 'package:ssb_runner/db/app_database.dart';
import 'package:ssb_runner/logging/app_logger.dart';
import 'package:ssb_runner/training/replay_answer_source.dart';
import 'package:ssb_runner/training/session_review.dart';
import 'package:ssb_runner/training/training_profile.dart';
import 'package:uuid/uuid.dart';

/// Lifecycle of a timed run. [resuming] is the 3-2-1 window before a paused
/// run continues; audio and the clock stay frozen until it completes.
enum ContestSessionPhase { idle, running, paused, resuming }

class ContestManager {
  final ContestDataManager _contestDataManager;

  ContestManager({required ContestDataManager contestDataManager})
    : _contestDataManager = contestDataManager {
    contestDataManager.appSettings.contestRunningCheck = () => isContestRunning;
  }

  late final ContestTimer contestTimer = ContestTimer(
    onContestEnd: () {
      stopContest(reason: 'duration_elapsed');
    },
  );

  String _currentContestRunId = '';
  final _contestRunIdStreamController = StreamController<String>.broadcast();

  Stream<String> get contestRunIdStream => _contestRunIdStreamController.stream;

  late final AppDatabase _appDatabase = _contestDataManager.appDatabase;

  ContestRunningManager? contestRunningManager;

  bool _isContestRunning = false;
  final _isContestRunningStreamController = StreamController<bool>.broadcast();

  Stream<bool> get isContestRunningStream =>
      _isContestRunningStreamController.stream;

  bool get isContestRunning => _isContestRunning;

  ContestSessionPhase _sessionPhase = ContestSessionPhase.idle;
  final _sessionPhaseStreamController =
      StreamController<ContestSessionPhase>.broadcast();

  Stream<ContestSessionPhase> get sessionPhaseStream =>
      _sessionPhaseStreamController.stream;

  ContestSessionPhase get sessionPhase => _sessionPhase;

  void _setSessionPhase(ContestSessionPhase phase) {
    if (_sessionPhase == phase) {
      return;
    }
    _sessionPhase = phase;
    _sessionPhaseStreamController.sink.add(phase);
  }

  late final AudioPlayer _audioPlayer = _contestDataManager.audioPlayer;
  late final ContestInputHandler _contestInputHandler =
      _contestDataManager.inputHandler;

  final _contestTypeStreamController =
      StreamController<ContestType>.broadcast();

  Stream<ContestType> get contestTypeStream =>
      _contestTypeStreamController.stream;

  final _reviewStreamController =
      StreamController<TrainingRunReview>.broadcast();
  Stream<TrainingRunReview> get reviewStream => _reviewStreamController.stream;

  TrainingRunMetadata? _activeRun;
  ContestType? _activeContestType;
  final List<TrainingRunEvent> _eventLog = [];
  String _answerSourceName = 'live';

  void _recordAnswer(ContestAnswer answer) {
    log.info(
      'Answer served',
      tag: 'contest.answer',
      fields: {
        'runId': _activeRun?.runId,
        'questionIndex': _eventLog.length + 1,
        'answerSource': _answerSourceName,
        'elapsedMs': contestTimer.elapseTime.inMilliseconds,
        'call': answer.callSign,
        'exchange': answer.exchange,
        'pileupCallsigns': answer.pileupCallsigns,
      },
    );
    _eventLog.add(
      TrainingRunEvent(
        elapsedMs: contestTimer.elapseTime.inMilliseconds,
        type: 'answer',
        callsign: answer.callSign,
        exchange: answer.exchange,
        pileupCallsigns: answer.pileupCallsigns,
        modeId: answer.mode.id,
      ),
    );
  }

  Future<RunStartResult> startContest() async {
    final runId = Uuid().v4();

    _contestInputHandler.clear();
    _eventLog.clear();

    final settings = _contestDataManager.appSettings;
    final pendingReplay = settings.pendingReplay;
    final requestedContestId = settings.contestId;
    final requestedModeId = settings.contestModeId;
    final requestedDifficultyId = settings.difficulty.id;

    ReplayLog? replayLog;
    if (pendingReplay != null) {
      try {
        replayLog = await _loadRunLog(pendingReplay.runId);
      } catch (error, stackTrace) {
        // A missing log is an abort condition, not a silent seed fallback: the
        // resolver turns it into a settings run with an explicit notice.
        log.warn(
          'replay log unavailable; the replay will be abandoned',
          tag: 'contest',
          fields: {'replayRunId': pendingReplay.runId},
        );
        log.error(
          'failed to load replay log',
          tag: 'contest',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }

    final generatedSeed = DateTime.now().microsecondsSinceEpoch & 0x7fffffff;
    // The resolver fills a replay from the pending snapshot and a settings run
    // (including an abandoned replay) from these ordinary seeds.
    final settingsQuestionSeed =
        settings.pendingQuestionSeed ??
        (settings.lockQuestionSeed
            ? (settings.questionSeed ?? generatedSeed)
            : generatedSeed);
    final settingsAudioSeed =
        settings.pendingAudioSeed ??
        (settings.lockAudioSeed
            ? (settings.audioSeed ?? settingsQuestionSeed)
            : settingsQuestionSeed);

    final plan = RunPlanResolver.resolve(
      pendingReplay: pendingReplay,
      replayLog: replayLog,
      settingsContestId: requestedContestId,
      settingsModeId: requestedModeId,
      settingsDifficultyId: requestedDifficultyId,
      questionSeed: settingsQuestionSeed,
      audioSeed: settingsAudioSeed,
    );
    final questionSeed = plan.questionSeed;
    final audioSeed = plan.audioSeed;

    final replayAnswers = plan.isReplay
        ? (replayLog?.answers ?? const <TrainingRunEvent>[])
        : const <TrainingRunEvent>[];

    // Pre-flight: pending and ordinary settings stay untouched until every
    // check that can fail has passed.
    final callsignPoolEmpty = !_contestDataManager.callsignLoader.callSigns.any(
      (call) => normalizeCallsign(call).isNotEmpty,
    );
    if (callsignPoolEmpty && replayAnswers.isEmpty) {
      log.warn(
        'Cannot start training with an empty callsign pool',
        tag: 'contest',
        fields: {'replayRunId': plan.replayRunId},
      );
      return RunStartResult(
        started: false,
        source: plan.source,
        abortedReason: plan.abortedReason,
        replayContestName: plan.abortedContestName,
        notices: const ['callsign_pool_empty'],
      );
    }

    final exchangeErrors = _stationExchangeErrors(plan);
    if (exchangeErrors.isNotEmpty) {
      log.warn(
        'Cannot start training: station exchange is incomplete',
        tag: 'contest',
        fields: {'contestId': plan.contestId, 'issues': exchangeErrors},
      );
      return RunStartResult(
        started: false,
        source: plan.source,
        abortedReason: plan.abortedReason,
        replayContestName: plan.abortedContestName,
        notices: exchangeErrors,
      );
    }

    if (plan.abortedReason != null) {
      settings.clearPendingReplay();
      log.info(
        'contest.replay.abort',
        tag: 'contest',
        fields: {
          'reason': plan.abortedReason!.name,
          'pendingContestId': pendingReplay?.contestId,
          'pendingModeId': pendingReplay?.modeId,
          'pendingDifficultyId': pendingReplay?.difficultyId,
          'recordedContestId': replayLog?.header?.contestId,
          'recordedModeId': replayLog?.header?.modeId,
          'recordedDifficultyId': replayLog?.header?.difficultyId,
          'fallbackContestId': plan.contestId,
        },
      );
    } else if (plan.source == RunPlanSource.pending) {
      // Only a verified replay turns the pending snapshot into ordinary
      // settings. One bump covers all three values plus the cleared snapshot.
      settings.commitRunSpec(plan);
    }

    settings
      ..pendingQuestionSeed = null
      ..pendingAudioSeed = null
      ..questionSeed = questionSeed
      ..audioSeed = audioSeed;

    final definition = plan.definition;
    final dxccManager = _contestDataManager.dxccManager;
    final mode = TrainingMode.fromId(plan.modeId);
    final difficulty = TrainingDifficulty.fromId(plan.difficultyId);
    final contestType = definition.create(
      stationCallsign: settings.stationCallsign,
      dxccManager: dxccManager,
      stationExchange: settings.stationExchangeConfig(definition.id),
    );
    // Session-level voice policy: fixed for the whole run, recorded with the
    // result so a replay stays traceable.
    final accentPolicy = AccentPolicy(settings.incomingAccent);
    _activeRun = TrainingRunMetadata(
      runId: runId,
      contestId: definition.id,
      contestName: definition.name,
      modeId: mode.id,
      difficultyId: difficulty.id,
      questionSeed: questionSeed,
      audioSeed: audioSeed,
      accentId: accentPolicy.accent.id,
      appVersion: AppInfo.version ?? '',
      startedAt: DateTime.now().toUtc(),
    );
    _activeContestType = contestType;

    final recording = plan.isReplay
        ? ReplayAnswerSource.fromEvents(replayAnswers)
        : null;
    final replaySource = recording != null && recording.length > 0
        ? recording
        : null;
    _answerSourceName = replaySource != null ? 'recorded-replay' : 'live';

    log.info(
      'Training started',
      tag: 'contest',
      fields: {
        'runId': runId,
        'requestedContestId': requestedContestId,
        'effectiveContestId': definition.id,
        'planSource': plan.source.name,
        'mode': mode.id,
        'difficulty': difficulty.id,
        'questionSeed': questionSeed,
        'audioSeed': audioSeed,
        'replayRunId': plan.replayRunId,
        'recordedContestId': replayLog?.header?.contestId,
        'recordedModeId': replayLog?.header?.modeId,
        'recordedDifficultyId': replayLog?.header?.difficultyId,
        'replayAbortedReason': plan.abortedReason?.name,
        'committedContestId': settings.contestId,
        'committedModeId': settings.contestModeId,
        'committedDifficultyId': settings.difficulty.id,
        'answerSource': _answerSourceName,
        'recordedAnswerCount': replayAnswers.length,
      },
    );

    await _persistRunStartHeader(
      runId,
      RecordedRunHeader(
        contestId: definition.id,
        contestName: definition.name,
        modeId: mode.id,
        difficultyId: difficulty.id,
        questionSeed: questionSeed,
        audioSeed: audioSeed,
        accentId: accentPolicy.accent.id,
        appVersion: AppInfo.version ?? '',
        replayOfRunId: plan.replayRunId,
      ),
    );

    _audioPlayer.setTrainingProfile(
      AudioTrainingProfile.fromDifficulty(
        difficulty: difficulty,
        volume: settings.audioVolume,
        questionSeed: questionSeed,
        audioSeed: audioSeed,
      ),
    );
    _audioPlayer.startPlay();

    // Reset the clock before the first answer is generated so the logged
    // elapsed time starts at zero.
    final durationInMinutes = settings.contestDuration;
    contestTimer.start(durationInMinutes);

    _contestTypeStreamController.sink.add(contestType);
    contestRunningManager = _createContestRunningManager(
      runId,
      contestType,
      mode: mode,
      difficulty: difficulty,
      seed: questionSeed,
      answerSource: replaySource,
      accentPolicy: accentPolicy,
    );

    // Emit the run id only once the new running manager is in place: listeners
    // (score area, QSO list) immediately bind to `contestRunningManager`, and
    // replay loading above is asynchronous, so an early emit would bind them to
    // the previous run.
    _contestRunIdStreamController.sink.add(runId);

    _currentContestRunId = runId;
    _isContestRunning = true;
    _isContestRunningStreamController.sink.add(true);
    _setSessionPhase(ContestSessionPhase.running);

    return RunStartResult(
      started: true,
      source: plan.source,
      abortedReason: plan.abortedReason,
      replayContestName: plan.abortedContestName,
      notices: plan.warnings,
    );
  }

  List<String> _stationExchangeErrors(RunPlan plan) {
    final settings = _contestDataManager.appSettings;
    final callsign = settings.stationCallsign;
    // Without a callsign the exchange cannot be derived; the readiness gate in
    // the UI reports that separately, so this pre-flight stays quiet.
    if (callsign.isEmpty) return const [];
    final exchangePlan = plan.definition.myExchangePlan(
      stationCallsign: callsign,
      dxccManager: _contestDataManager.dxccManager,
    );
    return [
      for (final error in validateStationExchangeAll(
        plan: exchangePlan,
        config: settings.stationExchangeConfig(plan.definition.id),
        stationCallsign: callsign,
        dxccManager: _contestDataManager.dxccManager,
      ))
        'exchange_${error.field.id}',
    ];
  }

  ContestRunningManager _createContestRunningManager(
    String runId,
    ContestType contestType, {
    required TrainingMode mode,
    required TrainingDifficulty difficulty,
    required int seed,
    AnswerSource? answerSource,
    required AccentPolicy accentPolicy,
  }) {
    return ContestRunningManager(
      runId: runId,
      contestTimer: contestTimer,
      contestType: contestType,
      contestDataManager: _contestDataManager,
      scoreCalculator: contestType.scoreCalculator,
      mode: mode,
      difficulty: difficulty,
      seed: seed,
      answerSource: answerSource,
      accentPolicy: accentPolicy,
      onAnswerGenerated: _recordAnswer,
      onAnswersExhausted: (reason) => stopContest(reason: reason),
    );
  }

  /// Freezes the run. Pause and resume are button-only: no keyboard shortcut
  /// exists by design.
  void pauseContest() {
    if (_sessionPhase != ContestSessionPhase.running) {
      return;
    }
    _setSessionPhase(ContestSessionPhase.paused);
    contestTimer.pause();
    contestRunningManager?.pause();
  }

  /// Enters the 3-2-1 window. Audio and the clock stay frozen until
  /// [completeResume] runs, so the countdown never counts as practice time.
  void beginResume() {
    if (_sessionPhase != ContestSessionPhase.paused) {
      return;
    }
    _setSessionPhase(ContestSessionPhase.resuming);
  }

  /// Ends the countdown (finished or skipped) and continues from the pause
  /// point. No rewind, no replay, no re-enqueue.
  void completeResume() {
    if (_sessionPhase != ContestSessionPhase.resuming) {
      return;
    }
    _setSessionPhase(ContestSessionPhase.running);
    contestRunningManager?.resume();
    contestTimer.resume();
  }

  void stopContest({String reason = 'stopped'}) {
    if (!_isContestRunning) {
      return;
    }

    final run = _activeRun;
    final contestType = _activeContestType;
    log.info(
      'Training stopped',
      tag: 'contest',
      fields: {
        'runId': run?.runId,
        'elapsedMs': contestTimer.elapseTime.inMilliseconds,
        'answerCount': _eventLog.length,
        'reason': reason,
      },
    );

    contestTimer.stop();
    contestRunningManager?.stop();

    _audioPlayer.setTrainingProfile(null);
    _audioPlayer.stopPlay();

    _isContestRunning = false;
    _isContestRunningStreamController.sink.add(false);
    _setSessionPhase(ContestSessionPhase.idle);

    if (run != null && contestType != null) {
      _saveReview(run, contestType, endReason: reason);
      _persistEventLog(run.runId);
      _eventLog.clear();
    }
  }

  Future<void> _persistEventLog(String runId) async {
    if (_eventLog.isEmpty) {
      return;
    }
    final createdAtUtc = DateTime.now().toUtc().millisecondsSinceEpoch;
    final events = List<TrainingRunEvent>.of(_eventLog);
    try {
      await _appDatabase.transaction(() async {
        for (final event in events) {
          await _appDatabase
              .into(_appDatabase.eventLogTable)
              .insert(
                EventLogTableCompanion.insert(
                  runId: runId,
                  elapsedMs: event.elapsedMs,
                  eventType: event.type,
                  payload: jsonEncode(event.toJson()),
                  createdAtUtc: createdAtUtc,
                ),
              );
        }
      });
    } catch (error, stackTrace) {
      log.error(
        'failed to persist training event log',
        tag: 'contest',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Loads a recording's answers and, when present, its run-start header.
  /// The header is parsed from the same event log with no schema change.
  Future<ReplayLog> _loadRunLog(String runId) async {
    final rows =
        await (_appDatabase.eventLogTable.select()
              ..where((row) => row.runId.equals(runId))
              ..orderBy([(row) => OrderingTerm.asc(row.id)]))
            .get();
    final answers = <TrainingRunEvent>[];
    RecordedRunHeader? header;
    for (final row in rows) {
      final json = jsonDecode(row.payload) as Map<String, dynamic>;
      if (row.eventType == 'run-start') {
        header ??= RecordedRunHeader.fromJson(json);
      } else {
        answers.add(TrainingRunEvent.fromJson(json));
      }
    }
    return ReplayLog(answers: answers, header: header);
  }

  /// Writes the self-describing header as the first event of a new run. A
  /// failure is downgraded to a warning: it must never block a session.
  Future<void> _persistRunStartHeader(
    String runId,
    RecordedRunHeader header,
  ) async {
    try {
      await _appDatabase
          .into(_appDatabase.eventLogTable)
          .insert(
            EventLogTableCompanion.insert(
              runId: runId,
              elapsedMs: 0,
              eventType: 'run-start',
              payload: jsonEncode(header.toJson()),
              createdAtUtc: DateTime.now().toUtc().millisecondsSinceEpoch,
            ),
          );
    } catch (error, stackTrace) {
      log.warn(
        'failed to persist the run-start header',
        tag: 'contest',
        fields: {'runId': runId, 'contestId': header.contestId},
      );
      log.error(
        'failed to persist the run-start header',
        tag: 'contest',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _saveReview(
    TrainingRunMetadata run,
    ContestType contestType, {
    required String endReason,
  }) async {
    final qsos =
        await (_appDatabase.qsoTable.select()
              ..where((row) => row.runId.equals(run.runId)))
            .get();
    final review = TrainingRunReview.fromQsos(
      metadata: run,
      qsos: qsos,
      score: contestType.scoreCalculator.calculateScore(qsos).score,
      endReason: endReason,
      pauseCount: contestTimer.pauseCount,
      pausedDuration: contestTimer.pausedDuration,
    );
    _contestDataManager.appSettings.saveSessionReview(review);
    _reviewStreamController.add(review);
  }

  /// The operator's own exchange for the 1-based [qsoNumber].
  ///
  /// While a session runs it uses the contest type frozen at start (identical
  /// to what is actually transmitted); on standby it previews the next session
  /// from the current contest, callsign and station settings.
  String myExchangeFor(int qsoNumber) {
    final active = _activeContestType;
    if (_isContestRunning && active != null) {
      return active.buildMyExchange(qsoNumber);
    }

    final settings = _contestDataManager.appSettings;
    final dxccManager = _contestDataManager.dxccManager;
    // Standby previews the effective contest: an armed replay shows the
    // recording's contest while the ordinary settings stay untouched.
    final definition = ContestRegistry.byId(settings.effectiveContestId);
    final plan = definition.myExchangePlan(
      stationCallsign: settings.stationCallsign,
      dxccManager: dxccManager,
    );
    return buildMyExchangeText(
      plan: plan,
      config: settings.stationExchangeConfig(definition.id),
      stationCallsign: settings.stationCallsign,
      dxccManager: dxccManager,
      qsoNumber: qsoNumber,
    );
  }

  Future<int> countCurrentRunQso() async {
    final qsos =
        await (_appDatabase.qsoTable.select()
              ..where((row) => row.runId.equals(_currentContestRunId)))
            .get();
    return uniqueQsos(qsos).length;
  }

  Future<List<int>> recentCurrentRunQsoTimes({int limit = 6}) async {
    final qsos =
        await (_appDatabase.qsoTable.select()
              ..where((row) => row.runId.equals(_currentContestRunId))
              ..orderBy([(row) => OrderingTerm.asc(row.utcInSeconds)]))
            .get();
    return uniqueQsos(qsos)
        .map((qso) => qso.utcInSeconds)
        .toList()
        .reversed
        .take(limit)
        .toList()
        .reversed
        .toList();
  }
}

/// Outcome of one `startContest` call, consumed by the RUN button so a replay
/// that had to be abandoned is explained instead of silently replaced.
class RunStartResult {
  const RunStartResult({
    required this.started,
    required this.source,
    this.abortedReason,
    this.replayContestName,
    this.notices = const [],
  });

  final bool started;
  final RunPlanSource source;
  final ReplayAbortReason? abortedReason;
  final String? replayContestName;
  final List<String> notices;
}
