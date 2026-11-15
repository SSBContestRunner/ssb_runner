import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:ssb_runner/audio/audio_alert_state.dart';
import 'package:ssb_runner/audio/audio_output_probe.dart';
import 'package:ssb_runner/logging/app_logger.dart';

/// Window visibility as seen by the monitor.
///
/// Implemented in the UI layer (`lib/ui/main_app/window_visibility.dart`) so the
/// audio layer never touches window_manager or any widget (design §4.1.1).
abstract interface class AudioWindowVisibility {
  bool get isVisible;
  Stream<bool> get changes;
  Future<void> dispose();
}

/// Watches the audio output and publishes [snapshot].
///
/// Event-driven when the platform offers it, with a periodic read that acts as
/// the fallback *and* as the health check: even a dead event channel can delay
/// a state change by only one poll interval (design §4.3.1).
class AudioOutputMonitor {
  AudioOutputMonitor({
    AudioOutputProbe? probe,
    AudioEngineStatus Function()? readEngine,
    AudioAlertAdjudicator? adjudicator,
    DateTime Function()? clock,
    Future<void> Function(Future<void> Function() task)? sampleScheduler,
    this.visibilityFactory,
    bool disabled = false,
    Duration? pollInterval,
  }) : _probe = probe ?? createAudioOutputProbe(),
       _readEngine = readEngine ?? readSoLoudEngineStatus,
       _adjudicator = adjudicator ?? AudioAlertAdjudicator(),
       _now = clock ?? DateTime.now,
       _sampleScheduler = sampleScheduler ?? _scheduleIdle,
       _disabled = disabled || _disabledByEnvironment,
       pollInterval = pollInterval ?? _defaultPollInterval();

  /// `SSB_RUNNER_DISABLE_AUDIO=1` skips engine initialisation in CI, so the
  /// monitor has to stay completely silent there (design §4.2.1).
  static const String _disableAudioEnv = 'SSB_RUNNER_DISABLE_AUDIO';

  static bool get _disabledByEnvironment =>
      Platform.environment[_disableAudioEnv] == '1';

  /// Fallback read interval while the window is visible.
  final Duration pollInterval;

  /// Fallback read interval while the window is hidden / minimised.
  static const Duration hiddenPollInterval = Duration(seconds: 10);

  /// Wait for a settled value before the badge appears or disappears.
  static const Duration recheckDelay = Duration(milliseconds: 600);

  /// Minimum spacing between event-driven samples (design §5 F).
  ///
  /// Dragging the volume slider emits ten to twenty property changes per
  /// second, each of which used to trigger a full sample. 300 ms keeps the
  /// badge inside the one-second target and cuts the read rate by an order of
  /// magnitude.
  static const Duration eventThrottle = Duration(milliseconds: 300);

  /// A sample that occupies the UI isolate longer than this gets a warning.
  ///
  /// The post-change budget is 50 microseconds, so anything near a frame
  /// boundary means expensive work slipped back into the sampling path
  /// (design §5 H).
  static const Duration slowSampleThreshold = Duration(milliseconds: 8);

  /// Budget for the platform round-trip, `null` where it is out of process.
  ///
  /// macOS and Windows answer on the platform main thread, so a slow reply
  /// jolts the window even though it never enters the Dart frame budget.
  /// Linux forks `pactl` by design and takes tens of milliseconds per read,
  /// so reporting it there would be a permanent false alarm (design §5 H).
  static final Duration? platformReadThreshold = Platform.isLinux
      ? null
      : const Duration(milliseconds: 8);

  final AudioOutputProbe _probe;
  final AudioEngineStatus Function() _readEngine;
  final AudioAlertAdjudicator _adjudicator;
  final DateTime Function() _now;

  /// Runs one sample in the scheduler's idle phase.
  ///
  /// Injected in tests so the deferral can be asserted without a live frame
  /// loop; production always uses [Priority.idle] (design §5 G).
  final Future<void> Function(Future<void> Function() task) _sampleScheduler;

  final bool _disabled;

  /// Resolved on [start] so the window handle exists by then; `null` keeps the
  /// poll rate at the visible-window value.
  final AudioWindowVisibility? Function()? visibilityFactory;

  AudioWindowVisibility? _visibility;

  final ValueNotifier<AudioMonitorSnapshot> snapshot =
      ValueNotifier<AudioMonitorSnapshot>(AudioMonitorSnapshot.initial);

  bool _started = false;
  bool _visible = true;
  bool _sampling = false;
  bool _unknownLogged = false;
  bool _firstReadingLogged = false;
  bool _slowSampleLogged = false;

  /// When the last event-driven sample was scheduled, for [eventThrottle].
  DateTime? _lastEventSampleAt;

  Timer? _pollTimer;
  Timer? _recheckTimer;
  StreamSubscription<void>? _eventsSub;
  StreamSubscription<bool>? _visibilitySub;

