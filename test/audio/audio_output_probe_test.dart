import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/audio/audio_alert_state.dart';
import 'package:ssb_runner/audio/audio_output_probe.dart';

void main() {
  group('platform map', () {
    test('reads volume, mute and device name', () {
      final status = statusFromPlatformMap({
        'hasDevice': true,
        'deviceName': 'MacBook Pro Speakers',
        'volume': 0.42,
        'muted': false,
      });

      expect(status.hasDevice, isTrue);
      expect(status.deviceName, 'MacBook Pro Speakers');
      expect(status.volume, 0.42);
      expect(status.muted, isFalse);
      expect(status.isUnknown, isFalse);
    });

    test('keeps missing or mistyped fields unknown', () {
      final status = statusFromPlatformMap({
        'hasDevice': 'yes',
        'volume': 'loud',
      });

      expect(status.hasDevice, isNull);
      expect(status.volume, isNull);
      expect(status.muted, isNull);
      expect(status.isUnknown, isTrue);
    });

    test('clamps out-of-range volumes', () {
      expect(
        statusFromPlatformMap({'volume': 1.7, 'muted': false}).volume,
        1.0,
      );
      expect(
        statusFromPlatformMap({'volume': -0.2, 'muted': false}).volume,
        0.0,
      );
    });
  });

  group('pactl subscribe lines', () {
    test('accepts sink events', () {
      expect(isPactlSinkEvent("Event 'change' on sink #0"), isTrue);
      expect(isPactlSinkEvent("Event 'new' on sink #3"), isTrue);
    });

    test('ignores per-stream and capture events', () {
      expect(isPactlSinkEvent("Event 'change' on sink-input #12"), isFalse);
      expect(isPactlSinkEvent("Event 'change' on source #2"), isFalse);
      expect(isPactlSinkEvent(""), isFalse);
    });
  });

  group('pactl parsing', () {
    test('reads the first percentage of a sink volume line', () {
      const output =
          'Volume: front-left: 32768 /  50% / -18.06 dB,'
          '   front-right: 32768 /  50% / -18.06 dB\n'
          '        balance 0.00\n';

      expect(parsePactlVolume(output), 0.5);
    });

    test('reads muted and unmuted', () {
      expect(parsePactlMute('Mute: yes\n'), isTrue);
      expect(parsePactlMute('Mute: no\n'), isFalse);
      expect(parsePactlMute('something else'), isNull);
    });

    test('returns null for unparsable output', () {
      expect(parsePactlVolume('Failure: No such entity'), isNull);
      expect(parsePactlVolume(''), isNull);
    });

    test('clamps percentages above 100', () {
      expect(parsePactlVolume('Volume: front-left: 70000 / 107% / 0.00 dB'), 1.0);
    });
  });

  group('wpctl parsing', () {
    test('reads a plain volume', () {
      final status = parseWpctlVolume('Volume: 0.65\n');

      expect(status.volume, 0.65);
      expect(status.muted, isFalse);
      expect(status.source, AudioProbeSource.wpctl);
    });

    test('reads the muted marker', () {
      final status = parseWpctlVolume('Volume: 0.30 [MUTED]\n');

      expect(status.volume, 0.30);
      expect(status.muted, isTrue);
    });

    test('keeps an unparsable volume unknown but the device present', () {
      final status = parseWpctlVolume('Cannot connect to PipeWire\n');

      expect(status.volume, isNull);
      expect(status.hasDevice, isTrue);
      expect(status.muted, isNull);
      expect(status.isUnknown, isTrue);
    });
  });
}
