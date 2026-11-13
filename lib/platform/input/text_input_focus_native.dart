/// Native platforms route characters through the platform text input, so the
/// UI may always treat the text input as attached.
bool get isTextInputDomFocused => true;

/// Web-only DOM focus facts; native builds have nothing to report.
String? inputFocusSnapshot() => null;

/// Focus opportunities only exist on the web.
void installTextInputFocusWatch(void Function() onFocusOpportunity) {}

void removeTextInputFocusWatch() {}