  /// Starts watching. Idempotent: a second call neither re-subscribes nor
  /// starts a second timer.
  void start() {
    if (_started) return;
    _started = true;

    if (_disabled) {
      log.warn(
        'audio output monitor disabled',
        tag: 'audio.monitor',
        fields: <String, Object?>{'env': _disableAudioEnv},
      );
      snapshot.value = const AudioMonitorSnapshot(disabled: true);
      return;
    }

    _subscribeEvents();
    _subscribeVisibility();
    _restartPollTimer();
    unawaited(_scheduleSample(eventDriven: false));
  }

  /// Stops watching. Idempotent and safe to call from the exit path.
  void stop() {
    if (!_started) return;
    _started = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    _recheckTimer?.cancel();
    _recheckTimer = null;
    final events = _eventsSub;
    _eventsSub = null;
    unawaited(events?.cancel());
    final visibility = _visibilitySub;
    _visibilitySub = null;
    unawaited(visibility?.cancel());
    final windowVisibility = _visibility;
    _visibility = null;
    unawaited(windowVisibility?.dispose());
    unawaited(_probe.dispose());
  }

  void dispose() {
    stop();
    snapshot.dispose();
  }

  /// Reads the output state now instead of waiting for the next poll.
  ///
  /// Used by the pre-flight "check again" button (design §5 E1).
  Future<void> refresh() => _scheduleSample(eventDriven: false);

