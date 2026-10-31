import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ssb_runner/audio/accent_policy.dart';
import 'package:ssb_runner/audio/audio_loader.dart';
import 'package:ssb_runner/common/constants.dart';
import 'package:ssb_runner/common/upper_case_formatter.dart';
import 'package:ssb_runner/contest_run/new/contest_manager.dart';
import 'package:ssb_runner/contest_type/contest_definition.dart';
import 'package:ssb_runner/contest_type/station_exchange.dart';
import 'package:ssb_runner/dxcc/dxcc_manager.dart';
import 'package:ssb_runner/l10n/domain_l10n.dart';
import 'package:ssb_runner/l10n/generated/app_localizations.dart';
import 'package:ssb_runner/logging/log_export.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/training/training_profile.dart';
import 'package:ssb_runner/ui/main_page/key_reference_dialog.dart';
import 'package:ssb_runner/ui/main_page/settings_cubits.dart';
import 'package:ssb_runner/ui/main_settings/contest_rules_dialog.dart';
import 'package:toastification/toastification.dart';

Future<void> showSettingsSheet(BuildContext context) {
  final settings = context.read<AppSettings>();
  final contestCubit = context.read<ContestSettingCubit>();
  final stationCubit = context.read<StationCallsignCubit>();
  final optionsCubit = context.read<TrainingOptionsCubit>();
  final runningCubit = context.read<MainSettingsCubit>();
  final dxccManager = context.read<DxccManager>();
  final contestManager = context.read<ContestManager>();
  final barrierLabel = MaterialLocalizations.of(
    context,
  ).modalBarrierDismissLabel;

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
          child: const SettingsSheet(),
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
  const SettingsSheet({super.key});

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this)
      ..addListener(() {
        if (!_tabController.indexIsChanging) {
          setState(() {});
        }
      });
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
                child: Column(
                  children: [
                    _SheetHeader(onClose: () => Navigator.of(context).pop()),
                    TabBar(
                      controller: _tabController,
                      tabs: [
                        Tab(text: l10n.settingsTabContestStation),
                        Tab(text: l10n.settingsTabTraining),
                        Tab(text: l10n.settingsTabAudio),
                        Tab(text: l10n.settingsTabSystem),
                      ],
                    ),
                    Expanded(
                      child: IndexedStack(
                        index: _tabController.index,
                        children: const [
                          _ContestStationPanel(),
                          _TrainingPanel(),
                          _AudioPanel(),
                          _SystemPanel(),
                        ],
                      ),
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
  const _ContestStationPanel();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isRunning = context.watch<MainSettingsCubit>().state;
    final enabled = !isRunning;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isRunning) ...[
            _PanelNote(
              icon: Icons.info_outline,
              text: l10n.settingsRunningLock,
            ),
            const SizedBox(height: 16),
          ],
          _SectionTitle(l10n.settingsContestSection),
          const SizedBox(height: 10),
          _ContestFields(enabled: enabled),
          const SizedBox(height: 12),
          _ContestRulesRow(enabled: true),
          const SizedBox(height: 20),
          Divider(color: Theme.of(context).colorScheme.outlineVariant),
          const SizedBox(height: 20),
          _SectionTitle(l10n.myStation),
          const SizedBox(height: 10),
          _StationFields(enabled: enabled),
        ],
      ),
    );
  }
}

