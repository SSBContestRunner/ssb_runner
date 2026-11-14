import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/audio/audio_alert_state.dart';
import 'package:ssb_runner/audio/audio_output_monitor.dart';
import 'package:ssb_runner/audio/audio_output_probe.dart';

const _engineReady = AudioEngineStatus(
  initialized: true,
  playbackDeviceCount: 1,
);

AudioOutputStatus _status({bool? muted, double volume = 0.5}) {
  return AudioOutputStatus(
    hasDevice: true,
    volume: volume,
    muted: muted ?? false,
    source: AudioProbeSource.coreAudio,
  );
}

class _FakeProbe implements AudioOutputProbe {
  _FakeProbe(this.status, {this.supportsEvents = false});

  AudioOutputStatus status;
  final StreamController<void> _events = StreamController<void>.broadcast();
  int reads = 0;

  @override
  final bool supportsEvents;

  @override
  Stream<void> get events => _events.stream;

  void emit() => _events.add(null);

  @override
  Future<AudioOutputStatus> read() async {
    reads++;
    return status;
  }

  @override
  Future<void> dispose() async {
    if (!_events.isClosed) await _events.close();
  }
}

class _FakeVisibility implements AudioWindowVisibility {
  _FakeVisibility(this._visible);

  bool _visible;
  final StreamController<bool> _changes = StreamController<bool>.broadcast();

  @override
  bool get isVisible => _visible;

  @override
  Stream<bool> get changes => _changes.stream;

  void update(bool visible) {
    _visible = visible;
    _changes.add(visible);
  }

  /// Changes the value without notifying, like a platform whose visibility
  /// events never arrive.
  void updateSilently(bool visible) {
    _visible = visible;
  }

  @override
  Future<void> dispose() async {
    if (!_changes.isClosed) await _changes.close();
  }
}

/// A probe whose event channel cannot be subscribed at all.
class _ThrowingEventsProbe extends _FakeProbe {
  _ThrowingEventsProbe(super.status) : super(supportsEvents: true);

  @override
  Stream<void> get events => throw StateError('no event channel');
}

AudioOutputMonitor _monitor(
  _FakeProbe probe, {
  bool disabled = false,
  AudioWindowVisibility Function()? visibilityFactory,
  DateTime Function()? clock,
}) {
  return AudioOutputMonitor(
    probe: probe,
    readEngine: () => _engineReady,
    clock: clock,
    visibilityFactory: visibilityFactory,
    disabled: disabled,
    pollInterval: const Duration(seconds: 2),
  );
}

