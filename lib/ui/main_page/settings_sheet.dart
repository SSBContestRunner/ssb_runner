import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ssb_runner/audio/accent_policy.dart';
import 'package:ssb_runner/audio/audio_check_service.dart';
import 'package:ssb_runner/audio/audio_loader.dart';
import 'package:ssb_runner/common/app_info.dart';
import 'package:ssb_runner/common/constants.dart';
import 'package:ssb_runner/common/upper_case_formatter.dart';
import 'package:ssb_runner/contest_run/new/contest_manager.dart';
import 'package:ssb_runner/contest_type/contest_definition.dart';
import 'package:ssb_runner/contest_type/station_exchange.dart';
import 'package:ssb_runner/db/history_backup.dart';
import 'package:ssb_runner/dxcc/dxcc_manager.dart';
import 'package:ssb_runner/l10n/domain_l10n.dart';
import 'package:ssb_runner/l10n/generated/app_localizations.dart';
import 'package:ssb_runner/logging/app_logger.dart';
import 'package:ssb_runner/platform/database/database_status_port.dart';
import 'package:ssb_runner/platform/export/export_port.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/settings/settings_issue.dart';
import 'package:ssb_runner/settings/settings_readiness.dart';
import 'package:ssb_runner/training/pending_replay.dart';
import 'package:ssb_runner/training/training_profile.dart';
import 'package:ssb_runner/ui/diagnostics_actions.dart';
import 'package:ssb_runner/ui/main_page/key_reference_dialog.dart';
import 'package:ssb_runner/ui/main_page/replay_armed_banner.dart';
import 'package:ssb_runner/ui/main_page/settings_cubits.dart';
import 'package:ssb_runner/ui/main_settings/contest_rules_dialog.dart';
import 'package:ssb_runner/ui/theme/app_theme.dart';
import 'package:toastification/toastification.dart';

Future<void> showSettingsSheet(
  BuildContext context, {
  SettingsTab initialTab = SettingsTab.contestStation,
  String? focusFieldKey,
}) {
  final settings = context.read<AppSettings>();
  final contestCubit = context.read<ContestSettingCubit>();
  final stationCubit = context.read<StationCallsignCubit>();
  final optionsCubit = context.read<TrainingOptionsCubit>();
  final runningCubit = context.read<MainSettingsCubit>();
  final dxccManager = context.read<DxccManager>();
  final contestManager = context.read<ContestManager>();
  final barrierLabel = MaterialLocalizations.of(context)
      .modalBarrierDismissLabel;

  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: barrierLabel,
    barrierColor: Theme.of(context).colorScheme.scrim,
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return MultiRepositoryProvider(
        providers: [
          RepositoryProvider<AppSettings>.value(value: settings),
          RepositoryProvider<DxccManager>.value(value: dxccManager),
          RepositoryProvider<ContestManager>.value(value: contestManager),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider<MainSettingsCubit>.value(value: runningCubit),
            BlocProvider<ContestSettingCubit>.value(value: contestCubit),
            BlocProvider<StationCallsignCubit>.value(value: stationCubit),
            BlocProvider<TrainingOptionsCubit>.value(value: optionsCubit),
          ],
          child: SettingsSheet(
            initialTab: initialTab,
            focusFieldKey: focusFieldKey,
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return Align(
        alignment: Alignment.centerRight,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.06, 0),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        ),
      );
    },
  );
}

class SettingsSheet extends StatefulWidget {
  const SettingsSheet({
    super.key,
    this.initialTab = SettingsTab.contestStation,
    this.focusFieldKey,
  });

  /// Tab the drawer opens on. Used by the "cannot start" checklist so the
  /// operator lands on the page that owns the problem.
  final SettingsTab initialTab;

  /// Field to scroll to and focus once the drawer is laid out.
  final String? focusFieldKey;

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  /// Stable anchors for the fields that can be the target of a deep link.
  final Map<String, GlobalKey> _fieldKeys = {};

  @override
  void initState() {
    super.initState();
    _tabController =
        TabController(
          length: SettingsTab.values.length,
          initialIndex: widget.initialTab.index,
          vsync: this,
        )..addListener(() {
          if (!_tabController.indexIsChanging) {
            setState(() {});
          }
        });

    WidgetsBinding.instance.addPostFrameCallback((_) => _revealFocusedField());
  }

  GlobalKey _keyFor(String focusKey) =>
      _fieldKeys.putIfAbsent(focusKey, () => GlobalKey());

