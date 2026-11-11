/// Outcome of a save request.
///
/// [displayName] is what the UI shows: the full path on desktop, just the file
/// name on the web. [path] is null when there is no filesystem path.
class ExportResult {
  const ExportResult({required this.displayName, this.path});

  final String displayName;
  final String? path;
}

/// File the user picked for import. [name] is the display name only; browsers
/// do not expose a path.
class PickedFile {
  const PickedFile({required this.name, required this.bytes});

  final String name;
  final List<int> bytes;
}
