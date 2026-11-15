// L0 of the packaging verification layer: static contracts over the three
// platforms' packaging configuration.
//
// Why this exists: the makers (make_config.yaml, Liquid templates, language
// files, appdmg layout, deb fields) are only executed on a tag, so every
// packaging mistake is discovered at release time. CI run 43702798064 lost 17
// minutes to a single `[` that started a continuation line and was parsed as a
// section tag by ISCC. This file is the seconds-level gate that catches that
// class of error before a build runs (docs/research/
// ci-run-43702798064-failure-analysis.md, sections 4.5-4.6).
//
// The checks are pure functions over a [RepoView] so the fixtures under
// test/packaging can exercise them without touching the real repository. The
// CLI wrapper lives in tool/packaging/validate_packaging.dart.
//
// Nothing here re-implements a maker: L0 only reads text. Anything that needs a
// real tool (ISCC, dpkg-deb, appdmg) belongs to L1-L3 in dry_run_packaging.dart.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Where the fastforge global activation keeps its resolved dependencies.
const String kFastforgeGlobalLockPath =
    '~/.pub-cache/global_packages/fastforge/pubspec.lock';

/// Where the fastforge global activation keeps its package config (used to read
/// the activated fastforge version itself).
const String kFastforgePackageConfigPath =
    '~/.pub-cache/global_packages/fastforge/.dart_tool/package_config.json';

/// The fastforge version ci.yml activates. Its own constraint on
/// `flutter_app_packager` is `^0.6.11`, so a fresh activation resolves the
/// newest 0.6.x (0.6.13 while this was written) -- that is the version the tag
/// build uses, which is why the dev_dependency pin has to follow it.
const String _expectedFastforgeVersion = '0.6.12';

const String _ciPath = '.github/workflows/ci.yml';
const String _pubspecPath = 'pubspec.yaml';

const String _windowsConfigPath = 'windows/packaging/exe/make_config.yaml';
const String _windowsTemplatePath = 'windows/packaging/exe/installer.iss';
const String _windowsLanguagesDir = 'windows/packaging/exe/languages';
const String _innoSetupScriptPath = '.github/scripts/ensure-inno-setup.ps1';
const String _appImageToolScriptPath = '.github/scripts/install-appimagetool.sh';

const String _debConfigPath = 'linux/packaging/deb/make_config.yaml';
const String _appImageConfigPath = 'linux/packaging/appimage/make_config.yaml';
const String _linuxCMakePath = 'linux/CMakeLists.txt';

const String _dmgConfigPath = 'macos/packaging/dmg/make_config.yaml';
const String _macAppInfoPath = 'macos/Runner/Configs/AppInfo.xcconfig';
const String _macInfoPlistPath = 'macos/Runner/Info.plist';

/// The dry run is its own package: flutter_app_packager pins archive ^3.6.1
/// while the app needs ^4.0.7, so they cannot share one resolution.
const String _dryRunPubspecPath = 'tool/packaging/dry_run/pubspec.yaml';
const String _dryRunLockPath = 'tool/packaging/dry_run/pubspec.lock';

const List<String> _platforms = <String>['linux', 'windows', 'macos'];

/// Makers that fastforge provides without a `make_config.yaml`.
const Set<String> _builtInTargets = <String>{'zip'};

/// Sections Inno Setup accepts. ISCC treats every line whose first non-blank
/// character is `[` as a section header, so this list doubles as the guard for
/// continuation lines that start with `[`.
const Set<String> _innoSections = <String>{
  'setup',
  'types',
  'components',
  'tasks',
  'dirs',
  'files',
  'icons',
  'ini',
  'installdelete',
  'languages',
  'messages',
  'custommessages',
  'registry',
  'run',
  'uninstallrun',
  'uninstalldelete',
  'code',
  'compiler',
};

/// The Liquid variables fastforge injects into the Inno Setup template
/// (`flutter_app_packager` 0.6.11, inno_setup_script.dart). A variable outside
/// this set renders to an empty string and silently drops a field.
const Set<String> _innoSetupLiquidVariables = <String>{
  'APP_ID',
  'APP_NAME',
  'APP_VERSION',
  'EXECUTABLE_NAME',
  'DISPLAY_NAME',
  'PUBLISHER_NAME',
  'PUBLISHER_URL',
  'CREATE_DESKTOP_ICON',
  'LAUNCH_AT_STARTUP',
  'INSTALL_DIR_NAME',
  'SOURCE_DIR',
  'OUTPUT_BASE_FILENAME',
  'LOCALES',
  'SETUP_ICON_FILE',
  'PRIVILEGES_REQUIRED',
  'ARCHITECTURES_ALLOWED',
  'ARCHITECTURES_INSTALL_IN_64BIT_MODE',
};

/// Language files that ship with Inno Setup itself (official translations).
const Set<String> _innoOfficialLanguages = <String>{
  'Default.isl',
  'Japanese.isl',
};

/// freedesktop.org menu categories: the main categories plus the additional
/// ones this app uses. Extend when a config adds a category.
const Set<String> _freedesktopCategories = <String>{
  'AudioVideo',
  'Audio',
  'Video',
  'Development',
  'Education',
  'Game',
  'Graphics',
  'Network',
  'Office',
  'Science',
  'Settings',
  'System',
  'Utility',
  'HamRadio',
};

enum ContractSeverity { error, warning }

class ContractIssue {
  const ContractIssue(
    this.file,
    this.message, {
    this.line,
    this.severity = ContractSeverity.error,
  });

  final String file;
  final int? line;
  final String message;
  final ContractSeverity severity;

  /// GitHub Actions annotation: `::error file=...,line=...::message`.
  String toAnnotation() {
    final buffer = StringBuffer('::${severity.name} file=$file');
    if (line != null) buffer.write(',line=$line');
    buffer.write(',title=Packaging contract');
    buffer.write('::');
    buffer.write(message.replaceAll('\n', ' '));
    return buffer.toString();
  }

  @override
  String toString() => line == null ? '$file: $message' : '$file:$line: $message';
}

/// Read-only view of the files the contract checks need.
abstract class RepoView {
  String read(String path);
  bool exists(String path);
  bool isDirectory(String path);

  /// Basenames of the files directly inside [directory], sorted.
  List<String> listFiles(String directory);

  /// Basenames of the directories directly inside [directory], sorted.
  List<String> listDirectories(String directory);
}

