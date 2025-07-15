import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ssb_contest_runner/contest_run/contests.dart';
import 'package:ssb_contest_runner/settings/setting_constants.dart';
import 'package:ssb_contest_runner/ui/main_settings/options_setting.dart';
import 'package:ssb_contest_runner/ui/setting_item.dart';

class MainSettings extends StatelessWidget {
  const MainSettings({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 370,
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

class _ContestSettings extends StatelessWidget {
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
}

class _StationSettings extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          decoration: InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Callsign',
          ),
        ),
      ],
    );
  }
}


