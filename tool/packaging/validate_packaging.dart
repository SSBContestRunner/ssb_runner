// L0 entry point: `dart run tool/packaging/validate_packaging.dart`.
//
// Must run from the repository root: the checks read paths relative to the CWD
// (the same way fastforge resolves make_config.yaml).
//
// Exit code 0 means the three platforms' packaging configuration, the CI
// orchestration and the pinned packager version agree. Any error exit is 1 and
// prints one GitHub Actions annotation per violation.

import 'dart:io';

import 'packaging_contract.dart';

void main(List<String> args) {
  final cwd = Directory.current.path;
  if (!File('pubspec.yaml').existsSync() ||
      !Directory('windows/packaging').existsSync()) {
    stderr.writeln('::error::run this script from the repository root (CWD: $cwd)');
    exit(2);
  }

  final fastforge = GlobalFastforge.read();
  final issues = validatePackagingContract(const DiskRepo(), fastforge: fastforge);

  for (final issue in issues) {
    stdout.writeln(issue.toAnnotation());
  }

  final errors = issues
      .where((ContractIssue issue) => issue.severity == ContractSeverity.error)
      .length;
  final warnings = issues.length - errors;

  if (errors > 0) {
    stdout.writeln('');
    stdout.writeln('packaging contract: $errors error(s), $warnings warning(s)');
    exit(1);
  }

  stdout.writeln(
    'packaging contract: OK (linux, windows, macos; '
    'fastforge ${fastforge.version ?? 'unknown'}, $warnings warning(s))',
  );
}