/// [RepoView] backed by the working tree. Paths are resolved against the CWD,
/// so callers must run from the repository root.
class DiskRepo implements RepoView {
  const DiskRepo();

  @override
  String read(String path) => File(path).readAsStringSync();

  @override
  bool exists(String path) =>
      FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound;

  @override
  bool isDirectory(String path) => FileSystemEntity.isDirectorySync(path);

  @override
  List<String> listFiles(String directory) {
    if (!isDirectory(directory)) return const <String>[];
    return Directory(directory)
        .listSync()
        .whereType<File>()
        .map((File file) => p.basename(file.path))
        .toList()
      ..sort();
  }

  @override
  List<String> listDirectories(String directory) {
    if (!isDirectory(directory)) return const <String>[];
    return Directory(directory)
        .listSync()
        .whereType<Directory>()
        .map((Directory dir) => p.basename(dir.path))
        .toList()
      ..sort();
  }
}

/// The activated fastforge, as read from the global pub cache.
class GlobalFastforge {
  const GlobalFastforge({this.version, this.lock});

  /// Version from the global package config; null when it cannot be read.
  final String? version;

  /// Contents of the global `pubspec.lock`; null when it cannot be read.
  final String? lock;

  static GlobalFastforge read() {
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home == null) return const GlobalFastforge();
    final lockFile =
        File(p.join(home, '.pub-cache/global_packages/fastforge/pubspec.lock'));
    final configFile = File(
      p.join(home, '.pub-cache/global_packages/fastforge/.dart_tool/package_config.json'),
    );
    String? version;
    if (configFile.existsSync()) {
      version = _fastforgeVersionFromPackageConfig(configFile.readAsStringSync());
    }
    return GlobalFastforge(
      version: version,
      lock: lockFile.existsSync() ? lockFile.readAsStringSync() : null,
    );
  }
}

String? _fastforgeVersionFromPackageConfig(String content) {
  try {
    final config = jsonDecode(content) as Map<String, dynamic>;
    final packages = (config['packages'] as List<dynamic>).cast<Map<String, dynamic>>();
    for (final package in packages) {
      if (package['name'] != 'fastforge') continue;
      final rootUri = package['rootUri'] as String? ?? '';
      final match = RegExp(r'fastforge-(\d+\.\d+\.\d+)').firstMatch(rootUri);
      return match?.group(1);
    }
  } on FormatException {
    return null;
  }
  return null;
}

/// Runs every L0 check. Returns the issues found; an empty list means the
/// packaging configuration is consistent with the CI orchestration and the
/// pinned tools.
List<ContractIssue> validatePackagingContract(
  RepoView repo, {
  GlobalFastforge fastforge = const GlobalFastforge(),
}) {
  final issues = <ContractIssue>[];
  final pubspec = _readYaml(repo, _pubspecPath, issues);
  final ci = _readFile(repo, _ciPath, issues);
  final matrix = ci == null ? null : _parseCiMatrix(ci, issues);

  if (matrix != null) {
    _checkTargetCoverage(repo, matrix, issues);
    _checkCiOrchestration(ci!, issues);
  }

  final exeConfig = _readYaml(repo, _windowsConfigPath, issues);
  if (exeConfig != null) {
    _checkWindows(repo, exeConfig, issues);
  }

  final debConfig = _readYaml(repo, _debConfigPath, issues);
  final appImageConfig = _readYaml(repo, _appImageConfigPath, issues);
  _checkLinux(repo, pubspec, debConfig, appImageConfig, issues);

  final dmgConfig = _readYaml(repo, _dmgConfigPath, issues);
  if (dmgConfig != null) {
    _checkMacos(repo, dmgConfig, issues);
  }

  if (exeConfig != null && debConfig != null && appImageConfig != null) {
    _checkDisplayNameConsistency(exeConfig, debConfig, appImageConfig, issues);
  }

  _checkNoVersionLiterals(repo, pubspec, issues);
  _checkPackagerPin(repo, matrix, fastforge, issues);

  return issues;
}

// --- repository helpers ------------------------------------------------------

String? _readFile(RepoView repo, String path, List<ContractIssue> issues) {
  if (!repo.exists(path)) {
    issues.add(ContractIssue(path, 'file is missing'));
    return null;
  }
  return repo.read(path);
}

Map<String, dynamic>? _readYaml(
  RepoView repo,
  String path,
  List<ContractIssue> issues,
) {
  final content = _readFile(repo, path, issues);
  if (content == null) return null;
  return _parseYamlMap(path, content, issues);
}

Map<String, dynamic>? _parseYamlMap(
  String path,
  String content,
  List<ContractIssue> issues,
) {
  try {
    final value = jsonDecode(jsonEncode(loadYaml(content)));
    if (value is! Map<String, dynamic>) {
      issues.add(ContractIssue(path, 'expected a YAML mapping'));
      return null;
    }
    return value;
  } on YamlException catch (error) {
    issues.add(ContractIssue(path, 'invalid YAML: ${error.message}'));
    return null;
  } on FormatException catch (error) {
    issues.add(ContractIssue(path, 'invalid YAML: ${error.message}'));
    return null;
  }
}

String? _stringAt(Map<String, dynamic>? map, String key) {
  final value = map?[key];
  return value is String ? value : null;
}

// --- CI / matrix -------------------------------------------------------------

class _MatrixEntry {
  const _MatrixEntry(this.os, this.platform, this.targets);

  final String os;
  final String platform;
  final Set<String> targets;
}

/// Parses the `matrix='[...]'` assignments in ci.yml, which is where the
/// release targets are declared.
List<_MatrixEntry>? _parseCiMatrix(String ci, List<ContractIssue> issues) {
  final entries = <_MatrixEntry>[];
  final matches = RegExp(r"matrix='(\[[^']*\])'").allMatches(ci);
  if (matches.isEmpty) {
    issues.add(
      ContractIssue(_ciPath, 'no matrix=\'[...]\' assignment found; cannot check targets'),
    );
    return null;
  }
  for (final match in matches) {
    final decoded = jsonDecode(match.group(1)!) as List<dynamic>;
    for (final raw in decoded) {
      final entry = raw as Map<String, dynamic>;
      entries.add(
        _MatrixEntry(
          entry['os'] as String,
          entry['platform'] as String,
          (entry['targets'] as String).split(',').toSet(),
        ),
      );
    }
  }
  return entries;
}

