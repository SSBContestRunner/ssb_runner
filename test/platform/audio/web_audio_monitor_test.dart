import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/audio/audio_alert_state.dart';
import 'package:ssb_runner/platform/audio/web/web_audio_monitor.dart';

void main() {
  test('an untouched engine stays silent', () {
    final harness = _Harness();
    addTearDown(harness.dispose);

    harness.monitor.start();

    expect(harness.monitor.snapshot.value.reason, AudioAlertReason.none);
  });

  test('a failed initialisation is an immediate engineDown', () {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.monitor.start();

    harness.initState.value = AudioInitState.failed;

    expect(harness.monitor.snapshot.value.reason, AudioAlertReason.engineDown);
  });

  test('ready but not initialised is engineDown', () {
    final harness = _Harness(initState: AudioInitState.ready);
    harness.engineInitialized = false;
    addTearDown(harness.dispose);

    harness.monitor.start();

    expect(harness.monitor.snapshot.value.reason, AudioAlertReason.engineDown);
  });

  for (final state in ['suspended', 'closed']) {
    test('a $state audio context is engineDown', () {
      final harness = _Harness(initState: AudioInitState.ready);
      harness.engineInitialized = true;
      harness.contextState = state;
      addTearDown(harness.dispose);

      harness.monitor.start();

      expect(
        harness.monitor.snapshot.value.reason,
        AudioAlertReason.engineDown,
      );
    });
  }

  test('a running context is healthy', () {
    final harness = _Harness(initState: AudioInitState.ready);
    harness.engineInitialized = true;
    harness.contextState = 'running';
    addTearDown(harness.dispose);

    harness.monitor.start();

    expect(harness.monitor.snapshot.value.reason, AudioAlertReason.none);
  });

  test('an unreadable context degrades silently', () {
    final harness = _Harness(initState: AudioInitState.ready);
    harness.engineInitialized = true;
    harness.contextState = null;
    addTearDown(harness.dispose);

    harness.monitor.start();

    expect(harness.monitor.snapshot.value.reason, AudioAlertReason.none);
  });

  test('a throwing engine reading is not a fault', () {
    final harness = _Harness(initState: AudioInitState.ready);
    harness.engineThrows = true;
    addTearDown(harness.dispose);

    harness.monitor.start();

    expect(harness.monitor.snapshot.value.reason, AudioAlertReason.none);
  });

  test('an uninitialized device with a live engine is engineDown', () {
    final harness = _Harness(initState: AudioInitState.ready);
    harness.engineInitialized = true;
    harness.deviceState = WebAudioDeviceState.uninitialized;
    addTearDown(harness.dispose);

    harness.monitor.start();

    expect(harness.monitor.snapshot.value.reason, AudioAlertReason.engineDown);
  });

  test('a hidden page does not sample', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.monitor.start();

    await harness.setVisible(false);
    harness.initState.value = AudioInitState.failed;

    expect(harness.monitor.snapshot.value.reason, AudioAlertReason.none);
    expect(harness.monitor.snapshot.value.windowVisible, isFalse);
  });

  test('recovery waits for the 600 ms quiet window', () async {
    final harness = _Harness(initState: AudioInitState.ready);
    harness.engineInitialized = false;
    addTearDown(harness.dispose);
    harness.monitor.start();
    expect(harness.monitor.snapshot.value.reason, AudioAlertReason.engineDown);

    harness.engineInitialized = true;
    await harness.setVisible(false);
    await harness.setVisible(true);

    final visibilityTask = harness.scheduler.tasks.last;
    expect(visibilityTask.delay, WebAudioMonitor.visibilityDelay);
    visibilityTask.fire();

    expect(harness.monitor.snapshot.value.reason, AudioAlertReason.engineDown);
    final recoveryTask = harness.scheduler.tasks.last;
    expect(recoveryTask.delay, WebAudioMonitor.recoveryDelay);

    recoveryTask.fire();

    expect(harness.monitor.snapshot.value.reason, AudioAlertReason.none);
  });

  test('a failed re-sample keeps the alert', () async {
    final harness = _Harness(initState: AudioInitState.ready);
    harness.engineInitialized = false;
    addTearDown(harness.dispose);
    harness.monitor.start();

    harness.engineInitialized = true;
    await harness.setVisible(false);
    await harness.setVisible(true);
    harness.scheduler.tasks.last.fire();
    final recoveryTask = harness.scheduler.tasks.last;

    // The engine dropped again before the window elapsed.
    harness.engineInitialized = false;
    recoveryTask.fire();

    expect(harness.monitor.snapshot.value.reason, AudioAlertReason.engineDown);
  });

  test('retry is single-flight and reports recovery', () async {
    final harness = _Harness(initState: AudioInitState.ready);
    harness.engineInitialized = false;
    addTearDown(harness.dispose);
    harness.monitor.start();

    final gate = Completer<bool>();
    harness.retryGate = gate;

    final first = harness.monitor.retry();
    final second = await harness.monitor.retry();

    expect(second, isFalse);
    expect(harness.retryCalls, 1);

    harness.engineInitialized = true;
    gate.complete(true);

    expect(await first, isTrue);
  });

  test('a failed retry stays in engineDown', () async {
    final harness = _Harness(initState: AudioInitState.ready);
    harness.engineInitialized = false;
    addTearDown(harness.dispose);
    harness.monitor.start();

    expect(await harness.monitor.retry(), isFalse);
    expect(harness.monitor.snapshot.value.reason, AudioAlertReason.engineDown);
  });
}

class _Harness {
  _Harness({AudioInitState initState = AudioInitState.notAttempted})
    : initState = ValueNotifier<AudioInitState>(initState);

  final ValueNotifier<AudioInitState> initState;
  final StreamController<bool> _visibility = StreamController<bool>.broadcast();
  final _FakeScheduler scheduler = _FakeScheduler();

  bool engineInitialized = false;
  bool engineThrows = false;
  WebAudioDeviceState deviceState = WebAudioDeviceState.stopped;
  String? contextState = 'running';
  bool visible = true;
  int retryCalls = 0;
  Completer<bool>? retryGate;
  bool retryResult = true;

  late final WebAudioMonitor monitor = WebAudioMonitor(
    initState: initState,
    engineInitialized: () {
      if (engineThrows) throw StateError('engine read failed');
      return engineInitialized;
    },
    deviceState: () => deviceState,
    audioContextState: () => contextState,
    isVisible: () => visible,
    visibilityChanges: _visibility.stream,
    retryInitialization: () {
      retryCalls++;
      final gate = retryGate;
      if (gate != null) return gate.future;
      return Future<bool>.value(retryResult);
    },
    scheduleTimer: scheduler.schedule,
  );

  Future<void> setVisible(bool value) async {
    visible = value;
    _visibility.add(value);
    await Future<void>.delayed(Duration.zero);
  }

  void dispose() {
    monitor.dispose();
    initState.dispose();
    _visibility.close();
  }
}

class _FakeScheduler {
  final List<_FakeTask> tasks = <_FakeTask>[];

  WebAudioTimer schedule(Duration delay, void Function() callback) {
    final task = _FakeTask(delay, callback);
    tasks.add(task);
    return task;
  }
}

class _FakeTask implements WebAudioTimer {
  _FakeTask(this.delay, this.callback);

  final Duration delay;
  final void Function() callback;
  bool cancelled = false;

  void fire() {
    if (!cancelled) callback();
  }

  @override
  void cancel() => cancelled = true;
}
