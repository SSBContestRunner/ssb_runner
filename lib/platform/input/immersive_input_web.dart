import 'dart:js_interop';

import 'package:web/web.dart' as web;

JSFunction? _keyGuard;

/// Blocks the browser defaults for keys the app owns during a run.
///
/// The app deliberately does not enter fullscreen, so the Keyboard Lock API
/// (Chrome/Edge only, and only honoured in fullscreen) is not available and
/// this guard is the fallback. F1–F12 are consumed so the browser does not
/// reload the page (F5), open help (F1) or scroll; reserved system shortcuts
/// such as F11 and F12 may still be handled by the browser, which no page can
/// override outside fullscreen. Space (page scroll) and Tab (focus traversal)
/// are consumed too. The listener does not stop propagation, so Flutter still
/// receives the key event and the app-level pause gate keeps deciding whether
/// a shortcut has any effect.
void installTrainingKeyGuard() {
  if (_keyGuard != null) {
    return;
  }

  _keyGuard = ((web.KeyboardEvent event) {
    if (_isFunctionKey(event.key) || event.key == ' ' || event.key == 'Tab') {
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

bool _isFunctionKey(String key) {
  if (key.length < 2 || key.length > 3 || !key.startsWith('F')) {
    return false;
  }
  final number = int.tryParse(key.substring(1));
  return number != null && number >= 1 && number <= 12;
}