void _checkTargetCoverage(
  RepoView repo,
  List<_MatrixEntry> matrix,
  List<ContractIssue> issues,
) {
  final declared = <String>{};
  for (final entry in matrix) {
    for (final target in entry.targets) {
      declared.add('${entry.platform}/$target');
      final configPath = '${entry.platform}/packaging/$target/make_config.yaml';
      if (_builtInTargets.contains(target)) {
        if (repo.exists(configPath)) {
          issues.add(
            ContractIssue(
              configPath,
              '$target is a built-in fastforge maker and needs no configuration; '
                  'this directory is dead weight',
              severity: ContractSeverity.warning,
            ),
          );
        }
        continue;
      }
      if (!repo.exists(configPath)) {
        issues.add(
          ContractIssue(
            configPath,
            'ci.yml builds $target for ${entry.platform} but this config is missing',
          ),
        );
      }
    }
  }

  // Reverse direction: a config nobody builds is a silent dead end.
  for (final platform in _platforms) {
    final packagingDir = '$platform/packaging';
    for (final target in repo.listDirectories(packagingDir)) {
      final configPath = '$packagingDir/$target/make_config.yaml';
      if (!repo.exists(configPath)) continue;
      if (!declared.contains('$platform/$target')) {
        issues.add(
          ContractIssue(
            configPath,
            'no ci.yml matrix entry builds $platform/$target (orphan configuration)',
          ),
        );
      }
    }
  }
}

void _checkCiOrchestration(String ci, List<ContractIssue> issues) {
  void requireJob(String job, String why) {
    if (!RegExp('^  $job:\\s*\$', multiLine: true).hasMatch(ci)) {
      issues.add(ContractIssue(_ciPath, 'missing job "$job": $why'));
    }
  }

  requireJob(
    'packaging-contract',
    'L0 must run on every PR so a template error fails in seconds, not after a full build',
  );
  for (final platform in _platforms) {
    requireJob(
      'validate-packaging-$platform',
      'L1-L3 must compile the packaging config with the real tool before merge',
    );
  }

  // Validate packaging (*) and Package (*) must not share an event: a manual
  // dispatch already packages a platform for real, so a dry run next to it
  // would repeat the same maker chain. Keeping dispatch out of the validate
  // jobs makes the two sets mutually exclusive by event type.
  for (final platform in _platforms) {
    final block = _jobBlock(ci, 'validate-packaging-$platform');
    if (block != null && block.contains('workflow_dispatch')) {
      final offset = ci.indexOf(block) + block.indexOf('workflow_dispatch');
      issues.add(
        ContractIssue(
          _ciPath,
          'validate-packaging-$platform runs on workflow_dispatch; '
              'validation and packaging must not share an event',
          line: _lineOf(ci, offset),
        ),
      );
    }
  }

  // A template error must short-circuit the retry loop instead of rebuilding
  // the bundle three times (~9m30s in run 43702798064).
  for (final marker in <String>['Invalid section tag', 'Compile aborted']) {
    if (!ci.contains(marker)) {
      issues.add(
        ContractIssue(
          _ciPath,
          'the package retry loop does not treat "$marker" as deterministic; '
              'a template error would rebuild the app three times',
        ),
      );
    }
  }
  // ci.yml writes the pattern itself, so compare the literal source text.
  if (!ci.contains(r'error C\d{4}:')) {
    issues.add(
      ContractIssue(_ciPath, 'the package retry loop lost its MSVC diagnostic short-circuit'),
    );
  }

  // The compiler layout and the appimagetool pin exist once, not per job.
  for (final script in <String>[_innoSetupScriptPath, _appImageToolScriptPath]) {
    if (!ci.contains(script)) {
      issues.add(
        ContractIssue(_ciPath, 'ci.yml does not call $script; the duplicated step would drift'),
      );
    }
  }

  for (final platform in _platforms) {
    final block = _jobBlock(ci, 'package-$platform');
    if (block == null) {
      issues.add(ContractIssue(_ciPath, 'missing job "package-$platform"'));
      continue;
    }
    if (!block.contains('packaging-contract')) {
      issues.add(
        ContractIssue(
          _ciPath,
          'package-$platform does not depend on the packaging contract; '
              'a template error would be found only after the bundle is built',
        ),
      );
    }
  }

  if (!RegExp(r'^  merge_group:\s*$', multiLine: true).hasMatch(ci)) {
    issues.add(
      ContractIssue(
        _ciPath,
        'merge_group is not registered; a required check would stay pending '
            'once the merge queue is enabled',
      ),
    );
  }
  if (!RegExp(r'^  pull_request:', multiLine: true).hasMatch(ci)) {
    issues.add(ContractIssue(_ciPath, 'pull_request is not a trigger'));
  }
}

/// The text of a job block in ci.yml (from `  name:` to the next job).
String? _jobBlock(String ci, String job) {
  final match = RegExp('^  $job:\\s*\$', multiLine: true).firstMatch(ci);
  if (match == null) return null;
  final start = match.end;
  final next = RegExp(r'^  \S[^\n]*:\s*$', multiLine: true)
      .firstMatch(ci.substring(start));
  return next == null ? ci.substring(start) : ci.substring(start, start + next.start);
}

// --- Windows ----------------------------------------------------------------

