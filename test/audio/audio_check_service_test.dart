import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/audio/audio_check_service.dart';

void main() {
  group('generateTestTonePcm', () {
    test('emits 0.8 s of 24 kHz mono 16-bit little-endian', () {
      final pcm = generateTestTonePcm();

      expect(pcm.lengthInBytes, 24000 * 2 * 8 ~/ 10);
    });

    test('starts and ends in near-silence because of the 30 ms fades', () {
      final pcm = generateTestTonePcm();
      final samples = pcm.buffer.asByteData();

      // The fade ends on a fraction of a sample, so "silent" is a small bound
      // rather than exactly zero.
      expect(samples.getInt16(0, Endian.little).abs(), lessThan(20));
      expect(
        samples.getInt16(pcm.lengthInBytes - 2, Endian.little).abs(),
        lessThan(20),
      );
    });

    test('carries an audible tone in each half', () {
      final pcm = generateTestTonePcm();
      final samples = pcm.buffer.asByteData();
      final sampleCount = pcm.lengthInBytes ~/ 2;

      int peak(int from, int to) {
        var maxAbs = 0;
        for (var index = from; index < to; index++) {
          final value = samples.getInt16(index * 2, Endian.little).abs();
          if (value > maxAbs) maxAbs = value;
        }
        return maxAbs;
      }

      expect(peak(0, sampleCount ~/ 2), greaterThan(3000));
      expect(peak(sampleCount ~/ 2, sampleCount), greaterThan(3000));
    });

    test('returns an empty buffer for a non-positive duration', () {
      expect(generateTestTonePcm(durationSeconds: 0).lengthInBytes, 0);
    });
  });

  test('the fallback tone is a valid PCM byte buffer', () {
    expect(generateTestTonePcm(), isA<Uint8List>());
  });

  test('play() reports failure when no engine is running', () async {
    // flutter test never initialises SoLoud, so the service must fail fast
    // instead of throwing out of the settings row.
    expect(await AudioCheckService().play(), isFalse);
  });
}
