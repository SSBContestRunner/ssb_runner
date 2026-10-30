import 'dart:async';
import 'dart:io';
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
import 'package:ssb_runner/db/database_bootstrap.dart';
import 'package:ssb_runner/dxcc/dxcc_manager.dart';
import 'package:ssb_runner/logging/app_logger.dart';
import 'package:ssb_runner/logging/boot_trace.dart';
import 'package:ssb_runner/logging/logging_bootstrap.dart';
import 'package:ssb_runner/main.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/ui/diagnostics_actions.dart';
import 'package:ssb_runner/ui/main_app/exit_flow.dart';
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
    _listener = AppLifecycleListener(onExitRequested: _handleExitRequest);

    // The window is hidden until the first frame is on screen, so it appears
    // straight into the loading view instead of as a blank window.
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealWindow());
  }

  /// Last line of defence for "the window closed but the process stays".
  ///
  /// The Windows runner tears the FlutterEngine down synchronously inside
  /// WM_DESTROY and only then posts WM_QUIT (windows/runner/win32_window.cpp).
  /// If any teardown step blocks, the window is already gone but the message
  /// loop never quits, leaving an idle process in Task Manager. The exit path
  /// therefore has a hard bound: whatever the cleanup does, the process ends.
  ///
  /// The timer only fires when the bounded cleanup (3.5 s worst case) hangs,
  /// because on the normal path the process is already gone by then.
  Future<AppExitResponse> _handleExitRequest() async {
    Timer(const Duration(seconds: 5), () => exit(0));

    // CI only: keeps the request unanswered so the smoke test can prove that
    // the fallback above ends the process on its own.
    if (Platform.environment['SSB_RUNNER_TEST_EXIT_HANG'] == '1') {
      await Completer<void>().future;
    }

    log.info('exit requested', tag: 'exit');

    await runBoundedExitCleanup(
      deinitAudio: _deinitAudio,
      flushLogs: flushLogs,
      onError: (step, error, stackTrace) => log.warn(
        '$step failed',
        tag: 'exit',
        error: error,
        stackTrace: stackTrace,
      ),
    );

    return AppExitResponse.exit;
  }

  /// Releases the audio device off the UI isolate.
  ///
  /// `deinit()` is a synchronous native call, and SoLoud blocks on its own
  /// init/deinit mutex while a device restart is in flight; running it here
  /// would freeze the UI isolate and with it the fallback timer.
  Future<void> _deinitAudio() async {
    if (SoLoud.instance.isInitialized) {
      await SoLoud.instance.deinitAsync();
    }
  }

  Future<void> _revealWindow() async {
    try {
      // macOS binds the native window to the plugin only during this call.
      await windowManager.ensureInitialized();
      await windowManager.setSize(const Size(1280, 720));
      await windowManager.center();
      await windowManager.setResizable(true);
      await windowManager.setMinimumSize(const Size(1024, 650));
    } catch (error, stackTrace) {
      log.warn(
        'window configure failed',
        tag: 'boot',
        error: error,
        stackTrace: stackTrace,
      );
    }

    try {
      // Always restore opacity, even when the configuration above failed.
      await windowManager.setOpacity(1);
      await windowManager.show();
      await windowManager.focus();
    } catch (error, stackTrace) {
      log.error(
        'window show failed',
        tag: 'boot',
        error: error,
        stackTrace: stackTrace,
      );
    }
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
            child: BlocListener<_MainAppCubit, _AppState>(
              listenWhen: (previous, current) =>
                  current is _Ready && current.deps.warning != null,
              listener: (context, state) {
                final warning = (state as _Ready).deps.warning;
                if (warning == null) {
                  return;
                }

                // The overlay may not be mounted yet when startup finishes
                // before the first frame.
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => _showStartupWarning(warning),
                );
              },
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

  /// Non-fatal problem to surface once the main page is up.
  final String? warning;

  _AppDeps({required this.prefs, this.warning});
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
    final warnings = <String>[];

    try {
      // Started first, awaited before `_Ready`: the engine takes 80-165 ms and
      // must be up before the first voice segment is played.
      final audioReady = boot.step('soloud_init', _initAudio);

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

      // Resolve the database folder before drift opens it: the result reports
      // whether the history could be carried over from older versions.
      final database = await boot.step('db_ready', ensureDatabaseReady);
      if (database.warning != null) {
        warnings.add(database.warning!);
      }

      try {
        await boot.step('dxcc_loaded', dxccManager.loadDxcc);
      } catch (_) {
        // BootTrace logged the error already. Callsign lookups stay disabled
        // rather than keeping the whole app from starting.
        warnings.add('Callsign lookups are unavailable.');
      }

      await boot.step('callsign_loaded', callsignLoader.loadCallsigns);

      await audioReady;

      emit(
        _Ready(
          _AppDeps(
            prefs: prefs,
            warning: warnings.isEmpty ? null : warnings.join('\n'),
          ),
        ),
      );
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

  /// Environment variable that skips audio initialisation when set to `1`.
  ///
  /// SoLoud starts its engine on a worker isolate, and on hosts whose CoreAudio
  /// stack is unusable (the headless macOS VMs used by CI, for example) that
  /// call dies inside Apple's `AVAudioSession` with a SIGSEGV. A native crash
  /// cannot be intercepted by the `catch` below and takes the whole process
  /// down, so callers that only need the rest of the app to run--notably the
  /// macOS smoke test--use this to opt out.
  static const String _disableAudioEnv = 'SSB_RUNNER_DISABLE_AUDIO';

  Future<void> _initAudio() async {
    if (Platform.environment[_disableAudioEnv] == '1') {
      log.warn(
        'SoLoud init skipped by environment',
        tag: 'audio.soloud',
        fields: <String, Object?>{'env': _disableAudioEnv},
      );
      return;
    }

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
}

/// Reports a non-fatal startup problem, such as the history not being where the
/// user expects it, without keeping the app from running.
void _showStartupWarning(String message) {
  toastification.show(
    title: const Text('History database'),
    description: Text(message),
    type: ToastificationType.warning,
    style: ToastificationStyle.fillColored,
    autoCloseDuration: const Duration(seconds: 10),
  );
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
                    onPressed: () => copyDiagnosticSummary(context),
                    child: const Text('Copy diagnostics'),
                  ),
                  FilledButton(
                    onPressed: () => exportDiagnosticArchive(context),
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
}
