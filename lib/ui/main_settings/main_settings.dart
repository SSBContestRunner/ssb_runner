import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ssb_runner/common/constants.dart';
import 'package:ssb_runner/common/upper_case_formatter.dart';
import 'package:ssb_runner/contest_run/new/contest_manager.dart';
import 'package:ssb_runner/contest_type/contest_definition.dart';
import 'package:ssb_runner/contest_type/station_exchange.dart';
import 'package:ssb_runner/dxcc/dxcc_manager.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/ui/common/setting_item.dart';
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
                    SettingItem(title: 'Contest', content: _ContestSettings()),
                    SettingItem(title: 'Station', content: _StationSettings()),
                    SettingItem(title: 'Options', content: OptionsSetting()),
                    SettingItem(
                      title: 'Diagnostics',
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

class _ContestSettings extends StatefulWidget {
  @override
  State<StatefulWidget> createState() {
    return _ContestSettingsState();
  }
}

class _ContestSettingsState extends State<_ContestSettings> {
  final _contestNameController = TextEditingController();
  final _contestExchangeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final contest = context.read<ContestSettingCubit>().state;
    _contestNameController.text = contest.name;
    _contestExchangeController.text = contest.exchangeLabel;
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ContestSettingCubit, ContestDefinition>(
      listener: (context, contest) {
        _contestNameController.text = contest.name;
        _contestExchangeController.text = contest.exchangeLabel;
      },
      child: BlocBuilder<MainSettingsCubit, bool>(
        builder: (context, isContestRunning) {
          final isEnabled = !isContestRunning;

          return Flex(
            direction: Axis.horizontal,
            spacing: 12.0,
            children: [
              Expanded(
                flex: 1,
                child: DropdownMenu<String>(
                  enabled: isEnabled,
                  controller: _contestNameController,
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
                  label: const Text('Name'),
                  inputDecorationTheme: const InputDecorationTheme(
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: TextField(
                  enabled: isEnabled,
                  readOnly: true,
                  controller: _contestExchangeController,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Exchange',
                  ),
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
        labelText: 'Callsign',
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
        labelText: field.label,
        helperText:
            field.helperText ?? (isDerived ? 'Default from callsign' : null),
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
