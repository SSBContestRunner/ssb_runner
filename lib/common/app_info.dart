import 'package:package_info_plus/package_info_plus.dart';

/// Package metadata shown in the UI.
///
/// [apply] runs once during startup, after the first frame, so widgets can
/// read the values synchronously instead of waiting on the platform channel.
abstract final class AppInfo {
  static String? version;
  static String? buildNumber;

  /// Stores metadata that was already read for the session header. A `null`
  /// [info] leaves both fields null so callers fall back instead of crashing
  /// when the plugin is unavailable.
  static void apply(PackageInfo? info) {
    version = info?.version;
    buildNumber = info?.buildNumber;
  }

  /// `v0.2.1·201003`, or `—` when the metadata could not be read.
  static String get display {
    final version = AppInfo.version;
    if (version == null || version.isEmpty) {
      return '—';
    }

    final buildNumber = AppInfo.buildNumber;
    if (buildNumber == null || buildNumber.isEmpty) {
      return 'v$version';
    }

    return 'v$version·$buildNumber';
  }
}
