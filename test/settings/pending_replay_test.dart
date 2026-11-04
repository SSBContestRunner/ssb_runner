import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/contest_run/new/run_plan.dart';
import 'package:ssb_runner/contest_type/contest_definition.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/training/pending_replay.dart';
import 'package:ssb_runner/training/session_review.dart';
import 'package:ssb_runner/training/training_profile.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('PendingReplay json roundtrip keeps every field', () {
    final pending = _pending(
      runId: 'run-1',
      contestId: 'CQ-WPX',
      contestName: 'CQ WPX',
      modeId: TrainingMode.pileup.id,
      difficultyId: TrainingDifficulty.advanced.id,
      questionSeed: 42,
      audioSeed: 43,
    );

    final decoded = PendingReplay.fromJson(
      jsonDecode(pending.encode()) as Map<String, dynamic>,
    );

    expect(decoded.runId, pending.runId);
    expect(decoded.contestId, pending.contestId);
    expect(decoded.contestName, pending.contestName);
    expect(decoded.modeId, pending.modeId);
    expect(decoded.difficultyId, pending.difficultyId);
    expect(decoded.questionSeed, pending.questionSeed);
    expect(decoded.audioSeed, pending.audioSeed);
    expect(decoded.armedAtUtc, pending.armedAtUtc);
  });

  test('PendingReplay tolerates unknown json fields and missing values', () {
    final decoded = PendingReplay.fromJson({
      'runId': 'run-1',
      'futureField': 'ignored',
    });

    expect(decoded.contestId, unknownReplayField);
    expect(decoded.modeId, unknownReplayField);
    expect(decoded.difficultyId, unknownReplayField);
    expect(decoded.hasKnownContest, isFalse);
    expect(decoded.questionSeed, 0);
  });

  test('the legacy run id is assembled from session history', () async {
    final settings = await _settings();
    settings.saveSessionReview(
      TrainingRunReview(
        metadata: _metadata(
          runId: 'legacy-run',
          contestId: 'CQ-WW-SSB',
          contestName: 'CQ WW',
        ),
        endedAt: DateTime.utc(2026, 1, 1, 1),
        qsoCount: 1,
        correctCount: 1,
        callsignErrors: 0,
        exchangeErrors: 0,
        score: 1,
      ),
    );
    await _writeLegacyRunId('legacy-run');

    final pending = settings.pendingReplay;
    expect(pending, isNotNull);
    expect(pending!.contestId, 'CQ-WW-SSB');
    expect(pending.modeId, TrainingMode.run.id);
    expect(pending.difficultyId, TrainingDifficulty.standard.id);
    expect(pending.questionSeed, 7);
    expect(pending.audioSeed, 8);
    expect(pending.armedAtUtc, DateTime.utc(2026, 1, 1, 1));
  });

  test('a legacy run id without history stays explicitly unknown', () async {
    final settings = await _settings();
    await _writeLegacyRunId('missing-run');

    final pending = settings.pendingReplay;
    expect(pending, isNotNull);
    expect(pending!.contestId, unknownReplayField);
    expect(pending.hasKnownContest, isFalse);
    expect(settings.effectiveContestId, settings.contestId);
  });

  test(
    'arming a replay does not touch ordinary settings and bumps once',
    () async {
      final settings = await _settings();
      settings
        ..contestId = 'CQ-WW-SSB'
        ..contestModeId = TrainingMode.run.id
        ..difficulty = TrainingDifficulty.advanced;
      final before = settings.settingsRevision.value;

      settings.armReplay(_pending(runId: 'wpx-run', contestId: 'CQ-WPX'));

      expect(settings.pendingReplay, isNotNull);
      expect(settings.pendingReplay!.runId, 'wpx-run');
      expect(settings.contestId, 'CQ-WW-SSB');
      expect(settings.contestModeId, TrainingMode.run.id);
      expect(settings.difficulty, TrainingDifficulty.advanced);
      expect(settings.settingsRevision.value, before + 1);
    },
  );

  test('effective values prefer the armed snapshot', () async {
    final settings = await _settings();
    settings
      ..contestId = 'CQ-WW-SSB'
      ..contestModeId = TrainingMode.run.id
      ..difficulty = TrainingDifficulty.standard;

    settings.armReplay(
      _pending(
        runId: 'wpx-run',
        contestId: 'CQ-WPX',
        modeId: TrainingMode.pileup.id,
        difficultyId: TrainingDifficulty.beginner.id,
      ),
    );

    expect(settings.effectiveContestId, 'CQ-WPX');
    expect(settings.effectiveModeId, TrainingMode.pileup.id);
    expect(settings.effectiveDifficultyId, TrainingDifficulty.beginner.id);
  });

  test('cancelling a replay clears it and keeps ordinary settings', () async {
    final settings = await _settings();
    settings
      ..contestId = 'CQ-WW-SSB'
      ..contestModeId = TrainingMode.run.id
      ..difficulty = TrainingDifficulty.advanced;
    settings.armReplay(_pending(runId: 'wpx-run', contestId: 'CQ-WPX'));
    final before = settings.settingsRevision.value;

    settings.clearPendingReplay();

    expect(settings.pendingReplay, isNull);
    expect(settings.contestId, 'CQ-WW-SSB');
    expect(settings.contestModeId, TrainingMode.run.id);
    expect(settings.difficulty, TrainingDifficulty.advanced);
    expect(settings.settingsRevision.value, before + 1);
  });

  test('commitRunSpec writes the plan once and clears the snapshot', () async {
    final settings = await _settings();
    settings
      ..contestId = 'CQ-WW-SSB'
      ..contestModeId = TrainingMode.run.id
      ..difficulty = TrainingDifficulty.standard;
    settings.armReplay(_pending(runId: 'wpx-run', contestId: 'CQ-WPX'));
    final before = settings.settingsRevision.value;

    settings.commitRunSpec(
      RunPlan(
        definition: ContestRegistry.byId('CQ-WPX'),
        modeId: TrainingMode.pileup.id,
        difficultyId: TrainingDifficulty.beginner.id,
        questionSeed: 42,
        audioSeed: 43,
        replayRunId: 'wpx-run',
        source: RunPlanSource.pending,
      ),
    );

    expect(settings.contestId, 'CQ-WPX');
    expect(settings.contestModeId, TrainingMode.pileup.id);
    expect(settings.difficulty, TrainingDifficulty.beginner);
    expect(settings.pendingReplay, isNull);
    expect(settings.settingsRevision.value, before + 1);
  });

  test('arming a replay is refused while a session runs', () async {
    final settings = await _settings();
    var running = false;
    settings.contestRunningCheck = () => running;

    settings.armReplay(_pending(runId: 'wpx-run', contestId: 'CQ-WPX'));
    expect(settings.pendingReplay, isNotNull);

    settings.clearPendingReplay();
    running = true;
    settings.armReplay(_pending(runId: 'second-run', contestId: 'CQ-WPX'));

    expect(settings.pendingReplay, isNull);
  });

  test('difficulty and audio options bump the settings revision', () async {
    final settings = await _settings();
    final before = settings.settingsRevision.value;

    settings.difficulty = TrainingDifficulty.advanced;
    settings.incomingAccent = settings.incomingAccent;
    settings.phonicType = settings.phonicType;

    expect(settings.settingsRevision.value, before + 3);
  });
}

