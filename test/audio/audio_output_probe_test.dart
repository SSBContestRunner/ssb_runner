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

  group('pactl json parsing', () {
    const sinksJson = '''
[
  {
    "index": 0,
    "state": "SUSPENDED",
    "name": "alsa_output.pci-0000_00_1f.3.analog-stereo",
    "description": "Built-in Audio Analog Stereo",
    "mute": false,
    "volume": {
      "front-left": {"value": 32768, "value_percent": "50%", "db": "-18.06 dB"},
      "front-right": {"value": 32768, "value_percent": "50%", "db": "-18.06 dB"}
    }
  }
]
''';

    test('reads the name, volume and mute of every sink', () {
      final sinks = parsePactlSinks(sinksJson);

      expect(sinks, isNotNull);
      expect(sinks!, hasLength(1));
      expect(sinks.single.name, 'alsa_output.pci-0000_00_1f.3.analog-stereo');
      expect(sinks.single.volume, 0.5);
      expect(sinks.single.muted, isFalse);
    });

    test('clamps a volume above 100%', () {
      final sinks = parsePactlSinks('''
[
  {
    "name": "loud",
    "volume": {
      "mono": {"value": 70000}
    }
  }
]
''');

      expect(sinks!.single.volume, 1.0);
    });

    test('keeps a missing volume and mute unknown', () {
      final sinks = parsePactlSinks('[{"name": "broken"}]');

      expect(sinks!.single.name, 'broken');
      expect(sinks.single.volume, isNull);
      expect(sinks.single.muted, isNull);
    });

    test('an empty list means the server has no sink', () {
      expect(parsePactlSinks('[]'), isEmpty);
    });

    test('returns null for a pactl without --format=json', () {
      expect(
        parsePactlSinks('Sink #0\n\tState: SUSPENDED\n\tMute: no\n'),
        isNull,
      );
      expect(parsePactlSinks(''), isNull);
    });

    test('reads the default sink name', () {
      expect(
        parsePactlDefaultSink('{"default_sink_name": "alsa_output.speakers"}'),
        'alsa_output.speakers',
      );
    });

    test('a missing default sink name is null', () {
      expect(parsePactlDefaultSink('{"default_sink_name": ""}'), isNull);
      expect(parsePactlDefaultSink('{"server_name": "pulse"}'), isNull);
      expect(parsePactlDefaultSink('not json'), isNull);
    });
  });

  group('pactl default sink', () {
    const speakers = PactlSink(name: 'speakers');
    const headset = PactlSink(name: 'headset');

    test('a single sink is the default by definition', () {
      expect(selectPactlSink(const [speakers], null), same(speakers));
    });

    test('several sinks need a matching default name', () {
      expect(
        selectPactlSink(const [speakers, headset], 'headset'),
        same(headset),
      );
    });

    test('no default endpoint means no selectable sink', () {
      // No sinks at all, no default name, or a stale default name.
      expect(selectPactlSink(const [], null), isNull);
      expect(selectPactlSink(const [speakers, headset], null), isNull);
      expect(selectPactlSink(const [speakers, headset], 'unplugged'), isNull);
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
