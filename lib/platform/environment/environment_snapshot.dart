/// Platform facts recorded at startup and in the diagnostic export.
///
/// [headerLines] are `key=value` lines reused verbatim in the session header, so
/// the log file and the exported summary describe the same environment.
/// [fields] is the structured form written into the log.
class EnvironmentSnapshot {
  const EnvironmentSnapshot({required this.headerLines, required this.fields});

  final List<String> headerLines;
  final Map<String, Object?> fields;
}
