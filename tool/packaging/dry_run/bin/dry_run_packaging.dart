// L1-L3 of the packaging verification layer: run the real maker, skip only the
// Flutter build.
//
// Why this exists: the makers were only ever executed on a tag, so a Liquid or
// tool-level mistake surfaced at release time (CI run 43702798064: a wrapped
// `[` in installer.iss was parsed by ISCC as a section tag). L0
// (validate_packaging.dart) catches the textual cases in seconds; this script
// hands the same configuration to the same `flutter_app_packager` API fastforge
// calls, so ISCC / dpkg-deb / appdmg / appimagetool still get the final word.
//
// The shortcut is `buildOutputDirectory`: `FlutterAppPackager.package` accepts
// any directory, so a stub bundle replaces the ~5 minute `flutter build` while
// everything after it stays real (config loading, Liquid rendering, tool
// invocation, artifact naming).
//
// Usage, from tool/packaging/dry_run (dependencies are resolved there):
//   dart run bin/dry_run_packaging.dart --platform=windows            (exe)
//   dart run bin/dry_run_packaging.dart --platform=linux              (deb)
//   dart run bin/dry_run_packaging.dart --platform=linux --target=appimage
//   dart run bin/dry_run_packaging.dart --platform=macos              (dmg)
//
// The script changes the process CWD to the repository root before doing
// anything else: the makers resolve make_config.yaml, icons and CMakeLists.txt
// relative to the CWD.
//
// Everything is written to build/packaging-dry-run/<slug>/ and removed on
// success. On failure it is kept: it holds the rendered .iss (Windows), the
// packaging directory and the tool log, which is what a failure report needs.
//
// Deliberately not covered (section 4.10): installing the artifact, launching
// the app, signing, and the bundle's contents. Those stay with the tag smoke
// tests, which run against the real build.

import 'dart:io';

import 'package:flutter_app_packager/flutter_app_packager.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

Future<void> main(List<String> argv) async {
  final options = _Options.parse(argv);
  _enterRepoRoot();

  final reproduced = _hostMismatch(options);
  if (reproduced != null) {
    stderr.writeln('::error::$reproduced');
    exit(2);
  }

  final name = _pubspecString('name');
  final version = _pubspecString('version');
  final workRoot = p.absolute(p.join('build', 'packaging-dry-run', options.slug));
  final work = Directory(workRoot);
  if (work.existsSync()) work.deleteSync(recursive: true);
  final stub = Directory(p.join(workRoot, 'stub'))..createSync(recursive: true);
  _writeStub(options, stub);

  // MakeConfig builds "dist/<version>/" by appending the version to
  // outputDirectory.path, so the trailing separator is load-bearing.
  final dist = Directory('${p.join(workRoot, 'dist')}${Platform.pathSeparator}')
    ..createSync(recursive: true);
  final buildName = version.split('+').first;
  final buildNumber = version.contains('+') ? '+${version.split('+').last}' : '';
  final expected = p.join(
    dist.path,
    version,
    '$name-$buildName$buildNumber-${options.platform}'
    '${options.target == 'exe' ? '-setup' : ''}.${options.extension}',
  );

  stdout.writeln('dry run: ${options.platform}/${options.target}, stub ${stub.path}');
  stdout.writeln('      expecting $expected');
  if (options.platform == 'windows') _printIsccVersion();

  try {
    final result = await FlutterAppPackager().package(
      options.platform,
      options.target,
      <String, dynamic>{
        'build_mode': 'release',
        'flavor': null,
        'channel': null,
        'artifact_name': null,
      },
      dist,
      buildOutputDirectory: stub,
      buildOutputFiles: const <File>[],
    );

    final artifact = File(result.artifacts.first.path);
    _verifyArtifact(options, artifact, expected);

    stdout.writeln('dry run: OK -> ${artifact.path} (${artifact.lengthSync()} bytes)');
    work.deleteSync(recursive: true);
  } catch (error, stackTrace) {
    stderr.writeln('::error::packaging dry run (${options.slug}) failed: $error');
    stderr.writeln(stackTrace);
    stderr.writeln('evidence kept at $workRoot');
    exitCode = 1;
  }
}

