import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssb_contest_runner/audio/audio_player.dart';
import 'package:ssb_contest_runner/contest_run/contest_manager.dart';
import 'package:ssb_contest_runner/db/app_database.dart';
import 'package:ssb_contest_runner/settings/app_settings.dart';
import 'package:ssb_contest_runner/ui/main_page.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize the window manager plugin.
  await windowManager.ensureInitialized();

  // Initialize the player.
  await SoLoud.instance.init(channels: Channels.mono);

  final windowOptions = WindowOptions(size: Size(1280, 720), center: true);

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  final prefs = await SharedPreferencesWithCache.create(
    cacheOptions: SharedPreferencesWithCacheOptions(),
  );

  runApp(MyApp(pref: prefs));
}

const _seedColor = Color(0xFF0059BA);

class MyApp extends StatelessWidget {
  final SharedPreferencesWithCache _prefs;

  const MyApp({super.key, required SharedPreferencesWithCache pref})
    : _prefs = pref;

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SSB Runner',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seedColor,
          primary: _seedColor,
        ),
      ),
      home: MultiRepositoryProvider(
        providers: [
          RepositoryProvider(create: (context) => AppDatabase()),
          RepositoryProvider(create: (context) => ContestManager()),
          RepositoryProvider(create: (context) => AudioPlayer()),
          RepositoryProvider(create: (context) => AppSettings(prefs: _prefs)),
        ],
        child: Scaffold(body: MainPage()),
      ),
    );
  }
}
