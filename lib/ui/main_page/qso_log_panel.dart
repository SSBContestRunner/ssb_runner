import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ssb_runner/l10n/generated/app_localizations.dart';
import 'package:ssb_runner/ui/qso_result_table/qso_result_list/qso_result.dart';
import 'package:ssb_runner/ui/qso_result_table/qso_result_list/qso_result_list.dart';
import 'package:ssb_runner/ui/qso_result_table/qso_result_list/qso_result_list_cubit.dart';
import 'package:ssb_runner/ui/qso_result_table/qso_result_list/qso_result_row.dart';

class QsoLogPanel extends StatelessWidget {
  const QsoLogPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return BlocBuilder<QsoRecordListCubit, List<QsoResult>>(
      builder: (context, qsos) {
        final corrections = qsos
            .where((qso) => qso.corrections.isNotEmpty)
            .length;

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
              SizedBox(
                height: 56,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.qsoRecordsTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 1),
                            Text(
                              l10n.logSubtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      _LogChip(
                        label: l10n.logCount(qsos.length),
                        background: scheme.secondaryContainer,
                        foreground: scheme.onSecondaryContainer,
                      ),
                      if (corrections > 0) ...[
                        const SizedBox(width: 6),
                        _LogChip(
                          label: l10n.logCorrections(corrections),
                          background: scheme.errorContainer,
                          foreground: scheme.onErrorContainer,
                          icon: Icons.error_outline,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Divider(height: 1, color: scheme.outlineVariant),
              const _LogHeader(),
              Expanded(child: QsoRecordList()),
            ],
          ),
        );
      },
    );
  }
}

class _LogChip extends StatelessWidget {
  const _LogChip({
    required this.label,
    required this.background,
    required this.foreground,
    this.icon,
  });

  final String label;
  final Color background;
  final Color foreground;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: foreground),
          ),
        ],
      ),
    );
  }
}

class _LogHeader extends StatelessWidget {
  const _LogHeader();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: scheme.onSurfaceVariant,
      letterSpacing: 0.5,
    );

    return Container(
      height: 34,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          SizedBox(
            width: qsoUtcColumnWidth,
            child: _headerCell(l10n.tableUtc, style),
          ),
          Expanded(
            flex: qsoCallColumnFlex.toInt(),
            child: _headerCell(l10n.tableCall, style),
          ),
          SizedBox(
            width: qsoRstColumnWidth,
            child: _headerCell(l10n.tableRst, style),
          ),
          Expanded(
            flex: qsoExchangeColumnFlex.toInt(),
            child: _headerCell(l10n.tableExchange, style),
          ),
          SizedBox(
            width: qsoCorrectionsColumnWidth,
            child: _headerCell(l10n.tableCorrections, style),
          ),
        ],
      ),
    );
  }

  Widget _headerCell(String label, TextStyle? style) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: qsoCellPadding),
      child: Text(
        label,
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