  void _subscribeEvents() {
    if (!_probe.supportsEvents) return;
    try {
      _eventsSub = _probe.events.listen(
        (_) => _onProbeEvent(),
        onError: (Object error, StackTrace stackTrace) {
          // Polling keeps the monitor correct; just record the degradation.
          log.warn(
            'audio output events unavailable, polling only',
            tag: 'audio.monitor',
            error: error,
            stackTrace: stackTrace,
          );
        },
      );
    } catch (error, stackTrace) {
      log.warn(
        'audio output events could not be subscribed',
        tag: 'audio.monitor',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _subscribeVisibility() {
    final factory = visibilityFactory;
    if (factory == null) return;

    final AudioWindowVisibility? visibility;
    try {
      visibility = factory();
    } catch (error, stackTrace) {
      log.warn(
        'window visibility unavailable, polling at full rate',
        tag: 'audio.monitor',
        error: error,
        stackTrace: stackTrace,
      );
      return;
    }
    if (visibility == null) return;
    _visibility = visibility;

    _visible = visibility.isVisible;
    try {
      _visibilitySub = visibility.changes.listen(_onVisibilityChanged);
    } catch (error, stackTrace) {
      log.warn(
        'window visibility events unavailable',
        tag: 'audio.monitor',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _onVisibilityChanged(bool visible) {
    if (visible == _visible) return;
    _visible = visible;
    _restartPollTimer();
    if (visible) {
      // Catch up immediately: the state may have changed while hidden.
      unawaited(_scheduleSample(eventDriven: false));
    }
  }

  void _onProbeEvent() {
    final now = _now();
    final last = _lastEventSampleAt;
    if (last != null && now.difference(last) < eventThrottle) return;
    _lastEventSampleAt = now;
    unawaited(_scheduleSample(eventDriven: true));
  }

  /// Re-reads visibility from the window handle.
  ///
  /// Platforms that never deliver the visibility events would otherwise keep
  /// polling at the full rate forever; this is the "read `isMinimized` in the
  /// poll loop" fallback of design §4.1.1.
  void _refreshVisibility() {
    final visibility = _visibility;
    if (visibility == null) return;
    final visible = visibility.isVisible;
    if (visible == _visible) return;
    _visible = visible;
    _restartPollTimer();
  }

  /// Queues one sample for the idle phase (design §5 G).
  ///
  /// Timers and platform events can fire while a frame is being built; sampling
  /// at [Priority.idle] moves the read between frames, turning a potential
  /// dropped frame into a slightly later sample.
  Future<void> _scheduleSample({required bool eventDriven}) {
    if (!_started || _disabled) return Future<void>.value();
    return _sampleScheduler(() => _sample(eventDriven: eventDriven));
  }

  static Future<void> _scheduleIdle(Future<void> Function() task) =>
      SchedulerBinding.instance.scheduleTask<void>(
        task,
        Priority.idle,
        debugLabel: 'audio output sample',
      );

  Future<void> _sample({required bool eventDriven}) async {
    if (!_started || _disabled) return;
    // A slow platform read must not stack up (Linux forks a process).
    if (_sampling) return;
    _sampling = true;

    try {
      _refreshVisibility();
      // The platform leg is timed on its own: it runs on the platform main
      // thread, so a slow reply is a jolt even though it never occupies the
      // Dart frame budget.
      final platformStopwatch = kDebugMode ? (Stopwatch()..start()) : null;
      final status = await _probe.read();
      platformStopwatch?.stop();
      if (!_started) return;
      // Only the synchronous part after the platform reply occupies the UI
      // isolate, so that is what the slow-sample budget measures.
      final stopwatch = kDebugMode ? (Stopwatch()..start()) : null;
      final engine = _readEngine();
      _apply(status, engine, eventDriven: eventDriven);
      stopwatch?.stop();
      if (stopwatch != null && platformStopwatch != null) {
        _reportSampleTiming(
          post: stopwatch.elapsed,
          platform: platformStopwatch.elapsed,
        );
      }
    } catch (error, stackTrace) {
      log.warn(
        'audio output read failed',
        tag: 'audio.monitor',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _sampling = false;
    }
  }

  void _apply(
    AudioOutputStatus status,
    AudioEngineStatus engine, {
    required bool eventDriven,
  }) {
    _reportFirstReadingOnce(status);
    _reportUnknownOnce(status);

    final previous = _adjudicator.current;
    final reason = _adjudicator.evaluate(
      status,
      engine,
      now: _now(),
      eventDriven: eventDriven,
    );

    snapshot.value = AudioMonitorSnapshot(
      reason: reason,
      volume: status.volume,
      muted: status.muted,
      deviceName: status.deviceName,
      source: status.source,
      windowVisible: _visible,
    );

    if (reason != previous) {
      _logTransition(previous, reason, status);
    }

    if (eventDriven && _adjudicator.hasPending) {
      _recheckTimer?.cancel();
      _recheckTimer = Timer(
        recheckDelay,
        () => unawaited(_scheduleSample(eventDriven: true)),
      );
    }
  }

  /// Records the first reading at debug level.
  ///
  /// Not a periodic log: only the first usable sample is recorded, and it is
  /// invisible unless verbose logging is on. It is the fastest way to tell
  /// "the platform answered" from "the probe silently degrades".
  void _reportFirstReadingOnce(AudioOutputStatus status) {
    if (_firstReadingLogged) return;
    _firstReadingLogged = true;
    log.debug(
      'audio output first reading',
      tag: 'audio.monitor',
      fields: <String, Object?>{
        'volume': status.volume,
        'muted': status.muted,
        'device': status.deviceName,
        'source': status.source.name,
      },
    );
  }

  void _logTransition(
    AudioAlertReason from,
    AudioAlertReason to,
    AudioOutputStatus status,
  ) {
    final fields = <String, Object?>{
      'from': from.name,
      'to': to.name,
      'volume': status.volume,
      'muted': status.muted,
      'device': status.deviceName,
      'source': status.source.name,
    };
    if (to == AudioAlertReason.engineDown || to == AudioAlertReason.noDevice) {
      log.warn('audio output alert', tag: 'audio.monitor', fields: fields);
      return;
    }
    log.info('audio output state changed', tag: 'audio.monitor', fields: fields);
  }

  /// `unknown` is a confidence drop, not a fault: log the first degradation
  /// once so the fallback is visible in diagnostics without flooding.
  void _reportUnknownOnce(AudioOutputStatus status) {
    if (status.source == AudioProbeSource.error ||
        status.source == AudioProbeSource.unsupported) {
      if (_unknownLogged) return;
      _unknownLogged = true;
      log.info(
        'audio output probe unavailable',
        tag: 'audio.monitor',
        fields: <String, Object?>{'source': status.source.name},
      );
      return;
    }
    _unknownLogged = false;
  }

  /// Records a sample that ran over budget on either leg.
  ///
  /// Logged once per slow streak rather than every time, so a permanently slow
  /// platform cannot turn into a log flood (design §5 H).
  void _reportSampleTiming({
    required Duration post,
    required Duration platform,
  }) {
    final platformBudget = platformReadThreshold;
    final postSlow = post >= slowSampleThreshold;
    final platformSlow = platformBudget != null && platform >= platformBudget;
    if (!postSlow && !platformSlow) {
      _slowSampleLogged = false;
      return;
    }
    if (_slowSampleLogged) return;
    _slowSampleLogged = true;
    log.warn(
      'audio output sample was slow',
      tag: 'audio.monitor',
      fields: <String, Object?>{
        'elapsedMs': post.inMicroseconds / 1000,
        'platformMs': platform.inMicroseconds / 1000,
        'thresholdMs': slowSampleThreshold.inMilliseconds,
        'platformThresholdMs': platformBudget?.inMilliseconds,
      },
    );
  }

  void _restartPollTimer() {
    _pollTimer?.cancel();
    final interval = _visible ? pollInterval : hiddenPollInterval;
    _pollTimer = Timer.periodic(
      interval,
      (_) => unawaited(_scheduleSample(eventDriven: false)),
    );
  }

  static Duration _defaultPollInterval() =>
      Platform.isLinux ? const Duration(seconds: 3) : const Duration(seconds: 2);
}
