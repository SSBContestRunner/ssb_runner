import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Whether the browser is currently delivering characters to Flutter's hidden
/// text input element.
///
/// The web build has two focus systems: the Flutter `FocusNode` graph and the
/// DOM. Flutter can report a focused `TextField` while `document.activeElement`
/// is the canvas, and every character typed in that state is dropped without an
/// error. This is the DOM half of that check.
bool get isTextInputDomFocused {
  final active = web.document.activeElement;
  return active.isA<web.HTMLInputElement>() ||
      active.isA<web.HTMLTextAreaElement>();
}

/// One-line DOM focus snapshot for the diagnostic export.
String? inputFocusSnapshot() {
  final document = web.document;
  final active = document.activeElement;
  final editingHost = document.querySelector('flt-text-editing-host');

  return 'document_has_focus=${document.hasFocus()} '
      'visibility=${document.visibilityState} '
      'active_element=${active?.tagName ?? 'none'} '
      'text_editing_host=${editingHost != null} '
      'text_input_focused=$isTextInputDomFocused';
}

void Function()? _onFocusOpportunity;
JSFunction? _focusHandler;
JSFunction? _visibilityHandler;
JSFunction? _pointerHandler;

/// Reports moments when DOM focus may have moved without Flutter noticing:
/// the window regaining focus, the tab becoming visible, and pointer releases.
///
/// None of these events guarantee drift, so the listener only hands the UI a
/// chance to verify and repair it.
void installTextInputFocusWatch(void Function() onFocusOpportunity) {
  _onFocusOpportunity = onFocusOpportunity;
  if (_focusHandler != null) {
    return;
  }

  _focusHandler = (() => _onFocusOpportunity?.call()).toJS;
  _visibilityHandler = (() {
    if (web.document.visibilityState == 'visible') {
      _onFocusOpportunity?.call();
    }
  }).toJS;
  _pointerHandler = (() => _onFocusOpportunity?.call()).toJS;

  web.window.addEventListener('focus', _focusHandler);
  web.window.addEventListener('pointerup', _pointerHandler);
  web.document.addEventListener('visibilitychange', _visibilityHandler);
}

void removeTextInputFocusWatch() {
  final focusHandler = _focusHandler;
  final visibilityHandler = _visibilityHandler;
  final pointerHandler = _pointerHandler;
  _focusHandler = null;
  _visibilityHandler = null;
  _pointerHandler = null;
  _onFocusOpportunity = null;

  if (focusHandler != null) {
    web.window.removeEventListener('focus', focusHandler);
  }
  if (pointerHandler != null) {
    web.window.removeEventListener('pointerup', pointerHandler);
  }
  if (visibilityHandler != null) {
    web.document.removeEventListener('visibilitychange', visibilityHandler);
  }
}
