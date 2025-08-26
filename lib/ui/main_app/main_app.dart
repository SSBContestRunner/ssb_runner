import 'dart:ui';

import 'package:catcher_2/catcher_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssb_runner/audio/audio_loader.dart';
import 'package:ssb_runner/audio/audio_player.dart';
import 'package:ssb_runner/callsign/callsign_loader.dart';
import 'package:ssb_runner/db/app_database.dart';
import 'package:ssb_runner/dxcc/dxcc_manager.dart';
import 'package:ssb_runner/ui/main_app/home_page.dart';
import 'package:ssb_runner/main.dart';
import 'package:toastification/toastification.dart';
import 'package:window_manager/window_manager.dart';
import 'package:worker_manager/worker_manager.dart';

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<StatefulWidget> createState() {
    return _MainAppState();
  }
}

class _MainAppState extends State<MainApp> {
  late final AppLifecycleListener _listener;

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(
      onExitRequested: () async {
        SoLoud.instance.deinit();
        return AppExitResponse.exit;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ToastificationWrapper(
      child: MaterialApp(
        navigatorKey: Catcher2.navigatorKey,
        title: 'SSB Runner',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: seedColor,
            primary: seedColor,
          ),
        ),
        home: MultiRepositoryProvider(
          providers: [
            RepositoryProvider(create: (context) => AppDatabase()),
            RepositoryProvider(create: (context) => AudioLoader()),
            RepositoryProvider(create: (context) => AudioPlayer()),
            RepositoryProvider(create: (context) => CallsignLoader()),
            RepositoryProvider(
              create: (context) => DxccManager(database: context.read()),
            ),
          ],
          child: BlocProvider(
            create: (context) =>
                _MainAppCubit()..load(dxccManager: context.read()),
            child: BlocBuilder<_MainAppCubit, _AppDeps?>(
              builder: (context, appDeps) {
                if (appDeps == null) {
                  return Container(
                    color: ColorScheme.of(context).surface,
                    child: const Center(child: CircularProgressIndicator()),
                  );
                }

                return HomePage(prefs: appDeps.prefs);
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _listener.dispose();
    super.dispose();
  }
}

class _AppDeps {
  final SharedPreferencesWithCache prefs;

  _AppDeps({required this.prefs});
}

class _MainAppCubit extends Cubit<_AppDeps?> {
  _MainAppCubit() : super(null);

  void load({required DxccManager dxccManager}) async {
    // Initialize the player.
    try {
      await SoLoud.instance.init(channels: Channels.mono);
    } on Exception catch (error, stackTrace) {
      Catcher2.reportCheckedError(error, stackTrace);
    }

    // Initialize the window manager plugin.
    await windowManager.ensureInitialized();
    final windowOptions = WindowOptions(size: Size(1280, 720), center: true);

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
      await windowManager.setResizable(false);
    });

    final prefs = await SharedPreferencesWithCache.create(
      cacheOptions: SharedPreferencesWithCacheOptions(),
    );

    await workerManager.init(dynamicSpawning: true);

    await dxccManager.loadDxcc();

    emit(_AppDeps(prefs: prefs));
  }
}
