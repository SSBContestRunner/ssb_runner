import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/logging/app_logger.dart';

void main() {
  test('writes structured records and a context dump to disk', () async {
    final directory = await Directory.systemTemp.createTemp('ssb_logger_test');
    addTearDown(() => directory.delete(recursive: true));

    final appLogger = AppLogger.fileBacked(
      directory: directory.path,
      header: '# session header',
    );
    await appLogger.ready;

    appLogger.info('hello', tag: 'boot', fields: <String, Object?>{'durMs': 7});
    appLogger.debug('before the failure', tag: 'audio');
    appLogger.error('boom', tag: 'crash', error: StateError('nope'));

    await appLogger.flush();

    final logFile = File('${directory.path}/latest.log');
    expect(logFile.existsSync(), isTrue);

    final content = await logFile.readAsString();
    expect(content, contains('# session header'));
    expect(content, contains('msg="hello"'));
    expect(content, contains('durMs=7'));
    expect(content, contains('msg="before the failure"'));
    expect(content, contains('CONTEXT DUMP'));
    expect(content, contains('error: Bad state: nope'));
  });

  test('redacts the home directory from messages and fields', () async {
    final home =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      return;
    }

    final directory = await Directory.systemTemp.createTemp('ssb_redact_test');
    addTearDown(() => directory.delete(recursive: true));

    final appLogger = AppLogger.fileBacked(
      directory: directory.path,
      header: '# header',
    );
    await appLogger.ready;

    final path = Platform.isWindows ? '$home\\data\\file' : '$home/data/file';
    appLogger.info(
      'reading $path',
      tag: 'io',
      fields: <String, Object?>{'path': path},
    );

    await appLogger.flush();

    final content = await File('${directory.path}/latest.log').readAsString();
    expect(content, contains('~'));
    expect(content, isNot(contains(home)));
  });

  test('console logger renders structured records with the logfmt printer', () {
    final lines = <String>[];

    runZoned(
      () => AppLogger.consoleOnly().warn(
        'disk almost full',
        tag: 'storage',
        fields: <String, Object?>{'pct': 91},
      ),
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) => lines.add(line),
      ),
    );

    final rendered = lines.join('\n');
    expect(rendered, contains('WARN'));
    expect(rendered, contains('storage'));
    expect(rendered, contains('msg="disk almost full"'));
    expect(rendered, contains('pct=91'));
    expect(rendered, isNot(contains("Instance of 'LogMessage'")));
  });
}
