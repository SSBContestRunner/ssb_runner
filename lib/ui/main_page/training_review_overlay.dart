import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ssb_runner/contest_run/new/contest_manager.dart';
import 'package:ssb_runner/l10n/domain_l10n.dart';
import 'package:ssb_runner/l10n/generated/app_localizations.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/training/session_review.dart';
import 'package:ssb_runner/training/training_profile.dart';

class TrainingReviewOverlay extends StatefulWidget {
  const TrainingReviewOverlay({super.key});
  @override
  State<TrainingReviewOverlay> createState() => _TrainingReviewOverlayState();
}

class _TrainingReviewOverlayState extends State<TrainingReviewOverlay> {
  StreamSubscription<TrainingRunReview>? _subscription;
  TrainingRunReview? _review;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _subscription ??= context.read<ContestManager>().reviewStream.listen(
      (review) => mounted ? setState(() => _review = review) : null,
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final review = _review;
    if (review == null) return const SizedBox.shrink();
    final color = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return Semantics(
      label: l10n.trainingReviewSemantics,
      liveRegion: true,
      child: ColoredBox(
        color: color.scrim.withAlpha(150),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 510),
            child: Material(
              color: color.surface,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.sessionReviewTitle,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    if (review.endReason == 'replay_completed')
                      const Text(
                        'Replay completed. All recorded answers have been replayed.',
                      ),
                    if (review.endReason == 'callsign_pool_exhausted')
                      const Text(
                        'Training completed. All available stations have been used.',
                      ),
                    const SizedBox(height: 8),
                    Text(
                      '${review.metadata.contestName} · '
                      '${l10n.trainingModeLabelById(review.metadata.modeId)} · '
                      '${l10n.trainingDifficultyLabelById(review.metadata.difficultyId)}',
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 24,
                      runSpacing: 12,
                      children: [
                        _stat(l10n.statQsos, '${review.qsoCount}'),
                        if (review.duplicateCount > 0)
                          _stat(
                            l10n.statDuplicates,
                            '${review.duplicateCount}',
                          ),
                        _stat(
                          l10n.statAccuracy,
                          '${(review.accuracy * 100).toStringAsFixed(1)}%',
                        ),
                        _stat(
                          l10n.statRate,
                          '${review.qsosPerHour.toStringAsFixed(1)}/h',
                        ),
                        _stat(l10n.scoreScore, '${review.score}'),
                        _stat(l10n.statCallErrors, '${review.callsignErrors}'),
                        _stat(
                          l10n.statExchangeErrors,
                          '${review.exchangeErrors}',
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      l10n.practiceSeedLine(review.metadata.questionSeed),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: () => _replay(review),
                          icon: const Icon(Icons.replay),
                          label: Text(l10n.replayThisSession),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () => setState(() => _review = null),
                          child: Text(l10n.close),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _replay(TrainingRunReview review) {
    final l10n = AppLocalizations.of(context);
    final settings = context.read<AppSettings>();
    settings
      ..pendingQuestionSeed = review.metadata.questionSeed
      ..pendingAudioSeed = review.metadata.audioSeed
      ..pendingReplayRunId = review.metadata.runId
      ..contestId = review.metadata.contestId
      ..contestModeId = review.metadata.modeId
      ..difficulty = TrainingDifficulty.fromId(review.metadata.difficultyId);
    setState(() => _review = null);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.replaySeedSnack(review.metadata.questionSeed)),
      ),
    );
  }

  Widget _stat(String label, String value) => SizedBox(
    width: 125,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        Text(
          value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}
