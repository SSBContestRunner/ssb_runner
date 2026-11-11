import 'dart:async';
import 'dart:js_interop';
import 'dart:ui' show AppExitResponse;

import 'package:web/web.dart' as web;

import 'package:ssb_runner/audio/audio_init_tracker.dart';
import 'package:ssb_runner/ui/main_app/exit_flow.dart';

/// The browser never asks the app to exit; the page is simply unloaded.
///
/// Cleanup still runs so a pagehide during a session stops the audio device,
/// but the process is not ours to end. There is no system audio monitor and no
/// native teardown to wait for, so those steps are skipped.
Future<AppExitResponse> handlePlatformExitRequest({
  required AudioInitTracker audio,
  required AsyncAction stopAudioMonitor,
  required AsyncAction deinitAudio,
  required AsyncAction flushLogs,
  required ExitCleanupErrorHandler onError,
}) async {
  await stopAudioMonitor();
  await runBoundedExitCleanup(
    deinitAudio: deinitAudio,
    flushLogs: flushLogs,
    onError: onError,
  );
  return AppExitResponse.exit;
}

/// Best-effort cleanup when the page is unloaded.
///
/// Async work cannot be guaranteed to finish once the page is going away, so
/// this is not treated as a save guarantee; it only releases the audio device.
void installPlatformExitHooks({required AsyncAction onPageHide}) {
  web.window.addEventListener(
    'pagehide',
    ((web.Event _) {
      unawaited(onPageHide());
    }).toJS,
  );
}
