import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:ssb_runner/audio/audio_player.dart';
import 'package:ssb_runner/contest_run/new/contest_answer_generator.dart';
import 'package:ssb_runner/contest_run/new/contest_data_manager.dart';
import 'package:ssb_runner/contest_run/new/contest_input_handler.dart';
import 'package:ssb_runner/contest_run/new/contest_running_manager.dart';
import 'package:ssb_runner/contest_run/new/contest_timer.dart';
import 'package:ssb_runner/contest_type/contest_definition.dart';
import 'package:ssb_runner/contest_type/contest_type.dart';
import 'package:ssb_runner/db/app_database.dart';
import 'package:ssb_runner/logging/app_logger.dart';
import 'package:ssb_runner/training/replay_answer_source.dart';
import 'package:ssb_runner/training/session_random.dart';
import 'package:ssb_runner/training/session_review.dart';
import 'package:ssb_runner/training/training_profile.dart';
import 'package:uuid/uuid.dart';

class ContestManager {
  final ContestDataManager _contestDataManager;

  ContestManager({required ContestDataManager contestDataManager})
    : _contestDataManager = contestDataManager;

  late final ContestTimer contestTimer = ContestTimer(
    onContestEnd: () {
      stopContest();
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

  void _recordAnswer(ContestAnswer answer) {
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

  Future<void> startContest() async {
    final runId = Uuid().v4();
    _currentContestRunId = runId;

    _contestInputHandler.clear();
    _eventLog.clear();

    final settings = _contestDataManager.appSettings;
    final replayRunId = settings.pendingReplayRunId;
    settings.pendingReplayRunId = null;
    var replayEvents = const <TrainingRunEvent>[];
    if (replayRunId != null) {
      try {
        replayEvents = await _loadEvents(replayRunId);
      } catch (error, stackTrace) {
        // Missing/failed log: fall back to the recorded seeds.
        log.warn(
          'replay log unavailable, falling back to practice seeds',
          tag: 'contest',
        );
        log.error(
          'failed to load replay log',
          tag: 'contest',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }

    final dxccManager = _contestDataManager.dxccManager;
    final definition = ContestRegistry.byId(settings.contestId);
    final mode = TrainingMode.fromId(settings.contestModeId);
    final difficulty = settings.difficulty;
    final generatedSeed = DateTime.now().microsecondsSinceEpoch & 0x7fffffff;
    final questionSeed =
        settings.pendingQuestionSeed ??
        (settings.lockQuestionSeed
            ? (settings.questionSeed ?? generatedSeed)
            : generatedSeed);
    final audioSeed =
        settings.pendingAudioSeed ??
        (settings.lockAudioSeed
            ? (settings.audioSeed ?? questionSeed)
            : questionSeed);
    settings
      ..pendingQuestionSeed = null
      ..pendingAudioSeed = null
      ..questionSeed = questionSeed
      ..audioSeed = audioSeed;
    final contestType = definition.create(
      stationCallsign: settings.stationCallsign,
      dxccManager: dxccManager,
      stationExchange: settings.stationExchangeConfig(definition.id),
    );
    _activeRun = TrainingRunMetadata(
      runId: runId,
      contestId: definition.id,
      contestName: definition.name,
      modeId: mode.id,
      difficultyId: difficulty.id,
      questionSeed: questionSeed,
      audioSeed: audioSeed,
      startedAt: DateTime.now().toUtc(),
    );
    _activeContestType = contestType;

    // Record first, recompute as a fallback: if the log runs out mid-replay,
    // continue from the question seed instead of crashing (design §5.5).
    final AnswerSource? replaySource = replayEvents.isEmpty
        ? null
        : ReplayAnswerSource.fromEvents(
            replayEvents,
            fallback: ContestAnswerGenerator(
              callsignLoader: _contestDataManager.callsignLoader,
              contestType: contestType,
              mode: mode,
              difficulty: difficulty,
              random: SessionRandom(questionSeed),
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
    final durationInMinutes = _contestDataManager.appSettings.contestDuration;
    contestTimer.start(durationInMinutes);

    _contestTypeStreamController.sink.add(contestType);
    contestRunningManager = _createContestRunningManager(
      runId,
      contestType,
      mode: mode,
      difficulty: difficulty,
      seed: questionSeed,
      answerSource: replaySource,
    );

    // Emit the run id only once the new running manager is in place: listeners
    // (score area, QSO list) immediately bind to `contestRunningManager`, and
    // replay loading above is asynchronous, so an early emit would bind them to
    // the previous run.
    _contestRunIdStreamController.sink.add(runId);

    _isContestRunning = true;
    _isContestRunningStreamController.sink.add(true);
  }

  ContestRunningManager _createContestRunningManager(
    String runId,
    ContestType contestType, {
    required TrainingMode mode,
    required TrainingDifficulty difficulty,
    required int seed,
    AnswerSource? answerSource,
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
      onAnswerGenerated: _recordAnswer,
    );
  }

  void stopContest() {
    if (!_isContestRunning) {
      return;
    }

    final run = _activeRun;
    final contestType = _activeContestType;

    contestTimer.stop();
    contestRunningManager?.stop();

    _audioPlayer.setTrainingProfile(null);
    _audioPlayer.stopPlay();

    _isContestRunning = false;
    _isContestRunningStreamController.sink.add(false);

    if (run != null && contestType != null) {
      _saveReview(run, contestType);
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

  Future<List<TrainingRunEvent>> _loadEvents(String runId) async {
    final rows =
        await (_appDatabase.eventLogTable.select()
              ..where((row) => row.runId.equals(runId))
              ..orderBy([(row) => OrderingTerm.asc(row.id)]))
            .get();
    return rows
        .map(
          (row) => TrainingRunEvent.fromJson(
            jsonDecode(row.payload) as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  Future<void> _saveReview(
    TrainingRunMetadata run,
    ContestType contestType,
  ) async {
    final qsos =
        await (_appDatabase.qsoTable.select()
              ..where((row) => row.runId.equals(run.runId)))
            .get();
    final review = TrainingRunReview.fromQsos(
      metadata: run,
      qsos: qsos,
      score: contestType.scoreCalculator.calculateScore(qsos).score,
    );
    _contestDataManager.appSettings.saveSessionReview(review);
    _reviewStreamController.add(review);
  }

  Future<int> countCurrentRunQso() async {
    return await _appDatabase.qsoTable
            .count(
              where: (row) {
                return row.runId.equals(_currentContestRunId);
              },
            )
            .getSingleOrNull() ??
        0;
  }

  Future<List<int>> recentCurrentRunQsoTimes({int limit = 6}) async {
    final qsos =
        await (_appDatabase.qsoTable.select()
              ..where((row) => row.runId.equals(_currentContestRunId))
              ..orderBy([(row) => OrderingTerm.asc(row.utcInSeconds)]))
            .get();
    return qsos
        .map((qso) => qso.utcInSeconds)
        .toList()
        .reversed
        .take(limit)
        .toList()
        .reversed
        .toList();
  }
}
