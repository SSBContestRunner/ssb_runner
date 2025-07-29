import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ssb_runner/common/constants.dart';
import 'package:ssb_runner/common/upper_case_formatter.dart';
import 'package:ssb_runner/contest_run/contest_manager.dart';
import 'package:ssb_runner/contest_run/contests.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/ui/bottom_panel/qso_operation_area.dart';
import 'package:ssb_runner/ui/main_settings/options_setting.dart';
import 'package:ssb_runner/ui/common/setting_item.dart';

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
      child: BlocProvider(
        create: (context) => MainSettingsCubit(contestManager: context.read()),
        child: BlocBuilder<MainSettingsCubit, bool>(
          builder: (context, isContestRunning) {
            return ExcludeFocus(
              excluding: isContestRunning,
              child: Flex(
                direction: Axis.vertical,
                spacing: 12.0,
                children: [
                  SettingItem(title: 'Contest', content: _ContestSettings()),
                  SettingItem(title: 'Station', content: _StationSettings()),
                  SettingItem(title: 'Options', content: OptionsSetting()),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class ContestSettingCubit extends Cubit<Contest> {
  final AppSettings _appSettings;

  ContestSettingCubit({required AppSettings appSettings})
    : _appSettings = appSettings,
      super(
        supportedContests.firstWhere(
          (element) => element.id == appSettings.contestId,
        ),
      );

  void changeContest(String contestId) {
    final contest = supportedContests.firstWhere(
      (element) => element.id == contestId,
    );
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
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) {
        final cubit = ContestSettingCubit(appSettings: context.read());

        _contestNameController.text = cubit.state.name;
        _contestExchangeController.text = cubit.state.exchange;

        return cubit;
      },
      child: BlocListener<ContestSettingCubit, Contest>(
        listener: (context, contest) {
          _contestNameController.text = contest.name;
          _contestExchangeController.text = contest.exchange;
        },
        child: Flex(
          direction: Axis.horizontal,
          spacing: 12.0,
          children: [
            Expanded(
              flex: 2,
              child: TextField(
                readOnly: true,
                controller: _contestNameController,
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Name',
                  suffixIcon: Icon(Icons.arrow_drop_down),
                ),
              ),
            ),
            Expanded(
              flex: 1,
              child: TextField(
                readOnly: true,
                controller: _contestExchangeController,
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Exchange',
                ),
              ),
            ),
          ],
        ),
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

class _StationSettingsCubit extends Cubit<String> {
  final AppSettings _appSettings;

  _StationSettingsCubit({required AppSettings appSettings})
    : _appSettings = appSettings,
      super(appSettings.stationCallsign);

  void onCallSignChange(String callSign) {
    _appSettings.stationCallsign = callSign;
  }
}

class _StationSettings extends StatefulWidget {
  @override
  State<StatefulWidget> createState() {
    return _StationSettingsState();
  }
}

class _StationSettingsState extends State<_StationSettings> {
  final _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        BlocProvider(
          create: (context) {
            final cubit = _StationSettingsCubit(appSettings: context.read());
            _controller.text = cubit.state;
            return cubit;
          },
          child: BlocConsumer<_StationSettingsCubit, String>(
            listener: (context, callSign) {
              _controller.text = callSign;
            },
            buildWhen: (previous, current) => false,
            builder: (context, callSign) {
              return TextField(
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
                  context.read<_StationSettingsCubit>().onCallSignChange(value);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
