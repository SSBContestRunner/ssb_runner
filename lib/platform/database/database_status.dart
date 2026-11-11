/// Storage facts shown in Settings and used by the startup health check.
class DatabaseStorageStatus {
  const DatabaseStorageStatus({
    this.applicable = false,
    this.persistent = false,
    this.implementation = '',
    this.quota,
    this.usage,
  });

  /// Whether the platform exposes browser-style storage controls. False on
  /// desktop, where the database is a normal file.
  final bool applicable;

  /// Whether persistent storage was granted.
  final bool persistent;

  /// Storage implementation reported by the database layer.
  final String implementation;

  /// `navigator.storage.estimate()` quota in bytes, when known.
  final int? quota;

  /// `navigator.storage.estimate()` usage in bytes, when known.
  final int? usage;

  double? get usedFraction {
    final quota = this.quota;
    final usage = this.usage;
    if (quota == null || usage == null || quota <= 0) {
      return null;
    }
    return usage / quota;
  }
}

/// Outcome of probing the database before the UI is shown.
class DatabaseHealth {
  const DatabaseHealth({
    this.error,
    this.implementation = '',
    this.persistent = true,
  });

  /// Machine-readable reason the database is not usable for history. Null when
  /// the database opened with persistent storage.
  final String? error;

  final String implementation;

  /// False when the database silently fell back to memory.
  final bool persistent;

  bool get ok => error == null;
}
