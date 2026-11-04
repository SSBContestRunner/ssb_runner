import 'package:ssb_runner/contest_run/new/run_plan.dart';
import 'package:ssb_runner/contest_type/contest_definition.dart';
import 'package:ssb_runner/logging/app_logger.dart';
import 'package:ssb_runner/training/pending_replay.dart';
import 'package:ssb_runner/training/session_review.dart';

/// Recorded events loaded for a replay, plus its optional run-start header.
class ReplayLog {
  const ReplayLog({required this.answers, this.header});

  final List<TrainingRunEvent> answers;
  final RecordedRunHeader? header;

  bool get hasAnswers => answers.isNotEmpty;
}

/// Resolves what the next run actually uses (design §7.5).
///
/// A replay is only accepted when the pending snapshot and the recording
/// header agree on contest, mode and difficulty. The header is used for
/// verification only; a mismatch or a missing recording aborts the replay and
/// falls back to the ordinary settings instead of silently merging the two.
class RunPlanResolver {
  static RunPlan resolve({
    required PendingReplay? pendingReplay,
    required ReplayLog? replayLog,
    required String settingsContestId,
    required String settingsModeId,
    required String settingsDifficultyId,
    required int questionSeed,
    required int audioSeed,
  }) {
    final settingsContestCanonical = ContestRegistry.canonicalId(
      settingsContestId,
    );
    if (settingsContestCanonical == null) {
      log.warn(
        'unknown contest id in settings, falling back to the registry default',
        tag: 'contest.replay',
        fields: {'settingsContestId': settingsContestId},
      );
    }
    final settingsPlan = RunPlan(
      definition: ContestRegistry.byId(settingsContestId),
      modeId: settingsModeId,
      difficultyId: settingsDifficultyId,
      questionSeed: questionSeed,
      audioSeed: audioSeed,
    );

    if (pendingReplay == null) {
      return settingsPlan;
    }

    final canonical = ContestRegistry.canonicalId(pendingReplay.contestId);
    final definition = canonical == null
        ? null
        : ContestRegistry.byIdOrNull(canonical);

    final snapshotIncomplete =
        !pendingReplay.hasKnownContest ||
        !pendingReplay.hasKnownMode ||
        !pendingReplay.hasKnownDifficulty;
    if (snapshotIncomplete) {
      // Legacy pending snapshots can lose their history entry. In that case
      // the recording's own header is the only evidence of ownership; a
      // concrete but unregistered id still aborts instead of falling back.
      final header = replayLog?.header;
      final headerDefinition = header == null
          ? null
          : ContestRegistry.byIdOrNull(
              ContestRegistry.canonicalId(header.contestId),
            );
      final headerKnown =
          header != null &&
          header.modeId != unknownReplayField &&
          header.difficultyId != unknownReplayField;
      if (header != null &&
          headerDefinition != null &&
          headerKnown &&
          replayLog!.hasAnswers) {
        log.info(
          'replay proven by the recording header',
          tag: 'contest.replay',
          fields: {
            'replayRunId': pendingReplay.runId,
            'recordedContestId': header.contestId,
            'recordedModeId': header.modeId,
            'recordedDifficultyId': header.difficultyId,
          },
        );
        return RunPlan(
          definition: headerDefinition,
          modeId: header.modeId,
          difficultyId: header.difficultyId,
          questionSeed: header.questionSeed,
          audioSeed: header.audioSeed,
          replayRunId: pendingReplay.runId,
          source: RunPlanSource.pending,
        );
      }
      log.warn(
        'replay snapshot is unknown and cannot be proven',
        tag: 'contest.replay',
        fields: {
          'replayRunId': pendingReplay.runId,
          'pendingContestId': pendingReplay.contestId,
          'pendingModeId': pendingReplay.modeId,
          'pendingDifficultyId': pendingReplay.difficultyId,
        },
      );
      return _abort(
        settingsPlan,
        ReplayAbortReason.contestUnknown,
        pendingReplay,
        warnings: const ['replay_unknown_contest'],
      );
    }

    if (definition == null) {
      log.warn(
        'pending replay contest id is not registered',
        tag: 'contest.replay',
        fields: {
          'replayRunId': pendingReplay.runId,
          'pendingContestId': pendingReplay.contestId,
        },
      );
      return _abort(
        settingsPlan,
        ReplayAbortReason.contestUnknown,
        pendingReplay,
        warnings: const ['replay_unknown_contest'],
      );
    }

    if (replayLog == null || !replayLog.hasAnswers) {
      return _abort(
        settingsPlan,
        ReplayAbortReason.eventsMissing,
        pendingReplay,
        warnings: const ['replay_events_missing'],
      );
    }

    final header = replayLog.header;
    if (header != null) {
      final sameContest =
          ContestRegistry.canonicalId(header.contestId) == definition.id;
      final sameMode = header.modeId == pendingReplay.modeId;
      final sameDifficulty = header.difficultyId == pendingReplay.difficultyId;
      if (!sameContest || !sameMode || !sameDifficulty) {
        log.warn(
          'replay header does not match the pending snapshot',
          tag: 'contest.replay',
          fields: {
            'replayRunId': pendingReplay.runId,
            'pendingContestId': pendingReplay.contestId,
            'pendingModeId': pendingReplay.modeId,
            'pendingDifficultyId': pendingReplay.difficultyId,
            'recordedContestId': header.contestId,
            'recordedModeId': header.modeId,
            'recordedDifficultyId': header.difficultyId,
          },
        );
        return _abort(
          settingsPlan,
          ReplayAbortReason.headerMismatch,
          pendingReplay,
          warnings: const ['replay_header_mismatch'],
        );
      }
    }

    return RunPlan(
      definition: definition,
      modeId: pendingReplay.modeId,
      difficultyId: pendingReplay.difficultyId,
      questionSeed: pendingReplay.questionSeed,
      audioSeed: pendingReplay.audioSeed,
      replayRunId: pendingReplay.runId,
      source: RunPlanSource.pending,
    );
  }

  static RunPlan _abort(
    RunPlan settingsPlan,
    ReplayAbortReason reason,
    PendingReplay pendingReplay, {
    required List<String> warnings,
  }) => RunPlan(
    definition: settingsPlan.definition,
    modeId: settingsPlan.modeId,
    difficultyId: settingsPlan.difficultyId,
    questionSeed: settingsPlan.questionSeed,
    audioSeed: settingsPlan.audioSeed,
    source: RunPlanSource.settings,
    abortedReason: reason,
    abortedContestName: pendingReplay.contestName,
    warnings: warnings,
  );
}
