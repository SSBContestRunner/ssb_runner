import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/contest_run/new/run_plan.dart';
import 'package:ssb_runner/contest_run/new/run_plan_resolver.dart';
import 'package:ssb_runner/training/pending_replay.dart';
import 'package:ssb_runner/training/session_review.dart';

void main() {
  test('without a pending replay the ordinary settings win', () {
    final plan = _resolve(pending: null, log: null);

    expect(plan.source, RunPlanSource.settings);
    expect(plan.contestId, 'CQ-WW-SSB');
    expect(plan.modeId, 'search-and-pounce');
    expect(plan.difficultyId, 'advanced');
    expect(plan.replayRunId, isNull);
    expect(plan.abortedReason, isNull);
  });

  test('missing recording events abort the replay', () {
    final plan = _resolve(
      pending: _pending(),
      log: const ReplayLog(answers: []),
    );

    expect(plan.source, RunPlanSource.settings);
    expect(plan.contestId, 'CQ-WW-SSB');
    expect(plan.abortedReason, ReplayAbortReason.eventsMissing);
    expect(plan.abortedContestName, 'CQ WPX');
    expect(plan.replayRunId, isNull);
    // An abandoned replay also falls back to the ordinary practice seeds.
    expect(plan.questionSeed, 1);
    expect(plan.audioSeed, 2);
  });

  test('a replay without a header is allowed when the recording exists', () {
    final plan = _resolve(
      pending: _pending(),
      log: ReplayLog(answers: [_answer()]),
    );

    expect(plan.source, RunPlanSource.pending);
    expect(plan.contestId, 'CQ-WPX');
    expect(plan.modeId, 'run');
    expect(plan.difficultyId, 'standard');
    expect(plan.replayRunId, 'wpx-run');
    expect(plan.questionSeed, 42);
    expect(plan.audioSeed, 43);
  });

  test('a matching header allows the replay', () {
    final plan = _resolve(
      pending: _pending(),
      log: ReplayLog(
        answers: [_answer()],
        header: _header(contestId: 'CQ-WPX'),
      ),
    );

    expect(plan.source, RunPlanSource.pending);
    expect(plan.replayRunId, 'wpx-run');
    expect(plan.abortedReason, isNull);
  });

  test('a contest mismatch aborts instead of adopting the header', () {
    final plan = _resolve(
      pending: _pending(),
      log: ReplayLog(
        answers: [_answer()],
        header: _header(contestId: 'CQ-WW-SSB', contestName: 'CQ WW'),
      ),
    );

    expect(plan.source, RunPlanSource.settings);
    expect(plan.contestId, 'CQ-WW-SSB');
    expect(plan.replayRunId, isNull);
    expect(plan.abortedReason, ReplayAbortReason.headerMismatch);
  });

  test('a mode mismatch aborts the replay', () {
    final plan = _resolve(
      pending: _pending(),
      log: ReplayLog(
        answers: [_answer()],
        header: _header(contestId: 'CQ-WPX', modeId: 'pileup'),
      ),
    );

    expect(plan.abortedReason, ReplayAbortReason.headerMismatch);
    expect(plan.modeId, 'search-and-pounce');
  });

  test('a difficulty mismatch aborts the replay', () {
    final plan = _resolve(
      pending: _pending(),
      log: ReplayLog(
        answers: [_answer()],
        header: _header(contestId: 'CQ-WPX', difficultyId: 'advanced'),
      ),
    );

    expect(plan.abortedReason, ReplayAbortReason.headerMismatch);
    expect(plan.difficultyId, 'advanced');
  });

  test('an unknown pending contest aborts without falling back to WPX', () {
    final plan = _resolve(
      pending: _pending(contestId: unknownReplayField),
      log: ReplayLog(answers: [_answer()]),
    );

    expect(plan.source, RunPlanSource.settings);
    expect(plan.contestId, 'CQ-WW-SSB');
    expect(plan.abortedReason, ReplayAbortReason.contestUnknown);
  });

  test('an unknown snapshot is proven by the recording header', () {
    final plan = _resolve(
      pending: _pending(
        contestId: unknownReplayField,
        modeId: unknownReplayField,
        difficultyId: unknownReplayField,
      ),
      log: ReplayLog(
        answers: [_answer()],
        header: _header(contestId: 'CQ-WPX'),
      ),
    );

    expect(plan.source, RunPlanSource.pending);
    expect(plan.contestId, 'CQ-WPX');
    expect(plan.modeId, 'run');
    expect(plan.difficultyId, 'standard');
    expect(plan.replayRunId, 'wpx-run');
    // The header supplies the seeds when the snapshot lost its metadata.
    expect(plan.questionSeed, 42);
    expect(plan.audioSeed, 43);
  });

  test('unknown mode or difficulty in the snapshot aborts the replay', () {
    final plan = _resolve(
      pending: _pending(modeId: unknownReplayField),
      log: ReplayLog(answers: [_answer()]),
    );

    expect(plan.source, RunPlanSource.settings);
    expect(plan.abortedReason, ReplayAbortReason.contestUnknown);
  });
}

RunPlan _resolve({required PendingReplay? pending, required ReplayLog? log}) =>
    RunPlanResolver.resolve(
      pendingReplay: pending,
      replayLog: log,
      settingsContestId: 'CQ-WW-SSB',
      settingsModeId: 'search-and-pounce',
      settingsDifficultyId: 'advanced',
      questionSeed: 1,
      audioSeed: 2,
    );

PendingReplay _pending({
  String contestId = 'CQ-WPX',
  String modeId = 'run',
  String difficultyId = 'standard',
}) => PendingReplay(
  runId: 'wpx-run',
  contestId: contestId,
  contestName: 'CQ WPX',
  modeId: modeId,
  difficultyId: difficultyId,
  questionSeed: 42,
  audioSeed: 43,
  armedAtUtc: DateTime.utc(2026, 1, 1),
);

TrainingRunEvent _answer() => const TrainingRunEvent(
  elapsedMs: 0,
  type: 'answer',
  callsign: '4X6ZM',
  exchange: '2500',
  pileupCallsigns: ['4X6ZM'],
  modeId: 'run',
);

RecordedRunHeader _header({
  String contestId = 'CQ-WPX',
  String contestName = 'CQ WPX',
  String modeId = 'run',
  String difficultyId = 'standard',
}) => RecordedRunHeader(
  contestId: contestId,
  contestName: contestName,
  modeId: modeId,
  difficultyId: difficultyId,
  questionSeed: 42,
  audioSeed: 43,
);