void main() {
  testWidgets('a muted output shows up on the first sample', (tester) async {
    final probe = _FakeProbe(_status(muted: true));
    final monitor = _monitor(probe);

    monitor.start();
    await tester.pump();

    expect(monitor.snapshot.value.reason, AudioAlertReason.muted);
    expect(probe.reads, 1);
    monitor.dispose();
  });

  testWidgets('a low volume needs two polling samples', (tester) async {
    final probe = _FakeProbe(_status(volume: 0.05));
    final monitor = _monitor(probe);

    monitor.start();
    await tester.pump();
    expect(monitor.snapshot.value.reason, AudioAlertReason.none);

    await tester.pump(const Duration(seconds: 2));
    expect(monitor.snapshot.value.reason, AudioAlertReason.low);
    expect(probe.reads, 2);
    monitor.dispose();
  });

  testWidgets('recovery removes the alert', (tester) async {
    final probe = _FakeProbe(_status(muted: true));
    final monitor = _monitor(probe);

    monitor.start();
    await tester.pump();
    expect(monitor.snapshot.value.hasAlert, isTrue);

    probe.status = _status();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));

    expect(monitor.snapshot.value.reason, AudioAlertReason.none);
    monitor.dispose();
  });

  testWidgets('start() and stop() are idempotent', (tester) async {
    final probe = _FakeProbe(_status());
    final monitor = _monitor(probe);

    monitor.start();
    monitor.start();
    await tester.pump();
    expect(probe.reads, 1);

    monitor.stop();
    monitor.stop();
    await tester.pump(const Duration(seconds: 10));
    expect(probe.reads, 1);
    monitor.dispose();
  });

  testWidgets('disabled never reads and never alerts', (tester) async {
    final probe = _FakeProbe(_status(muted: true));
    final monitor = _monitor(probe, disabled: true);

    monitor.start();
    await tester.pump(const Duration(seconds: 4));

    expect(monitor.snapshot.value.disabled, isTrue);
    expect(monitor.snapshot.value.hasAlert, isFalse);
    expect(probe.reads, 0);
    monitor.dispose();
  });

  testWidgets('a hidden window drops the poll rate to 10 s', (tester) async {
    final probe = _FakeProbe(_status());
    final visibility = _FakeVisibility(true);
    final monitor = _monitor(probe, visibilityFactory: () => visibility);

    monitor.start();
    await tester.pump();
    expect(probe.reads, 1);

    visibility.update(false);
    await tester.pump();
    // The 2 s poll was replaced by a 10 s one.
    await tester.pump(const Duration(seconds: 2));
    expect(probe.reads, 1);

    await tester.pump(const Duration(seconds: 8));
    expect(probe.reads, 2);
    expect(monitor.snapshot.value.windowVisible, isFalse);

    visibility.update(true);
    await tester.pump();
    // Restoring visibility samples immediately instead of waiting.
    expect(probe.reads, 3);
    expect(monitor.snapshot.value.windowVisible, isTrue);

    monitor.dispose();
    await visibility.dispose();
  });

  testWidgets('events shorten the low-volume debounce to 600 ms', (
    tester,
  ) async {
    final probe = _FakeProbe(_status(volume: 0.04), supportsEvents: true);
    var now = DateTime(2026, 1, 1, 12);
    final monitor = _monitor(probe, clock: () => now);

    monitor.start();
    await tester.pump();
    expect(monitor.snapshot.value.reason, AudioAlertReason.none);

    probe.emit();
    await tester.pump();
    expect(monitor.snapshot.value.reason, AudioAlertReason.none);

    now = now.add(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    expect(monitor.snapshot.value.reason, AudioAlertReason.low);
    monitor.dispose();
  });

  testWidgets('a dead event channel does not stop the polling fallback', (
    tester,
  ) async {
    final probe = _FakeProbe(_status(muted: true), supportsEvents: true);
    // No event is ever emitted; the periodic read must still decide.
    final monitor = _monitor(probe);

    monitor.start();
    await tester.pump();

    expect(monitor.snapshot.value.reason, AudioAlertReason.muted);
    monitor.dispose();
  });

  testWidgets('an event channel that cannot be subscribed falls back cleanly', (
    tester,
  ) async {
    final probe = _ThrowingEventsProbe(_status(volume: 0.05));
    final monitor = _monitor(probe);

    monitor.start();
    await tester.pump();

    // The first sample was taken and no alert was asserted prematurely.
    expect(probe.reads, 1);
    expect(monitor.snapshot.value.reason, AudioAlertReason.none);

    await tester.pump(const Duration(seconds: 2));
    expect(monitor.snapshot.value.reason, AudioAlertReason.low);
    monitor.dispose();
  });

  testWidgets('a platform without visibility events still drops to 10 s', (
    tester,
  ) async {
    final probe = _FakeProbe(_status());
    final visibility = _FakeVisibility(true);
    final monitor = _monitor(probe, visibilityFactory: () => visibility);

    monitor.start();
    await tester.pump();
    expect(probe.reads, 1);

    // The window was minimised but no event was delivered.
    visibility.updateSilently(false);
    await tester.pump(const Duration(seconds: 2));
    expect(probe.reads, 2);
    expect(monitor.snapshot.value.windowVisible, isFalse);

    // The poll now runs at the hidden rate.
    await tester.pump(const Duration(seconds: 2));
    expect(probe.reads, 2);
    await tester.pump(const Duration(seconds: 8));
    expect(probe.reads, 3);

    monitor.dispose();
    await visibility.dispose();
  });
}
