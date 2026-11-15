// Fixtures for the L0 packaging contract (tool/packaging/packaging_contract.dart).
//
// Why these live in `flutter test` instead of a new job: the contract replaces a
// gate that used to be a handful of PowerShell regexes inside the installer smoke
// test, and a checker nobody checks is a new single point of failure. Every case
// here is a mutation of the real repository files, so the fixtures cannot drift
// into hand-written approximations of the templates.
//
// The real-configuration case also guards against false positives: if the
// checked-in templates stop passing, unrelated PRs would be blocked.

import 'package:flutter_test/flutter_test.dart';

import '../../tool/packaging/packaging_contract.dart';

const String _templatePath = 'windows/packaging/exe/installer.iss';
const String _windowsConfigPath = 'windows/packaging/exe/make_config.yaml';
const String _debConfigPath = 'linux/packaging/deb/make_config.yaml';
const String _appInfoPath = 'macos/Runner/Configs/AppInfo.xcconfig';

/// The values the real CI activation resolves (fastforge 0.6.12 ->
/// flutter_app_packager 0.6.13). Injected so the fixtures do not depend on a
/// pub cache being present; the real comparison runs in the contract job.
const GlobalFastforge _fastforge = GlobalFastforge(
  version: '0.6.12',
  lock: '''
packages:
  flutter_app_packager:
    dependency: transitive
    version: "0.6.13"
''',
);

