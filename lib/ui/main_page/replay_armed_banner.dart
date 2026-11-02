import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ssb_runner/l10n/domain_l10n.dart';
import 'package:ssb_runner/l10n/generated/app_localizations.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/training/pending_replay.dart';
import 'package:toastification/toastification.dart';

/// Shared "a replay is armed" banner for the session card and the settings
/// drawer. It explains the snapshot and is the single explicit exit: cancelling
/// returns the UI to the ordinary settings, which were never touched.
class ReplayArmedBanner extends StatelessWidget {
  const ReplayArmedBanner({
    super.key,
    required this.pending,
    this.showLockHint = false,
    this.compact = false,
  });

  final PendingReplay pending;

  /// The settings drawer also explains that contest/mode/difficulty are locked.
  final bool showLockHint;

  /// The session card uses a two-line strip; the settings drawer keeps the
  /// full explanation with the station hint and lock hint.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = context.read<AppSettings>();
    final scheme = Theme.of(context).colorScheme;
    final local = pending.armedAtUtc.toLocal();
    final material = MaterialLocalizations.of(context);
    final time =
        '${material.formatMediumDate(local)} '
        '${material.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
    final contest = pending.hasKnownContest
        ? pending.contestName
        : pending.contestId;
    final mode = pending.hasKnownMode
        ? l10n.trainingModeLabelById(pending.modeId)
        : pending.modeId;
    final difficulty = pending.hasKnownDifficulty
        ? l10n.trainingDifficultyLabelById(pending.difficultyId)
        : pending.difficultyId;

    void cancelReplay() {
      settings.clearPendingReplay();
      toastification.show(
        title: Text(l10n.replayCancelledToast),
        autoCloseDuration: const Duration(seconds: 2),
        type: ToastificationType.success,
        style: ToastificationStyle.fillColored,
      );
    }

    if (compact) {
      final bodySmall = Theme.of(context).textTheme.bodySmall;
      return Container(
        key: const Key('replayArmedBanner'),
        padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(
                Icons.replay_outlined,
                size: 16,
                color: scheme.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        l10n.replayArmedTitle,
                        maxLines: 1,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Flexible(
                        child: Text(
                          ' · $contest · $mode · $difficulty',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '$time · ${l10n.replayArmedCompactHint}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: cancelReplay,
              icon: const Icon(Icons.close, size: 18),
              tooltip: l10n.cancelReplay,
              color: scheme.onSurfaceVariant,
              padding: EdgeInsets.zero,
            ),
          ],
        ),
      );
    }

    return Container(
      key: const Key('replayArmedBanner'),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          scheme.primaryContainer.withValues(alpha: 0.38),
          scheme.surface,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Color.alphaBlend(
            scheme.primary.withValues(alpha: 0.22),
            scheme.outlineVariant,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.replay_outlined, size: 16, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.replayArmedTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(color: scheme.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            l10n.replayArmedDetail(contest, mode, difficulty, time),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 2),
          Text(
            l10n.replayArmedStationHint,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (showLockHint) ...[
            const SizedBox(height: 2),
            Text(
              l10n.replayLockedHint,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: cancelReplay,
              icon: const Icon(Icons.close, size: 16),
              label: Text(l10n.cancelReplay),
              style: TextButton.styleFrom(
                foregroundColor: scheme.primary,
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
