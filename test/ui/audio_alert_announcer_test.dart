import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/audio/audio_alert_state.dart';
import 'package:ssb_runner/ui/main_page/audio_alert_toaster.dart';

void main() {
  test('announces a fault that starts while the session runs', () {
    final announcer = AudioAlertAnnouncer();

    expect(
      announcer.shouldAnnounce(
        previous: AudioAlertReason.none,
        current: AudioAlertReason.muted,
        running: true,
      ),
      isTrue,
    );
  });

  test('never announces outside a running session', () {
    final announcer = AudioAlertAnnouncer();

    expect(
      announcer.shouldAnnounce(
        previous: AudioAlertReason.none,
        current: AudioAlertReason.muted,
        running: false,
      ),
      isFalse,
    );
  });

  test('a permission is consumed by the first announcement', () {
    final announcer = AudioAlertAnnouncer();
    announcer.shouldAnnounce(
      previous: AudioAlertReason.none,
      current: AudioAlertReason.low,
      running: true,
    );

    // A change between two faults is not a new "none → fault" edge.
    expect(
      announcer.shouldAnnounce(
        previous: AudioAlertReason.low,
        current: AudioAlertReason.muted,
        running: true,
      ),
      isFalse,
    );
  });

  test('recovery clears the allowance, so a relapse announces again', () {
    final announcer = AudioAlertAnnouncer();
    bool edge(AudioAlertReason previous, AudioAlertReason current) {
      return announcer.shouldAnnounce(
        previous: previous,
        current: current,
        running: true,
      );
    }

    expect(edge(AudioAlertReason.none, AudioAlertReason.muted), isTrue);
    expect(edge(AudioAlertReason.muted, AudioAlertReason.none), isFalse);
    expect(edge(AudioAlertReason.none, AudioAlertReason.muted), isTrue);
  });

  test('a new session starts with a fresh allowance', () {
    final announcer = AudioAlertAnnouncer();
    announcer.shouldAnnounce(
      previous: AudioAlertReason.none,
      current: AudioAlertReason.noDevice,
      running: true,
    );

    announcer.reset();

    expect(
      announcer.shouldAnnounce(
        previous: AudioAlertReason.none,
        current: AudioAlertReason.noDevice,
        running: true,
      ),
      isTrue,
    );
  });
}