void main() {
  const base = DiskRepo();

  test('the checked-in packaging configuration satisfies the contract', () {
    final errors = _errors(validatePackagingContract(base, fastforge: _fastforge));
    expect(errors, isEmpty, reason: errors.join('\n'));
  });

  test('a wrapped statement that starts a line with "[" fails at its line', () {
    final template = base.read(_templatePath);
    // Restore the shape of run 43702798064: the argument array folded onto the
    // next line, which ISCC parses as a section header.
    final wrapped = template.replaceFirst(
      '  FVersionLabel.Caption := FmtMessage(\n'
      "    CustomMessage('UpgradeVersionLine'), [Prev, PackageVersion]);",
      "  FVersionLabel.Caption := FmtMessage(CustomMessage('UpgradeVersionLine'),\n"
      '    [Prev, PackageVersion]);',
    );
    expect(wrapped, isNot(template), reason: 'fixture did not apply; update the template excerpt');
    // Derive the expected line from the mutated text: the contract is "reports
    // the continuation line", not "reports line 438". A hard-coded number goes
    // red whenever an unrelated edit shifts the template.
    final expectedLine =
        wrapped.split('\n').indexWhere((String line) => line.trimLeft().startsWith('[Prev')) + 1;
    expect(expectedLine, greaterThan(0), reason: 'fixture did not apply; update the template excerpt');

    final issues = validatePackagingContract(
      _OverlayRepo(base, <String, String>{_templatePath: wrapped}),
      fastforge: _fastforge,
    );
    final reported = issues
        .where((ContractIssue issue) => issue.message.contains('Invalid section tag'))
        .toList();
    expect(reported, hasLength(1));
    expect(reported.single.file, _templatePath);
    expect(reported.single.line, expectedLine);
    expect(reported.single.toAnnotation(), contains('line=$expectedLine'));
  });

  test('an indented "[" ends a section, matching ISCC', () {
    // The trap in the old smoke script: it ended sections on `^\[`, so an
    // indented `[` was invisible to every check that read a section body.
    const fixture = '[Code]\n'
        '  Value := 1;\n'
        '  [Prev, PackageVersion]);\n'
        '  Unreachable := 2;\n'
        '[Setup]\n'
        'AppId=1\n';
    expect(sectionBodyLines(fixture, 'Code'), <String>['  Value := 1;']);
  });

  test('an unknown Liquid variable is reported with its name', () {
    final template = base.read(_templatePath).replaceFirst('[Setup]', '[Setup]\nBogus={{BOGUS}}');
    final issues = validatePackagingContract(
      _OverlayRepo(base, <String, String>{_templatePath: template}),
      fastforge: _fastforge,
    );
    expect(
      issues.where(
        (ContractIssue issue) => issue.message.contains('unknown Liquid variable {{BOGUS}}'),
      ),
      hasLength(1),
    );
  });

  test('a changed PRODUCT_NAME breaks the dmg layout', () {
    final appInfo = base
        .read(_appInfoPath)
        .replaceFirst(RegExp(r'^PRODUCT_NAME.*$', multiLine: true), 'PRODUCT_NAME =  SSB Runner2 ');
    final issues = validatePackagingContract(
      _OverlayRepo(base, <String, String>{_appInfoPath: appInfo}),
      fastforge: _fastforge,
    );
    expect(
      issues.where(
        (ContractIssue issue) =>
            issue.file == 'macos/packaging/dmg/make_config.yaml' &&
            issue.message.contains('SSB Runner.app'),
      ),
      isNotEmpty,
    );
  });

  test('a missing Japanese translation is reported per language', () {
    final template = base.read(_templatePath).replaceFirst(
          RegExp(r'^japanese\.UpgradeTargetLine=.*$\n?', multiLine: true),
          '',
        );
    final issues = validatePackagingContract(
      _OverlayRepo(base, <String, String>{_templatePath: template}),
      fastforge: _fastforge,
    );
    expect(
      issues.where(
        (ContractIssue issue) => issue.message.contains('"UpgradeTargetLine" has no "japanese"'),
      ),
      hasLength(1),
    );
  });

  test('a missing deb maintainer is reported', () {
    final deb = base.read(_debConfigPath).replaceFirst(
          RegExp(r'^maintainer:\n(?:  .*\n)+', multiLine: true),
          '',
        );
    final issues = validatePackagingContract(
      _OverlayRepo(base, <String, String>{_debConfigPath: deb}),
      fastforge: _fastforge,
    );
    expect(
      issues.where(
        (ContractIssue issue) => issue.file == _debConfigPath && issue.message.contains('maintainer'),
      ),
      isNotEmpty,
    );
  });

  test('a display_name that drifts between platforms is reported', () {
    final config = base.read(_windowsConfigPath).replaceFirst(
          RegExp(r'^display_name:\s*.*$', multiLine: true),
          'display_name: SSB Runner Dev',
        );
    final issues = validatePackagingContract(
      _OverlayRepo(base, <String, String>{_windowsConfigPath: config}),
      fastforge: _fastforge,
    );
    expect(
      issues.where(
        (ContractIssue issue) => issue.message.contains('display_name differs across platforms'),
      ),
      hasLength(1),
    );
  });

  test('running validation on workflow_dispatch is rejected', () {
    const String ciPath = '.github/workflows/ci.yml';
    final ci = base.read(ciPath);
    // Reintroduce the overlap: the validate job would dry-run every platform on
    // the same dispatch that packages one of them for real.
    final mutated = ci.replaceFirst(
      "    if: >-\n"
      "      github.event_name == 'pull_request' ||\n"
      "      github.event_name == 'merge_group'\n"
      '    runs-on: windows-latest',
      "    if: >-\n"
      "      github.event_name == 'pull_request' ||\n"
      "      github.event_name == 'merge_group' ||\n"
      "      github.event_name == 'workflow_dispatch'\n"
      '    runs-on: windows-latest',
    );
    expect(mutated, isNot(ci), reason: 'fixture did not apply; update the ci.yml excerpt');

    final issues = validatePackagingContract(
      _OverlayRepo(base, <String, String>{ciPath: mutated}),
      fastforge: _fastforge,
    );
    final reported = issues
        .where(
          (ContractIssue issue) =>
              issue.message.contains('validate-packaging-windows') &&
              issue.message.contains('workflow_dispatch'),
        )
        .toList();
    expect(reported, hasLength(1));
    expect(reported.single.file, ciPath);
    // Derive the expected line instead of hard-coding it: take the validate
    // block up to its own `runs-on`, then find the injected line inside it.
    final start = mutated.indexOf('  validate-packaging-windows:');
    final end = mutated.indexOf('    runs-on: windows-latest', start);
    final expectedLine = mutated
            .substring(start, end)
            .split('\n')
            .lastIndexWhere((String line) => line.contains('workflow_dispatch')) +
        1 +
        '\n'.allMatches(mutated.substring(0, start)).length;
    expect(reported.single.line, expectedLine);
  });
}

List<String> _errors(List<ContractIssue> issues) => issues
    .where((ContractIssue issue) => issue.severity == ContractSeverity.error)
    .map((ContractIssue issue) => issue.toString())
    .toList();

/// [RepoView] over the real working tree with selected files replaced, so each
/// fixture is a one-field mutation of the shipped configuration.
class _OverlayRepo implements RepoView {
  _OverlayRepo(this.base, this.overrides);

  final RepoView base;
  final Map<String, String> overrides;

  @override
  String read(String path) => overrides[path] ?? base.read(path);

  @override
  bool exists(String path) => overrides.containsKey(path) || base.exists(path);

  @override
  bool isDirectory(String path) => base.isDirectory(path);

  @override
  List<String> listFiles(String directory) => base.listFiles(directory);

  @override
  List<String> listDirectories(String directory) => base.listDirectories(directory);
}
