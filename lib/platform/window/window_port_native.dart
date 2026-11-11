import 'dart:async';
import 'dart:io';

import 'package:ssb_runner/logging/app_logger.dart';
import 'package:ssb_runner/ui/main_app/window_geometry.dart';
import 'package:window_manager/window_manager.dart';

/// Keeps the window invisible until the first frame is painted.
///
/// This does not call `windowManager.hide()`: on macOS the window is the only
/// one, and the runner's `applicationShouldTerminateAfterLastWindowClosed`
/// returns true, so ordering it out quits the app. A fully transparent window
/// stays "visible" and therefore does not terminate, while still drawing no
/// white frame. [revealWindow] makes it opaque again after the first frame.
Future<void> hideWindowUntilFirstFrame() async {
  try {
    final window = WindowManager.instance.getCurrent();
    window?.opacity = 0;
  } catch (error, stackTrace) {
    log.warn(
      'window hide failed',
      tag: 'boot',
      error: error,
      stackTrace: stackTrace,
    );
  }
}

/// Applies the minimum content size and shows the window.
Future<void> revealWindow() async {
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
          'content': '${window.contentSize.width}x${window.contentSize.height}',
          'minimum': '${window.minimumSize.width}x${window.minimumSize.height}',
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

/// CI only: closes the window the way a user does, so the macOS and Linux
/// smoke tests can assert that closing it ends the process.
///
/// Neither platform can be closed from the outside in a CI session: macOS
/// would need Accessibility/automation permissions, and the Linux container
/// has no window manager to deliver a close request. window_manager's
/// `close()` is `[NSWindow performClose]` / `gtk_window_close`, i.e. the same
/// native path as clicking the close button.
void scheduleTestWindowClose() {
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
