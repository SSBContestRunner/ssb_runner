// Injected signals keep public names while the fields stay private.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ssb_runner/audio/audio_alert_state.dart';
import 'package:ssb_runner/platform/audio/web/web_audio_alert_source.dart';

/// How far the deferred engine initialisation progressed.
///
/// Browsers only allow audio to start inside a user gesture, so before the
/// first gesture the engine is simply "not attempted" and must not warn.
enum AudioInitState { notAttempted, ready, failed }

/// Device state as the web monitor understands it.
///
/// Mirrors the subset of SoLoud's `AudioDeviceState` that matters here so this
/// file stays free of plugin imports and runs in VM unit tests. `unknown` means
/// the reading failed; it is never treated as a fault.
enum WebAudioDeviceState {
  unknown,
  uninitialized,
  stopped,
  started,
  starting,
  stopping,
}

/// A cancellable delayed task, injectable so the quiet window is testable.
abstract interface class WebAudioTimer {
  void cancel();
}

typedef WebAudioTimerScheduler = WebAudioTimer Function(
  Duration delay,
  void Function() callback,
);

/// Turns the few signals a browser actually exposes into an
/// [AudioMonitorSnapshot] (design `web_audio_alert_design.md` §5.2).
///
/// The web port only ever reports [AudioAlertReason.engineDown]: system volume,
/// system mute and the output device list are not observable from a page, so
/// claiming to know them would produce false alarms.
class WebAudioMonitor implements WebAudioAlertSource {
  WebAudioMonitor({
    required ValueListenable<AudioInitState> initState,
    required bool Function() engineInitialized,
    required WebAudioDeviceState Function() deviceState,
    required String? Function() audioContextState,
    required bool Function() isVisible,
    required Stream<bool> visibilityChanges,
    required Future<bool> Function() retryInitialization,
    WebAudioTimerScheduler? scheduleTimer,
  }) : _initState = initState,
       _engineInitialized = engineInitialized,
       _deviceState = deviceState,
       _audioContextState = audioContextState,
       _isVisible = isVisible,
       _visibilityChanges = visibilityChanges,
       _retryInitialization = retryInitialization,
       _scheduleTimer = scheduleTimer ?? _scheduleWithTimer;

  /// The recovery quiet window; matches the desktop `recheckDelay`.
  static const Duration recoveryDelay = Duration(milliseconds: 600);

  /// The browser needs a moment to resume its audio context after the page
  /// becomes visible again, so the sample is deferred.
  static const Duration visibilityDelay = Duration(milliseconds: 300);

  final ValueListenable<AudioInitState> _initState;
  final bool Function() _engineInitialized;
  final WebAudioDeviceState Function() _deviceState;
  final String? Function() _audioContextState;
  final bool Function() _isVisible;
  final Stream<bool> _visibilityChanges;
  final Future<bool> Function() _retryInitialization;
  final WebAudioTimerScheduler _scheduleTimer;

  @override
  final ValueNotifier<AudioMonitorSnapshot> snapshot =
      ValueNotifier<AudioMonitorSnapshot>(AudioMonitorSnapshot.initial);

  bool _started = false;
  bool _retrying = false;
  bool _visible = true;
  WebAudioTimer? _recoveryTimer;
  WebAudioTimer? _visibilityTimer;
  StreamSubscription<bool>? _visibilitySubscription;

  /// Starts watching. Idempotent, like the desktop monitor.
  void start() {
    if (_started) return;
    _started = true;
    _visible = _readVisibility();
    _initState.addListener(_onInitStateChanged);
    _visibilitySubscription = _visibilityChanges.listen(_onVisibilityChanged);
    _publish(AudioAlertReason.none);
    _sample();
  }

  void stop() {
    if (!_started) return;
    _started = false;
    _initState.removeListener(_onInitStateChanged);
    unawaited(_visibilitySubscription?.cancel());
    _visibilitySubscription = null;
    _cancelRecovery();
    _visibilityTimer?.cancel();
    _visibilityTimer = null;
  }