void _checkWindows(
  RepoView repo,
  Map<String, dynamic> config,
  List<ContractIssue> issues,
) {
  final template = _readFile(repo, _windowsTemplatePath, issues);
  final appId = _stringAt(config, 'app_id');
  if (appId == null) {
    issues.add(ContractIssue(_windowsConfigPath, 'app_id is missing'));
  } else if (!RegExp(
    r'^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$',
  ).hasMatch(appId)) {
    issues.add(
      ContractIssue(
        _windowsConfigPath,
        'app_id "$appId" is not a GUID without braces; Inno Setup parses braces '
            'as constants and the AppId is the upgrade identity',
      ),
    );
  }

  final privileges = _stringAt(config, 'privileges_required');
  if (privileges != null && !const <String>{'lowest', 'admin', 'none'}.contains(privileges)) {
    issues.add(
      ContractIssue(
        _windowsConfigPath,
        'privileges_required "$privileges" is not one of lowest / admin / none',
      ),
    );
  }

  final installDir = _stringAt(config, 'install_dir_name');
  if (installDir != null && !installDir.startsWith('{')) {
    issues.add(
      ContractIssue(
        _windowsConfigPath,
        'install_dir_name "$installDir" does not start with an Inno Setup constant',
      ),
    );
  }

  final scriptTemplate = _stringAt(config, 'script_template');
  if (scriptTemplate == null) {
    issues.add(ContractIssue(_windowsConfigPath, 'script_template is missing'));
  } else {
    final templatePath = 'windows/packaging/exe/$scriptTemplate';
    if (!repo.exists(templatePath)) {
      issues.add(ContractIssue(_windowsConfigPath, 'script_template "$scriptTemplate" does not exist'));
    }
  }

  final icon = _stringAt(config, 'setup_icon_file');
  if (icon == null) {
    issues.add(ContractIssue(_windowsConfigPath, 'setup_icon_file is missing'));
  } else {
    if (!repo.exists(icon)) {
      issues.add(ContractIssue(_windowsConfigPath, 'setup_icon_file "$icon" does not exist'));
    } else if (!icon.toLowerCase().endsWith('.ico')) {
      issues.add(ContractIssue(_windowsConfigPath, 'setup_icon_file "$icon" is not a .ico'));
    }
    final iconDir = p.dirname(icon);
    for (final size in <int>[58, 116, 174]) {
      final path = p.posix.join(iconDir, 'wizard_small_image_$size.png');
      if (!repo.exists(path)) {
        issues.add(
          ContractIssue(
            path,
            'missing wizard image; the template derives it from setup_icon_file at compile time',
          ),
        );
      }
    }
  }

  if (template == null) return;
  _checkInnoSectionTags(template, issues);
  _checkInnoLiquid(template, issues);
  _checkInnoLanguages(repo, template, issues);
  _checkInnoCustomMessages(template, issues);
  _checkInnoInstallDelete(template, issues);
  _checkInnoMinVersion(repo, template, issues);
}

/// ISCC splits sections line by line: any line whose first non-blank character
/// is `[` starts a section. A wrapped statement must therefore never put `[` at
/// the start of a continuation line (run 43702798064).
void _checkInnoSectionTags(String template, List<ContractIssue> issues) {
  final lines = template.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final match = RegExp(r'^\s*\[([^\]]*)').firstMatch(lines[i]);
    if (match == null) continue;
    final tag = match.group(1)!.trim();
    if (_innoSections.contains(tag.toLowerCase())) continue;
    issues.add(
      ContractIssue(
        _windowsTemplatePath,
        'Invalid section tag "[$tag": ISCC treats a line whose first non-blank '
            'character is "[" as a section header, so a continuation line must not '
            'start with "["',
        line: i + 1,
      ),
    );
  }
}

void _checkInnoLiquid(String template, List<ContractIssue> issues) {
  for (final match in RegExp(r'\{\{\s*([A-Za-z0-9_]+)\s*\}\}').allMatches(template)) {
    final variable = match.group(1)!;
    if (_innoSetupLiquidVariables.contains(variable)) continue;
    issues.add(
      ContractIssue(
        _windowsTemplatePath,
        'unknown Liquid variable {{$variable}}: fastforge injects only '
            '${_innoSetupLiquidVariables.length} variables, so it renders to an empty string',
        line: _lineOf(template, match.start),
      ),
    );
  }
  for (final match in RegExp(r'\{%\s*(?:if|unless|elsif)\s+([A-Za-z0-9_]+)').allMatches(template)) {
    final variable = match.group(1)!;
    if (_innoSetupLiquidVariables.contains(variable)) continue;
    issues.add(
      ContractIssue(
        _windowsTemplatePath,
        'unknown Liquid variable "$variable" in a {% if %} tag',
        line: _lineOf(template, match.start),
      ),
    );
  }
  for (final match in RegExp(r'\{%\s*(?:for|assign)\s+[A-Za-z0-9_]*\s*(?:in|=)\s*([A-Za-z0-9_]+)')
      .allMatches(template)) {
    final variable = match.group(1)!;
    if (_innoSetupLiquidVariables.contains(variable)) continue;
    issues.add(
      ContractIssue(
        _windowsTemplatePath,
        'unknown Liquid variable "$variable" in a loop/assignment',
        line: _lineOf(template, match.start),
      ),
    );
  }

  final ifCount = RegExp(r'\{%\s*if\b').allMatches(template).length;
  final endifCount = RegExp(r'\{%\s*endif\s*%\}').allMatches(template).length;
  if (ifCount != endifCount) {
    issues.add(
      ContractIssue(
        _windowsTemplatePath,
        'unbalanced Liquid conditionals: $ifCount {% if %} vs $endifCount {% endif %}',
      ),
    );
  }

  final code = _sectionBody(template, 'code');
  if (code != null) {
    for (var i = 0; i < code.lines.length; i++) {
      if (code.lines[i].contains('{{') || code.lines[i].contains('{%')) {
        issues.add(
          ContractIssue(
            _windowsTemplatePath,
            '[Code] contains a Liquid delimiter; the file is rendered by Liquid '
                'before ISCC runs, so it would silently change the upgrade logic',
            line: code.headerLine + 1 + i,
          ),
        );
      }
    }
  }
}

