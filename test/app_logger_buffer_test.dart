import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/logging/app_logger.dart';

void main() {
  test('replays pre-frame records in order with their timestamps', () async {
    final directory = await Directory.systemTemp.createTemp('ssb_buffer_test');
    addTearDown(() => directory.delete(recursive: true));

    final buffered = AppLogger.buffered();
    buffered.info('boot one', tag: 'boot');
    buffered.debug('boot two', tag: 'audio');
    buffered.warn('boot three', tag: 'storage');

    final pending = buffered.bufferedEvents;
    expect(pending, hasLength(3));
    // The printer renders the event's own (UTC) timestamp on the first line.
    final firstTimestamp = pending.first.lines.first.split(' ').first;

    final restored = await AppLogger.restoreFileBacked(
      directory: directory.path,
      header: '# session header',
      pending: pending,
    );
    restored.info('after frame', tag: 'boot');
    await restored.flush();

    final content = await File('${directory.path}/latest.log').readAsString();

    final headerIndex = content.indexOf('# session header');
    final firstIndex = content.indexOf('msg="boot one"');
    final secondIndex = content.indexOf('msg="boot two"');
    final thirdIndex = content.indexOf('msg="boot three"');
    final liveIndex = content.indexOf('msg="after frame"');

    expect(headerIndex, greaterThanOrEqualTo(0));
    expect(firstIndex, greaterThan(headerIndex));
    expect(secondIndex, greaterThan(firstIndex));
    expect(thirdIndex, greaterThan(secondIndex));
    expect(liveIndex, greaterThan(thirdIndex));

    expect(content, contains(firstTimestamp));
  });
}