  void dispose() {
    stop();
    snapshot.dispose();
  }

  /// Restarts the engine after a user gesture and re-samples.
  ///
  /// Single-flight: a second call while one is running reports the current
  /// state instead of starting a competing initialisation.
  @override
  Future<bool> retry() async {
    if (_retrying) {
      return snapshot.value.reason == AudioAlertReason.none;
    }
    _retrying = true;
    try {
      final initialized = await _retryInitialization();
      final healthy = initialized && _evaluate() == AudioAlertReason.none;
      _sample();
      return healthy;
    } finally {
      _retrying = false;
    }
  }

  void _onInitStateChanged() => _sample();

  void _onVisibilityChanged(bool visible) {
    if (_visible == visible) return;
    _visible = visible;
    // An invisible page keeps the last verdict; only the flag is refreshed.
    _publish(snapshot.value.reason);
    _visibilityTimer?.cancel();
    _visibilityTimer = null;
    if (!visible) {
      _cancelRecovery();
      return;
    }
    _visibilityTimer = _scheduleTimer(visibilityDelay, () {
      _visibilityTimer = null;
      _sample();
    });
  }

  void _sample() {
    if (!_started || !_visible) return;

    final candidate = _evaluate();
    final current = snapshot.value.reason;
    if (candidate == current) {
      // A settled value wins over a pending recovery.
      _cancelRecovery();
      return;
    }

    if (candidate == AudioAlertReason.engineDown) {
      _cancelRecovery();
      _publish(candidate);
      return;
    }

    // Recovery is the only transition that waits: the context may be resumed
    // asynchronously, and a badge that flickers is worse than a late one.
    _cancelRecovery();
    _recoveryTimer = _scheduleTimer(recoveryDelay, () {
      _recoveryTimer = null;
      _confirmRecovery();
    });
  }

  void _confirmRecovery() {
    if (!_started || !_visible) return;
    // A retry resets the state to `notAttempted` while it runs; that is not
    // evidence of recovery, so keep the badge until the engine settles.
    if (_initState.value == AudioInitState.notAttempted) return;
    if (_evaluate() != AudioAlertReason.engineDown) {
      _publish(AudioAlertReason.none);
    }
  }

  AudioAlertReason _evaluate() {
    switch (_initState.value) {
      case AudioInitState.notAttempted:
        return AudioAlertReason.none;
      case AudioInitState.failed:
        return AudioAlertReason.engineDown;
      case AudioInitState.ready:
        break;
    }

    final bool initialized;
    try {
      initialized = _engineInitialized();
    } catch (_) {
      // An unreadable engine is not evidence of a fault.
      return AudioAlertReason.none;
    }
    if (!initialized) return AudioAlertReason.engineDown;

    WebAudioDeviceState device;
    try {
      device = _deviceState();
    } catch (_) {
      device = WebAudioDeviceState.unknown;
    }
    if (device == WebAudioDeviceState.uninitialized) {
      return AudioAlertReason.engineDown;
    }

    String? context;
    try {
      context = _audioContextState();
    } catch (_) {
      context = null;
    }
    if (context == 'suspended' || context == 'closed') {
      return AudioAlertReason.engineDown;
    }
    return AudioAlertReason.none;
  }

  bool _readVisibility() {
    try {
      return _isVisible();
    } catch (_) {
      return true;
    }
  }

  void _publish(AudioAlertReason reason) {
    final next = AudioMonitorSnapshot(reason: reason, windowVisible: _visible);
    if (next == snapshot.value) return;
    snapshot.value = next;
  }

  void _cancelRecovery() {
    _recoveryTimer?.cancel();
    _recoveryTimer = null;
  }
}

WebAudioTimer _scheduleWithTimer(Duration delay, void Function() callback) {
  return _TimerHandle(Timer(delay, callback));
}

class _TimerHandle implements WebAudioTimer {
  _TimerHandle(this._timer);

  final Timer _timer;

  @override
  void cancel() => _timer.cancel();
}
