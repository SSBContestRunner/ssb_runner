import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ssb_runner/common/time_format.dart';
import 'package:ssb_runner/contest_run/data/score_data.dart';
import 'package:ssb_runner/contest_run/new/contest_manager.dart';
import 'package:ssb_runner/contest_run/new/contest_timer.dart';
import 'package:ssb_runner/contest_run/score_manager.dart';
import 'package:ssb_runner/dxcc/dxcc_manager.dart';
import 'package:ssb_runner/l10n/generated/app_localizations.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/settings/settings_issue.dart';
import 'package:ssb_runner/settings/settings_readiness.dart';
import 'package:ssb_runner/training/pending_replay.dart';
import 'package:ssb_runner/ui/main_page/replay_armed_banner.dart';
import 'package:ssb_runner/ui/main_page/settings_cubits.dart';
import 'package:ssb_runner/ui/main_page/settings_issues_dialog.dart';
import 'package:ssb_runner/ui/qso_result_table/qso_result_list/qso_result_list_cubit.dart';
import 'package:ssb_runner/ui/theme/app_theme.dart';
import 'package:toastification/toastification.dart';

class SessionPanel extends StatelessWidget {
  const SessionPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (context) => _ScoreCubit(context: context)),
        BlocProvider(
          create: (context) => _TimerCubit(contestTimer: context.read()),
        ),
        BlocProvider(
          create: (context) => _QsoSpeedCubit(
            contestTimer: context.read(),
            contestManager: context.read(),
          ),
        ),
        BlocProvider(
          create: (context) => _RunBtnCubit(contestManager: context.read()),
        ),
      ],
      child: const _SessionCard(),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final settings = context.read<AppSettings>();
    final dxccManager = context.read<DxccManager>();
    final contest = context.watch<ContestSettingCubit>().state;
    final options = context.watch<TrainingOptionsCubit>().state;
    final isCompact = MediaQuery.sizeOf(context).height <= 700;

    return BlocBuilder<_RunBtnCubit, bool>(
      builder: (context, isRunning) {
        return ValueListenableBuilder<int>(
          valueListenable: settings.settingsRevision,
          builder: (context, _, _) {
            // Readiness is computed once per settings revision and shared by
            // the status chip and the start button, so both always describe
            // the same set of blockers. Running sessions do not re-evaluate
            // settings: editing them mid-run must not disturb the chip.
            final issues = isRunning
                ? const <SettingsIssue>[]
                : checkSettingsReadiness(
                    settings: settings,
                    dxccManager: dxccManager,
                  );
            final pendingReplay = isRunning ? null : settings.pendingReplay;

            return Container(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.6),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  _SessionHeader(
                    isRunning: isRunning,
                    issues: issues,
                    pendingReplay: pendingReplay,
                    contestName: contest.name,
                    duration: options.duration,
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _TimerBlock(compact: isCompact),
                          const SizedBox(height: 10),
                          _ProgressBlock(duration: options.duration),
                          const SizedBox(height: 14),
                          const _SessionStatsBlock(),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                    child: _RunSection(
                      isRunning: isRunning,
                      issues: issues,
                      hasPendingReplay: pendingReplay != null,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _SessionHeader extends StatelessWidget {
  const _SessionHeader({
    required this.isRunning,
    required this.issues,
    required this.pendingReplay,
    required this.contestName,
    required this.duration,
  });

  final bool isRunning;
  final List<SettingsIssue> issues;
  final PendingReplay? pendingReplay;
  final String contestName;
  final int duration;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final pending = pendingReplay;

    return ConstrainedBox(
      key: const Key('sessionHeader'),
      // Grows with the text scale instead of clipping the metadata line.
      constraints: const BoxConstraints(minHeight: 68),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final available = constraints.maxWidth;
            final scaler = MediaQuery.textScalerOf(context);
            final direction = Directionality.of(context);
            final titleStyle = textTheme.titleMedium;
            final metaStyle = textTheme.bodySmall;

            // The replay capsule is the only status item that can carry an
            // extra time label, so it yields first when the title row is tight.
            var showTime = false;
            var compactStatus = false;
            if (pending != null) {
              final statusWidth = _StatusChip.widthFor(
                context: context,
                isRunning: isRunning,
                issues: issues,
              );
              final compactStatusWidth = _StatusChip.compactWidthFor(
                isRunning: isRunning,
                issues: issues,
              );
              final titleWidth = measureText(
                l10n.sessionTitle,
                titleStyle,
                scaler,
                direction,
              );
              final labelStyle = ReplayStatusCapsule.labelStyleOf(context);
              final timeStyle = ReplayStatusCapsule.timeStyleOf(context);
              final capsuleWidth = ReplayStatusCapsule.measureWidth(
                labelStyle: labelStyle,
                timeStyle: timeStyle,
                textScaler: scaler,
                textDirection: direction,
                label: l10n.replayStatusChip,
              );
              final capsuleTimeWidth = ReplayStatusCapsule.measureWidth(
                labelStyle: labelStyle,
                timeStyle: timeStyle,
                textScaler: scaler,
                textDirection: direction,
                label: l10n.replayStatusChip,
                time: formatReplayArmedTimeOnly(context, pending.armedAtUtc),
              );
              final budget = available - 2;
              if (titleWidth + 8 + statusWidth + 6 + capsuleTimeWidth <=
                  budget) {
                showTime = true;
              } else if (titleWidth + 8 + statusWidth + 6 + capsuleWidth >
                  budget) {
                // The label is the least critical part of the readiness chip:
                // keep the icon, its tooltip and its tap target instead of
                // ellipsising the session title.
                compactStatus = true;
              }
              // If even the compact chip cannot fit, the title ellipsises as
              // the last resort rather than hiding a state the operator needs.
              compactStatus =
                  compactStatus ||
                  titleWidth + 8 + compactStatusWidth + 6 + capsuleWidth >
                      budget;
            }

            final items = <_HeaderItem, String>{
              _HeaderItem.contest: pending == null
                  ? contestName
                  : replayContestLabel(pending),
              if (pending != null)
                _HeaderItem.mode: replayModeLabel(l10n, pending),
              if (pending != null)
                _HeaderItem.difficulty: replayDifficultyLabel(l10n, pending),
              _HeaderItem.duration: '$duration ${l10n.durationUnit}',
            };

            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        l10n.sessionTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: titleStyle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _StatusChip(
                      isRunning: isRunning,
                      issues: issues,
                      compact: compactStatus,
                    ),
                    if (pending != null) ...[
                      const SizedBox(width: 6),
                      ReplayStatusCapsule(
                        pending: pending,
                        duration: duration,
                        showTime: showTime,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 1),
                _HeaderMetadataLine(
                  items: items,
                  style: metaStyle,
                  maxWidth: available,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Header facts with whole-item hiding.
///
/// Items are measured with the same text style they render with and removed in
/// priority order, so a narrow card never shows an ellipsis or an orphaned
/// separator. Duration goes first (the timer and progress bar already repeat
/// it), then the contest name (the card subtitle owns it), then difficulty,
/// leaving mode last because it decides how the session behaves.
enum _HeaderItem { contest, mode, difficulty, duration }

class _HeaderMetadataLine extends StatelessWidget {
  const _HeaderMetadataLine({
    required this.items,
    required this.style,
    required this.maxWidth,
  });

  final Map<_HeaderItem, String> items;
  final TextStyle? style;
  final double maxWidth;

  static const _hideOrder = [
    _HeaderItem.duration,
    _HeaderItem.contest,
    _HeaderItem.difficulty,
    _HeaderItem.mode,
  ];

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final separatorWidth = measureText(' · ', style, scaler, direction);
    final hidden = <_HeaderItem>{};

    double totalWidth() {
      final visible = items.keys.where((key) => !hidden.contains(key)).toList();
      if (visible.isEmpty) return 0;
      var width = separatorWidth * (visible.length - 1);
      for (final key in visible) {
        width += measureText(items[key]!, style, scaler, direction);
      }
      return width;
    }

    for (final key in _hideOrder) {
      if (totalWidth() <= maxWidth - 2) break;
      if (items.containsKey(key)) hidden.add(key);
    }

    final visible = items.entries
        .where((entry) => !hidden.contains(entry.key))
        .toList();

    return Row(
      key: const Key('sessionHeaderMetadata'),
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < visible.length; index++) ...[
          if (index > 0) Text(' · ', maxLines: 1, style: style),
          Text(visible[index].value, maxLines: 1, style: style),
        ],
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.isRunning,
    required this.issues,
    this.compact = false,
  });

  final bool isRunning;
  final List<SettingsIssue> issues;

  /// Drops the label (keeping the icon, tooltip, semantics and tap target) when
  /// the header row also has to fit the replay capsule.
  final bool compact;

  static String labelFor(
    BuildContext context, {
    required bool isRunning,
    required List<SettingsIssue> issues,
  }) {
    final l10n = AppLocalizations.of(context);
    final isPending = !isRunning && issues.isNotEmpty;
    return isPending
        ? l10n.sessionStatusPending(issues.length)
        : isRunning
        ? l10n.sessionStatusRunning
        : l10n.sessionStatusReady;
  }

  static String semanticsLabelFor(
    BuildContext context, {
    required bool isRunning,
    required List<SettingsIssue> issues,
  }) {
    final l10n = AppLocalizations.of(context);
    final isPending = !isRunning && issues.isNotEmpty;
    return isPending
        ? l10n.readinessIncomplete(issues.length)
        : isRunning
        ? l10n.sessionStatusRunning
        : l10n.sessionStatusReady;
  }

  static double _indicatorWidth({
    required bool isRunning,
    required List<SettingsIssue> issues,
  }) => isRunning || issues.isNotEmpty ? 7 : 14;

  static double widthFor({
    required BuildContext context,
    required bool isRunning,
    required List<SettingsIssue> issues,
  }) {
    final style = Theme.of(
      context,
    ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600);
    return 10 +
        _indicatorWidth(isRunning: isRunning, issues: issues) +
        6 +
        measureText(
          labelFor(context, isRunning: isRunning, issues: issues),
          style,
          MediaQuery.textScalerOf(context),
          Directionality.of(context),
        ) +
        10;
  }

  static double compactWidthFor({
    required bool isRunning,
    required List<SettingsIssue> issues,
  }) => 20 + _indicatorWidth(isRunning: isRunning, issues: issues);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final semantic = context.semanticColors;

    final isPending = !isRunning && issues.isNotEmpty;
    final background = isRunning
        ? semantic.successContainer
        : isPending
        ? scheme.errorContainer
        : scheme.primaryContainer;
    final foreground = isRunning
        ? semantic.onSuccessContainer
        : isPending
        ? scheme.onErrorContainer
        // V2 keeps the container fill but draws the check and label in the
        // brand blue, matching the approved prototype instead of the darker
        // onPrimaryContainer role.
        : scheme.primary;

    final semanticsLabel = semanticsLabelFor(
      context,
      isRunning: isRunning,
      issues: issues,
    );
    final label = labelFor(context, isRunning: isRunning, issues: issues);

    final chip = SizedBox(
      height: 40,
      child: Center(
        widthFactor: 1,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: isPending
                ? () => showSettingsIssuesDialog(context, issues: issues)
                : null,
            borderRadius: BorderRadius.circular(8),
            child: Semantics(
              button: isPending,
              label: semanticsLabel,
              excludeSemantics: true,
              child: Container(
                key: const Key('sessionStatusChip'),
                height: 26,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isRunning || isPending)
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: foreground,
                        ),
                      )
                    else
                      Icon(Icons.check_rounded, size: 14, color: foreground),
                    if (!compact) ...[
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (!compact) return chip;
    return Tooltip(message: label, child: chip);
  }
}

class _TimerBlock extends StatelessWidget {
  const _TimerBlock({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final options = context.watch<TrainingOptionsCubit>().state;

    return BlocBuilder<_TimerCubit, Duration>(
      builder: (context, elapsed) {
        final remaining = Duration(
          seconds: (options.duration * 60 - elapsed.inSeconds).clamp(
            0,
            options.duration * 60,
          ),
        );

        final metaStyle = AppDataText.style(
          context,
          fontSize: 12,
          color: scheme.onSurfaceVariant,
        );

        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              flex: 3,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  formatDuration(elapsed),
                  maxLines: 1,
                  style: AppDataText.style(
                    context,
                    fontSize: compact ? 34 : 42,
                    height: compact ? 40 / 34 : 48 / 42,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${l10n.elapsedLabel} ${formatDuration(elapsed)}',
                      key: const Key('timerElapsedLabel'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: metaStyle,
                    ),
                    Text(
                      '${l10n.remainingLabel} ${formatDuration(remaining)}',
                      key: const Key('timerRemainingLabel'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: metaStyle,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ProgressBlock extends StatelessWidget {
  const _ProgressBlock({required this.duration});

  final int duration;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return BlocBuilder<_TimerCubit, Duration>(
      builder: (context, elapsed) {
        final totalSeconds = duration * 60;
        final progress = totalSeconds <= 0
            ? 0.0
            : (elapsed.inSeconds / totalSeconds).clamp(0.0, 1.0);
        final metaStyle = AppDataText.style(
          context,
          fontSize: 12,
          color: scheme.onSurfaceVariant,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(value: progress, minHeight: 6),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('0 ${l10n.durationUnit}', style: metaStyle),
                Text('$duration ${l10n.durationUnit}', style: metaStyle),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _SessionStatsBlock extends StatelessWidget {
  const _SessionStatsBlock();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final corrections = context
        .watch<QsoRecordListCubit>()
        .state
        .where((qso) => qso.corrections.isNotEmpty)
        .length;

    final metaStyle = AppDataText.style(
      context,
      fontSize: 11,
      letterSpacing: 0.4,
      color: scheme.onSurfaceVariant,
    );
    final scoreNumberStyle = AppDataText.style(
      context,
      fontSize: 12.5,
      letterSpacing: 0.3,
    );

    return BlocBuilder<_ScoreCubit, _ScoreData>(
      builder: (context, data) {
        final score = data.verifiedScore;
        final raw = data.rawScore;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(
                              Icons.emoji_events_outlined,
                              size: 12,
                              color: scheme.tertiary,
                            ),
                          ),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(l10n.verifiedScoreLabel, style: metaStyle),
                              const SizedBox(width: 4),
                              Text(
                                _formatNumber(score.score),
                                style: scoreNumberStyle,
                              ),
                              const SizedBox(width: 3),
                              Text(l10n.scoreUnit, style: metaStyle),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(l10n.rawScoreLabel, style: metaStyle),
                          const SizedBox(width: 4),
                          Text(
                            _formatNumber(raw.score),
                            style: scoreNumberStyle,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Text('·', style: metaStyle),
                          ),
                          Text('$corrections', style: scoreNumberStyle),
                          const SizedBox(width: 3),
                          Text(l10n.correctionsLabel, style: metaStyle),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: scheme.outlineVariant)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.statRate.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppDataText.style(
                            context,
                            fontSize: 11,
                            letterSpacing: 0.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        BlocBuilder<_QsoSpeedCubit, double?>(
                          builder: (context, speed) => Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    speed == null
                                        ? '---'
                                        : speed.toStringAsFixed(1),
                                    maxLines: 1,
                                    style: AppDataText.style(
                                      context,
                                      fontSize: 30,
                                      height: 38 / 30,
                                    ),
                                  ),
                                ),
                              ),
                              if (speed != null)
                                Padding(
                                  padding: const EdgeInsets.only(left: 3),
                                  child: Text(
                                    l10n.rateSuffix,
                                    style: AppDataText.style(
                                      context,
                                      fontSize: 11,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Container(
                    padding: const EdgeInsets.only(left: 14),
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(color: scheme.outlineVariant),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _SideStat(
                          label: l10n.statQsos,
                          value: _formatNumber(score.count),
                        ),
                        const SizedBox(height: 6),
                        _SideStat(
                          label: l10n.statMultiplier,
                          value: _formatNumber(score.multiple),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SideStat extends StatelessWidget {
  const _SideStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 104),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppDataText.style(
              context,
              fontSize: 10.5,
              letterSpacing: 0.4,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            maxLines: 1,
            style: AppDataText.style(context, fontSize: 17, height: 22 / 17),
          ),
        ],
      ),
    );
  }
}

/// Readiness is computed once per settings revision by [_SessionCard] and
/// shared by the status chip and the start button, so clicking start always
/// explains the same set of blockers the chip is showing.
class _RunSection extends StatelessWidget {
  const _RunSection({
    required this.isRunning,
    required this.issues,
    required this.hasPendingReplay,
  });

  final bool isRunning;
  final List<SettingsIssue> issues;
  final bool hasPendingReplay;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _RunButton(
          isRunning: isRunning,
          issues: issues,
          hasPendingReplay: hasPendingReplay,
        ),
        const SizedBox(height: 8),
        _RunNote(isRunning: isRunning),
      ],
    );
  }
}

class _RunButton extends StatelessWidget {
  const _RunButton({
    required this.isRunning,
    required this.issues,
    required this.hasPendingReplay,
  });

  final bool isRunning;
  final List<SettingsIssue> issues;
  final bool hasPendingReplay;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontSize: 15, letterSpacing: 0.5),
        ),
        onPressed: () async {
          if (!isRunning && issues.isNotEmpty) {
            showSettingsIssuesDialog(context, issues: issues);
            return;
          }
          final manager = context.read<ContestManager>();
          if (isRunning) {
            manager.stopContest();
            return;
          }
          final result = await manager.startContest();
          if (!context.mounted) return;
          // An abandoned replay started a fresh session instead; say so
          // explicitly rather than silently changing what RUN did.
          if (result.started && result.abortedReason != null) {
            toastification.show(
              title: Text(
                l10n.replayAbortedToast(result.replayContestName ?? '—'),
              ),
              autoCloseDuration: const Duration(seconds: 3),
              type: ToastificationType.warning,
              style: ToastificationStyle.fillColored,
            );
          }
        },
        icon: Icon(
          isRunning ? Icons.stop_circle_outlined : Icons.play_arrow,
          size: 20,
        ),
        label: Text(
          isRunning
              ? l10n.stopTraining
              : hasPendingReplay
              ? l10n.startReplay
              : l10n.startTraining,
        ),
      ),
    );
  }
}

class _RunNote extends StatelessWidget {
  const _RunNote({required this.isRunning});

  final bool isRunning;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Text(
      isRunning ? l10n.sessionRunningNote : l10n.sessionIdleNote,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}

class _ScoreData {
  const _ScoreData({required this.rawScore, required this.verifiedScore});

  final ScoreData rawScore;
  final ScoreData verifiedScore;

  _ScoreData copyWith({ScoreData? rawScore, ScoreData? verifiedScore}) {
    return _ScoreData(
      rawScore: rawScore ?? this.rawScore,
      verifiedScore: verifiedScore ?? this.verifiedScore,
    );
  }
}

class _ScoreCubit extends Cubit<_ScoreData> {
  StreamSubscription<ScoreData>? _rawScoreDataSubscription;
  StreamSubscription<ScoreData>? _verifiedScoreDataSubscription;
  ScoreManager? _subscribedScoreManager;
  late final StreamSubscription<String> _runSubscription;

  _ScoreCubit({required BuildContext context})
    : super(
        _ScoreData(
          rawScore: ScoreData.initial(),
          verifiedScore: ScoreData.initial(),
        ),
      ) {
    final contestManager = context.read<ContestManager>();
    _runSubscription = contestManager.contestRunIdStream.listen((_) {
      _unsubscribeScoreUpdate();
      emit(
        _ScoreData(
          rawScore: ScoreData.initial(),
          verifiedScore: ScoreData.initial(),
        ),
      );

      final contestRunningManager = contestManager.contestRunningManager;

      if (contestRunningManager == null) {
        return;
      }

      _subscribeScoreUpdate(contestRunningManager.scoreManager);
    });
  }

  void _subscribeScoreUpdate(ScoreManager scoreManager) {
    if (identical(_subscribedScoreManager, scoreManager)) {
      return;
    }
    _unsubscribeScoreUpdate();
    _subscribedScoreManager = scoreManager;

    _rawScoreDataSubscription = scoreManager.rawScoreDataStream.stream.listen((
      scoreData,
    ) {
      emit(state.copyWith(rawScore: scoreData));
    });

    _verifiedScoreDataSubscription = scoreManager.verifiedScoreDataStream.stream
        .listen((scoreData) {
          emit(state.copyWith(verifiedScore: scoreData));
        });
  }

  void _unsubscribeScoreUpdate() {
    _rawScoreDataSubscription?.cancel();
    _verifiedScoreDataSubscription?.cancel();
    _rawScoreDataSubscription = null;
    _verifiedScoreDataSubscription = null;
    _subscribedScoreManager = null;
  }

  @override
  Future<void> close() {
    _runSubscription.cancel();
    _unsubscribeScoreUpdate();
    return super.close();
  }
}

class _TimerCubit extends Cubit<Duration> {
  late final StreamSubscription<Duration> _subscription;

  _TimerCubit({required ContestTimer contestTimer}) : super(Duration.zero) {
    _subscription = contestTimer.elapseTimeStream.listen(emit);
  }

  @override
  Future<void> close() {
    _subscription.cancel();
    return super.close();
  }
}

class _QsoSpeedCubit extends Cubit<double?> {
  final ContestTimer _contestTimer;
  final ContestManager _contestManager;
  late final StreamSubscription<Duration> _subscription;

  _QsoSpeedCubit({
    required ContestTimer contestTimer,
    required ContestManager contestManager,
  }) : _contestTimer = contestTimer,
       _contestManager = contestManager,
       super(null) {
    _subscription = _contestTimer.elapseTimeStream.listen(_updateQsoSpeed);
  }

  Future<void> _updateQsoSpeed(Duration elapseTime) async {
    final totalSeconds = elapseTime.inSeconds;

    if (totalSeconds == 0) {
      emit(null);
      return;
    }

    final qsoTimes = await _contestManager.recentCurrentRunQsoTimes();
    final qsoCount = qsoTimes.length;
    if (qsoCount == 0) {
      emit(null);
      return;
    }
    // The first contacts use elapsed practice time. Once five intervals exist,
    // display a rolling five-QSO rate rather than a diluted session rate.
    final measuredSeconds = qsoCount >= 6
        ? qsoTimes.last - qsoTimes.first
        : totalSeconds;
    if (measuredSeconds <= 0) return;
    final measuredQsos = qsoCount >= 6 ? 5 : qsoCount;
    final qsoSpeed = measuredQsos / measuredSeconds * 3600;

    emit(qsoSpeed);
  }

  @override
  Future<void> close() {
    _subscription.cancel();
    return super.close();
  }
}

class _RunBtnCubit extends Cubit<bool> {
  late final StreamSubscription<bool> _subscription;

  _RunBtnCubit({required ContestManager contestManager})
    : super(contestManager.isContestRunning) {
    _subscription = contestManager.isContestRunningStream.listen(emit);
  }

  @override
  Future<void> close() {
    _subscription.cancel();
    return super.close();
  }
}

String _formatNumber(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(digits[index]);
  }
  return value < 0 ? '-$buffer' : buffer.toString();
}