void _checkInnoLanguages(
  RepoView repo,
  String template,
  List<ContractIssue> issues,
) {
  final section = _sectionBody(template, 'languages');
  if (section == null) {
    issues.add(ContractIssue(_windowsTemplatePath, 'no [Languages] section'));
    return;
  }
  final files = RegExp(r'MessagesFile:\s*"([^"]+)"')
      .allMatches(section.lines.join('\n'))
      .map((Match m) => m.group(1)!.replaceAll('\\', '/'))
      .toList();
  if (files.length != 4) {
    issues.add(
      ContractIssue(
        _windowsTemplatePath,
        '[Languages] must list the four shipped languages, found ${files.length}',
        line: section.headerLine,
      ),
    );
  }
  for (final expected in <String>[
    'compiler:Default.isl',
    'compiler:Languages/ChineseSimplified.isl',
    'compiler:Languages/ChineseTraditional.isl',
    'compiler:Languages/Japanese.isl',
  ]) {
    if (!files.contains(expected)) {
      issues.add(
        ContractIssue(
          _windowsTemplatePath,
          '[Languages] is missing $expected; a dropped language file makes the '
              'installer fall back to English',
          line: section.headerLine,
        ),
      );
    }
  }

  // The vendored unofficial translations must match both the template and the
  // copy step in ci.yml: Inno Setup ships no Chinese .isl, so a file that is
  // not copied into the compiler's Languages\ directory fails at compile time.
  final referenced = files
      .map(_languageFileName)
      .where((String file) => !_innoOfficialLanguages.contains(file))
      .toSet();
  final vendored = repo.listFiles(_windowsLanguagesDir).toSet();
  if (referenced.length != vendored.length || !referenced.containsAll(vendored)) {
    issues.add(
      ContractIssue(
        _windowsLanguagesDir,
        'vendored language files $vendored do not match the unofficial files '
            'referenced by [Languages] $referenced',
      ),
    );
  }

  final setupScript = _readFile(repo, _innoSetupScriptPath, issues);
  if (setupScript == null) return;
  final copyBlock = RegExp(r'foreach \(\$name in @\(([\s\S]*?)\)\)').firstMatch(setupScript);
  if (copyBlock == null) {
    issues.add(
      ContractIssue(
        _innoSetupScriptPath,
        'cannot locate the vendored language copy list (foreach \$name in @(...))',
      ),
    );
  } else {
    final copied = RegExp(r"'([^']+\.isl)'")
        .allMatches(copyBlock.group(1)!)
        .map((Match m) => m.group(1)!)
        .toSet();
    if (copied.length != vendored.length || !copied.containsAll(vendored)) {
      issues.add(
        ContractIssue(
          _innoSetupScriptPath,
          'the Inno Setup copy step copies $copied but $vendored is vendored; '
              'the installer would fail to find a language file at compile time',
        ),
      );
    }
  }
}

/// `compiler:Languages\ChineseSimplified.isl` -> `ChineseSimplified.isl`.
String _languageFileName(String messagesFile) {
  final withoutPrefix = messagesFile.replaceFirst('compiler:', '');
  return p.posix.basename(withoutPrefix.replaceAll('\\', '/'));
}

void _checkInnoCustomMessages(String template, List<ContractIssue> issues) {
  final languagesSection = _sectionBody(template, 'languages');
  if (languagesSection == null) return;
  final languages = RegExp(r'Name:\s*"([^"]+)"')
      .allMatches(languagesSection.lines.join('\n'))
      .map((Match m) => m.group(1)!)
      .toList();
  final messages = _sectionBody(template, 'custommessages');
  if (messages == null) {
    issues.add(ContractIssue(_windowsTemplatePath, 'no [CustomMessages] section'));
    return;
  }

  final keys = <String>{};
  final present = <String>{};
  for (var i = 0; i < messages.lines.length; i++) {
    final match = RegExp(r'^\s*([A-Za-z]+)\.([A-Za-z0-9_]+)\s*=').firstMatch(messages.lines[i]);
    if (match == null) continue;
    keys.add(match.group(2)!);
    present.add('${match.group(1)}.${match.group(2)}');
  }
  if (keys.isEmpty) {
    issues.add(ContractIssue(_windowsTemplatePath, '[CustomMessages] has no entries'));
    return;
  }
  for (final key in keys) {
    for (final language in languages) {
      if (!present.contains('$language.$key')) {
        issues.add(
          ContractIssue(
            _windowsTemplatePath,
            '[CustomMessages] key "$key" has no "$language" translation; the '
                'wizard would show the key name',
            line: messages.headerLine,
          ),
        );
      }
    }
  }

  final code = _sectionBody(template, 'code');
  if (code != null) {
    for (var i = 0; i < code.lines.length; i++) {
      for (final match in RegExp(r"CustomMessage\(\s*'([^']+)'\s*\)").allMatches(code.lines[i])) {
        if (keys.contains(match.group(1))) continue;
        issues.add(
          ContractIssue(
            _windowsTemplatePath,
            'CustomMessage(\'${match.group(1)}\') is not defined in [CustomMessages]',
            line: code.headerLine + 1 + i,
          ),
        );
      }
    }
  }
}

void _checkInnoInstallDelete(String template, List<ContractIssue> issues) {
  final section = _sectionBody(template, 'installdelete');
  if (section == null) {
    issues.add(ContractIssue(_windowsTemplatePath, 'no [InstallDelete] section'));
    return;
  }
  final names = RegExp(r'Name:\s*"([^"]+)"')
      .allMatches(section.lines.join('\n'))
      .map((Match m) => m.group(1)!)
      .toList();
  if (names.isEmpty) {
    issues.add(ContractIssue(_windowsTemplatePath, '[InstallDelete] has no Name entries'));
    return;
  }
  for (final name in names) {
    final normalized = name.replaceAll(RegExp(r'\\+$'), '');
    if (normalized == r'{app}\*' || normalized == '{app}') {
      issues.add(
        ContractIssue(
          _windowsTemplatePath,
          '[InstallDelete] deletes the whole install directory ($name)',
          line: section.headerLine,
        ),
      );
      continue;
    }
    if (RegExp(r'\\(db|log)(\\|$)').hasMatch(normalized)) {
      issues.add(
        ContractIssue(
          _windowsTemplatePath,
          '[InstallDelete] touches user data ($name); lib/common/dirs.dart can fall '
              'back to writing under the install directory',
          line: section.headerLine,
        ),
      );
    }
  }
}

void _checkInnoMinVersion(
  RepoView repo,
  String template,
  List<ContractIssue> issues,
) {
  final setup = _sectionBody(template, 'setup');
  if (setup == null) {
    issues.add(ContractIssue(_windowsTemplatePath, 'no [Setup] section'));
    return;
  }
  final match = RegExp(r'^\s*MinVersion\s*=\s*(\S+)\s*$', multiLine: true)
      .firstMatch(setup.lines.join('\n'));
  if (match == null) {
    issues.add(ContractIssue(_windowsTemplatePath, '[Setup] has no MinVersion'));
    return;
  }
  final floor = match.group(1)!;
  final buildMatch = RegExp(r'^10\.0\.(\d+)$').firstMatch(floor);
  if (buildMatch == null) {
    issues.add(
      ContractIssue(
        _windowsTemplatePath,
        'MinVersion "$floor" is not of the form 10.0.<build>',
        line: setup.headerLine,
      ),
    );
    return;
  }
  final build = buildMatch.group(1)!;
  const runner = 'windows/runner/main.cpp';
  if (!repo.exists(runner)) {
    issues.add(ContractIssue(runner, 'file is missing'));
    return;
  }
  if (!repo.read(runner).contains(build)) {
    issues.add(
      ContractIssue(
        _windowsTemplatePath,
        'MinVersion build $build does not match the runtime floor enforced by $runner',
        line: setup.headerLine,
      ),
    );
  }
}