class _TrainingPanel extends StatelessWidget {
  const _TrainingPanel();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = context.read<AppSettings>();
    final cubit = context.watch<TrainingOptionsCubit>();
    final enabled = !context.watch<MainSettingsCubit>().state;
    final scheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
            onSelectionChanged: enabled
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
                child: Semantics(
                  label: l10n.practiceDurationSemantics,
                  child: TextFormField(
                    enabled: enabled,
                    controller: cubit.durationController,
                    focusNode: cubit.durationFocusNode,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    keyboardType: TextInputType.number,
                    onChanged: (value) => cubit.setDuration(value, l10n),
                    decoration: InputDecoration(
                      labelText: l10n.durationLabel,
                      suffixText: l10n.durationUnit,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _menu<TrainingDifficulty>(
                  context: context,
                  enabled: enabled,
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

class _SystemPanel extends StatefulWidget {
  const _SystemPanel();

  @override
  State<_SystemPanel> createState() => _SystemPanelState();
}

class _SystemPanelState extends State<_SystemPanel> {
  late bool _verbose;

  @override
  void initState() {
    super.initState();
    _verbose = context.read<AppSettings>().verboseLogging;
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
            subtitle: l10n.settingsHistoryRowSubtitle,
            onTap: () => showDialog<void>(
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
          const SizedBox(height: 16),
          _PanelNote(
            icon: Icons.check_circle_outline,
            text: l10n.settingsAutoSaveNote,
          ),
        ],
      ),
    );
  }

  Future<void> _copySummary() async {
    final l10n = AppLocalizations.of(context);
    final summary = await diagnosticSummary();
    await Clipboard.setData(ClipboardData(text: summary));
    if (!mounted) {
      return;
    }

    toastification.show(
      title: Text(l10n.diagnosticsCopied),
      autoCloseDuration: const Duration(seconds: 2),
      type: ToastificationType.success,
      style: ToastificationStyle.fillColored,
    );
  }

  Future<void> _exportLogs() async {
    final l10n = AppLocalizations.of(context);
    try {
      final file = await exportLogArchive(fileTypeLabel: l10n.zipArchive);
      if (!mounted || file == null) {
        return;
      }

      await Clipboard.setData(ClipboardData(text: file.path));
      toastification.show(
        title: Text(l10n.exportedTo(file.path)),
        autoCloseDuration: const Duration(seconds: 4),
        type: ToastificationType.success,
        style: ToastificationStyle.fillColored,
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      toastification.show(
        title: Text(l10n.logExportFailed),
        autoCloseDuration: const Duration(seconds: 4),
        type: ToastificationType.error,
        style: ToastificationStyle.fillColored,
      );
    }
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
  const _StationFields({required this.enabled});

  final bool enabled;

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
        _CallsignField(enabled: enabled),
        if (plan.fields.isEmpty)
          _ReadonlyExchangeField(
            enabled: enabled,
            contestId: definition.id,
            label: l10n.contestExchangeFieldLabel,
            value: l10n.contestExchangeLabel(
              definition.id,
              definition.exchangeLabel,
            ),
            helper: l10n.stationExchangeReadonlyHint,
          ),
        for (final field in plan.fields)
          _StationExchangeFieldInput(
            key: ValueKey('${definition.id}-${field.id}-$callsign'),
            definitionId: definition.id,
            field: field,
            enabled: enabled,
          ),
      ],
    );
  }
}

class _ReadonlyExchangeField extends StatefulWidget {
  const _ReadonlyExchangeField({
    required this.enabled,
    required this.contestId,
    required this.label,
    required this.value,
    required this.helper,
  });

  final bool enabled;
  final String contestId;
  final String label;
  final String value;
  final String helper;

  @override
  State<_ReadonlyExchangeField> createState() => _ReadonlyExchangeFieldState();
}

class _ReadonlyExchangeFieldState extends State<_ReadonlyExchangeField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

  @override
  void didUpdateWidget(covariant _ReadonlyExchangeField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      enabled: widget.enabled,
      readOnly: true,
      controller: _controller,
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.helper,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class _CallsignField extends StatefulWidget {
  const _CallsignField({required this.enabled});

  final bool enabled;

  @override
  State<_CallsignField> createState() => _CallsignFieldState();
}

class _CallsignFieldState extends State<_CallsignField> {
  final _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final callsign = context.watch<StationCallsignCubit>().state;
    if (_controller.text != callsign) {
      _controller.text = callsign;
    }

    return TextField(
      key: const Key('station-callsign'),
      enabled: widget.enabled,
      controller: _controller,
      inputFormatters: [
        UpperCaseTextFormatter(),
        LengthLimitingTextInputFormatter(maxCallsignLength),
        FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9/]')),
      ],
      decoration: InputDecoration(
        labelText: AppLocalizations.of(context).stationCallsignLabel,
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
  });

  final String definitionId;
  final StationExchangeField field;
  final bool enabled;

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

    return TextField(
      enabled: widget.enabled,
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
    return AlertDialog(
      title: Text(l10n.pastSessionsTitle),
      content: SizedBox(
        width: 440,
        child: sessions.isEmpty
            ? Text(l10n.noCompletedSessions)
            : ListView.separated(
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
                      onTap: () {
                        final messenger = ScaffoldMessenger.of(context);
                        settings
                          ..pendingQuestionSeed = review.metadata.questionSeed
                          ..pendingAudioSeed = review.metadata.audioSeed
                          ..pendingReplayRunId = review.metadata.runId
                          ..contestId = review.metadata.contestId
                          ..contestModeId = review.metadata.modeId
                          ..difficulty = TrainingDifficulty.fromId(
                            review.metadata.difficultyId,
                          );
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
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.close),
        ),
      ],
    );
  }
}
