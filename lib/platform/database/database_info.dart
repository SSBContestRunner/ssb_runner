/// What the database layer needs to open storage, plus anything the UI should
/// tell the user about history not being where they expect it.
class DatabaseBootstrap {
  const DatabaseBootstrap({
    required this.directory,
    required this.path,
    required this.fallbackIndex,
    this.migratedFrom,
    this.warning,
    this.implementation = 'native-file',
    this.persistent = true,
    this.quota,
    this.usage,
  });

  const DatabaseBootstrap.inMemory({required this.warning})
    : directory = null,
      path = null,
      fallbackIndex = -1,
      migratedFrom = null,
      implementation = 'memory',
      persistent = false,
      quota = null,
      usage = null;

  /// Browser storage metadata. The path-based fields are null because the
  /// database lives in OPFS or IndexedDB, not in a filesystem path.
  const DatabaseBootstrap.web({
    required this.implementation,
    this.warning,
    this.persistent = false,
    this.quota,
    this.usage,
  }) : directory = null,
       path = null,
       fallbackIndex = -1,
       migratedFrom = null;

  /// Directory holding the database file; `null` for web or in-memory storage.
  final String? directory;

  /// Full path of the database file; `null` for web or in-memory storage.
  final String? path;

  /// Index of the storage root that was used, 0 being the preferred one.
  final int fallbackIndex;

  /// Legacy database copied into [directory], when a migration ran.
  final String? migratedFrom;

  /// User-facing message. Startup is never blocked on it.
  final String? warning;

  /// Storage implementation name recorded in the log.
  final String implementation;

  /// Whether the browser granted persistent storage. Always true natively.
  final bool persistent;

  /// `navigator.storage.estimate()` quota in bytes, when known.
  final int? quota;

  /// `navigator.storage.estimate()` usage in bytes, when known.
  final int? usage;
}
