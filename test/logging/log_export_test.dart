import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/logging/log_export.dart';
import 'package:ssb_runner/logging/log_paths.dart';
import 'package:ssb_runner/logging/log_session.dart';

void main() {
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
}
