import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:catcher_2/catcher_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssb_runner/audio/audio_init_tracker.dart';
import 'package:ssb_runner/audio/audio_loader.dart';
import 'package:ssb_runner/audio/audio_player.dart';
import 'package:ssb_runner/callsign/callsign_loader.dart';
import 'package:ssb_runner/db/app_database.dart';
import 'package:ssb_runner/db/database_bootstrap.dart';
import 'package:ssb_runner/dxcc/dxcc_manager.dart';
import 'package:ssb_runner/l10n/app_l10n.dart';
import 'package:ssb_runner/l10n/generated/app_localizations.dart';
import 'package:ssb_runner/l10n/locale_resolution.dart';
import 'package:ssb_runner/logging/app_logger.dart';
import 'package:ssb_runner/logging/boot_trace.dart';
import 'package:ssb_runner/logging/logging_bootstrap.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/ui/diagnostics_actions.dart';
import 'package:ssb_runner/ui/main_app/exit_flow.dart';
import 'package:ssb_runner/ui/main_app/home_page.dart';
import 'package:ssb_runner/ui/main_app/window_geometry.dart';
import 'package:ssb_runner/ui/theme/app_theme.dart';
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

  /// Owned here so the MaterialApp can rebuild when the language changes.
  final ValueNotifier<AppLanguage> _language = ValueNotifier(AppLanguage.auto);

  /// Owned here so the MaterialApp can rebuild when the theme changes.
  final ValueNotifier<ThemeMode> _themeMode = ValueNotifier(ThemeMode.light);

  /// Restores the saved window size after prefs load and records later
  /// resizes. The window itself is configured in [_revealWindow].
  final WindowGeometryController _geometry = WindowGeometryController();

  /// Tracks the audio initialisation so the exit path knows whether it is safe
  /// to answer the platform's exit request (see `_handleExitRequest`).
  final AudioInitTracker _audio = AudioInitTracker();

  /// Set by the exit path so the boot sequence stops dispatching new steps.
  final _ExitSignal _exitSignal = _ExitSignal();

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(onExitRequested: _handleExitRequest);

    // The window is hidden until the first frame is on screen, so it appears
    // straight into the loading view instead of as a blank window. `_revealWindow`
    // has no awaits in its body, so it finishes synchronously here and the
    // "first frame visible" record lands before `_BootGate` starts any IO.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      boot.markFirstFrame();
      unawaited(_revealWindow());
      log.info(
        'first frame visible',
        tag: 'boot',
        fields: <String, Object?>{
          'sinceProcessMs': boot.sinceProcessMs,
          'sinceMainMs': boot.elapsedMs,
        },
      );
    });

    _scheduleTestWindowClose();
  }

  /// CI only: closes the window the way a user does, so the macOS and Linux
  /// smoke tests can assert that closing it ends the process.
  ///
  /// Neither platform can be closed from the outside in a CI session: macOS
  /// would need Accessibility/automation permissions, and the Linux container
  /// has no window manager to deliver a close request. window_manager's
  /// `close()` is `[NSWindow performClose]` / `gtk_window_close`, i.e. the same
  /// native path as clicking the close button.
  void _scheduleTestWindowClose() {
    final seconds = int.tryParse(
      Platform.environment['SSB_RUNNER_TEST_CLOSE_WINDOW_AFTER'] ?? '',
    );
    if (seconds == null) {
      return;
    }

    Timer(Duration(seconds: seconds), () async {
      log.warn('closing window by test hook', tag: 'exit');
      try {
        WindowManager.instance.getCurrent()?.close();
      } catch (error, stackTrace) {
        log.warn(
          'test window close failed',
          tag: 'exit',
          error: error,
          stackTrace: stackTrace,
        );
      }
    });
  }

  /// Last line of defence for "the window closed but the process stays".
  ///
  /// The Windows runner tears the FlutterEngine down synchronously inside
  /// WM_DESTROY and only then posts WM_QUIT (windows/runner/win32_window.cpp).
  /// If any teardown step blocks, the window is already gone but the message
  /// loop never quits, leaving an idle process in Task Manager. The exit path
  /// therefore has a hard bound: whatever the cleanup does, the process ends.
  ///
  /// The timer below only covers a stuck *cleanup*; it cannot cover a hang
  /// inside `ExitProcess`, because that happens after the Dart VM is gone. The
  /// native exit watchdog (windows/runner/exit_watchdog.cpp) covers that phase.
  /// On the normal path the process is already gone by then.
  ///
  /// Invariant (docs/design/desktop_exit_design.md §3): `AppExitResponse.exit`
  /// is only answered when the audio engine is either never initialised or
  /// fully disposed. Any other state ends in a forced termination instead,
  /// because `ExitProcess` runs the plugin's DLL detach and that wait can be
  /// permanent once the Dart VM is gone.
  Future<AppExitResponse> _handleExitRequest() async {
    _exitSignal.requested = true;
    _exitTrace('enter');
    Timer(const Duration(seconds: 5), _forceExit);

    // CI only: keeps the request unanswered so the smoke test can prove that
    // the fallback above ends the process on its own.
    if (Platform.environment['SSB_RUNNER_TEST_EXIT_HANG'] == '1') {
      await Completer<void>().future;
    }

    log.info('exit requested', tag: 'exit');
    _exitTrace('logged');

    // A resize within the last 500ms may still be debounced.
    _geometry.flush();
    _exitTrace('geometry_flushed');

    // 1) Let an in-flight initialisation settle (normally 28-411 ms). Closing
    // the window inside that window used to skip the deinit and answer `exit`,
    // which hangs inside ExitProcess (mechanism B in the design doc).
    final settled = await _audio.settledWithin(const Duration(seconds: 2));
    _exitTrace(settled ? 'settled' : 'settled_timeout');
    if (!settled) {
      await _hardExit('hard_exit_init_running');
    }

    // 2) Always dispose, bounded, whether the engine is running, never
    // initialised or failed to initialise; see §4.1 for why no state is
    // allowed to skip this.
    final disposed = await runBoundedExitCleanup(
      deinitAudio: _deinitAudio,
      flushLogs: flushLogs,
      onError: (step, error, stackTrace) => log.warn(
        '$step failed',
        tag: 'exit',
        error: error,
        stackTrace: stackTrace,
      ),
    );
    _exitTrace(disposed ? 'deinit_done' : 'deinit_unfinished');
    if (!disposed) {
      await _hardExit('hard_exit_deinit_unfinished');
    }

    _exitTrace('answering_exit');
    return AppExitResponse.exit;
  }

  /// Ends the process without answering the exit request.
  ///
  /// Used when the engine cannot be brought to a settled, disposed state.
  /// `exit()` would enter `ExitProcess` and its DLL detach, which is exactly
  /// where the process hangs; `Process.killPid` skips CRT and DLL teardown.
  /// Logs are flushed first so the trace survives the termination.
  Future<AppExitResponse> _hardExit(String reason) async {
    _exitTrace(reason);
    await runBoundedExitStep(
      step: 'log flush',
      action: flushLogs,
      timeout: const Duration(milliseconds: 500),
      onError: (step, error, stackTrace) => log.warn(
        '$step failed',
        tag: 'exit',
        error: error,
        stackTrace: stackTrace,
      ),
    );
    if (!Process.killPid(pid)) {
      exit(1);
    }
    // The process is being terminated; never answer the request.
    return Completer<AppExitResponse>().future;
  }

  /// Appends one line to the exit trace, written synchronously.
  ///
  /// The app logger is buffered, so nothing it wrote after this point survives
  /// a process that hangs inside engine teardown. This file is created next to
  /// the native startup timeline (`--boot-trace-dir`) and never throws.
  void _exitTrace(String mark) {
    final directory = boot.nativeTraceDirectory;
    if (directory == null) {
      return;
    }
    try {
      final line =
          '${DateTime.now().toUtc().toIso8601String()} mark=$mark'
          ' pid=$pid step=${boot.stepIndex} lastStep=${boot.lastStep ?? '-'}'
          ' phase=${boot.phase}\n';
      File('$directory/exit_$pid.log')
          .writeAsStringSync(line, mode: FileMode.append, flush: true);
    } catch (_) {
      // Tracing must never affect the exit path.
    }
  }

  /// Ends the process when the bounded cleanup never answers.
  ///
  /// Scope: a stuck cleanup only. A hang in the process-exit phase is invisible
  /// here (Dart is already gone) and is handled by the native exit watchdog.
  ///
  /// `exit(0)` is deliberately not the first attempt: it runs CRT and DLL
  /// teardown handlers, and on Windows the engine is torn down while still
  /// holding an unanswered exit request, so a plugin thread blocked there keeps
  /// the process alive even though `exit()` was called (observed in CI). A
  /// termination signal skips every teardown handler.
  void _forceExit() {
    _exitTrace('fallback_fired');
    log.warn('exit fallback fired', tag: 'exit');
    if (Process.killPid(pid)) {
      return;
    }
    exit(0);
  }

  /// Releases the audio device off the UI isolate.
  ///
  /// Unconditional: `SoLoud.isInitialized` is false for the whole
  /// initialisation, so gating on it is what let a half-initialised engine
  /// reach `ExitProcess`. On an engine that never initialised, `deinitAsync()`
  /// only spawns an isolate and the native `dispose()` returns immediately.
  ///
  /// The synchronous `deinit()` is forbidden here: it runs the native teardown
  /// on the UI isolate, and a blocked teardown would freeze the 5 s fallback
  /// timer with it.
  Future<void> _deinitAudio() => SoLoud.instance.deinitAsync();

  Future<void> _revealWindow() async {
    // 0.6.0 resolves the app's own window from the native window manager,
    // so there is no `ensureInitialized` step before these calls.
    final window = resolveAppWindow();

    try {
      if (window != null) {
        final stopwatch = Stopwatch()..start();
        window.isResizable = true;
        // Content is the contract; the frame minimum is derived from the
        // platform chrome measured at runtime.
        applyWindowGeometry(window);
        log.info(
          'window geometry',
          tag: 'boot',
          fields: <String, Object?>{
            'frame': '${window.size.width}x${window.size.height}',
            'content':
                '${window.contentSize.width}x${window.contentSize.height}',
            'minimum':
                '${window.minimumSize.width}x${window.minimumSize.height}',
            'durMs': stopwatch.elapsedMilliseconds,
          },
        );
      }
    } catch (error, stackTrace) {
      log.warn(
        'window configure failed',
        tag: 'boot',
        error: error,
        stackTrace: stackTrace,
      );
    }

    try {
      if (window != null) {
        // Always restore opacity, even when the configuration above failed.
        if (window.isMinimized) {
          window.restore();
        }
        window.opacity = 1;
        window.show();
        window.focus();
      }
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
      child: ValueListenableBuilder<AppLanguage>(
        valueListenable: _language,
        builder: (context, language, _) {
          return ValueListenableBuilder<ThemeMode>(
            valueListenable: _themeMode,
            builder: (context, themeMode, _) => MaterialApp(
              navigatorKey: Catcher2.navigatorKey,
              title: 'SSB Runner',
              locale: appLanguageLocale(language),
              localeListResolutionCallback: resolveAppLocale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) {
                AppL10n.update(AppLocalizations.of(context));
                return child ?? const SizedBox.shrink();
              },
              theme: AppTheme.light,
              darkTheme: AppTheme.dark,
              themeMode: themeMode,
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
                  // No `load()` here: the first frame must only paint the
                  // splash. `_BootGate` starts the IO after it.
                  create: (context) => _MainAppCubit(
                    language: _language,
                    themeMode: _themeMode,
                    audio: _audio,
                    exitSignal: _exitSignal,
                  ),
                  child: _BootGate(
                    geometry: _geometry,
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
                                child: const Center(
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            case _Ready(:final deps):
                              return HomePage(settings: deps.settings);
                            case _Failed(:final message):
                              return _StartupFailure(message: message);
                          }
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _geometry.dispose();
    _listener.dispose();
    _language.dispose();
    _themeMode.dispose();
    super.dispose();
  }
}

/// Starts the IO that used to run in `main()` once the first frame is on
/// screen.
///
/// Sits below `MultiRepositoryProvider` and inside `BlocProvider`, so it can
/// read the dependencies without touching them in `initState`.
class _BootGate extends StatefulWidget {
  const _BootGate({required this.geometry, required this.child});

  final WindowGeometryController geometry;
  final Widget child;

  @override
  State<_BootGate> createState() => _BootGateState();
}

class _BootGateState extends State<_BootGate> {
  @override
  void initState() {
    super.initState();
    // Only register the callback here: `_MainAppState` registered its
    // reveal callback first, so the window is opaque before this runs.
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_start()));
  }

  Future<void> _start() async {
    try {
      await bootstrapLoggingAfterFirstFrame();
    } catch (error, stackTrace) {
      // File logging is optional; the app must start without it. This record
      // still reaches the in-memory buffer.
      log.error(
        'logging bootstrap failed',
        tag: 'boot',
        error: error,
        stackTrace: stackTrace,
      );
    }

    if (!mounted) {
      return;
    }

    await context.read<_MainAppCubit>().load(
      dxccManager: context.read(),
      callsignLoader: context.read(),
      onSettingsReady: widget.geometry.attach,
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _AppDeps {
  final AppSettings settings;

  /// Non-fatal problem to surface once the main page is up.
  final String? warning;

  _AppDeps({required this.settings, this.warning});
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

/// Set once the platform asked the app to exit.
///
/// The boot sequence reads it between steps, so a close during startup stops
/// dispatching new work instead of racing the exit path.
class _ExitSignal {
  bool requested = false;
}

class _MainAppCubit extends Cubit<_AppState> {
  final ValueNotifier<AppLanguage> _language;
  final ValueNotifier<ThemeMode> _themeMode;

  /// Shared with `_MainAppState` so the exit path can tell whether the audio
  /// initialisation already settled.
  final AudioInitTracker _audio;

  /// Shared with `_MainAppState` so a close during startup stops the sequence.
  final _ExitSignal _exitSignal;

  _MainAppCubit({
    required this._language,
    required this._themeMode,
    required this._audio,
    required this._exitSignal,
  }) : super(const _Loading());

  Future<void> load({
    required DxccManager dxccManager,
    required CallsignLoader callsignLoader,
    void Function(AppSettings settings)? onSettingsReady,
  }) async {
    final warnings = <String>[];

    // Layer ⑤ of docs/design/desktop_exit_design.md §4.5: once a close arrived,
    // no further startup work is dispatched. The checks sit between steps only,
    // so the audio start below keeps its place and concurrency.
    bool aborted() => _exitSignal.requested;

    try {
      if (aborted()) {
        return;
      }

      // Started first, awaited before `_Ready`: the engine takes 80-165 ms and
      // must be up before the first voice segment is played. The tracker wraps
      // this call in place; it must not delay or serialize the start.
      final audioReady = _audio.start(
        () => boot.step('soloud_init', _initAudio),
      );

      final prefs = await boot.step(
        'prefs_ready',
        () => SharedPreferencesWithCache.create(
          cacheOptions: SharedPreferencesWithCacheOptions(),
        ),
      );
      if (aborted()) {
        return;
      }

      final settings = AppSettings(
        prefs: prefs,
        languageNotifier: _language,
        themeModeNotifier: _themeMode,
      );

      // The earliest point at which the saved window size can be known: the
      // prefs cache is loaded, so this adds no IO before the first frame.
      onSettingsReady?.call(settings);

      // Apply the persisted verbosity choice as early as possible.
      log.setVerbose(settings.verboseLogging);

      await boot.step(
        'worker_manager_init',
        () => workerManager.init(dynamicSpawning: true),
      );
      if (aborted()) {
        return;
      }

      // Resolve the database folder before drift opens it: the result reports
      // whether the history could be carried over from older versions.
      final database = await boot.step('db_ready', ensureDatabaseReady);
      if (database.warning != null) {
        warnings.add(database.warning!);
      }
      if (aborted()) {
        return;
      }

      try {
        await boot.step('dxcc_loaded', dxccManager.loadDxcc);
      } catch (_) {
        // BootTrace logged the error already. Callsign lookups stay disabled
        // rather than keeping the whole app from starting.
        warnings.add('Callsign lookups are unavailable.');
      }
      if (aborted()) {
        return;
      }

      await boot.step('callsign_loaded', callsignLoader.loadCallsigns);
      if (aborted()) {
        return;
      }

      await audioReady;
      if (aborted()) {
        return;
      }

      // Stops the native startup heartbeat: everything below is runtime.
      boot.markReady();
      emit(
        _Ready(
          _AppDeps(
            settings: settings,
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
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 16),
              Text(l10n.startupFailedTitle),
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
                    child: Text(l10n.copyDiagnostics),
                  ),
                  FilledButton(
                    onPressed: () => exportDiagnosticArchive(context),
                    child: Text(l10n.exportLogs),
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
