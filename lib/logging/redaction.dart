/// Path redaction shared by the native and web logging backends.
///
/// The patterns are platform-neutral: browser builds have no home directory,
/// and the native backend additionally registers the exact values exposed by
/// `Platform.environment` so sandboxed releases are covered too.
final RegExp _posixHomePattern = RegExp(r'/(?:Users|home)/[^/\s]+');
final RegExp _windowsHomePattern = RegExp(r'[A-Za-z]:[\\/]Users[\\/][^\\/\s]+');

Set<String> _homeCandidates = <String>{};

/// Registers the concrete home directories of the current process.
void configureHomeCandidates(Iterable<String> candidates) {
  _homeCandidates = <String>{
    for (final candidate in candidates)
      if (candidate.isNotEmpty) candidate,
  };
}

String _replaceHome(String text) {
  var redacted = text;
  for (final candidate in _homeCandidates) {
    redacted = redacted
        .replaceAll(candidate.replaceAll('\\', '/'), '~')
        .replaceAll(candidate, '~');
  }
  return redacted;
}

/// Replaces the user home directory prefix with a tilde.
String redactPath(String path) {
  if (path.isEmpty) {
    return path;
  }

  return _replaceHome(path)
      .replaceFirst(_posixHomePattern, '~')
      .replaceFirst(_windowsHomePattern, '~');
}

/// Redacts user-home prefixes anywhere in [text], including log messages that
/// embed paths inside a field value.
String redactText(String text) {
  if (text.isEmpty) {
    return text;
  }

  return _replaceHome(text)
      .replaceAll(_posixHomePattern, '~')
      .replaceAll(_windowsHomePattern, '~');
}
