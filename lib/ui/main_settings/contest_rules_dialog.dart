import 'package:flutter/material.dart';
import 'package:ssb_runner/contest_type/contest_definition.dart';
import 'package:ssb_runner/l10n/domain_l10n.dart';
import 'package:ssb_runner/l10n/generated/app_localizations.dart';

/// Read-only help dialog that explains what each side sends for [contest].
///
/// The text is display-only: it does not derive from the exchange plan, so it
/// must be kept in sync manually when a contest's exchange changes.
class ContestRulesDialog extends StatelessWidget {
  const ContestRulesDialog({required this.contest, super.key});

  final ContestDefinition contest;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rules = l10n.contestRulesSummary(contest.id, contest.rulesSummary);

    return AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.all(24.0),
      title: Text(l10n.contestRulesTitle(contest.name)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8.0,
          children: [for (final line in rules.split('\n')) Text(line)],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.close),
        ),
      ],
    );
  }
}
