import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/logging/boot_beat.dart';

void main() {
  test('maps boot phases to the native enum', () {
    expect(bootPhaseValue('preFrame'), beatPhasePreFrame);
    expect(bootPhaseValue('booting'), beatPhaseBooting);
    expect(bootPhaseValue('firstFrame'), beatPhaseFirstFrame);
    expect(bootPhaseValue('ready'), beatPhaseReady);
    expect(bootPhaseValue('unknown'), beatPhasePreFrame);
  });

  testWidgets('beats periodically and stops once ready', (tester) async {
    var phase = 'preFrame';
    var step = 0;
    final calls = <(int, int)>[];

    final beat = BootBeat(
      beat: (value, index) => calls.add((value, index)),
      phase: () => phase,
      step: () => step,
      interval: const Duration(seconds: 2),
    );

    beat.start();
    expect(calls, <(int, int)>[(beatPhasePreFrame, 0)]);
    expect(beat.isRunning, isTrue);

    phase = 'booting';
    step = 2;
    await tester.pump(const Duration(seconds: 2));
    expect(calls.last, (beatPhaseBooting, 2));

    phase = 'firstFrame';
    step = 4;
    await tester.pump(const Duration(seconds: 2));
    expect(calls.last, (beatPhaseFirstFrame, 4));

    phase = 'ready';
    await tester.pump(const Duration(seconds: 2));
    expect(calls.last, (beatPhaseReady, 4));
    expect(beat.isRunning, isFalse);

    final sent = calls.length;
    await tester.pump(const Duration(seconds: 6));
    expect(calls.length, sent);
  });

  testWidgets('start is idempotent and stop cancels the timer', (tester) async {
    final calls = <(int, int)>[];
    final beat = BootBeat(
      beat: (value, index) => calls.add((value, index)),
      phase: () => 'booting',
      step: () => 1,
      interval: const Duration(seconds: 1),
    );

    beat.start();
    beat.start();
    expect(calls.length, 1);

    beat.stop();
    await tester.pump(const Duration(seconds: 3));
    expect(calls.length, 1);
  });
}
