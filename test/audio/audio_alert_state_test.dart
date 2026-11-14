import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/audio/audio_alert_state.dart';

const _engineReady = AudioEngineStatus(
  initialized: true,
  playbackDeviceCount: 2,
);

AudioOutputStatus _status({bool? muted, double? volume, bool? hasDevice}) {
  return AudioOutputStatus(
    hasDevice: hasDevice ?? true,
    volume: volume ?? 0.5,
    muted: muted ?? false,
    source: AudioProbeSource.coreAudio,
  );
}

void main() {
  group('classifyAudioAlert', () {
    test('engine down wins over every other reading', () {
      expect(
        classifyAudioAlert(
          status: _status(muted: true, volume: 0),
          engine: const AudioEngineStatus(initialized: false),
        ),
        AudioAlertReason.engineDown,
      );
    });

    test('no playback device is reported as noDevice', () {
      expect(
        classifyAudioAlert(
          status: _status(),
          engine: const AudioEngineStatus(
            initialized: true,
            playbackDeviceCount: 0,
          ),
        ),
        AudioAlertReason.noDevice,
      );
    });

    test('uninitialized audio device is reported as noDevice', () {
      expect(
        classifyAudioAlert(
          status: _status(),
          engine: const AudioEngineStatus(
            initialized: true,
            playbackDeviceCount: 1,
            deviceUninitialized: true,
          ),
        ),
        AudioAlertReason.noDevice,
      );
    });

    test('stopped device state is not a fault', () {
      expect(
        classifyAudioAlert(status: _status(), engine: _engineReady),
        AudioAlertReason.none,
      );
    });

    test('mute is reported before a low volume', () {
      expect(
        classifyAudioAlert(
          status: _status(muted: true, volume: 0.02),
          engine: _engineReady,
        ),
        AudioAlertReason.muted,
      );
    });

    test('volume below 10% is low', () {
      for (final volume in [0.0, 0.05, 0.099]) {
        expect(
          classifyAudioAlert(
            status: _status(volume: volume),
            engine: _engineReady,
          ),
          AudioAlertReason.low,
          reason: 'volume $volume should be low',
        );
      }
      expect(
        classifyAudioAlert(
          status: _status(volume: 0.10),
          engine: _engineReady,
        ),
        AudioAlertReason.none,
      );
      expect(
        classifyAudioAlert(
          status: _status(volume: 0.2),
          engine: _engineReady,
        ),
        AudioAlertReason.none,
      );
    });

    test('unknown readings never produce an alert', () {
      expect(
        classifyAudioAlert(
          status: const AudioOutputStatus(source: AudioProbeSource.error),
          engine: AudioEngineStatus.unknown,
        ),
        AudioAlertReason.none,
      );
      expect(
        classifyAudioAlert(
          status: const AudioOutputStatus(source: AudioProbeSource.unsupported),
          engine: const AudioEngineStatus(initialized: true),
        ),
        AudioAlertReason.none,
      );
    });
  });

  group('AudioAlertAdjudicator', () {
    final start = DateTime(2026, 1, 1, 12);

    test('mute is hard and applies on the first event sample', () {
      final adjudicator = AudioAlertAdjudicator();

      final state = adjudicator.evaluate(
        _status(muted: true),
        _engineReady,
        now: start,
        eventDriven: true,
      );

      expect(state, AudioAlertReason.muted);
      expect(adjudicator.hasPending, isFalse);
    });

    test('low volume needs the 600 ms quiet window on the event path', () {
      final adjudicator = AudioAlertAdjudicator();

      // A slider drag: the candidate stays the same, so the window is not
      // restarted and the badge must not appear before it elapsed.
      expect(
        adjudicator.evaluate(
          _status(volume: 0.04),
          _engineReady,
          now: start,
          eventDriven: true,
        ),
        AudioAlertReason.none,
      );
      expect(
        adjudicator.evaluate(
          _status(volume: 0.06),
          _engineReady,
          now: start.add(const Duration(milliseconds: 300)),
          eventDriven: true,
        ),
        AudioAlertReason.none,
      );
      expect(
        adjudicator.evaluate(
          _status(volume: 0.06),
          _engineReady,
          now: start.add(const Duration(milliseconds: 599)),
          eventDriven: true,
        ),
        AudioAlertReason.none,
      );

      expect(
        adjudicator.evaluate(
          _status(volume: 0.06),
          _engineReady,
          now: start.add(const Duration(milliseconds: 600)),
          eventDriven: true,
        ),
        AudioAlertReason.low,
      );
      expect(adjudicator.current, AudioAlertReason.low);
    });

    test('a candidate change restarts the quiet window', () {
      final adjudicator = AudioAlertAdjudicator();

      adjudicator.evaluate(
        _status(volume: 0.05),
        _engineReady,
        now: start,
        eventDriven: true,
      );
      // The operator dragged back up: the pending low must be dropped.
      expect(
        adjudicator.evaluate(
          _status(volume: 0.5),
          _engineReady,
          now: start.add(const Duration(milliseconds: 300)),
          eventDriven: true,
        ),
        AudioAlertReason.none,
      );
      expect(adjudicator.hasPending, isFalse);
    });

    test('leaving an alert needs the same quiet window', () {
      final adjudicator = AudioAlertAdjudicator();
      adjudicator.evaluate(
        _status(muted: true),
        _engineReady,
        now: start,
        eventDriven: true,
      );

      expect(
        adjudicator.evaluate(
          _status(muted: false),
          _engineReady,
          now: start.add(const Duration(milliseconds: 100)),
          eventDriven: true,
        ),
        AudioAlertReason.muted,
      );
      expect(
        adjudicator.evaluate(
          _status(muted: false),
          _engineReady,
          now: start.add(const Duration(milliseconds: 800)),
          eventDriven: true,
        ),
        AudioAlertReason.none,
      );
    });

    test('the polling path needs two consecutive samples', () {
      final adjudicator = AudioAlertAdjudicator();

      expect(
        adjudicator.evaluate(
          _status(volume: 0.05),
          _engineReady,
          now: start,
          eventDriven: false,
        ),
        AudioAlertReason.none,
      );
      expect(
        adjudicator.evaluate(
          _status(volume: 0.05),
          _engineReady,
          now: start.add(const Duration(seconds: 2)),
          eventDriven: false,
        ),
        AudioAlertReason.low,
      );
    });

    test('unknown never produces a badge', () {
      final adjudicator = AudioAlertAdjudicator();
      for (var i = 0; i < 5; i++) {
        expect(
          adjudicator.evaluate(
            const AudioOutputStatus(source: AudioProbeSource.unsupported),
            AudioEngineStatus.unknown,
            now: start.add(Duration(seconds: i * 2)),
            eventDriven: false,
          ),
          AudioAlertReason.none,
        );
      }
      expect(adjudicator.hasPending, isFalse);
    });

    test('unknown samples hold the current state', () {
      final adjudicator = AudioAlertAdjudicator();
      adjudicator.evaluate(
        _status(muted: true),
        _engineReady,
        now: start,
        eventDriven: true,
      );

      for (var i = 0; i < 5; i++) {
        final state = adjudicator.evaluate(
          const AudioOutputStatus(source: AudioProbeSource.error),
          AudioEngineStatus.unknown,
          now: start.add(Duration(seconds: i + 1)),
          eventDriven: false,
        );
        expect(state, AudioAlertReason.muted);
      }
    });
  });
}
