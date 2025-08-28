import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssb_runner/contest_run/new/contest_data_manager.dart';
import 'package:ssb_runner/contest_run/new/contest_input_handler.dart';
import 'package:ssb_runner/contest_run/new/contest_manager_new.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/ui/main_page/main_page.dart';

class HomePage extends StatelessWidget {
  final SharedPreferencesWithCache _prefs;

  const HomePage({super.key, required SharedPreferencesWithCache prefs})
    : _prefs = prefs;

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider(create: (context) => AppSettings(prefs: _prefs)),
        RepositoryProvider(
          create: (context) => ContestDataManager(
            audioLoader: context.read(),
            audioPlayer: context.read(),
            appSettings: context.read(),
            appDatabase: context.read(),
            callsignLoader: context.read(),
            dxccManager: context.read(),
            inputHandler: ContestInputHandler(),
          ),
        ),
        RepositoryProvider(
          create: (context) =>
              ContestManagerNew(contestDataManager: context.read()),
        ),
        RepositoryProvider(
          create: (context) {
            final contestManager = context.read<ContestManagerNew>();
            return contestManager.contestTimer;
          },
        ),
      ],
      child: Scaffold(body: MainPage()),
    );
  }
}