// --- macOS ------------------------------------------------------------------

void _checkMacos(
  RepoView repo,
  Map<String, dynamic> config,
  List<ContractIssue> issues,
) {
  final title = _stringAt(config, 'title');
  if (title == null || title.trim().isEmpty) {
    issues.add(ContractIssue(_dmgConfigPath, 'title is missing'));
  }

  final contents = config['contents'];
  if (contents is! List || contents.isEmpty) {
    issues.add(ContractIssue(_dmgConfigPath, 'contents must be a non-empty list'));
    return;
  }

  final productName = _readProductName(repo, issues);
  var fileCount = 0;
  var applicationsLink = 0;
  final window = config['window'];
  num? windowWidth;
  num? windowHeight;
  if (window is Map<String, dynamic>) {
    final size = window['size'];
    if (size is Map<String, dynamic>) {
      windowWidth = size['width'] as num?;
      windowHeight = size['height'] as num?;
    }
  }

  for (var i = 0; i < contents.length; i++) {
    final item = contents[i];
    if (item is! Map<String, dynamic>) {
      issues.add(ContractIssue(_dmgConfigPath, 'contents[$i] is not a mapping'));
      continue;
    }
    final type = item['type'];
    final path = item['path'];
    if (type is! String || !const <String>{'file', 'link', 'position'}.contains(type)) {
      issues.add(ContractIssue(_dmgConfigPath, 'contents[$i].type "$type" is not file / link / position'));
    }
    if (item['x'] is! num || item['y'] is! num) {
      issues.add(ContractIssue(_dmgConfigPath, 'contents[$i] needs numeric x and y'));
    }
    if (path is! String) {
      issues.add(ContractIssue(_dmgConfigPath, 'contents[$i].path is missing'));
      continue;
    }
    if (type == 'file') {
      fileCount++;
      if (productName != null) {
        final basename = p.posix.basename(path);
        if (basename != '$productName.app') {
          issues.add(
            ContractIssue(
              _dmgConfigPath,
              'contents[$i].path "$path" does not match PRODUCT_NAME "$productName" '
                  'from $_macAppInfoPath (expected "$productName.app")',
            ),
          );
        }
      }
    }
    if (type == 'link' && path == '/Applications') applicationsLink++;
    if (windowWidth != null && windowHeight != null && item['x'] is num && item['y'] is num) {
      final x = item['x'] as num;
      final y = item['y'] as num;
      if (x < 0 || y < 0 || x > windowWidth || y > windowHeight) {
        issues.add(
          ContractIssue(
            _dmgConfigPath,
            'contents[$i] at ($x, $y) falls outside the '
                '${windowWidth.toInt()}x${windowHeight.toInt()} window',
          ),
        );
      }
    }
  }
  if (fileCount != 1) {
    issues.add(ContractIssue(_dmgConfigPath, 'expected exactly one type: file item, found $fileCount'));
  }
  if (applicationsLink != 1) {
    issues.add(
      ContractIssue(_dmgConfigPath, 'expected exactly one link to /Applications, found $applicationsLink'),
    );
  }

  final infoPlist = _readFile(repo, _macInfoPlistPath, issues);
  if (infoPlist == null) return;
  for (final key in <String>['CFBundleShortVersionString', 'CFBundleVersion']) {
    final expected = key == 'CFBundleShortVersionString'
        ? r'$(FLUTTER_BUILD_NAME)'
        : r'$(FLUTTER_BUILD_NUMBER)';
    final value = RegExp('<key>$key</key>\\s*<string>([^<]*)</string>')
        .firstMatch(infoPlist)
        ?.group(1)
        ?.trim();
    if (value == null) {
      issues.add(ContractIssue(_macInfoPlistPath, '$key is missing'));
    } else if (value != expected) {
      issues.add(
        ContractIssue(
          _macInfoPlistPath,
          '$key is "$value" but must be "$expected"; a literal version drifts from pubspec.yaml',
        ),
      );
    }
  }
}

String? _readProductName(RepoView repo, List<ContractIssue> issues) {
  final content = _readFile(repo, _macAppInfoPath, issues);
  if (content == null) return null;
  final match = RegExp(r'^\s*PRODUCT_NAME\s*=\s*(.*)$', multiLine: true).firstMatch(content);
  if (match == null) {
    issues.add(ContractIssue(_macAppInfoPath, 'PRODUCT_NAME is missing'));
    return null;
  }
  return match.group(1)!.trim();
}

// --- Linux ------------------------------------------------------------------

void _checkLinux(
  RepoView repo,
  Map<String, dynamic>? pubspec,
  Map<String, dynamic>? deb,
  Map<String, dynamic>? appImage,
  List<ContractIssue> issues,
) {
  if (deb != null) _checkDebConfig(repo, deb, issues);
  if (appImage != null) _checkAppImageConfig(repo, appImage, issues);

  final cmake = _readFile(repo, _linuxCMakePath, issues);
  final appName = _stringAt(pubspec, 'name');
  if (cmake != null) {
    final binary = RegExp(r'set\(BINARY_NAME\s+"([^"]+)"\)').firstMatch(cmake)?.group(1);
    if (binary == null) {
      issues.add(ContractIssue(_linuxCMakePath, 'set(BINARY_NAME "...") is missing'));
    } else if (appName != null && binary != appName) {
      issues.add(
        ContractIssue(
          _linuxCMakePath,
          'BINARY_NAME "$binary" differs from the package name "$appName"; the deb '
              'desktop file, /usr/bin symlink and install path are derived from it',
        ),
      );
    }
  }
}

