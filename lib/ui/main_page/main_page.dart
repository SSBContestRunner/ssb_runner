import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/ui/main_page/app_topbar.dart';
import 'package:ssb_runner/ui/main_page/qso_console.dart';
import 'package:ssb_runner/ui/main_page/qso_log_panel.dart';
import 'package:ssb_runner/ui/main_page/rules_card.dart';
import 'package:ssb_runner/ui/main_page/session_panel.dart';
import 'package:ssb_runner/ui/main_page/settings_cubits.dart';
import 'package:ssb_runner/ui/main_page/training_review_overlay.dart';
import 'package:ssb_runner/ui/qso_result_table/qso_result_list/qso_result_list_cubit.dart';

class MainPage extends StatelessWidget {
  const MainPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
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
              StationCallsignCubit(appSettings: context.read<AppSettings>()),
        ),
        BlocProvider(
          create: (context) =>
              TrainingOptionsCubit(context.read<AppSettings>()),
        ),
        BlocProvider(
          create: (context) => QsoRecordListCubit(
            appDatabase: context.read(),
            contestManager: context.read(),
          ),
        ),
      ],
      child: const Stack(
        children: [
          Column(
            children: [
              AppTopbar(),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: _ConsoleGrid(),
                ),
              ),
            ],
          ),
          TrainingReviewOverlay(),
        ],
      ),
    );
  }
}

class _ConsoleGrid extends StatelessWidget {
  const _ConsoleGrid();

  @override
  Widget build(BuildContext context) {
    final windowWidth = MediaQuery.sizeOf(context).width;
    final sideWidth = windowWidth <= 1060
        ? 310.0
        : windowWidth <= 1180
        ? 332.0
        : 360.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Column(
            children: const [
              Expanded(child: QsoLogPanel()),
              SizedBox(height: 12),
              QsoConsole(),
            ],
          ),
        ),
        const SizedBox(width: 14),
        SizedBox(
          width: sideWidth,
          child: const Column(
            children: [
              Expanded(child: SessionPanel()),
              SizedBox(height: 12),
              RulesCard(),
            ],
          ),
        ),
      ],
    );
  }
}
