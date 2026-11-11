/// A resolved, writable location for log files.
///
/// Browser builds have no filesystem, so the value only exists natively; the
/// diagnostic summary no longer depends on it and asks the log source instead.
class LogLocation {
  const LogLocation({required this.path, required this.fallbackIndex});

  final String path;
  final int fallbackIndex;
}