void _checkDebConfig(
  RepoView repo,
  Map<String, dynamic> deb,
  List<ContractIssue> issues,
) {
  final packageName = _stringAt(deb, 'package_name');
  if (packageName == null || packageName.isEmpty) {
    issues.add(ContractIssue(_debConfigPath, 'package_name is required'));
  } else if (!RegExp(r'^[a-z0-9][a-z0-9+.-]*$').hasMatch(packageName)) {
    issues.add(
      ContractIssue(
        _debConfigPath,
        'package_name "$packageName" is outside the Debian policy character set '
            '(lowercase letters, digits, + . -)',
      ),
    );
  }

  final maintainer = deb['maintainer'];
  if (maintainer is! Map<String, dynamic>) {
    issues.add(ContractIssue(_debConfigPath, 'maintainer is required'));
  } else {
    for (final field in <String>['name', 'email']) {
      final value = maintainer[field];
      if (value is! String || value.trim().isEmpty) {
        issues.add(ContractIssue(_debConfigPath, 'maintainer.$field is required'));
      }
    }
  }

  final installedSize = deb['installed_size'];
  if (installedSize is! int || installedSize <= 0) {
    issues.add(ContractIssue(_debConfigPath, 'installed_size must be a positive integer'));
  }

  final dependencies = deb['dependencies'];
  if (dependencies is! List || dependencies.isEmpty) {
    issues.add(ContractIssue(_debConfigPath, 'dependencies must be a non-empty list'));
  } else {
    final normalized = <String>[];
    for (final dependency in dependencies) {
      if (dependency is! String) {
        issues.add(ContractIssue(_debConfigPath, 'dependency "$dependency" is not a string'));
        continue;
      }
      final compact = dependency.replaceAll(RegExp(r'\s+'), ' ');
      normalized.add(compact);
      if (!RegExp(r'^[a-z0-9][a-z0-9+.-]*(\s*\((<<|<=|=|>=|>>)\s*[0-9A-Za-z.+~:-]+\))?$')
          .hasMatch(compact)) {
        issues.add(
          ContractIssue(
            _debConfigPath,
            'dependency "$dependency" is not "name" or "name (>= version)"',
          ),
        );
      }
    }
    if (!normalized.contains('libc6 (>= 2.35)')) {
      issues.add(
        ContractIssue(
          _debConfigPath,
          'libc6 (>= 2.35) is missing; the floor is Ubuntu 22.04 / Debian 12 (issue #23)',
        ),
      );
    }
  }

  _checkIconAndCategories(repo, deb, _debConfigPath, issues);
}

void _checkAppImageConfig(
  RepoView repo,
  Map<String, dynamic> config,
  List<ContractIssue> issues,
) {
  final displayName = _stringAt(config, 'display_name');
  if (displayName == null || displayName.trim().isEmpty) {
    issues.add(ContractIssue(_appImageConfigPath, 'display_name is required'));
  }
  _checkIconAndCategories(repo, config, _appImageConfigPath, issues);
}

void _checkIconAndCategories(
  RepoView repo,
  Map<String, dynamic> config,
  String path,
  List<ContractIssue> issues,
) {
  final icon = _stringAt(config, 'icon');
  if (icon == null || icon.isEmpty) {
    issues.add(ContractIssue(path, 'icon is required'));
  } else if (!repo.exists(icon)) {
    issues.add(ContractIssue(path, 'icon "$icon" does not exist'));
  } else if (!icon.toLowerCase().endsWith('.png')) {
    issues.add(ContractIssue(path, 'icon "$icon" is not a PNG'));
  }

  final genericName = _stringAt(config, 'generic_name');
  if (genericName == null || genericName.trim().isEmpty) {
    issues.add(ContractIssue(path, 'generic_name is required'));
  }

  final keywords = config['keywords'];
  if (keywords is! List || keywords.isEmpty) {
    issues.add(ContractIssue(path, 'keywords must be a non-empty list'));
  }

  final categories = config['categories'];
  if (categories is! List || categories.isEmpty) {
    issues.add(ContractIssue(path, 'categories must be a non-empty list'));
    return;
  }
  for (final category in categories) {
    if (category is! String || !_freedesktopCategories.contains(category)) {
      issues.add(
        ContractIssue(path, 'category "$category" is not a freedesktop menu category'),
      );
    }
  }
  // freedesktop.org: Audio and Video are sub-categories, so they require the
  // main AudioVideo category. appimagetool warns about this today and says the
  // warning becomes fatal in the future; dpkg-deb does not check it at all.
  final present = categories.whereType<String>().toSet();
  if ((present.contains('Audio') || present.contains('Video')) &&
      !present.contains('AudioVideo')) {
    issues.add(
      ContractIssue(
        path,
        'categories contain Audio/Video without AudioVideo; freedesktop.org '
            'requires the main AudioVideo category alongside them',
      ),
    );
  }
}

void _checkDisplayNameConsistency(
  Map<String, dynamic> exe,
  Map<String, dynamic> deb,
  Map<String, dynamic> appImage,
  List<ContractIssue> issues,
) {
  final names = <String, String?>{
    _windowsConfigPath: _stringAt(exe, 'display_name'),
    _debConfigPath: _stringAt(deb, 'display_name'),
    _appImageConfigPath: _stringAt(appImage, 'display_name'),
  };
  final distinct = names.values.whereType<String>().toSet();
  if (distinct.length > 1) {
    final detail = names.entries.map((e) => '${e.key}=${e.value}').join(', ');
    issues.add(ContractIssue(_windowsConfigPath, 'display_name differs across platforms: $detail'));
  }
}

// --- version literals --------------------------------------------------------

/// Files under the three packaging directories, minus the vendored `.isl`
/// translations (which legitimately contain version-looking strings).
List<String> _packagingFiles(RepoView repo) {
  final files = <String>[];
  for (final platform in _platforms) {
    final root = '$platform/packaging';
    for (final target in repo.listDirectories(root)) {
      final dir = '$root/$target';
      for (final name in repo.listFiles(dir)) {
        if (!_isPackagingConfig(name)) continue;
        files.add('$dir/$name');
      }
    }
  }
  return files;
}

bool _isPackagingConfig(String name) {
  final lower = name.toLowerCase();
  return lower.endsWith('.yaml') || lower.endsWith('.yml') || lower.endsWith('.iss');
}

