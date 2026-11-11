import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Requests fullscreen and locks the function keys.
///
/// Must be called from the click that starts the run: both APIs require a user
/// gesture. Returns whether fullscreen was granted; a refusal is not fatal and
/// the caller falls back to the on-screen buttons.
Future<bool> enterTrainingInputMode() async {
  try {
    final element = web.document.documentElement;
    if (element == null) {
      return false;
    }

    await element.requestFullscreen().toDart;
    await _lockFunctionKeys();
    return web.document.fullscreenElement != null;
  } catch (_) {
    return false;
  }
}

Future<void> _lockFunctionKeys() async {
  try {
    final keyboard = (web.window.navigator as JSObject).getProperty<JSObject?>(
      'keyboard'.toJS,
    );
    if (keyboard == null) {
      return;
    }

    final keys = <JSString>[
      for (var index = 1; index <= 12; index++) 'F$index'.toJS,
    ].toJS;
    await keyboard.callMethod<JSPromise<JSAny?>>('lock'.toJS, keys).toDart;
  } catch (_) {
    // Keyboard Lock is Chrome/Edge only; the fallback is the screen buttons.
  }
}

Future<void> leaveTrainingInputMode() async {
  try {
    final keyboard = (web.window.navigator as JSObject).getProperty<JSObject?>(
      'keyboard'.toJS,
    );
    keyboard?.callMethod<JSAny?>('unlock'.toJS);
  } catch (_) {
    // Nothing to release.
  }

  try {
    if (web.document.fullscreenElement != null) {
      await web.document.exitFullscreen().toDart;
    }
  } catch (_) {
    // The browser may have already left fullscreen (Esc).
  }
}

JSFunction? _keyGuard;

/// Blocks the browser defaults for keys the app owns during a run.
///
/// Only Space (page scroll) and Tab (browser focus traversal) are consumed;
/// reserved keys such as F5, F11 and F12 are left to the browser. The listener
/// does not stop propagation, so Flutter still receives the key event.
void installTrainingKeyGuard() {
  if (_keyGuard != null) {
    return;
  }

  _keyGuard = ((web.KeyboardEvent event) {
    if (event.key == ' ' || event.key == 'Tab') {
      event.preventDefault();
    }
  }).toJS;
  web.window.addEventListener('keydown', _keyGuard);
}

void removeTrainingKeyGuard() {
  final guard = _keyGuard;
  if (guard == null) {
    return;
  }
  _keyGuard = null;
  web.window.removeEventListener('keydown', guard);
}