/// Walks up from the CWD (tool/packaging/dry_run) to the repository root, so it
/// does not matter where the package was activated from.
void _enterRepoRoot() {
  var directory = Directory.current;
  while (true) {
    final isRepoRoot =
        File(p.join(directory.path, 'pubspec.yaml')).existsSync() &&
            Directory(p.join(directory.path, 'windows', 'packaging')).existsSync() &&
            Directory(p.join(directory.path, 'tool', 'packaging')).existsSync();
    if (isRepoRoot) {
      Directory.current = directory.path;
      return;
    }
    if (directory.parent.path == directory.path) {
      stderr.writeln('::error::cannot find the repository root above ${Directory.current.path}');
      exit(2);
    }
    directory = directory.parent;
  }
}

class _Options {
  const _Options(this.platform, this.target);

  final String platform;
  final String target;

  static const Map<String, String> _defaultTarget = <String, String>{
    'windows': 'exe',
    'linux': 'deb',
    'macos': 'dmg',
  };

  static const Map<String, String> _extension = <String, String>{
    'exe': 'exe',
    'deb': 'deb',
    'dmg': 'dmg',
    'appimage': 'AppImage',
  };

  static const Map<String, List<String>> _targetsByPlatform = <String, List<String>>{
    'windows': <String>['exe'],
    'linux': <String>['deb', 'appimage'],
    'macos': <String>['dmg'],
  };

  String get extension => _extension[target]!;

  String get slug => target == _defaultTarget[platform] ? platform : '$platform-$target';

  static _Options parse(List<String> argv) {
    String? platform;
    String? target;
    for (final argument in argv) {
      if (argument.startsWith('--platform=')) {
        platform = argument.substring('--platform='.length);
      } else if (argument.startsWith('--target=')) {
        target = argument.substring('--target='.length);
      } else {
        stderr.writeln('::error::unknown argument "$argument"');
        exit(2);
      }
    }
    if (platform == null || !_targetsByPlatform.containsKey(platform)) {
      stderr.writeln('::error::--platform must be one of ${_targetsByPlatform.keys.join(', ')}');
      exit(2);
    }
    final resolvedTarget = target ?? _defaultTarget[platform]!;
    if (!_targetsByPlatform[platform]!.contains(resolvedTarget)) {
      stderr.writeln(
        '::error::--target for $platform must be one of ${_targetsByPlatform[platform]!.join(', ')}',
      );
      exit(2);
    }
    return _Options(platform, resolvedTarget);
  }
}

String? _hostMismatch(_Options options) {
  final tool = <String, String>{
    'exe': 'ISCC.exe',
    'deb': 'dpkg-deb',
    'appimage': 'appimagetool',
    'dmg': 'hdiutil',
  }[options.target]!;
  final host = <String, bool>{
    'exe': Platform.isWindows,
    'deb': Platform.isLinux,
    'appimage': Platform.isLinux,
    'dmg': Platform.isMacOS,
  }[options.target]!;
  if (host) return null;
  return '${options.target} needs a ${options.platform} host ($tool); '
      'run this target on its own CI runner';
}

// --- pubspec ----------------------------------------------------------------

String _pubspecString(String key) {
  final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
  final value = pubspec[key];
  if (value is! String || value.isEmpty) {
    stderr.writeln('::error::pubspec.yaml has no "$key"');
    exit(2);
  }
  return value;
}

String _productName() {
  final content = File('macos/Runner/Configs/AppInfo.xcconfig').readAsStringSync();
  final match = RegExp(r'^\s*PRODUCT_NAME\s*=\s*(.*)$', multiLine: true).firstMatch(content);
  final name = match?.group(1)?.trim();
  if (name == null || name.isEmpty) {
    stderr.writeln('::error::macos/Runner/Configs/AppInfo.xcconfig has no PRODUCT_NAME');
    exit(2);
  }
  return name;
}

