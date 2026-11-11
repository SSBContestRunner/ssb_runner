import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:ssb_runner/audio/audio_init_tracker.dart';
import 'package:ssb_runner/logging/app_logger.dart';
import 'package:ssb_runner/logging/boot_trace.dart';
import 'package:ssb_runner/ui/main_app/exit_flow.dart';

/// Answers the desktop exit request with a hard bound.
///
/// The Windows runner tears the FlutterEngine down synchronously inside
/// WM_DESTROY and only then posts WM_QUIT. If any teardown step blocks, the
/// window is already gone but the message loop never quits, leaving an idle
/// process in Task Manager. The timer therefore only fires when the bounded
/// cleanup (3.5 s worst case) hangs; on the normal path the process is gone.
///
/// Invariant (docs/design/desktop_exit_design.md §3): `AppExitResponse.exit` is
/// only answered when the audio engine is either never initialised or fully
/// disposed. Any other state ends in a forced termination instead, because
/// `ExitProcess` runs the plugin's DLL detach and that wait can be permanent
/// once the Dart VM is gone.
Future<AppExitResponse> handlePlatformExitRequest({
  required AudioInitTracker audio,
  required AsyncAction stopAudioMonitor,
  required AsyncAction deinitAudio,
  required AsyncAction flushLogs,
  required ExitCleanupErrorHandler onError,
}) async {
  _trace('enter');
  Timer(const Duration(seconds: 5), _forceExit);

  // CI only: keeps the request unanswered so the smoke test can prove that
  // the fallback above ends the process on its own.
  if (Platform.environment['SSB_RUNNER_TEST_EXIT_HANG'] == '1') {
    await Completer<void>().future;
  }

  log.info('exit requested', tag: 'exit');
  _trace('logged');

  // Stop probing before the engine is torn down, so no platform read can run
  // concurrently with `deinitAsync()`.
  await stopAudioMonitor();
  _trace('audio_monitor_stopped');

  // 1) Let an in-flight initialisation settle (normally 28-411 ms). Closing the
  // window inside that window used to skip the deinit and answer `exit`, which
  // hangs inside ExitProcess (mechanism B in the design doc).
  final settled = await audio.settledWithin(const Duration(seconds: 2));
  _trace(settled ? 'settled' : 'settled_timeout');
  if (!settled) {
    return _hardExit(
      'hard_exit_init_running',
      flushLogs: flushLogs,
      onError: onError,
    );
  }

  // 2) Always dispose, bounded, whether the engine is running, never
  // initialised or failed to initialise; see §4.1 for why no state is allowed
  // to skip this.
  final disposed = await runBoundedExitCleanup(
    deinitAudio: deinitAudio,
    flushLogs: flushLogs,
    onError: onError,
  );
  _trace(disposed ? 'deinit_done' : 'deinit_unfinished');
  if (!disposed) {
    return _hardExit(
      'hard_exit_deinit_unfinished',
      flushLogs: flushLogs,
      onError: onError,
    );
  }

  _trace('answering_exit');
  return AppExitResponse.exit;
}

/// Ends the process without answering the exit request.
///
/// Used when the engine cannot be brought to a settled, disposed state.
/// `exit()` would enter `ExitProcess` and its DLL detach, which is exactly
/// where the process hangs; `Process.killPid` skips CRT and DLL teardown.
/// Logs are flushed first so the trace survives the termination.
Future<AppExitResponse> _hardExit(
  String reason, {
  required AsyncAction flushLogs,
  required ExitCleanupErrorHandler onError,
}) async {
  _trace(reason);
  await runBoundedExitStep(
    step: 'log flush',
    action: flushLogs,
    timeout: const Duration(milliseconds: 500),
    onError: onError,
  );
  if (!Process.killPid(pid)) {
    exit(1);
  }
  // The process is being terminated; never answer the request.
  return Completer<AppExitResponse>().future;
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
  _trace('fallback_fired');
  log.warn('exit fallback fired', tag: 'exit');
  if (Process.killPid(pid)) {
    return;
  }
  exit(0);
}

/// Appends one line to the exit trace, written synchronously.
///
/// The app logger is buffered, so nothing it wrote after this point survives a
/// process that hangs inside engine teardown. This file is created next to the
/// native startup timeline (`--boot-trace-dir`) and never throws.
void _trace(String mark) {
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

/// Desktop processes are terminated by the platform, so there is no page
/// lifecycle to hook.
void installPlatformExitHooks({required AsyncAction onPageHide}) {}
