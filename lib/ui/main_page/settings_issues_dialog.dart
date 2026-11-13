import 'package:flutter/material.dart';
import 'package:ssb_runner/l10n/domain_l10n.dart';
import 'package:ssb_runner/l10n/generated/app_localizations.dart';
import 'package:ssb_runner/settings/settings_issue.dart';
import 'package:ssb_runner/ui/main_page/settings_sheet.dart';

/// Blocking checklist shown when a run cannot start.
///
/// Every row is a deep link into the settings drawer, so the operator sees what
/// is missing, where it lives, and can jump straight to the field.
Future<void> showSettingsIssuesDialog(
  BuildContext context, {
  required List<SettingsIssue> issues,
}) {
  // Captured before the dialog route is pushed: the dialog context does not
  // inherit the providers that [showSettingsSheet] needs.
  final pageContext = context;

  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final l10n = AppLocalizations.of(dialogContext);
      final media = MediaQuery.sizeOf(dialogContext);

      void open(SettingsIssue issue) {
        Navigator.of(dialogContext).pop();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!pageContext.mounted) return;
          showSettingsSheet(
            pageContext,
            initialTab: issue.tab,
            focusFieldKey: issue.focusKey,
          );
        });
      }

      return AlertDialog(
        title: Text(l10n.readinessTitle),
        content: SizedBox(
          width: 440,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: media.height * 0.6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (issues.length > 1) ...[
                  Text(
                    l10n.readinessIncomplete(issues.length),
                    style: Theme.of(dialogContext).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                ],
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (final issue in issues)
                          _IssueRow(issue: issue, onTap: () => open(issue)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.close),
          ),
          FilledButton(
            onPressed: issues.isEmpty ? null : () => open(issues.first),
            child: Text(l10n.readinessOpenSettings),
          ),
        ],
      );
    },
  );
}

class _IssueRow extends StatelessWidget {
  const _IssueRow({required this.issue, required this.onTap});

  final SettingsIssue issue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final message = l10n.settingsIssueMessage(issue);
    final path = l10n.settingsIssuePath(issue);
    final currentValue = issue.kind == SettingsIssueKind.exchangeOutOfRange
        ? issue.currentValue
        : null;

    return Semantics(
      button: true,
      excludeSemantics: true,
      label: '$message · $path',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, size: 18, color: scheme.error),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      path,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    if (currentValue != null)
                      Text(
                        l10n.readinessCurrentValue(currentValue),
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
