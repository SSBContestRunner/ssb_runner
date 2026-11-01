import 'package:package_info_plus/package_info_plus.dart';

/// Package metadata shown in the UI.
///
/// [load] runs once during startup so widgets can read the values
/// synchronously instead of waiting on the platform channel.
abstract final class AppInfo {
  static String? version;
  static String? buildNumber;

  /// Reads the package metadata. Failures leave both fields null so callers
  /// can fall back instead of crashing when the plugin is unavailable.
  static Future<void> load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      version = info.version;
      buildNumber = info.buildNumber;
    } on Exception {
      version = null;
      buildNumber = null;
    }
  }

  /// `v0.2.1 · 201003`, or `—` when the metadata could not be read.
  static String get display {
    final version = AppInfo.version;
    if (version == null || version.isEmpty) {
      return '—';
    }

    final buildNumber = AppInfo.buildNumber;
    if (buildNumber == null || buildNumber.isEmpty) {
      return 'v$version';
    }

    return 'v$version · $buildNumber';
  }
}
