import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ssb_runner/contest_run/new/contest_manager.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/ui/main_page/app_topbar.dart';
import 'package:ssb_runner/ui/main_page/qso_console.dart';
import 'package:ssb_runner/ui/main_page/qso_log_panel.dart';
import 'package:ssb_runner/ui/main_page/rules_card.dart';
import 'package:ssb_runner/ui/main_page/session_panel.dart';
import 'package:ssb_runner/ui/main_page/settings_cubits.dart';
import 'package:ssb_runner/ui/main_page/training_review_overlay.dart';
import 'package:ssb_runner/ui/qso_result_table/qso_result_list/qso_result_list_cubit.dart';
import 'package:ssb_runner/ui/qso_result_table/qso_voice_replay_cubit.dart';

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
        BlocProvider(
          create: (context) {
            final contestManager = context.read<ContestManager>();
            return QsoVoiceReplayCubit(
              contestManager: contestManager,
              audioLoader: contestManager.audioLoader,
              audioPlayer: contestManager.audioPlayer,
            );
          },
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
    // The session card owns the fixed track on the right; the log column on
    // the left is Expanded and takes whatever is left. At the 1024 minimum,
    // the English timer labels need a 362dp card (113.4dp for
    // "Remaining 00:00:00" plus 12dp slack in its 2/5 share of the row), so
    // 372 keeps the label intact and shortens the log column instead. The
    // wider tiers grow the card just enough to stay comfortable.
    final sideWidth = windowWidth <= 1060
        ? 372.0
        : windowWidth <= 1180
        ? 384.0
        : 396.0;

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