PendingReplay _pending({
  required String runId,
  String contestId = 'CQ-WPX',
  String contestName = 'CQ WPX',
  String modeId = 'run',
  String difficultyId = 'standard',
  int questionSeed = 42,
  int audioSeed = 43,
}) => PendingReplay(
  runId: runId,
  contestId: contestId,
  contestName: contestName,
  modeId: modeId,
  difficultyId: difficultyId,
  questionSeed: questionSeed,
  audioSeed: audioSeed,
  armedAtUtc: DateTime.utc(2026, 1, 1, 1),
);

TrainingRunMetadata _metadata({
  required String runId,
  required String contestId,
  required String contestName,
}) => TrainingRunMetadata(
  runId: runId,
  contestId: contestId,
  contestName: contestName,
  modeId: TrainingMode.run.id,
  difficultyId: TrainingDifficulty.standard.id,
  questionSeed: 7,
  audioSeed: 8,
  startedAt: DateTime.utc(2026, 1, 1),
);

Future<AppSettings> _settings() async {
  final prefs = await SharedPreferencesWithCache.create(
    cacheOptions: const SharedPreferencesWithCacheOptions(),
  );
  _prefs = prefs;
  return AppSettings(prefs: prefs);
}

SharedPreferencesWithCache? _prefs;

/// The legacy key is private on purpose; tests write the persisted name to
/// exercise the read-only migration path.
Future<void> _writeLegacyRunId(String runId) async {
  await _prefs!.setString('setting_pending_replay_run_id', runId);
}
