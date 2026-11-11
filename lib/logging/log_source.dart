/// One log file inside the diagnostic archive.
class LogFileContents {
  const LogFileContents({required this.name, required this.bytes});

  final String name;
  final List<int> bytes;
}

/// Content the diagnostic export and the summary read from the active backend.
///
/// The native implementation reads the rotating file on disk; the web
/// implementation reads the in-memory diagnostic buffer.
abstract interface class LogSource {
  /// All lines of the current log, oldest first.
  Future<List<String>> latestLogLines();

  /// Files to place under `logs/` in the exported archive.
  Future<List<LogFileContents>> logFiles();
}
