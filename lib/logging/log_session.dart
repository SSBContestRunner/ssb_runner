import 'package:package_info_plus/package_info_plus.dart';
import 'package:ssb_runner/platform/environment/environment.dart';

import 'log_location.dart';
import 'redaction.dart';

/// Environment snapshot for the current process run.
///
/// [headerLines] is reused by the diagnostic export so users can hand over the
/// same environment facts that were written into the log file.
class LogSession {
  static LogLocation? location;
  static List<String> headerLines = const <String>[];
}

/// Reads the package metadata once, or `null` when the plugin is unavailable.
///
/// The result is shared with [AppInfo] so the platform channel is only hit
/// once per start.
Future<PackageInfo?> readPackageInfo() async {
  try {
    return await PackageInfo.fromPlatform();
  } on Exception {
    return null;
  }
}

/// Builds the session header written at the top of every log file.
Future<List<String>> buildSessionHeader({
  required LogLocation location,
  PackageInfo? packageInfo,
  required EnvironmentSnapshot environment,
}) async {
  var packageName = 'ssb_runner';
  var version = 'unknown';
  var buildNumber = '';

  final info = packageInfo;
  if (info != null) {
    packageName = info.packageName;
    version = info.version;
    buildNumber = info.buildNumber;
  }

  final lines = <String>[
    'app=$packageName version=$version+$buildNumber',
    ...environment.headerLines,
    'log_dir=${redactPath(location.path)} '
        'fallback_index=${location.fallbackIndex}',
  ];

  LogSession.location = location;
  LogSession.headerLines = lines;
  return lines;
}
