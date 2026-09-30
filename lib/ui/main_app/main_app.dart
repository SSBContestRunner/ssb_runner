import 'dart:ui';

import 'package:catcher_2/catcher_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssb_runner/audio/audio_loader.dart';
import 'package:ssb_runner/audio/audio_player.dart';
import 'package:ssb_runner/callsign/callsign_loader.dart';
import 'package:ssb_runner/db/app_database.dart';
import 'package:ssb_runner/dxcc/dxcc_manager.dart';
import 'package:ssb_runner/logging/app_logger.dart';
import 'package:ssb_runner/logging/boot_trace.dart';
import 'package:ssb_runner/logging/log_export.dart';
import 'package:ssb_runner/logging/logging_bootstrap.dart';
import 'package:ssb_runner/main.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/ui/main_app/home_page.dart';
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
        await flushLogs();
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
            create: (context) => _MainAppCubit()
              ..load(
                dxccManager: context.read(),
                callsignLoader: context.read(),
              ),
            child: BlocBuilder<_MainAppCubit, _AppState>(
              builder: (context, state) {
                switch (state) {
                  case _Loading():
                    return Container(
                      color: ColorScheme.of(context).surface,
                      child: const Center(child: CircularProgressIndicator()),
                    );
                  case _Ready(:final deps):
                    return HomePage(prefs: deps.prefs);
                  case _Failed(:final message):
                    return _StartupFailure(message: message);
                }
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

sealed class _AppState {
  const _AppState();
}

class _Loading extends _AppState {
  const _Loading();
}

class _Ready extends _AppState {
  const _Ready(this.deps);

  final _AppDeps deps;
}

class _Failed extends _AppState {
  const _Failed(this.message);

  final String message;
}

class _MainAppCubit extends Cubit<_AppState> {
  _MainAppCubit() : super(const _Loading());

  Future<void> load({
    required DxccManager dxccManager,
    required CallsignLoader callsignLoader,
  }) async {
    try {
      await boot.step('soloud_init', _initAudio);
      await boot.step('window_ready', _initWindow);

      final prefs = await boot.step(
        'prefs_ready',
        () => SharedPreferencesWithCache.create(
          cacheOptions: SharedPreferencesWithCacheOptions(),
        ),
      );

      // Apply the persisted verbosity choice as early as possible.
      log.setVerbose(AppSettings(prefs: prefs).verboseLogging);

      await boot.step(
        'worker_manager_init',
        () => workerManager.init(dynamicSpawning: true),
      );

      await boot.step('dxcc_loaded', dxccManager.loadDxcc);
      await boot.step('callsign_loaded', callsignLoader.loadCallsigns);

      emit(_Ready(_AppDeps(prefs: prefs)));
      log.info('application ready', tag: 'boot');
    } catch (error, stackTrace) {
      log.fatal(
        'startup failed',
        tag: 'boot',
        error: error,
        stackTrace: stackTrace,
      );
      emit(_Failed('$error'));
    }
  }

  Future<void> _initAudio() async {
    try {
      await SoLoud.instance.init(channels: Channels.mono);
      log.info('SoLoud initialized', tag: 'audio.soloud');
    } catch (error, stackTrace) {
      // Audio failure must not stop the rest of the app from starting.
      log.error(
        'SoLoud init failed, audio disabled',
        tag: 'audio.soloud',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _initWindow() async {
    await windowManager.ensureInitialized();
    final windowOptions = WindowOptions(size: Size(1280, 720), center: true);

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
      await windowManager.setResizable(true);
      await windowManager.setMinimumSize(const Size(1024, 650));
    });
  }
}

class _StartupFailure extends StatelessWidget {
  const _StartupFailure({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 16),
              const Text('SSB Runner failed to start'),
              const SizedBox(height: 8),
              SelectableText(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                children: [
                  OutlinedButton(
                    onPressed: () => _copySummary(context),
                    child: const Text('Copy diagnostics'),
                  ),
                  FilledButton(
                    onPressed: () => _exportLogs(context),
                    child: const Text('Export logs'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _copySummary(BuildContext context) async {
    final summary = await diagnosticSummary();
    await Clipboard.setData(ClipboardData(text: summary));
    if (!context.mounted) {
      return;
    }

    toastification.show(
      title: const Text('Diagnostics copied'),
      autoCloseDuration: const Duration(seconds: 2),
      type: ToastificationType.success,
      style: ToastificationStyle.fillColored,
    );
  }

  Future<void> _exportLogs(BuildContext context) async {
    try {
      final file = await exportLogArchive();
      await Clipboard.setData(ClipboardData(text: file.path));
      if (!context.mounted) {
        return;
      }

      toastification.show(
        title: Text('Exported to ${file.path}'),
        autoCloseDuration: const Duration(seconds: 4),
        type: ToastificationType.success,
        style: ToastificationStyle.fillColored,
      );
    } catch (error, stackTrace) {
      log.error(
        'log export failed',
        tag: 'crash',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
