import 'package:web/web.dart' as web;

import '../web/browser_storage.dart';
import 'environment_snapshot.dart';

export 'environment_snapshot.dart';

/// Captures browser facts instead of process facts.
///
/// Executable paths, the working directory and the full URL are deliberately
/// absent: they do not exist on the web and the query string must not leak into
/// a report.
Future<EnvironmentSnapshot> captureEnvironment() async {
  final navigator = web.window.navigator;
  final storage = await browserStorageEstimate();
  final timezone = DateTime.now().timeZoneName;
  final processors = navigator.hardwareConcurrency;
  final language = navigator.language;
  final isolated = isCrossOriginIsolated;

  return EnvironmentSnapshot(
    headerLines: <String>[
      'runtime=web',
      'browser=${navigator.userAgent}',
      if (language.isNotEmpty) 'language=$language',
      'tz=$timezone',
      'processors=$processors',
      'cross_origin_isolated=$isolated',
      if (storage?.quota != null) 'storage_quota=${storage!.quota}',
      if (storage?.usage != null) 'storage_usage=${storage!.usage}',
    ],
    fields: <String, Object?>{
      'runtime': 'web',
      'browser': navigator.userAgent,
      'language': language,
      'timezone': timezone,
      'processors': processors,
      'cross_origin_isolated': isolated,
      'storage_quota': storage?.quota,
      'storage_usage': storage?.usage,
    },
  );
}