/// The maker derives the deb payload path, desktop file name and /usr/bin
/// symlink from `linux/CMakeLists.txt`, so the stub has to use the same name.
String _linuxBinaryName() {
  final content = File('linux/CMakeLists.txt').readAsStringSync();
  final match = RegExp(r'set\(BINARY_NAME\s+"([^"]+)"\)').firstMatch(content);
  final name = match?.group(1);
  if (name == null || name.isEmpty) {
    stderr.writeln('::error::linux/CMakeLists.txt has no set(BINARY_NAME "...")');
    exit(2);
  }
  return name;
}

// --- stub bundle ------------------------------------------------------------

/// Writes the smallest bundle the maker accepts. It proves the configuration
/// and the tool invocation, not the contents of a real build: the makers copy
/// this directory (or its .app) and hand it to the packaging tool.
void _writeStub(_Options options, Directory stub) {
  const stubText = 'stub artifact written by tool/packaging/dry_run_packaging.dart\n';
  switch (options.platform) {
    case 'windows':
      File(p.join(stub.path, 'ssb_runner.exe')).writeAsStringSync(stubText);
      _write(p.join(stub.path, 'data', 'icudtl.dat'), stubText);
    case 'linux':
      File(p.join(stub.path, _linuxBinaryName())).writeAsStringSync(stubText);
      _write(p.join(stub.path, 'data', 'icudtl.dat'), stubText);
      if (options.target == 'appimage') {
        // The appimage maker runs `ldd` on lib/libflutter_linux_gtk.so and
        // copies its dependencies, so the stub must be a real ELF (section 4.9,
        // P2). Any system lib works; libm is present on every runner.
        final source = _firstExisting(<String>[
          '/lib/x86_64-linux-gnu/libm.so.6',
          '/usr/lib/x86_64-linux-gnu/libm.so.6',
          '/lib64/libm.so.6',
          '/usr/lib64/libm.so.6',
        ]);
        if (source == null) {
          stderr.writeln('::error::no libm.so.6 found to use as the AppImage stub ELF');
          exit(2);
        }
        final target = File(p.join(stub.path, 'lib', 'libflutter_linux_gtk.so'))
          ..createSync(recursive: true);
        File(source).copySync(target.path);
      }
    case 'macos':
      final app = p.join(stub.path, '${_productName()}.app');
      final executable = File(p.join(app, 'Contents', 'MacOS', _productName()))
        ..createSync(recursive: true)
        ..writeAsStringSync('#!/bin/sh\nexit 0\n');
      Process.runSync('chmod', <String>['+x', executable.path]);
      _write(
        p.join(app, 'Contents', 'Info.plist'),
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
        '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
        '<plist version="1.0"><dict>\n'
        '  <key>CFBundleIdentifier</key><string>com.ssbrunner.app</string>\n'
        '  <key>CFBundleName</key><string>${_productName()}</string>\n'
        '  <key>CFBundleExecutable</key><string>${_productName()}</string>\n'
        '  <key>CFBundlePackageType</key><string>APPL</string>\n'
        '</dict></plist>\n',
      );
  }
}

void _write(String path, String content) {
  File(path)
    ..createSync(recursive: true)
    ..writeAsStringSync(content);
}

String? _firstExisting(List<String> paths) {
  for (final path in paths) {
    if (File(path).existsSync()) return path;
  }
  return null;
}

// --- verification -----------------------------------------------------------

void _verifyArtifact(_Options options, File artifact, String expectedPath) {
  if (!artifact.existsSync()) {
    throw StateError('maker reported success but ${artifact.path} does not exist');
  }
  if (artifact.lengthSync() == 0) {
    throw StateError('${artifact.path} is empty');
  }
  // D8: the dry-run artifact name must match what the tag build produces.
  final expectedName = p.basename(expectedPath);
  if (p.basename(artifact.path) != expectedName) {
    throw StateError('artifact name ${p.basename(artifact.path)} != $expectedName');
  }

  switch (options.target) {
    case 'exe':
      _verifyExe(artifact);
    case 'deb':
      _verifyDeb(artifact);
    case 'appimage':
      _verifyElf(artifact);
    case 'dmg':
      _verifyDmg(artifact);
  }
}

