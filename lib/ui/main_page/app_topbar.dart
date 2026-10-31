import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ssb_runner/contest_run/new/contest_manager.dart';
import 'package:ssb_runner/l10n/domain_l10n.dart';
import 'package:ssb_runner/l10n/generated/app_localizations.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/ui/main_page/key_reference_dialog.dart';
import 'package:ssb_runner/ui/main_page/settings_cubits.dart';
import 'package:ssb_runner/ui/main_page/settings_sheet.dart';
import 'package:ssb_runner/ui/theme/app_theme.dart';

class AppTopbar extends StatelessWidget {
  const AppTopbar({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = context.read<AppSettings>();
    final contest = context.watch<ContestSettingCubit>().state;
    final options = context.watch<TrainingOptionsCubit>().state;
    final callsign = context.watch<StationCallsignCubit>().state;
    final isCompact = MediaQuery.sizeOf(context).height <= 700;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      height: isCompact ? 60 : 64,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            const _BrandMark(),
            const SizedBox(width: 12),
            Container(width: 1, height: 28, color: scheme.outlineVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contest.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '${l10n.trainingModeLabelById(options.mode.id)}'
                    ' · '
                    '${l10n.trainingDifficultyLabel(options.difficulty)}'
                    ' · '
                    '${callsign.isEmpty ? '—' : callsign}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppDataText.style(
                      context,
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: l10n.keyboardReference,
              onPressed: () => showKeyReferenceDialog(
                context,
                settings: settings,
                canCustomize: !context.read<ContestManager>().isContestRunning,
              ),
              icon: const Icon(Icons.keyboard_outlined),
            ),
            IconButton(
              tooltip: l10n.toggleTheme,
              onPressed: () {
                settings.themeMode = isDark ? ThemeMode.light : ThemeMode.dark;
              },
              icon: Icon(
                isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              ),
            ),
            const SizedBox(width: 4),
            IconButton.filledTonal(
              tooltip: l10n.settingsTitle,
              style: IconButton.styleFrom(
                backgroundColor: scheme.secondaryContainer,
                foregroundColor: scheme.onSecondaryContainer,
                minimumSize: const Size(40, 40),
                fixedSize: const Size(40, 40),
                shape: const CircleBorder(),
              ),
              onPressed: () => showSettingsSheet(context),
              icon: const Icon(Icons.settings_outlined, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.radio, size: 22, color: scheme.onPrimary),
        ),
        const SizedBox(width: 10),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SSB Runner',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 1),
            Text(
              l10n.appSubtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ],
    );
  }
}
