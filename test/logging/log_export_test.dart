import 'dart:io';

import 'package:archive/archive.dart';
import 'package:catcher_2/model/platform_type.dart';
import 'package:catcher_2/model/report.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/logging/crash_issue_reporter.dart';
import 'package:ssb_runner/logging/log_export.dart';
import 'package:ssb_runner/logging/log_paths.dart';
import 'package:ssb_runner/logging/log_session.dart';

/// Stubs the file_selector save dialog to resolve to [path], or to a cancel
/// when [path] is null.
void _mockSaveLocation(String? path) {
  const channel = MethodChannel('plugins.flutter.io/file_selector');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(channel, (call) async {
    return call.method == 'getSavePath' ? path : null;
  });
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('listLogFiles returns only sorted .log files', () async {
    final directory = await Directory.systemTemp.createTemp('ssb_logs_test');
    addTearDown(() => directory.delete(recursive: true));

    await File('${directory.path}/b.log').writeAsString('b');
    await File('${directory.path}/a.log').writeAsString('a');
    await File('${directory.path}/ignore.txt').writeAsString('x');

    final files = listLogFiles(directory.path);

    expect(files.map((file) => file.uri.pathSegments.last).toList(), <String>[
      'a.log',
      'b.log',
    ]);
  });

  test('listLogFiles tolerates a missing directory', () {
    expect(listLogFiles('/definitely/not/here'), isEmpty);
  });

  test(
    'diagnosticSummary includes the session header and the log tail',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ssb_summary_test',
      );
      addTearDown(() => directory.delete(recursive: true));

      await File(
        '${directory.path}/latest.log',
      ).writeAsString('line1\nline2\nline3\n');

      LogSession.location = LogLocation(path: directory.path, fallbackIndex: 0);
      LogSession.headerLines = <String>['os=test-os'];

      final summary = await diagnosticSummary(tailLines: 2);

      expect(summary, contains('os=test-os'));
      expect(summary, contains('line2'));
      expect(summary, contains('line3'));
      expect(summary, isNot(contains('line1')));
    },
  );

  test('diagnosticSummary can drop records from earlier app runs', () async {
    final directory = await Directory.systemTemp.createTemp(
      'ssb_summary_session_test',
    );
    addTearDown(() => directory.delete(recursive: true));

    await File('${directory.path}/latest.log').writeAsString(
      '# app=old\n# os=old\nold line\n'
      '# app=new\n# os=new\nnew line 1\nnew line 2\n',
    );

    LogSession.location = LogLocation(path: directory.path, fallbackIndex: 0);
    LogSession.headerLines = <String>['os=test-os'];

    final summary = await diagnosticSummary(
      tailLines: 10,
      currentSessionOnly: true,
    );

    expect(summary, contains('new line 1'));
    expect(summary, contains('new line 2'));
    expect(summary, isNot(contains('old line')));
  });

  test('redactPath hides standard user-home prefixes', () {
    expect(
      redactPath('/Users/someone/Applications/SSB Runner.app'),
      '~/Applications/SSB Runner.app',
    );
    expect(redactPath('/home/someone/ssb/app'), '~/ssb/app');
    expect(
      redactPath(r'C:\Users\someone\SSB Runner\app.exe'),
      r'~\SSB Runner\app.exe',
    );
    expect(
      redactText('msg="exe_dir=/Users/someone/app"'),
      'msg="exe_dir=~/app"',
    );
  });

  test('safeDeviceParameters removes machine identifiers', () {
    final safe = safeDeviceParameters(<String, dynamic>{
      'computerName': 'Wafer-Mac',
      'hostName': 'Darwin',
      'machineId': 'machine-id',
      'arch': 'arm64',
      'model': 'MacBookPro18,2',
      'memorySize': 68719476736,
    });

    expect(safe, isNot(contains('computerName')));
    expect(safe, isNot(contains('hostName')));
    expect(safe, isNot(contains('machineId')));
    expect(safe['arch'], 'arm64');
    expect(safe['model'], 'MacBookPro18,2');
  });

  test('crash issue payload omits machine identifiers', () async {
    final directory = await Directory.systemTemp.createTemp('ssb_payload_test');
    addTearDown(() => directory.delete(recursive: true));

    await File('${directory.path}/latest.log').writeAsString(
      '# app=old\n# os=old\nold line\n'
      '# app=new\n# os=new\ncurrent line\n',
    );

    LogSession.location = LogLocation(path: directory.path, fallbackIndex: 0);
    LogSession.headerLines = <String>['os=test-os'];

    final report = Report(
      StateError('boom'),
      StackTrace.current,
      DateTime.utc(2026, 10, 21),
      <String, dynamic>{'computerName': 'secret-machine', 'arch': 'arm64'},
      <String, dynamic>{'environment': 'release', 'appName': 'SSB Runner'},
      <String, dynamic>{},
      null,
      PlatformType.macOS,
      null,
    );

    final payload = await buildCrashIssuePayload(report);

    expect(payload.body, contains('## Device'));
    expect(payload.body, contains('arch=arm64'));
    expect(payload.body, isNot(contains('secret-machine')));
    expect(payload.body, contains('## Application'));
    expect(payload.body, contains('current line'));
    expect(payload.body, isNot(contains('old line')));
  });

  test('exportLogArchive writes the zip to the path the user picked', () async {
    final logs = await Directory.systemTemp.createTemp('ssb_export_logs');
    final target = await Directory.systemTemp.createTemp('ssb_export_target');
    addTearDown(() => logs.delete(recursive: true));
    addTearDown(() => target.delete(recursive: true));

    await File('${logs.path}/latest.log').writeAsString('boot ok\n');
    LogSession.location = LogLocation(path: logs.path, fallbackIndex: 0);
    LogSession.headerLines = <String>['os=test-os'];

    final destination = '${target.path}/picked.zip';
    _mockSaveLocation(destination);

    final file = await exportLogArchive();

    expect(file?.path, destination);
    final archive = ZipDecoder().decodeBytes(
      await File(destination).readAsBytes(),
    );
    expect(
      archive.files.map((entry) => entry.name),
      containsAll(<String>['diagnostic-summary.txt', 'logs/latest.log']),
    );
  });

  test(
    'exportLogArchive returns null and writes nothing when cancelled',
    () async {
      _mockSaveLocation(null);

      expect(await exportLogArchive(), isNull);
    },
  );
}
