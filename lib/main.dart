import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:logger/web.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssb_runner/audio/audio_player.dart';
import 'package:ssb_runner/callsign/callsign_loader.dart';
import 'package:ssb_runner/contest_run/contest_manager.dart';
import 'package:ssb_runner/crash_repoter.dart';
import 'package:ssb_runner/db/app_database.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/ui/main_page.dart';
import 'package:toastification/toastification.dart';
import 'package:window_manager/window_manager.dart';
import 'package:worker_manager/worker_manager.dart';

final logger = Logger(printer: PrettyPrinter(methodCount: 5));
final crashLogger = CrashLogger();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(MyApp());
}

Future<void> _initCrashHandling() async {
  // 初始化日志系统
  await crashLogger.initialize();

  // 设置全局异常处理
  FlutterError.onError = (FlutterErrorDetails details) {
    crashLogger.logCrash(details.exceptionAsString(), details.stack);
    FlutterError.presentError(details); // 保留默认错误显示
  };

  // 捕获异步异常
  PlatformDispatcher.instance.onError = (error, stack) {
    crashLogger.logCrash(error.toString(), stack);
    return true;
  };
}

const _seedColor = Color(0xFF0059BA);

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<StatefulWidget> createState() {
    return _MyAppState();
  }
}

class _MyAppState extends State<MyApp> {
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
        home: BlocProvider(
          create: (context) => _MyAppCubit(),
          child: BlocBuilder<_MyAppCubit, _AppDeps?>(
            builder: (context, appDeps) {
              if (appDeps == null) {
                return const Center(child: CircularProgressIndicator());
              } else {
                return _HomePage(prefs: appDeps.prefs);
              }
            },
          ),
        ),
      ),
    );
  }
}

class _AppDeps {
  final SharedPreferencesWithCache prefs;

  _AppDeps({required this.prefs});
}

class _MyAppCubit extends Cubit<_AppDeps?> {
  _MyAppCubit() : super(null);

  void load() async {
    await _initCrashHandling();

    // Initialize the window manager plugin.
    await windowManager.ensureInitialized();

    // Initialize the player.
    try {
      await SoLoud.instance.init(channels: Channels.mono);
    } on Exception catch (e, stack) {
      crashLogger.logCrash(e.toString(), stack);
    }

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

    emit(_AppDeps(prefs: prefs));
  }
}

class _HomePage extends StatelessWidget {
  final SharedPreferencesWithCache _prefs;

  const _HomePage({required SharedPreferencesWithCache prefs})
    : _prefs = prefs;

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
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
    );
  }
}
