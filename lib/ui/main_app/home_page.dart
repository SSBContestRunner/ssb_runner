import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssb_runner/contest_run/contest_manager.dart';
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
          create: (context) => ContestManager(
            callsignLoader: context.read(),
            appSettings: context.read(),
            appDatabase: context.read(),
            audioPlayer: context.read(),
            dxccManager: context.read(),
          ),
        ),
      ],
      child: Scaffold(body: MainPage()),
    );
  }
}
