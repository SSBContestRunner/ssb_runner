import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:catcher_2/catcher_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssb_runner/audio/audio_init_tracker.dart';
import 'package:ssb_runner/audio/audio_loader.dart';
import 'package:ssb_runner/audio/audio_player.dart';
import 'package:ssb_runner/callsign/callsign_loader.dart';
import 'package:ssb_runner/db/app_database.dart';
import 'package:ssb_runner/db/database_bootstrap.dart';
import 'package:ssb_runner/db/history_maintenance.dart';
import 'package:ssb_runner/dxcc/dxcc_manager.dart';
import 'package:ssb_runner/l10n/app_l10n.dart';
import 'package:ssb_runner/l10n/generated/app_localizations.dart';
import 'package:ssb_runner/l10n/locale_resolution.dart';
import 'package:ssb_runner/logging/app_logger.dart';
import 'package:ssb_runner/logging/boot_trace.dart';
import 'package:ssb_runner/logging/logging_bootstrap.dart';
import 'package:ssb_runner/platform/audio/audio_bootstrap.dart';
import 'package:ssb_runner/platform/audio/audio_monitor_ui.dart';
import 'package:ssb_runner/platform/capabilities.dart';
import 'package:ssb_runner/platform/database/database_health.dart';
import 'package:ssb_runner/platform/exit/exit_port.dart';
import 'package:ssb_runner/platform/multi_tab/multi_tab_monitor.dart';
import 'package:ssb_runner/platform/multi_tab/multi_tab_status.dart';
import 'package:ssb_runner/platform/restart/restart_app.dart';
import 'package:ssb_runner/platform/window/window_port.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/ui/diagnostics_actions.dart';
import 'package:ssb_runner/ui/main_app/home_page.dart';
import 'package:ssb_runner/ui/main_app/window_geometry.dart';
import 'package:ssb_runner/ui/theme/app_theme.dart';
import 'package:toastification/toastification.dart';
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

  /// One database instance for the whole app: the provider, the startup health
  /// probe and the history backup entry all share it.
  late final AppDatabase _database = AppDatabase();

  /// Toasts are only shown once the overlay exists.
  bool _uiReady = false;

  /// Owned here so the MaterialApp can rebuild when the language changes.
  final ValueNotifier<AppLanguage> _language = ValueNotifier(AppLanguage.auto);

  /// Owned here so the MaterialApp can rebuild when the theme changes.
  final ValueNotifier<ThemeMode> _themeMode = ValueNotifier(ThemeMode.light);

  /// Restores the saved window size after prefs load and records later
  /// resizes. The window itself is configured in [revealWindow].
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
    installPlatformExitHooks(onPageHide: deinitializeAudioForExit);
    startMultiTabMonitor();

    storagePressureRevision.addListener(_showStoragePressureWarning);
    backupReminderRevision.addListener(_showBackupReminder);
    multiTabRevision.addListener(_showMultiTabWarning);

    // The window is hidden until the first frame is on screen, so it appears
    // straight into the loading view instead of as a blank window.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      boot.markFirstFrame();
      _uiReady = true;
      unawaited(revealWindow());
      log.info(
        'first frame visible',
        tag: 'boot',
        fields: <String, Object?>{
          'sinceProcessMs': boot.sinceProcessMs,
          'sinceMainMs': boot.elapsedMs,
        },
      );
    });

    scheduleTestWindowClose();
  }

  /// Last line of defence for "the window closed but the process stays".
  ///
  /// The bounded cleanup, the audio settle step and the force-exit fallback live
  /// in the desktop exit port; the browser only gets best-effort pagehide
  /// cleanup.
  Future<AppExitResponse> _handleExitRequest() {
    _exitSignal.requested = true;

    // A resize within the last 500ms may still be debounced.
    _geometry.flush();
    return handlePlatformExitRequest(
      audio: _audio,
      stopAudioMonitor: () async => stopAudioMonitor(),
      deinitAudio: deinitializeAudioForExit,
      flushLogs: flushLogs,
      onError: (step, error, stackTrace) => log.warn(
        '$step failed',
        tag: 'exit',
        error: error,
        stackTrace: stackTrace,
      ),
    );
  }

  void _showStoragePressureWarning() {
    _showMaintenanceWarning(
      AppL10n.current.storageAlmostFull,
      AppL10n.current.storageBackupHint,
    );
  }

  void _showBackupReminder() {
    // The reminder is a web storage concern; desktop history is a normal file.
    if (!PlatformCapabilities.isWeb) {
      return;
    }
    _showMaintenanceWarning(
      AppL10n.current.historyBackupReminder,
      AppL10n.current.storageBackupHint,
    );
  }

  void _showMultiTabWarning() {
    _showMaintenanceWarning(AppL10n.current.multiTabWarning, null);
  }

  void _showMaintenanceWarning(String title, String? description) {
    if (!_uiReady) {
      return;
    }
    toastification.show(
      title: Text(title),
      description: description == null ? null : Text(description),
      autoCloseDuration: const Duration(seconds: 8),
      type: ToastificationType.warning,
      style: ToastificationStyle.fillColored,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      // The browser only allows audio to start inside a user gesture, so the
      // first click anywhere unlocks the engine instead of waiting for the run
      // button to do it.
      onPointerDown: (_) {
        if (!initializesAudioAtStartup) {
          unawaited(ensureAudioInitialized());
        }
      },
      child: ToastificationWrapper(
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
                    RepositoryProvider<AppDatabase>.value(value: _database),
                    RepositoryProvider(create: (context) => AudioLoader()),
                    RepositoryProvider(create: (context) => AudioPlayer()),
                    RepositoryProvider(create: (context) => CallsignLoader()),
                    RepositoryProvider(
                      create: (context) =>
                          DxccManager(database: context.read()),
                    ),
                  ],
                  child: wrapWithAudioMonitor(
                    BlocProvider(
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

                            // The overlay may not be mounted yet when startup
                            // finishes before the first frame.
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
                                case _Failed(
                                  :final message,
                                  :final retryable,
                                  :final storage,
                                ):
                                  return _StartupFailure(
                                    message: message,
                                    retryable: retryable,
                                    storage: storage,
                                    onRetry: restartApplication,
                                  );
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    disposeAudioMonitor();
    _geometry.dispose();
    storagePressureRevision.removeListener(_showStoragePressureWarning);
    backupReminderRevision.removeListener(_showBackupReminder);
    multiTabRevision.removeListener(_showMultiTabWarning);
    unawaited(_database.close());
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

    final cubit = context.read<_MainAppCubit>();
    await cubit.load(
      database: context.read(),
      dxccManager: context.read(),
      callsignLoader: context.read(),
      // Desktop window controls do not exist in the browser.
      onSettingsReady: PlatformCapabilities.hasNativeWindow
          ? widget.geometry.attach
          : null,
    );

    // Only a complete boot starts the monitor: a failed start or an abort by
    // the exit path leaves it off (design §4.1.1).
    if (!mounted || cubit.state is! _Ready) {
      return;
    }
    startAudioMonitor();
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
  const _Failed(this.message, {this.retryable = false, this.storage = false});

  final String message;

  /// Whether the page offers a reload. Only web storage failures do.
  final bool retryable;

  /// Whether the failure is about history storage, so the page can explain it
  /// instead of showing a raw driver error.
  final bool storage;
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
    required AppDatabase database,
    required DxccManager dxccManager,
    required CallsignLoader callsignLoader,
    bool Function(AppSettings settings)? onSettingsReady,
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
      // this call in place so the exit path can wait for a settled engine; the
      // browser only allows audio after a user gesture and starts on click.
      final audioReady = initializesAudioAtStartup
          ? _audio.start(
              () => boot.step('soloud_init', ensureAudioInitialized),
            )
          : Future<void>.value();

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
      // Window geometry is optional; a system where the native window manager
      // cannot load keeps running without size restore and resize memory.
      if (onSettingsReady?.call(settings) == false) {
        warnings.add(AppL10n.current.windowGeometryUnavailable);
      }

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
      final bootstrap = await boot.step('db_ready', ensureDatabaseReady);
      if (bootstrap.warning != null) {
        warnings.add(bootstrap.warning!);
      }

      // On the web a WASM failure must not silently continue with an in-memory
      // database: that would lose history on refresh. The probe makes the
      // failure explicit and the page offers a reload. A stuck worker becomes
      // the same retryable page instead of leaving the loading spinner up.
      final health = await boot.step(
        'db_health',
        () => verifyDatabaseHealth(database).timeout(
          const Duration(seconds: 10),
          onTimeout: () => const DatabaseHealth(
            error: 'database open timed out',
            persistent: false,
          ),
        ),
      );
      if (!health.ok) {
        log.error(
          'database is not usable for history',
          tag: 'db',
          fields: <String, Object?>{
            'error': health.error,
            'implementation': health.implementation,
            'persistent': health.persistent,
          },
        );
        emit(
          _Failed(
            health.error!,
            retryable: PlatformCapabilities.isWeb,
            storage: true,
          ),
        );
        return;
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
}

/// Reports a non-fatal startup problem, such as the history not being where the
/// user expects it, without keeping the app from running.
void _showStartupWarning(String message) {
  toastification.show(
    title: Text(AppL10n.current.startupWarningTitle),
    description: Text(message),
    type: ToastificationType.warning,
    style: ToastificationStyle.fillColored,
    autoCloseDuration: const Duration(seconds: 10),
  );
}

class _StartupFailure extends StatelessWidget {
  const _StartupFailure({
    required this.message,
    required this.retryable,
    required this.storage,
    required this.onRetry,
  });

  final String message;
  final bool retryable;
  final bool storage;
  final Future<void> Function() onRetry;

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
              Text(
                storage ? l10n.startupStorageFailed : message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              SelectableText(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  if (retryable)
                    FilledButton.icon(
                      onPressed: () => onRetry(),
                      icon: const Icon(Icons.refresh),
                      label: Text(l10n.retry),
                    ),
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
