import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ssb_runner/l10n/generated/app_localizations.dart';
import 'package:ssb_runner/ui/qso_result_table/qso_result_list/qso_result.dart';
import 'package:ssb_runner/ui/qso_result_table/qso_result_list/qso_result_row.dart';
import 'package:ssb_runner/ui/qso_result_table/qso_voice_replay_button.dart';
import 'package:ssb_runner/ui/qso_result_table/qso_voice_replay_cubit.dart';
import 'package:ssb_runner/ui/theme/app_theme.dart';

Future<void> showQsoVoiceReplayDialog(
  BuildContext context,
  List<QsoResult> corrections,
) {
  final cubit = context.read<QsoVoiceReplayCubit>();
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => BlocProvider.value(
      value: cubit,
      child: QsoVoiceReplayDialog(items: corrections),
    ),
  );
}

class QsoVoiceReplayDialog extends StatelessWidget {
  const QsoVoiceReplayDialog({super.key, required this.items});

  final List<QsoResult> items;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final height = MediaQuery.sizeOf(context).height;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: height - 96),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 12, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l10n.correctionsDialogTitle(items.length),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l10n.correctionsDialogSubtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: l10n.close,
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: scheme.outlineVariant),
            Flexible(
              child: BlocBuilder<QsoVoiceReplayCubit, QsoVoiceReplayState>(
                builder: (context, playback) {
                  if (items.isEmpty) {
                    return const SizedBox(height: 64);
                  }
                  return ListView.builder(
                    itemExtent: 64,
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return _QsoVoiceReplayEntryRow(
                        item: item,
                        isPlaying: playback.playingId == item.id,
                      );
                    },
                  );
                },
              ),
            ),
            Divider(height: 1, color: scheme.outlineVariant),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.close),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QsoVoiceReplayEntryRow extends StatelessWidget {
  const _QsoVoiceReplayEntryRow({
    required this.item,
    required this.isPlaying,
  });

  final QsoResult item;
  final bool isPlaying;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final cubit = context.read<QsoVoiceReplayCubit>();
    final muted = AppDataText.style(
      context,
      fontSize: 12,
      color: scheme.onSurfaceVariant,
    );

    return Container(
      decoration: BoxDecoration(
        color: isPlaying
            ? scheme.primaryContainer.withValues(alpha: 0.42)
            : Colors.transparent,
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: qsoCellPadding + 4),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.serial,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppDataText.style(
                    context,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(item.utc, maxLines: 1, style: muted),
              ],
            ),
          ),
          Expanded(child: _QsoVoiceReplayComparison(item: item)),
          SizedBox(
            width: 76,
            child: Center(child: _action(context, l10n, cubit)),
          ),
        ],
      ),
    );
  }

  Widget _action(
    BuildContext context,
    AppLocalizations l10n,
    QsoVoiceReplayCubit cubit,
  ) {
    if (item.canReplay) {
      return QsoVoiceReplayButton(
        isPlaying: isPlaying,
        hitHeight: 48,
        onTap: () => cubit.play(item),
      );
    }
    if (item.isLegacy) {
      return Text(
        l10n.replayUnavailable,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

class _QsoVoiceReplayComparison extends StatelessWidget {
  const _QsoVoiceReplayComparison({required this.item});

  final QsoResult item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final missingStyle = AppDataText.style(
      context,
      fontSize: 13,
      color: scheme.onSurfaceVariant,
    );

    if (item.isLegacy) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Text(
              '${item.call.data} ${item.exchange.data}',
              style: AppDataText.style(
                context,
                fontSize: 14,
                color: scheme.onSurfaceVariant,
              ).copyWith(decoration: TextDecoration.lineThrough),
            ),
            const SizedBox(width: 8),
            Text(l10n.replayMissingCorrectValue, style: missingStyle),
          ],
        ),
      );
    }

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          if (item.corrections.contains('DUPE')) ...[
            _QsoVoiceReplayTag(label: 'DUPE', color: scheme.onSurfaceVariant),
            const SizedBox(width: 8),
          ],
          _QsoVoiceReplayPair(
            heard: item.call.data,
            correct: item.correctCall,
            isCorrect: item.call.isCorrect,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text('·', style: missingStyle),
          ),
          _QsoVoiceReplayPair(
            heard: item.exchange.data,
            correct: item.correctExchange,
            isCorrect: item.exchange.isCorrect,
          ),
        ],
      ),
    );
  }
}

class _QsoVoiceReplayPair extends StatelessWidget {
  const _QsoVoiceReplayPair({
    required this.heard,
    required this.correct,
    required this.isCorrect,
  });

  final String heard;
  final String correct;
  final bool isCorrect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final heardStyle = AppDataText.style(
      context,
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: isCorrect ? scheme.onSurface : scheme.error,
    ).copyWith(decoration: isCorrect ? null : TextDecoration.lineThrough);
    final correctStyle = AppDataText.style(
      context,
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: scheme.onSurface,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(heard, style: heardStyle),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Icon(
            Icons.arrow_right_alt_rounded,
            size: 16,
            color: scheme.onSurfaceVariant,
          ),
        ),
        Text(correct, style: correctStyle),
      ],
    );
  }
}

class _QsoVoiceReplayTag extends StatelessWidget {
  const _QsoVoiceReplayTag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: color, letterSpacing: 0.6),
      ),
    );
  }
}
