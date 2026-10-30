import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ssb_runner/common/constants.dart';
import 'package:ssb_runner/common/upper_case_formatter.dart';
import 'package:ssb_runner/contest_run/new/contest_manager.dart';
import 'package:ssb_runner/contest_type/contest_definition.dart';
import 'package:ssb_runner/contest_type/station_exchange.dart';
import 'package:ssb_runner/dxcc/dxcc_manager.dart';
import 'package:ssb_runner/l10n/domain_l10n.dart';
import 'package:ssb_runner/l10n/generated/app_localizations.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/ui/common/setting_item.dart';
import 'package:ssb_runner/ui/main_settings/contest_rules_dialog.dart';
import 'package:ssb_runner/ui/main_settings/diagnostics_setting.dart';
import 'package:ssb_runner/ui/main_settings/options_setting.dart';

class MainSettingsCubit extends Cubit<bool> {
  final ContestManager _contestManager;

  MainSettingsCubit({required ContestManager contestManager})
    : _contestManager = contestManager,
      super(contestManager.isContestRunning) {
    _contestManager.isContestRunningStream.listen((isContestRunning) {
      emit(isContestRunning);
    });
  }
}

class MainSettings extends StatelessWidget {
  const MainSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      width: 370,
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (context) =>
                MainSettingsCubit(contestManager: context.read()),
          ),
          BlocProvider(
            create: (context) =>
                ContestSettingCubit(appSettings: context.read<AppSettings>()),
          ),
          BlocProvider(
            create: (context) =>
                _StationCallsignCubit(appSettings: context.read<AppSettings>()),
          ),
        ],
        child: BlocBuilder<MainSettingsCubit, bool>(
          builder: (context, isContestRunning) {
            return ExcludeFocus(
              excluding: isContestRunning,
              // The settings panel is a fixed-width sidebar. Its content can
              // exceed the available height, so make it scrollable.
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 12.0,
                  children: [
                    SettingItem(
                      title: l10n.settingsContest,
                      titleTrailing: const _ContestRulesButton(),
                      content: _ContestSettings(),
                    ),
                    SettingItem(
                      title: l10n.settingsStation,
                      content: _StationSettings(),
                    ),
                    SettingItem(
                      title: l10n.settingsOptions,
                      content: OptionsSetting(),
                    ),
                    SettingItem(
                      title: l10n.settingsDiagnostics,
                      content: DiagnosticsSetting(),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class ContestSettingCubit extends Cubit<ContestDefinition> {
  final AppSettings _appSettings;

  ContestSettingCubit({required AppSettings appSettings})
    : _appSettings = appSettings,
      super(ContestRegistry.byId(appSettings.contestId));

  void changeContest(String contestId) {
    final contest = ContestRegistry.byId(contestId);
    _appSettings.contestId = contestId;

    emit(contest);
  }
}

/// Info button in the Contest title row.
class _ContestRulesButton extends StatelessWidget {
  const _ContestRulesButton();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return IconButton.filledTonal(
      key: const Key('contest-rules-button'),
      tooltip: l10n.contestRulesTooltip,
      iconSize: 18.0,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 32.0, height: 32.0),
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: () {
        // Read at press time so the dialog reflects the contest selected when
        // it opens, even if the row was built before the dropdown changed.
        final contest = context.read<ContestSettingCubit>().state;
        showDialog<void>(
          context: context,
          builder: (_) => ContestRulesDialog(contest: contest),
        );
      },
      icon: const Icon(Icons.info_outlined),
    );
  }
}

class _ContestSettings extends StatefulWidget {
  @override
  State<StatefulWidget> createState() {
    return _ContestSettingsState();
  }
}

class _ContestSettingsState extends State<_ContestSettings> {
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
      child: BlocBuilder<MainSettingsCubit, bool>(
        builder: (context, isContestRunning) {
          final isEnabled = !isContestRunning;

          // Stack the two fields instead of placing them side by side: the
          // 370px sidebar cannot fit the Name dropdown and the Exchange label
          // (ARRL's is "59 State/Province (W/VE) / 59 Power (DX)") on one row,
          // so a horizontal layout clipped both.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12.0,
            children: [
              DropdownMenu<String>(
                enabled: isEnabled,
                controller: _contestNameController,
                // Fill the full width; without this the dropdown sizes to its
                // intrinsic (content) width instead of the column width.
                expandedInsets: EdgeInsets.zero,
                onSelected: (id) {
                  if (id != null) {
                    context.read<ContestSettingCubit>().changeContest(id);
                  }
                },
                dropdownMenuEntries: ContestRegistry.all
                    .map(
                      (contest) => DropdownMenuEntry(
                        value: contest.id,
                        label: contest.name,
                      ),
                    )
                    .toList(),
                label: Text(l10n.contestNameLabel),
                inputDecorationTheme: const InputDecorationTheme(
                  border: OutlineInputBorder(),
                ),
              ),
              TextField(
                enabled: isEnabled,
                readOnly: true,
                // The exchange label can be long, so let it wrap onto more
                // lines rather than being clipped at the field edge.
                maxLines: null,
                controller: _contestExchangeController,
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: l10n.contestExchangeFieldLabel,
                ),
              ),
            ],
          );
        },
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

class _StationCallsignCubit extends Cubit<String> {
  final AppSettings _appSettings;

  _StationCallsignCubit({required AppSettings appSettings})
    : _appSettings = appSettings,
      super(appSettings.stationCallsign);

  void onCallSignChange(String callSign) {
    _appSettings.stationCallsign = callSign;
    emit(callSign);
  }
}

class _StationSettings extends StatelessWidget {
  const _StationSettings();

  @override
  Widget build(BuildContext context) {
    final isContestRunning = context.watch<MainSettingsCubit>().state;
    final definition = context.watch<ContestSettingCubit>().state;
    final callsign = context.watch<_StationCallsignCubit>().state;
    final dxccManager = context.read<DxccManager>();

    // The plan depends on the station callsign, so this rebuilds when the
    // callsign changes (ARRL/JIDX switch on DXCC).
    final plan = definition.myExchangePlan(
      stationCallsign: callsign,
      dxccManager: dxccManager,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12.0,
      children: [
        _CallsignField(enabled: !isContestRunning),
        for (final field in plan.fields)
          _StationExchangeFieldInput(
            key: ValueKey('${definition.id}-${field.id}-$callsign'),
            definitionId: definition.id,
            field: field,
            enabled: !isContestRunning,
          ),
      ],
    );
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
    final callsign = context.watch<_StationCallsignCubit>().state;
    if (_controller.text != callsign) {
      _controller.text = callsign;
    }

    return TextField(
      enabled: widget.enabled,
      controller: _controller,
      style: TextStyle(fontFamily: qsoFontFamily),
      inputFormatters: [
        UpperCaseTextFormatter(),
        LengthLimitingTextInputFormatter(maxCallsignLength),
        FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9/]')),
      ],
      decoration: InputDecoration(
        border: OutlineInputBorder(),
        labelText: AppLocalizations.of(context).stationCallsignLabel,
      ),
      onChanged: (value) {
        context.read<_StationCallsignCubit>().onCallSignChange(value);
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
    final callsign = context.read<_StationCallsignCubit>().state;
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
      style: TextStyle(fontFamily: qsoFontFamily),
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
        border: OutlineInputBorder(),
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
