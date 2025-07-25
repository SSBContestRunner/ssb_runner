import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:logger/web.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssb_runner/audio/audio_player.dart';
import 'package:ssb_runner/callsign/callsign_loader.dart';
import 'package:ssb_runner/contest_run/contest_manager.dart';
import 'package:ssb_runner/db/app_database.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/ui/main_page.dart';
import 'package:toastification/toastification.dart';
import 'package:window_manager/window_manager.dart';
import 'package:worker_manager/worker_manager.dart';

final logger = Logger(printer: PrettyPrinter(methodCount: 5));

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize the window manager plugin.
  await windowManager.ensureInitialized();

  // Initialize the player.
  await SoLoud.instance.init(channels: Channels.mono);

  final windowOptions = WindowOptions(size: Size(1280, 720), center: true);

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  final prefs = await SharedPreferencesWithCache.create(
    cacheOptions: SharedPreferencesWithCacheOptions(),
  );

  await workerManager.init(dynamicSpawning: true);

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
    return ToastificationWrapper(
      child: MaterialApp(
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
            RepositoryProvider(create: (context) => AudioPlayer()),
            RepositoryProvider(
              create: (context) => CallsignLoader()..loadCallsigns(),
            ),
            RepositoryProvider(create: (context) => AppSettings(prefs: _prefs)),
          ],
          child: RepositoryProvider(
            create: (context) => ContestManager(
              callsignLoader: context.read(),
              appSettings: context.read(),
              appDatabase: context.read(),
              audioPlayer: context.read(),
            ),
            child: Scaffold(body: MainPage()),
          ),
        ),
      ),
    );
  }
}
