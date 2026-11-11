import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:nativeapi/nativeapi.dart' show DisplayManager;
import 'package:ssb_runner/logging/app_logger.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:window_manager/window_manager.dart';

/// Layout acceptance baseline: the *content* area that keeps every screen
/// whole at 5 languages x textScale 1.0/1.3.
///
/// Width: the read-only RST cell is 1/9 of the QSO row. With the 10dp text
/// inset, 1084 shows 30.5dp of text, which is 1.1dp short of the 31.6dp `59`
/// needs at textScale 1.3; the three-digit sent exchange needs 47.1dp and gets
/// 46.1dp there. 1108 shows 32.9dp and 49.8dp, so both cells are whole at
/// every supported scale.
///
/// Height: with the single-row resume strip the session card does not scroll
/// in any of running / armed replay / paused / resuming at 5 languages x
/// textScale 1.0/1.3, measured at content 768 already; 772 keeps 4dp of
/// headroom. The wide layout is therefore the only form.
///
/// The native runners create the window with this same content size, so the
/// post-frame geometry calls are no-ops and the first frame is final.
const Size kMinWindowContentSize = Size(1108, 772);

/// Content size + platform non-client area = window frame size.
///
/// The chrome is measured at runtime (`window.size - window.contentSize`) so
/// no platform title-bar height is hard-coded.
Size minimumFrameFor(Size content, Size chrome) =>
    Size(content.width + chrome.width, content.height + chrome.height);

/// Raises a saved size to the minimum content area and caps it at the primary
/// display's work area.
Size clampWindowContentSize(Size saved, Size minimum, Size? workArea) {
  var width = max(saved.width, minimum.width);
  var height = max(saved.height, minimum.height);
  if (workArea != null) {
    width = min(width, workArea.width);
    height = min(height, workArea.height);
  }
  return Size(width, height);
}

/// Resolves the app's own window.
///
/// `getCurrent()` is based on `GetActiveWindow()` on Windows, which returns
/// null while the window has not been shown or activated. `getAll()` only
/// enumerates this process's top-level windows, so a single-window app has
/// exactly one candidate; anything else is not guessed.
Window? resolveAppWindow() {
  final current = WindowManager.instance.getCurrent();
  if (current != null) return current;

  final all = WindowManager.instance.getAll();
  if (all.length == 1) return all.first;

  log.warn(
    'window not resolved',
    tag: 'boot',
    fields: <String, Object?>{'candidates': all.length},
  );
  return null;
}

/// Applies the minimum *content* size to [window].
///
/// Order matters:
/// 1. measure `frame - content` first, so the current DPI's non-client area is
///    used instead of a written-down macOS/Windows offset;
/// 2. write the content size before the frame minimum, otherwise Windows can
///    clamp the window to the old `WM_GETMINMAXINFO` minimum;
/// 3. center last, so a cross-DPI monitor move cannot precede the resize.
void applyWindowGeometry(Window window) {
  final frame = window.size.toSize();
  final content = window.contentSize.toSize();
  final chrome = Size(
    frame.width - content.width,
    frame.height - content.height,
  );

  window.contentSize = kMinWindowContentSize.toNative();
  window.minimumSize = minimumFrameFor(
    kMinWindowContentSize,
    chrome,
  ).toNative();
  window.center();
}

/// Restores the saved content size once prefs are ready and tracks later user
/// resizes.
///
/// The saved value is read from [AppSettings], which is already backed by the
/// `prefs_ready` cache, so restoring adds no IO before the first frame. A value
/// that differs from the default costs exactly one post-reveal resize.
class WindowGeometryController {
  Window? _window;
  ListenerId? _listenerId;
  Timer? _saveDebounce;
  AppSettings? _settings;
  Size? _lastSaved;

  /// Called once prefs are ready: restores the saved content size, then starts
  /// tracking user resizes.
  void attach(AppSettings settings) {
    _settings = settings;

    final window = resolveAppWindow();
    if (window == null) return;
    _window = window;

    final saved = settings.windowContentSize;
    if (saved != null) {
      final workArea = DisplayManager.instance.getPrimary()?.workArea;
      final target = clampWindowContentSize(
        saved,
        kMinWindowContentSize,
        workArea == null ? null : Size(workArea.width, workArea.height),
      );
      if (target != window.contentSize.toSize()) {
        window.contentSize = target.toNative();
        window.center();
      }
      _lastSaved = target;
      log.info(
        'window size restored',
        tag: 'boot',
        fields: <String, Object?>{
          'saved': '${saved.width}x${saved.height}',
          'applied': '${target.width}x${target.height}',
        },
      );
    }

    _listenerId = window.addListener(_onWindowEvent);
  }

  void _onWindowEvent(WindowEvent event) {
    if (event is! WindowResizedEvent) return;
    final window = _window;
    if (window == null) return;
    // Maximized / full-screen / minimized sizes are not the size the operator
    // chose for the normal state.
    if (window.isMaximized || window.isFullScreen || window.isMinimized) {
      return;
    }

    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 500), _saveNow);
  }

  void _saveNow() {
    final window = _window;
    final settings = _settings;
    if (window == null || settings == null) return;
    if (window.isMaximized || window.isFullScreen || window.isMinimized) {
      return;
    }

    final size = window.contentSize.toSize();
    if (size.width < kMinWindowContentSize.width ||
        size.height < kMinWindowContentSize.height) {
      return;
    }
    if (size == _lastSaved) return;
    _lastSaved = size;
    settings.saveWindowContentSize(size);
  }

  /// Writes a still-debounced value before the app exits.
  void flush() {
    _saveDebounce?.cancel();
    _saveDebounce = null;
    _saveNow();
  }

  void dispose() {
    _saveDebounce?.cancel();
    final window = _window;
    final listenerId = _listenerId;
    if (window != null && listenerId != null) {
      window.removeListener(listenerId);
    }
    _listenerId = null;
    _window = null;
    _settings = null;
    _lastSaved = null;
  }
}
