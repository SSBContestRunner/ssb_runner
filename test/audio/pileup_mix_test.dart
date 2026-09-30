import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/audio/mix_pileup.dart';

Uint8List _tone({required int samples, required int amplitude}) {
  final bytes = Uint8List(samples * 2);
  final data = ByteData.sublistView(bytes);
  for (var index = 0; index < samples; index++) {
    data.setInt16(
      index * 2,
      (sin(index / 10) * amplitude).round(),
      Endian.little,
    );
  }
  return bytes;
}

void main() {
  test('the target keeps full gain instead of being divided by caller count',
      () {
    final target = _tone(samples: 240, amplitude: 1000);
    final interferer = _tone(samples: 240, amplitude: 1000);

    final mixed = mixPileup(target, [interferer]);

    final data = ByteData.sublistView(mixed);
    var targetPeak = 0;
    for (var index = 0; index < 240; index++) {
      targetPeak = max(targetPeak, data.getInt16(index * 2, Endian.little).abs());
    }
    // Interferers are offset by default, so the start is dominated by the
    // target; a plain ~/2 average would halve this.
    expect(targetPeak, greaterThan(900));
  });

  test('overlapping peaks are soft-limited instead of hard-clipped', () {
    final target = _tone(samples: 400, amplitude: 30000);
    final interferer = _tone(samples: 400, amplitude: 30000);

    final mixed = mixPileup(
      target,
      [interferer],
      offsetSamples: 0,
      interfererGain: 1.0,
    );

    final data = ByteData.sublistView(mixed);
    var clippedRun = 0;
    var maxRun = 0;
    for (var index = 0; index < 400; index++) {
      if (data.getInt16(index * 2, Endian.little).abs() == 32767) {
        clippedRun++;
        maxRun = max(maxRun, clippedRun);
      } else {
        clippedRun = 0;
      }
    }
    expect(maxRun, lessThan(4));
  });

  test('interferers are offset in time', () {
    final target = Uint8List(20);
    final interferer = _tone(samples: 20, amplitude: 2000);

    final mixed = mixPileup(target, [interferer], offsetSamples: 4);

    final data = ByteData.sublistView(mixed);
    expect(data.getInt16(0, Endian.little), 0);
    // The interferer starts at sample 4; its own sample 2 (a non-zero point on
    // the tone) lands at output sample 6.
    expect(data.getInt16(6 * 2, Endian.little).abs(), greaterThan(0));
  });
}