  void _revealFocusedField() {
    if (!mounted) return;
    final focusKey = widget.focusFieldKey;
    if (focusKey == null) return;
    final target = _fieldKeys[focusKey]?.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      alignment: 0.12,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  SettingsIssue? _focusedIssue(List<SettingsIssue> issues) {
    final focusKey = widget.focusFieldKey;
    if (focusKey == null) return null;
    for (final issue in issues) {
      if (issue.focusKey == focusKey) return issue;
    }
    return null;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);
    final settings = context.read<AppSettings>();
    final dxccManager = context.read<DxccManager>();

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          Navigator.of(context).maybePop();
        },
      },
      child: FocusScope(
        autofocus: true,
        child: Semantics(
          scopesRoute: true,
          explicitChildNodes: true,
          label: l10n.settingsTitle,
          child: Align(
            alignment: Alignment.centerRight,
            child: Material(
              color: scheme.surfaceContainerLow,
              surfaceTintColor: Colors.transparent,
              elevation: 2,
              shadowColor: scheme.shadow,
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(28),
              ),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                width: min(480, size.width * 0.94),
                height: size.height,
                // Exchange values are written straight to storage, so the
                // revision notifier is the single signal that keeps both the
                // tab badges and the focused-field error in sync.
                child: ValueListenableBuilder<int>(
                  valueListenable: settings.settingsRevision,
                  builder: (context, _, _) {
                    final issues = checkSettingsReadiness(
                      settings: settings,
                      dxccManager: dxccManager,
                    );
                    final counts = settingsIssueCountsByTab(issues);
                    final focusedIssue = _focusedIssue(issues);

                    return Column(
                      children: [
                        _SheetHeader(
                          onClose: () => Navigator.of(context).pop(),
                        ),
                        TabBar(
                          controller: _tabController,
                          tabs: [
                            for (final tab in SettingsTab.values)
                              _SettingsTab(
                                label: l10n.settingsTabLabel(tab),
                                issueCount: counts[tab] ?? 0,
                              ),
                          ],
                        ),
                        Expanded(
                          child: _SettingsFocusRegistry(
                            keyFor: _keyFor,
                            child: IndexedStack(
                              index: _tabController.index,
                              children: [
                                _ContestStationPanel(
                                  focusedIssue: focusedIssue,
                                ),
                                _TrainingPanel(focusedIssue: focusedIssue),
                                const _AudioPanel(),
                                const _SystemPanel(),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A tab label that shows a dot when the page still has issues.
class _SettingsTab extends StatelessWidget {
  const _SettingsTab({required this.label, required this.issueCount});

  final String label;
  final int issueCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Tab(
      child: Semantics(
        excludeSemantics: true,
        label: issueCount == 0
            ? label
            : AppLocalizations.of(context).readinessTabBadge(label, issueCount),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(label, softWrap: false, overflow: TextOverflow.fade),
            ),
            if (issueCount > 0) ...[
              const SizedBox(width: 6),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Exposes the field anchors so a deep link can scroll to its target.
class _SettingsFocusRegistry extends InheritedWidget {
  const _SettingsFocusRegistry({required this.keyFor, required super.child});

  final GlobalKey Function(String focusKey) keyFor;

  @override
  bool updateShouldNotify(_SettingsFocusRegistry oldWidget) => false;
}

class _FieldAnchor extends StatelessWidget {
  const _FieldAnchor({required this.focusKey, required this.child});

  final String focusKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final registry = context
        .dependOnInheritedWidgetOfExactType<_SettingsFocusRegistry>();
    if (registry == null) return child;
    return KeyedSubtree(key: registry.keyFor(focusKey), child: child);
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SSB RUNNER',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    letterSpacing: 1.2,
                  ),
                ),
                Text(
                  l10n.settingsTitle,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: l10n.close,
            onPressed: onClose,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _ContestStationPanel extends StatelessWidget {
  const _ContestStationPanel({required this.focusedIssue});

  final SettingsIssue? focusedIssue;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = context.read<AppSettings>();
    final isRunning = context.watch<MainSettingsCubit>().state;
    final pendingReplay = settings.pendingReplay;
    final enabled = !isRunning;
    final contestLocked = isRunning || pendingReplay != null;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (pendingReplay != null) ...[
            ReplayArmedBanner(pending: pendingReplay, showLockHint: true),
            const SizedBox(height: 16),
          ],
          if (isRunning) ...[
            _PanelNote(
              icon: Icons.info_outline,
              text: l10n.settingsRunningLock,
            ),
            const SizedBox(height: 16),
          ],
          _SectionTitle(l10n.settingsContestSection),
          const SizedBox(height: 10),
          _ContestFields(enabled: !contestLocked),
          const SizedBox(height: 12),
          _ContestRulesRow(enabled: true),
          const SizedBox(height: 20),
          Divider(color: Theme.of(context).colorScheme.outlineVariant),
          const SizedBox(height: 20),
          _SectionTitle(l10n.myStation),
          const SizedBox(height: 10),
          _StationFields(enabled: enabled, focusedIssue: focusedIssue),
        ],
      ),
    );
  }
}

class _TrainingPanel extends StatelessWidget {
  const _TrainingPanel({required this.focusedIssue});

  final SettingsIssue? focusedIssue;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = context.read<AppSettings>();
    final cubit = context.watch<TrainingOptionsCubit>();
    final pendingReplay = settings.pendingReplay;
    final enabled = !context.watch<MainSettingsCubit>().state;
    final replayLocked = pendingReplay != null;
    final modeEnabled = enabled && !replayLocked;
    final scheme = Theme.of(context).colorScheme;
    final durationIssue =
        focusedIssue?.focusKey == SettingsFocusKeys.trainingDuration
        ? focusedIssue
        : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (pendingReplay != null) ...[
            ReplayArmedBanner(pending: pendingReplay, showLockHint: true),
            const SizedBox(height: 16),
          ],
          _SectionTitle(l10n.trainingModeFieldLabel),
          const SizedBox(height: 10),
          SegmentedButton<TrainingMode>(
            showSelectedIcon: false,
            segments: [
              for (final mode in TrainingMode.values)
                ButtonSegment(
                  value: mode,
                  label: Text(l10n.trainingModeLabel(mode)),
                ),
            ],
            selected: {cubit.state.mode},
            onSelectionChanged: modeEnabled
                ? (selection) => cubit.setMode(selection.first)
                : null,
            style: SegmentedButton.styleFrom(
              backgroundColor: scheme.surfaceContainer,
              foregroundColor: scheme.onSurfaceVariant,
              selectedBackgroundColor: scheme.primaryContainer,
              selectedForegroundColor: scheme.onPrimaryContainer,
              side: BorderSide(color: scheme.outlineVariant),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _FieldAnchor(
                  focusKey: SettingsFocusKeys.trainingDuration,
                  child: Semantics(
                    label: l10n.practiceDurationSemantics,
                    child: TextFormField(
                      enabled: enabled,
                      autofocus: durationIssue != null,
                      controller: cubit.durationController,
                      focusNode: cubit.durationFocusNode,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      keyboardType: TextInputType.number,
                      onChanged: (value) => cubit.setDuration(value, l10n),
                      decoration: InputDecoration(
                        labelText: l10n.durationLabel,
                        suffixText: l10n.durationUnit,
                        errorText: durationIssue == null
                            ? null
                            : l10n.settingsIssueMessage(durationIssue),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _menu<TrainingDifficulty>(
                  context: context,
                  enabled: modeEnabled,
                  label: l10n.difficultyFieldLabel,
                  value: cubit.state.difficulty,
                  entries: TrainingDifficulty.values
                      .map(
                        (it) => DropdownMenuEntry(
                          value: it,
                          label: l10n.trainingDifficultyLabel(it),
                        ),
                      )
                      .toList(),
                  onSelected: cubit.setDifficulty,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _ListRow(
            icon: Icons.casino_outlined,
            title: l10n.practiceSeed,
            subtitle: settings.practiceSeedSummary.isEmpty
                ? l10n.practiceSeed
                : l10n.practiceSeedWithSummary(settings.practiceSeedSummary),
            enabled: enabled,
            onTap: enabled
                ? () => showDialog<void>(
                    context: context,
                    builder: (_) => _PracticeSeedDialog(settings: settings),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

class _AudioPanel extends StatelessWidget {
  const _AudioPanel();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.watch<TrainingOptionsCubit>();
    final enabled = !context.watch<MainSettingsCubit>().state;
    final percent = (cubit.state.volume * 100).round();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionTitle(l10n.volumeLabel(percent)),
          const SizedBox(height: 6),
          Semantics(
            label: l10n.volumeSemantics,
            value: l10n.volumeValue(percent),
            child: Row(
              children: [
                Icon(
                  Icons.volume_up_outlined,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Slider(
                    value: cubit.state.volume,
                    min: 0.2,
                    max: 1.2,
                    divisions: 10,
                    label: l10n.volumeLabel(percent),
                    onChanged: enabled ? cubit.setVolume : null,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _AudioTestToneRow(enabled: enabled),
          const SizedBox(height: 4),
          _LowVolumeWarningSwitch(enabled: enabled),
          const SizedBox(height: 16),
          _menu<IncomingAccent>(
            context: context,
            enabled: enabled,
            label: l10n.incomingAccentFieldLabel,
            value: cubit.state.incomingAccent,
            entries: IncomingAccent.values
                .map(
                  (it) => DropdownMenuEntry(
                    value: it,
                    label: l10n.incomingAccentLabel(it),
                  ),
                )
                .toList(),
            onSelected: cubit.setIncomingAccent,
          ),
          const SizedBox(height: 4),
          Text(
            l10n.incomingAccentAutoHint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          _menu<PhonicType>(
            context: context,
            enabled: enabled,
            label: l10n.phonicTypeFieldLabel,
            value: cubit.state.phonicType,
            entries: [
              DropdownMenuEntry(
                value: PhonicType.standard,
                label: l10n.phonicStandard,
              ),
              DropdownMenuEntry(
                value: PhonicType.location,
                label: l10n.phonicLocation,
              ),
              DropdownMenuEntry(
                value: PhonicType.mixed,
                label: l10n.phonicMixed,
              ),
            ],
            onSelected: cubit.setPhonic,
          ),
        ],
      ),
    );
  }
}

class _AudioTestToneRow extends StatefulWidget {
  const _AudioTestToneRow({required this.enabled});

  final bool enabled;

  @override
  State<_AudioTestToneRow> createState() => _AudioTestToneRowState();
}

/// Manual check that the output is actually audible.
///
/// It covers the blind spots the OS cannot report (HDMI routing, a powered-off
/// Bluetooth speaker, a speaker knob at zero) but leaves the judgement to the
/// operator: no dialog, no effect on a running session (design §5 E2).
class _AudioTestToneRowState extends State<_AudioTestToneRow> {
  final AudioCheckService _service = AudioCheckService();
  bool _playing = false;

  Future<void> _play() async {
    setState(() => _playing = true);
    final played = await _service.play();
    if (!mounted) return;
    setState(() => _playing = false);
    if (played) return;

    final l10n = AppLocalizations.of(context);
    toastification.show(
      title: Text(l10n.audioTestToneFailed),
      autoCloseDuration: const Duration(seconds: 4),
      type: ToastificationType.error,
      style: ToastificationStyle.fillColored,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return _ListRow(
      icon: Icons.hearing_outlined,
      title: l10n.audioTestToneTitle,
      subtitle: _playing
          ? l10n.audioTestTonePlaying
          : l10n.audioTestToneSubtitle,
      enabled: widget.enabled && !_playing,
      onTap: _play,
    );
  }
}

class _LowVolumeWarningSwitch extends StatefulWidget {
  const _LowVolumeWarningSwitch({required this.enabled});

  final bool enabled;

  @override
  State<_LowVolumeWarningSwitch> createState() =>
      _LowVolumeWarningSwitchState();
}

class _LowVolumeWarningSwitchState extends State<_LowVolumeWarningSwitch> {
  late bool _value = context.read<AppSettings>().audioPreflightLowVolumeWarning;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = context.read<AppSettings>();

    return Opacity(
      opacity: widget.enabled ? 1 : 0.38,
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _value,
        title: Text(
          l10n.audioPreflightLowVolumeWarningLabel,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        subtitle: Text(l10n.audioPreflightLowVolumeWarningHint),
        onChanged: widget.enabled
            ? (value) {
                settings.audioPreflightLowVolumeWarning = value;
                setState(() => _value = value);
              }
            : null,
      ),
    );
  }
}

class _SystemPanel extends StatefulWidget {
  const _SystemPanel();

  @override
  State<_SystemPanel> createState() => _SystemPanelState();
}

class _SystemPanelState extends State<_SystemPanel> {
  late bool _verbose;
  DatabaseStorageStatus? _storageStatus;

  @override
  void initState() {
    super.initState();
    _verbose = context.read<AppSettings>().verboseLogging;
    unawaited(_loadStorageStatus());
  }

  Future<void> _loadStorageStatus() async {
    final status = await readDatabaseStorageStatus();
    if (!mounted) {
      return;
    }
    setState(() => _storageStatus = status);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = context.read<AppSettings>();
    final isRunning = context.watch<MainSettingsCubit>().state;
    final scheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ValueListenableBuilder<AppLanguage>(
            valueListenable: settings.languageNotifier,
            builder: (context, language, _) => Semantics(
              label: l10n.language,
              child: DropdownMenu<AppLanguage>(
                expandedInsets: EdgeInsets.zero,
                initialSelection: language,
                label: Text(l10n.language),
                dropdownMenuEntries: [
                  DropdownMenuEntry(
                    value: AppLanguage.auto,
                    label: l10n.languageAuto,
                  ),
                  DropdownMenuEntry(
                    value: AppLanguage.english,
                    label: l10n.languageEnglish,
                  ),
                  DropdownMenuEntry(
                    value: AppLanguage.simplifiedChinese,
                    label: l10n.languageSimplifiedChinese,
                  ),
                  DropdownMenuEntry(
                    value: AppLanguage.traditionalChinese,
                    label: l10n.languageTraditionalChinese,
                  ),
                  DropdownMenuEntry(
                    value: AppLanguage.japanese,
                    label: l10n.languageJapanese,
                  ),
                ],
                onSelected: (value) {
                  if (value != null) settings.language = value;
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          _ListRow(
            icon: Icons.keyboard_outlined,
            title: l10n.functionKeysTitle,
            subtitle: l10n.settingsFunctionKeysRowSubtitle,
            enabled: !isRunning,
            onTap: isRunning
                ? null
                : () => showKeyReferenceDialog(
                    context,
                    settings: settings,
                    canCustomize: true,
                  ),
          ),
          _ListRow(
            icon: Icons.history,
            title: l10n.pastSessionsTitle,
            subtitle: isRunning
                ? l10n.pastSessionsUnavailableWhileRunning
                : l10n.settingsHistoryRowSubtitle,
            enabled: !isRunning,
            onTap: isRunning
                ? null
                : () => showDialog<void>(
                    context: context,
                    builder: (_) => _SessionHistoryDialog(settings: settings),
                  ),
          ),
          const SizedBox(height: 12),
          Divider(color: scheme.outlineVariant),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _verbose,
            title: Text(
              l10n.verboseLogging,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            subtitle: Text(l10n.verboseLoggingSubtitle),
            onChanged: (value) {
              settings.verboseLogging = value;
              setState(() => _verbose = value);
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _copySummary,
                  icon: const Icon(Icons.copy, size: 18),
                  label: Text(l10n.copyDiagnostics),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _exportLogs,
                  icon: const Icon(Icons.archive_outlined, size: 18),
                  label: Text(l10n.exportLogs),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: scheme.outlineVariant),
          const SizedBox(height: 8),
          if (_storageStatus?.applicable ?? false)
            _ListRow(
              icon: Icons.storage_outlined,
              title: l10n.storageStatusTitle,
              subtitle: _storageStatusText(l10n),
              onTap: _backupHistory,
            ),
          if (_storageStatus?.applicable ?? false) const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _backupHistory,
                  icon: const Icon(Icons.backup_outlined, size: 18),
                  label: Text(l10n.backupHistory),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isRunning ? null : _restoreHistory,
                  icon: const Icon(Icons.settings_backup_restore, size: 18),
                  label: Text(l10n.restoreHistory),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _PanelNote(
            icon: Icons.check_circle_outline,
            text: l10n.settingsAutoSaveNote,
          ),
        ],
      ),
    );
  }

  Future<void> _copySummary() => copyDiagnosticSummary(context);

  Future<void> _exportLogs() => exportDiagnosticArchive(context);

  /// Exports the QSO/event rows plus the session list as one zip.
  Future<void> _backupHistory() async {
    final l10n = AppLocalizations.of(context);
    final database = context.read<ContestManager>().database;
    final settings = context.read<AppSettings>();

    try {
      final backup = await createHistoryBackup(
        database,
        sessionReviews: settings.sessionHistory,
        appVersion: AppInfo.version ?? '',
        buildNumber: AppInfo.buildNumber ?? '',
      );
      final result = await saveBytes(
        suggestedName: backup.fileName,
        bytes: backup.bytes,
        fileTypeLabel: l10n.zipArchive,
      );
      if (result == null || !mounted) {
        return;
      }

      toastification.show(
        title: Text(l10n.historyBackupCreated(backup.qsoCount)),
        autoCloseDuration: const Duration(seconds: 4),
        type: ToastificationType.success,
        style: ToastificationStyle.fillColored,
      );
      unawaited(_loadStorageStatus());
    } catch (error, stackTrace) {
      log.error(
        'history backup failed',
        tag: 'history',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) {
        return;
      }
      toastification.show(
        title: Text(l10n.historyBackupFailed),
        autoCloseDuration: const Duration(seconds: 4),
        type: ToastificationType.warning,
        style: ToastificationStyle.fillColored,
      );
    }
  }

  /// Validates the picked file, asks for confirmation, then replaces history.
  Future<void> _restoreHistory() async {
    final l10n = AppLocalizations.of(context);
    final database = context.read<ContestManager>().database;
    final settings = context.read<AppSettings>();

    try {
      final picked = await pickFile(
        fileTypeLabel: l10n.historyBackupFileType,
        extensions: const <String>['zip', 'json'],
      );
      if (picked == null || !mounted) {
        return;
      }

      // Parsing throws before anything is written, so an invalid file cannot
      // leave a half-restored history behind.
      final backup = parseHistoryBackup(picked.bytes);
      if (!mounted) {
        return;
      }

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(l10n.historyRestoreTitle),
          content: Text(
            l10n.historyRestoreBody(
              _formatBackupTime(dialogContext, backup.exportedAt),
              _backupVersionLabel(backup),
              backup.qsoCount,
              backup.eventCount,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.historyRestoreConfirm),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) {
        return;
      }

      await restoreHistoryBackup(
        database,
        backup,
        replaceSessionHistory: settings.replaceSessionHistory,
      );
      if (!mounted) {
        return;
      }

      toastification.show(
        title: Text(l10n.historyRestored(backup.qsoCount)),
        autoCloseDuration: const Duration(seconds: 4),
        type: ToastificationType.success,
        style: ToastificationStyle.fillColored,
      );
      unawaited(_loadStorageStatus());
    } on HistoryBackupException catch (error) {
      log.warn(
        'history backup rejected',
        tag: 'history',
        fields: <String, Object?>{
          'reason': error.message,
          'newer_version': error.createdByNewerVersion,
        },
      );
      if (!mounted) {
        return;
      }
      toastification.show(
        title: Text(
          error.createdByNewerVersion
              ? l10n.historyBackupNewer
              : l10n.historyBackupInvalid,
        ),
        autoCloseDuration: const Duration(seconds: 6),
        type: ToastificationType.warning,
        style: ToastificationStyle.fillColored,
      );
    } catch (error, stackTrace) {
      log.error(
        'history restore failed',
        tag: 'history',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) {
        return;
      }
      toastification.show(
        title: Text(l10n.historyRestoreFailed),
        autoCloseDuration: const Duration(seconds: 4),
        type: ToastificationType.warning,
        style: ToastificationStyle.fillColored,
      );
    }
  }

  String _formatBackupTime(BuildContext context, DateTime utc) {
    final local = utc.toLocal();
    final localizations = MaterialLocalizations.of(context);
    return '${localizations.formatCompactDate(local)} '
        '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
  }

  String _backupVersionLabel(HistoryBackup backup) {
    if (backup.appVersion.isEmpty) {
      return '—';
    }
    if (backup.buildNumber.isEmpty) {
      return 'v${backup.appVersion}';
    }
    return 'v${backup.appVersion}·${backup.buildNumber}';
  }

  String _storageStatusText(AppLocalizations l10n) {
    final status = _storageStatus;
    if (status == null) {
      return l10n.storageUnknown;
    }

    final base = status.persistent
        ? l10n.storagePersistent
        : l10n.storageNotPersistent;
    final quota = status.quota;
    final usage = status.usage;
    if (quota == null || usage == null || quota <= 0) {
      return base;
    }

    return '$base · ${l10n.storageUsage(_formatBytes(usage), _formatBytes(quota))}';
  }

  static String _formatBytes(int bytes) {
    const units = <String>['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }

    final decimals = unit == 0 || value >= 100 ? 0 : 1;
    return '${value.toStringAsFixed(decimals)} ${units[unit]}';
  }
}

class _ContestFields extends StatefulWidget {
  const _ContestFields({required this.enabled});

  final bool enabled;

  @override
  State<_ContestFields> createState() => _ContestFieldsState();
}

class _ContestFieldsState extends State<_ContestFields> {
  final _contestNameController = TextEditingController();
  final _contestExchangeController = TextEditingController();

  ContestDefinition? _syncedContest;
  AppLocalizations? _syncedL10n;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncControllers(
      context.read<ContestSettingCubit>().state,
      AppLocalizations.of(context),
    );
  }

  void _syncControllers(ContestDefinition contest, AppLocalizations l10n) {
    if (identical(contest, _syncedContest) && identical(l10n, _syncedL10n)) {
      return;
    }
    _syncedContest = contest;
    _syncedL10n = l10n;
    _contestNameController.text = contest.name;
    _contestExchangeController.text = l10n.contestExchangeLabel(
      contest.id,
      contest.exchangeLabel,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BlocListener<ContestSettingCubit, ContestDefinition>(
      listener: (context, contest) {
        _syncControllers(contest, AppLocalizations.of(context));
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          DropdownMenu<String>(
            enabled: widget.enabled,
            controller: _contestNameController,
            expandedInsets: EdgeInsets.zero,
            onSelected: (id) {
              if (id != null) {
                context.read<ContestSettingCubit>().changeContest(id);
              }
            },
            dropdownMenuEntries: ContestRegistry.all
                .map(
                  (contest) =>
                      DropdownMenuEntry(value: contest.id, label: contest.name),
                )
                .toList(),
            label: Text(l10n.contestNameLabel),
          ),
          TextField(
            enabled: widget.enabled,
            readOnly: true,
            maxLines: null,
            controller: _contestExchangeController,
            decoration: InputDecoration(
              labelText: l10n.contestExchangeFieldLabel,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _contestExchangeController.dispose();
    _contestNameController.dispose();
    super.dispose();
  }
}

class _ContestRulesRow extends StatelessWidget {
  const _ContestRulesRow({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final contest = context.watch<ContestSettingCubit>().state;
    final firstLine = l10n
        .contestRulesSummary(contest.id, contest.rulesSummary)
        .split('\n')
        .first;

    return _ListRow(
      icon: Icons.flag_outlined,
      title: l10n.contestRulesTooltip,
      subtitle: firstLine,
      enabled: enabled,
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => ContestRulesDialog(contest: contest),
      ),
    );
  }
}

class _StationFields extends StatelessWidget {
  const _StationFields({required this.enabled, required this.focusedIssue});

  final bool enabled;
  final SettingsIssue? focusedIssue;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final definition = context.watch<ContestSettingCubit>().state;
    final callsign = context.watch<StationCallsignCubit>().state;
    final dxccManager = context.read<DxccManager>();

    // The plan depends on the station callsign, so this rebuilds when the
    // callsign changes (ARRL/JIDX switch on DXCC).
    final plan = definition.myExchangePlan(
      stationCallsign: callsign,
      dxccManager: dxccManager,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        _FieldAnchor(
          focusKey: SettingsFocusKeys.stationCallsign,
          child: _CallsignField(
            enabled: enabled,
            focusedIssue:
                focusedIssue?.focusKey == SettingsFocusKeys.stationCallsign
                ? focusedIssue
                : null,
          ),
        ),
        // CQ WPX derives the serial from completed QSOs, so it has no field to
        // configure; an input-shaped read-only box was mistaken for one.
        if (plan.sendsSerial)
          _PanelNote(
            icon: Icons.info_outline,
            text: l10n.stationSerialAutoHint,
          ),
        for (final field in plan.fields)
          _FieldAnchor(
            focusKey: SettingsFocusKeys.exchangeField(field.id),
            child: _StationExchangeFieldInput(
              key: ValueKey('${definition.id}-${field.id}-$callsign'),
              definitionId: definition.id,
              field: field,
              enabled: enabled,
              focusedIssue:
                  focusedIssue?.focusKey ==
                      SettingsFocusKeys.exchangeField(field.id)
                  ? focusedIssue
                  : null,
            ),
          ),
        // Connects the configured value (`5`) to what is actually read out
        // (`05`), so the console preview does not look like a bug.
        Padding(
          // 12px column spacing + 4px keeps the MD3 16px rhythm.
          padding: const EdgeInsets.only(top: 4),
          child: _StationSentPreview(
            definitionId: definition.id,
            plan: plan,
            callsign: callsign,
            dxccManager: dxccManager,
          ),
        ),
      ],
    );
  }
}

/// Read-only "Sending: 59 05" preview under the station fields (D4).
class _StationSentPreview extends StatelessWidget {
  const _StationSentPreview({
    required this.definitionId,
    required this.plan,
    required this.callsign,
    required this.dxccManager,
  });

  final String definitionId;
  final MyExchangePlan plan;
  final String callsign;
  final DxccManager dxccManager;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = context.read<AppSettings>();

    return ValueListenableBuilder<int>(
      // Station values are written straight to storage; this keeps the preview
      // in step while the operator types.
      valueListenable: settings.settingsRevision,
      builder: (context, _, _) {
        final scheme = Theme.of(context).colorScheme;
        final exchange = buildMyExchangeText(
          plan: plan,
          config: settings.stationExchangeConfig(definitionId),
          stationCallsign: callsign,
          dxccManager: dxccManager,
          qsoNumber: 1,
        );
        final fieldLabel = plan.fields.isEmpty
            ? ''
            : l10n.stationFieldLabel(
                plan.fields.first.id,
                plan.fields.first.label,
              );

        final hasExchange = exchange.isNotEmpty;
        final value = hasExchange
            ? '59 $exchange'
            : l10n.stationSentPreviewNotSet;
        final sub = !hasExchange
            ? l10n.stationSentPreviewNotSetHint(fieldLabel)
            : plan.sendsSerial
            ? l10n.stationSentPreviewSerialHint
            : l10n.stationSentPreviewHint(exchange, fieldLabel);

        return Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            // The prototype's primary-tinted "what goes out" card.
            color: Color.alphaBlend(
              scheme.primaryContainer.withValues(alpha: 0.42),
              scheme.surface,
            ),
            border: Border.all(
              color: Color.alphaBlend(
                scheme.primary.withValues(alpha: 0.26),
                scheme.outlineVariant,
              ),
            ),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.stationSentPreviewTitle,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  letterSpacing: 0.7,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    value,
                    style: AppDataText.style(
                      context,
                      fontSize: 24,
                      letterSpacing: 1.4,
                      color: hasExchange
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                  if (hasExchange) ...[
                    const SizedBox(width: 9),
                    Text(
                      l10n.stationSentPreviewRstHint,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 5),
              Text(
                sub,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CallsignField extends StatefulWidget {
  const _CallsignField({required this.enabled, this.focusedIssue});

  final bool enabled;
  final SettingsIssue? focusedIssue;

  @override
  State<_CallsignField> createState() => _CallsignFieldState();
}

class _CallsignFieldState extends State<_CallsignField> {
  final _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final issue = widget.focusedIssue;
    final callsign = context.watch<StationCallsignCubit>().state;
    if (_controller.text != callsign) {
      _controller.text = callsign;
    }

    return TextField(
      key: const Key('station-callsign'),
      enabled: widget.enabled,
      autofocus: issue != null && widget.enabled,
      controller: _controller,
      inputFormatters: [
        UpperCaseTextFormatter(),
        LengthLimitingTextInputFormatter(maxCallsignLength),
        FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9/]')),
      ],
      decoration: InputDecoration(
        labelText: l10n.stationCallsignLabel,
        errorText: issue == null ? null : l10n.settingsIssueMessage(issue),
      ),
      onChanged: (value) {
        context.read<StationCallsignCubit>().onCallSignChange(value);
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

/// One station-configured exchange field. Shows the explicit value when set,
/// otherwise the value derived from the callsign; editing stores it explicitly.
class _StationExchangeFieldInput extends StatefulWidget {
  const _StationExchangeFieldInput({
    super.key,
    required this.definitionId,
    required this.field,
    required this.enabled,
    this.focusedIssue,
  });

  final String definitionId;
  final StationExchangeField field;
  final bool enabled;
  final SettingsIssue? focusedIssue;

  @override
  State<_StationExchangeFieldInput> createState() =>
      _StationExchangeFieldInputState();
}

class _StationExchangeFieldInputState
    extends State<_StationExchangeFieldInput> {
  late final TextEditingController _controller;
  late final AppSettings _appSettings;

  @override
  void initState() {
    super.initState();
    _appSettings = context.read<AppSettings>();
    final dxccManager = context.read<DxccManager>();
    final callsign = context.read<StationCallsignCubit>().state;
    final config = _appSettings.stationExchangeConfig(widget.definitionId);
    final resolved =
        resolveExchangeValue(widget.field, config, callsign, dxccManager) ?? '';
    _controller = TextEditingController(text: resolved);
  }

  @override
  Widget build(BuildContext context) {
    final field = widget.field;
    final l10n = AppLocalizations.of(context);
    final isDerived =
        _appSettings
            .stationExchangeConfig(widget.definitionId)[field.id]
            ?.trim()
            .isEmpty ??
        true;

    final issue = widget.focusedIssue;

    return TextField(
      enabled: widget.enabled,
      autofocus: issue != null && widget.enabled,
      controller: _controller,
      keyboardType: field.numeric ? TextInputType.number : TextInputType.text,
      inputFormatters: [
        UpperCaseTextFormatter(),
        LengthLimitingTextInputFormatter(8),
        if (field.numeric)
          FilteringTextInputFormatter.digitsOnly
        else
          FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
      ],
      decoration: InputDecoration(
        labelText: l10n.stationFieldLabel(field.id, field.label),
        helperText:
            l10n.stationFieldHelper(field.id) ??
            field.helperText ??
            (isDerived ? l10n.defaultFromCallsign : null),
        errorText: issue == null ? null : l10n.settingsIssueMessage(issue),
      ),
      onChanged: (value) {
        _appSettings.setStationExchangeValue(
          widget.definitionId,
          field.id,
          value,
        );
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.titleSmall);
  }
}

class _PanelNote extends StatelessWidget {
  const _PanelNote({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class _ListRow extends StatelessWidget {
  const _ListRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Opacity(
      opacity: enabled ? 1 : 0.38,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 20, color: scheme.onPrimaryContainer),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 1),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget _menu<T>({
  required BuildContext context,
  required bool enabled,
  required String label,
  required T value,
  required List<DropdownMenuEntry<T>> entries,
  required void Function(T?) onSelected,
}) {
  return Semantics(
    label: label,
    child: DropdownMenu<T>(
      enabled: enabled,
      expandedInsets: EdgeInsets.zero,
      initialSelection: value,
      label: Text(label),
      dropdownMenuEntries: entries,
      onSelected: onSelected,
    ),
  );
}

class _PracticeSeedDialog extends StatefulWidget {
  const _PracticeSeedDialog({required this.settings});

  final AppSettings settings;

  @override
  State<_PracticeSeedDialog> createState() => _PracticeSeedDialogState();
}

class _PracticeSeedDialogState extends State<_PracticeSeedDialog> {
  late final TextEditingController questionController;
  late final TextEditingController audioController;
  late bool lockQuestion;
  late bool lockAudio;

  @override
  void initState() {
    super.initState();
    questionController = TextEditingController(
      text: widget.settings.questionSeed?.toString() ?? '',
    );
    audioController = TextEditingController(
      text: widget.settings.audioSeed?.toString() ?? '',
    );
    lockQuestion = widget.settings.lockQuestionSeed;
    lockAudio = widget.settings.lockAudioSeed;
  }

  @override
  void dispose() {
    questionController.dispose();
    audioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.practiceSeed),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                label: l10n.questionSeedLabel,
                child: TextField(
                  controller: questionController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: l10n.questionSeedLabel,
                    helperText: l10n.questionSeedHelper,
                  ),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.lockQuestionSeed),
                subtitle: Text(l10n.lockQuestionSeedSubtitle),
                value: lockQuestion,
                onChanged: (value) => setState(() => lockQuestion = value),
              ),
              const SizedBox(height: 12),
              Semantics(
                label: l10n.audioSeedLabel,
                child: TextField(
                  controller: audioController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: l10n.audioSeedLabel,
                    helperText: l10n.audioSeedHelper,
                  ),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.lockAudioSeed),
                subtitle: Text(l10n.lockAudioSeedSubtitle),
                value: lockAudio,
                onChanged: (value) => setState(() => lockAudio = value),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            final value = questionController.text.trim();
            if (value.isEmpty) {
              return;
            }
            await Clipboard.setData(ClipboardData(text: value));
          },
          child: Text(l10n.copyQuestionSeed),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () {
            final question = int.tryParse(questionController.text.trim());
            final audio = int.tryParse(audioController.text.trim());
            widget.settings
              ..lockQuestionSeed = lockQuestion
              ..lockAudioSeed = lockAudio
              ..questionSeed = question
              ..audioSeed = audio
              ..pendingQuestionSeed = question
              ..pendingAudioSeed = audio;
            Navigator.pop(context);
          },
          child: Text(l10n.save),
        ),
      ],
    );
  }
}

class _SessionHistoryDialog extends StatelessWidget {
  const _SessionHistoryDialog({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sessions = settings.sessionHistory;
    final running = settings.contestRunningCheck?.call() ?? false;
    return AlertDialog(
      title: Text(l10n.pastSessionsTitle),
      content: SizedBox(
        width: 440,
        child: sessions.isEmpty
            ? Text(l10n.noCompletedSessions)
            // Keep the tiles' hover/ink feedback inside the scroll viewport;
            // otherwise it is painted on the dialog's Material and leaks under
            // the actions row when the last tile is partially scrolled out.
            : Material(
                type: MaterialType.transparency,
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: sessions.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (_, index) {
                    final review = sessions[index];
                    final accuracy = (review.accuracy * 100).toStringAsFixed(1);
                    return Semantics(
                      label: l10n.sessionHistorySemantics(
                        review.metadata.contestName,
                        accuracy,
                      ),
                      child: ListTile(
                        enabled: !running,
                        onTap: () {
                          final messenger = ScaffoldMessenger.of(context);
                          // Arming replaces the snapshot only; ordinary
                          // settings stay exactly as they were until a run
                          // really starts.
                          settings.armReplay(PendingReplay.fromReview(review));
                          Navigator.pop(context);
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                l10n.replaySeedSnack(
                                  review.metadata.questionSeed,
                                ),
                              ),
                            ),
                          );
                        },
                        title: Text(
                          '${review.metadata.contestName} · '
                          '${l10n.trainingModeLabelById(review.metadata.modeId)}',
                        ),
                        subtitle: Text(
                          l10n.sessionHistorySubtitle(
                            review.qsoCount,
                            accuracy,
                            review.qsosPerHour.toStringAsFixed(1),
                            review.metadata.questionSeed,
                          ),
                        ),
                        trailing: Text(l10n.sessionHistoryScore(review.score)),
                      ),
                    );
                  },
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.close),
        ),
      ],
    );
  }
}
