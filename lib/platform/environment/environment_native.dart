import 'dart:ffi';
import 'dart:io';

import 'package:ssb_runner/logging/redaction.dart';

import 'environment_snapshot.dart';

export 'environment_snapshot.dart';

/// Captures the native process environment.
Future<EnvironmentSnapshot> captureEnvironment() async {
  final dartVersion = Platform.version.split(' ').first;
  final os = '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
  final arch = '${Abi.current()}';
  final processors = Platform.numberOfProcessors;
  final locale = Platform.localeName;
  final timezone = DateTime.now().timeZoneName;
  final executable = redactPath(Platform.resolvedExecutable);
  final workingDirectory = redactPath(Directory.current.path);

  return EnvironmentSnapshot(
    headerLines: <String>[
      'runtime=native',
      'dart=$dartVersion',
      'os=$os',
      'arch=$arch',
      'processors=$processors',
      'locale=$locale',
      'tz=$timezone',
      'exe=$executable',
      'cwd=$workingDirectory',
    ],
    fields: <String, Object?>{
      'runtime': 'native',
      'dart': dartVersion,
      'os': Platform.operatingSystem,
      'os_version': Platform.operatingSystemVersion,
      'arch': arch,
      'processors': processors,
      'locale': locale,
      'timezone': timezone,
      'exe': executable,
      'cwd': workingDirectory,
    },
  );
}
