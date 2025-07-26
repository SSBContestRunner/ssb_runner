import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/ui/bottom_panel/bottom_panel.dart';
import 'package:ssb_runner/ui/main_cubit.dart';
import 'package:ssb_runner/ui/main_settings/main_settings.dart';
import 'package:ssb_runner/ui/qso_result_table/qso_record_table.dart';

class MainPage extends StatelessWidget {
  const MainPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => MainCubit(),
      child: BlocBuilder<MainCubit, bool>(
        builder: (context, isShowKeyTips) {
          return Padding(
            padding: const EdgeInsets.only(
              top: 16.0,
              bottom: 12.0,
              left: 16.0,
              right: 16.0,
            ),
            child: Flex(
              direction: Axis.vertical,
              spacing: 12.0,
              children: [
                Expanded(child: _TopPanel()),
                BottomPanel(),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TopPanel extends StatelessWidget {
  const _TopPanel();

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider(
      create: (context) => context.read<AppSettings>(),
      child: Flex(
        spacing: 18.0,
        direction: Axis.horizontal,
        children: [
          Expanded(child: QsoRecordTable()),
          MainSettings(),
        ],
      ),
    );
  }
}