void _printIsccVersion() {
  final iscc = InnoSetupCompiler.resolveIsccPath();
  final result = Process.runSync(iscc, <String>['/?'], runInShell: true);
  final banner = '${result.stdout}'
      .split('\n')
      .where((String line) => line.trim().isNotEmpty)
      .take(3)
      .join(' | ');
  stdout.writeln('dry run: ISCC $iscc -> $banner');
}

void _verifyExe(File artifact) {
  final config = loadYaml(
    File('windows/packaging/exe/make_config.yaml').readAsStringSync(),
  ) as YamlMap;
  final displayName = config['display_name'] as String;
  final literal = artifact.path.replaceAll("'", "''");
  final result = Process.runSync('powershell', <String>[
    '-NoProfile',
    '-Command',
    "(Get-Item -LiteralPath '$literal').VersionInfo.ProductName",
  ]);
  final productName = '${result.stdout}'.trim();
  if (productName != displayName) {
    throw StateError('ProductName is "$productName", expected "$displayName"');
  }
  stdout.writeln('dry run: ProductName "$productName"');
}

void _verifyDeb(File artifact) {
  final fields = Process.runSync('dpkg-deb', <String>['--field', artifact.path, 'Package', 'Version']);
  if (fields.exitCode != 0) {
    throw StateError('dpkg-deb --field failed: ${fields.stderr}');
  }
  final packageLine = '${fields.stdout}'.split('\n').firstWhere(
        (String line) => line.startsWith('Package:'),
        orElse: () => '',
      );
  final config = loadYaml(
    File('linux/packaging/deb/make_config.yaml').readAsStringSync(),
  ) as YamlMap;
  final expectedPackage = config['package_name'] as String;
  if (packageLine.trim() != 'Package: $expectedPackage') {
    throw StateError('control Package is "$packageLine", expected "Package: $expectedPackage"');
  }

  final listing = Process.runSync('dpkg-deb', <String>['--contents', artifact.path]);
  if (listing.exitCode != 0) {
    throw StateError('dpkg-deb --contents failed: ${listing.stderr}');
  }
  final contents = '${listing.stdout}';
  final binary = _linuxBinaryName();
  for (final required in <String>[
    './opt/$binary/$binary',
    './usr/share/applications/$binary.desktop',
    './DEBIAN/control',
  ]) {
    if (!contents.contains(required)) {
      throw StateError('deb is missing $required');
    }
  }
  stdout.writeln('dry run: deb contains opt/$binary, desktop entry and control');
}

void _verifyElf(File artifact) {
  final header = artifact.openSync()..setPositionSync(0);
  final magic = header.readSync(4);
  header.closeSync();
  if (magic.length != 4 || magic[0] != 0x7f || magic[1] != 0x45 || magic[2] != 0x4c || magic[3] != 0x46) {
    throw StateError('${artifact.path} is not an ELF AppImage');
  }
  stdout.writeln('dry run: AppImage is an ELF image');
}

void _verifyDmg(File artifact) {
  final mountPoint = Directory(p.join(p.dirname(artifact.path), 'mnt'))..createSync(recursive: true);
  final attach = Process.runSync('hdiutil', <String>[
    'attach',
    '-nobrowse',
    '-readonly',
    '-mountpoint',
    mountPoint.path,
    artifact.path,
  ]);
  if (attach.exitCode != 0) {
    throw StateError('hdiutil attach failed: ${attach.stderr}');
  }
  try {
    final entries = mountPoint.listSync().map((FileSystemEntity e) => p.basename(e.path)).toSet();
    if (!entries.contains('${_productName()}.app')) {
      throw StateError('dmg volume has no ${_productName()}.app (found $entries)');
    }
    final link = Link(p.join(mountPoint.path, 'Applications'));
    if (!link.existsSync() || link.targetSync() != '/Applications') {
      throw StateError('dmg volume has no /Applications link');
    }
    stdout.writeln('dry run: dmg volume has ${_productName()}.app and /Applications');
  } finally {
    Process.runSync('hdiutil', <String>['detach', mountPoint.path]);
    if (mountPoint.existsSync()) mountPoint.deleteSync(recursive: true);
  }
}
