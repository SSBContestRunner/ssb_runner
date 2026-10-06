import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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

  test('exportLogArchive returns null and writes nothing when cancelled',
      () async {
    _mockSaveLocation(null);

    expect(await exportLogArchive(), isNull);
  });
}