/// The package version comes from pubspec.yaml only. A literal copy in a config
/// or template silently disagrees after the next release bump.
void _checkNoVersionLiterals(
  RepoView repo,
  Map<String, dynamic>? pubspec,
  List<ContractIssue> issues,
) {
  final version = _stringAt(pubspec, 'version');
  if (version == null) {
    issues.add(ContractIssue(_pubspecPath, 'version is missing'));
    return;
  }
  final buildName = version.split('+').first;
  final pattern = RegExp('(?<![\\d.])${RegExp.escape(buildName)}(?!\\d)');

  for (final file in _packagingFiles(repo)) {
    final lines = repo.read(file).split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (_isComment(file, lines[i])) continue;
      if (!pattern.hasMatch(lines[i])) continue;
      issues.add(
        ContractIssue(
          file,
          'literal version "$buildName" in packaging configuration; the version '
              'must come from pubspec.yaml',
          line: i + 1,
        ),
      );
    }
  }
}

bool _isComment(String file, String line) {
  final trimmed = line.trimLeft();
  if (file.endsWith('.yaml') || file.endsWith('.yml')) return trimmed.startsWith('#');
  if (file.endsWith('.iss')) return trimmed.startsWith(';') || trimmed.startsWith('//');
  return false;
}

// --- packager pin ------------------------------------------------------------

void _checkPackagerPin(
  RepoView repo,
  List<_MatrixEntry>? matrix,
  GlobalFastforge fastforge,
  List<ContractIssue> issues,
) {
  final pubspec = repo.exists(_dryRunPubspecPath)
      ? _parseYamlMap(_dryRunPubspecPath, repo.read(_dryRunPubspecPath), issues)
      : null;
  final dependencies = pubspec?['dependencies'];
  final pinValue = dependencies is Map<String, dynamic>
      ? dependencies['flutter_app_packager']
      : null;
  final pin = pinValue is String
      ? pinValue
      : pinValue is Map<String, dynamic>
          ? pinValue['version'] as String?
          : null;
  if (pin == null) {
    issues.add(
      ContractIssue(
        _dryRunPubspecPath,
        'dependencies.flutter_app_packager must pin the packager the dry run uses',
      ),
    );
  } else if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(pin)) {
    issues.add(
      ContractIssue(
        _dryRunPubspecPath,
        'flutter_app_packager must be an exact version, got "$pin"',
      ),
    );
  }

  final lock = repo.exists(_dryRunLockPath)
      ? _parseYamlMap(_dryRunLockPath, repo.read(_dryRunLockPath), issues)
      : null;
  final lockedPackager = _lockedVersion(lock, 'flutter_app_packager');

  if (fastforge.lock == null) {
    issues.add(
      ContractIssue(
        kFastforgeGlobalLockPath,
        'cannot read the activated fastforge lock file; run `dart pub global '
            'activate fastforge $_expectedFastforgeVersion` (D7: fail instead of skipping)',
      ),
    );
  }
  final globalLock = fastforge.lock == null
      ? null
      : _parseYamlMap(kFastforgeGlobalLockPath, fastforge.lock!, issues);
  final globalPackager = _lockedVersion(globalLock, 'flutter_app_packager');

  final versions = <String, String?>{
    'dry run pin': pin,
    _dryRunLockPath: lockedPackager,
    kFastforgeGlobalLockPath: globalPackager,
  };
  if (pin != null && lockedPackager != null && pin != lockedPackager) {
    issues.add(
      ContractIssue(
        _dryRunLockPath,
        'flutter_app_packager is pinned to $pin but the lock resolved $lockedPackager; '
            'run `dart pub get` in tool/packaging/dry_run',
      ),
    );
  }
  if (lockedPackager != null && globalPackager != null && lockedPackager != globalPackager) {
    issues.add(
      ContractIssue(
        kFastforgeGlobalLockPath,
        'fastforge resolves flutter_app_packager $globalPackager but this repo locks '
            '$lockedPackager; the dry run would validate a different packager than the '
            'tag build ($versions)',
      ),
    );
  }

  if (fastforge.version == null) {
    issues.add(
      ContractIssue(
        kFastforgePackageConfigPath,
        'cannot read the activated fastforge version; run `dart pub global '
            'activate fastforge $_expectedFastforgeVersion`',
      ),
    );
  } else if (matrix != null) {
    final ci = repo.exists(_ciPath) ? repo.read(_ciPath) : '';
    final activated = RegExp(r'dart pub global activate fastforge\s+(\S+)')
        .allMatches(ci)
        .map((Match m) => m.group(1)!)
        .toSet();
    if (activated.isEmpty) {
      issues.add(ContractIssue(_ciPath, 'ci.yml never activates fastforge'));
    } else if (activated.length > 1) {
      issues.add(ContractIssue(_ciPath, 'ci.yml activates more than one fastforge version: $activated'));
    } else if (activated.single != fastforge.version) {
      issues.add(
        ContractIssue(
          _ciPath,
          'ci.yml activates fastforge ${activated.single} but ${fastforge.version} is '
              'installed locally; the dry run and the tag build must use the same maker',
        ),
      );
    }
  }
}

String? _lockedVersion(Map<String, dynamic>? lock, String package) {
  final packages = lock?['packages'];
  if (packages is! Map<String, dynamic>) return null;
  final entry = packages[package];
  if (entry is! Map<String, dynamic>) return null;
  return entry['version'] as String?;
}

// --- generic helpers ---------------------------------------------------------

int _lineOf(String content, int offset) =>
    '\n'.allMatches(content.substring(0, offset)).length + 1;

class _SectionBody {
  const _SectionBody(this.headerLine, this.lines);

  /// 1-based line number of the section header.
  final int headerLine;
  final List<String> lines;
}

/// Returns the lines of a section, ending at the next line whose first
/// non-blank character is `[` — the same rule ISCC uses.
_SectionBody? _sectionBody(String content, String section) {
  final lines = content.split('\n');
  final header = RegExp(r'^\s*\[([^\]]*)\]');
  for (var i = 0; i < lines.length; i++) {
    final match = header.firstMatch(lines[i]);
    if (match == null) continue;
    if (match.group(1)!.trim().toLowerCase() != section.toLowerCase()) continue;
    final body = <String>[];
    for (var j = i + 1; j < lines.length; j++) {
      if (RegExp(r'^\s*\[').hasMatch(lines[j])) break;
      body.add(lines[j]);
    }
    return _SectionBody(i + 1, body);
  }
  return null;
}

/// Exposed for the fixture that guards the `^\[` vs `^\s*\[` trap (§3.5): an
/// indented `[` must end the section, exactly like ISCC.
List<String> sectionBodyLines(String content, String section) =>
    _sectionBody(content, section)?.lines ?? const <String>[];
