import 'package:flutter/foundation.dart';

/// Which system API produced a reading.
enum AudioProbeSource { coreAudio, wasapi, pactl, wpctl, unsupported, error }

/// One reading of the system output state (volume, mute, device).
///
/// Every field is nullable on purpose: `null` means "this reading could not
/// determine the value", which the adjudicator treats as `unknown` and never
/// as a fault (design §4.2.2, §4.3.3).
@immutable
class AudioOutputStatus {
  const AudioOutputStatus({
    this.hasDevice,
    this.deviceName,
    this.volume,
    this.muted,
    this.source = AudioProbeSource.unsupported,
  });

  /// The reading used when no platform probe is available.
  static const AudioOutputStatus unknown = AudioOutputStatus();

  final bool? hasDevice;
  final String? deviceName;

  /// Main output volume, 0.0–1.0.
  final double? volume;
  final bool? muted;
  final AudioProbeSource source;

  /// True when neither volume nor mute could be read; a device that exists but
  /// cannot be measured must not be treated as healthy.
  bool get isUnknown => volume == null && muted == null;

  @override
  String toString() =>
      'AudioOutputStatus(hasDevice: $hasDevice, device: $deviceName, '
      'volume: $volume, muted: $muted, source: ${source.name})';
}

/// One reading of the SoLoud engine and its output device.
///
/// [deviceUninitialized] mirrors `getAudioDeviceState() == uninitialized`,
/// which is the only device state that counts as a fault: `stopped` is what
/// flutter_soloud reports whenever the output has been idle for 500 ms
/// (design §4.2.1).
@immutable
class AudioEngineStatus {
  const AudioEngineStatus({
    this.initialized,
    this.playbackDeviceCount,
    this.deviceUninitialized = false,
  });

  static const AudioEngineStatus unknown = AudioEngineStatus();

  final bool? initialized;
  final int? playbackDeviceCount;
  final bool deviceUninitialized;
}

/// What the badge should say. `none` is the healthy state.
enum AudioAlertReason { none, low, muted, noDevice, engineDown }

/// Immutable snapshot published by [AudioOutputMonitor].
@immutable
class AudioMonitorSnapshot {
  const AudioMonitorSnapshot({
    this.reason = AudioAlertReason.none,
    this.volume,
    this.muted,
    this.deviceName,
    this.source = AudioProbeSource.unsupported,
    this.windowVisible = true,
    this.disabled = false,
  });

  static const AudioMonitorSnapshot initial = AudioMonitorSnapshot();

  final AudioAlertReason reason;
  final double? volume;
  final bool? muted;
  final String? deviceName;
  final AudioProbeSource source;

  /// Whether the app window is visible; invisible windows poll at 10 s.
  final bool windowVisible;

  /// True when `SSB_RUNNER_DISABLE_AUDIO=1` turned the monitor off.
  final bool disabled;

  bool get hasAlert => reason != AudioAlertReason.none;

  @override
  bool operator ==(Object other) =>
      other is AudioMonitorSnapshot &&
      other.reason == reason &&
      other.volume == volume &&
      other.muted == muted &&
      other.deviceName == deviceName &&
      other.source == source &&
      other.windowVisible == windowVisible &&
      other.disabled == disabled;

  @override
  int get hashCode => Object.hash(
    reason,
    volume,
    muted,
    deviceName,
    source,
    windowVisible,
    disabled,
  );

  @override
  String toString() =>
      'AudioMonitorSnapshot(reason: ${reason.name}, volume: $volume, '
      'muted: $muted, device: $deviceName, visible: $windowVisible, '
      'disabled: $disabled)';
}

/// Classifies one pair of readings into the alert the badge should show.
///
/// Priority: engine, device, mute, volume. `unknown` readings never produce an
/// alert, so a platform without the capability stays silent instead of warning
/// wrongly (design §3.1.4).
AudioAlertReason classifyAudioAlert({
  required AudioOutputStatus status,
  required AudioEngineStatus engine,
  double lowVolumeThreshold = 0.10,
}) {
  if (engine.initialized == false) return AudioAlertReason.engineDown;

  final deviceCount = engine.playbackDeviceCount;
  if (deviceCount != null && deviceCount == 0) {
    return AudioAlertReason.noDevice;
  }
  if (status.hasDevice == false) return AudioAlertReason.noDevice;
  if (engine.deviceUninitialized) return AudioAlertReason.noDevice;

  if (status.muted == true) return AudioAlertReason.muted;

  final volume = status.volume;
  if (volume != null && volume < lowVolumeThreshold) {
    return AudioAlertReason.low;
  }
  return AudioAlertReason.none;
}

/// Turns raw readings into a debounced alert state.
///
/// Pure logic with an injected clock, so the 600 ms quiet window and the
/// hysteresis are unit-testable without timers (design §4.3.2):
///
/// * entering `muted`, `noDevice` and `engineDown` is immediate — those are
///   hard states and must not lag behind a mute button;
/// * entering `low` and leaving *any* alert waits for the quiet window or two
///   consecutive samples, which keeps the badge from flickering while a volume
///   slider is dragged or a device is re-enumerated.
class AudioAlertAdjudicator {
  AudioAlertAdjudicator({
    this.lowVolumeThreshold = 0.10,
    this.quietWindow = const Duration(milliseconds: 600),
    this.stableSamples = 2,
  });

  final double lowVolumeThreshold;
  final Duration quietWindow;
  final int stableSamples;

  AudioAlertReason _current = AudioAlertReason.none;
  AudioAlertReason? _pending;
  DateTime? _pendingSince;
  int _pendingCount = 0;

  AudioAlertReason get current => _current;

  /// True when a candidate is waiting for the quiet window or more samples.
  bool get hasPending => _pending != null;

  /// Feeds one sample and returns the (possibly unchanged) alert state.
  ///
  /// [eventDriven] selects the debounce rule: an event wake-up needs the
  /// 600 ms quiet window (a re-check scheduled by the monitor), the polling
  /// fallback needs [stableSamples] consecutive hits.
  AudioAlertReason evaluate(
    AudioOutputStatus status,
    AudioEngineStatus engine, {
    required DateTime now,
    required bool eventDriven,
  }) {
    final candidate = classifyAudioAlert(
      status: status,
      engine: engine,
      lowVolumeThreshold: lowVolumeThreshold,
    );

    // A failed read is a confidence drop, not evidence of health: hold the
    // current state instead of clearing an alert the probe can no longer see.
    if (status.isUnknown && candidate == AudioAlertReason.none) {
      return _current;
    }

    if (candidate == _current) {
      _clearPending();
      return _current;
    }

    if (candidate != _pending) {
      _pending = candidate;
      _pendingSince = now;
      _pendingCount = 1;
    } else {
      _pendingCount++;
    }

    final isHardEntry =
        candidate != AudioAlertReason.none && candidate != AudioAlertReason.low;
    final elapsed = now.difference(_pendingSince!);
    final bool settled;
    if (isHardEntry) {
      settled = true;
    } else if (eventDriven) {
      settled = elapsed >= quietWindow;
    } else {
      settled = _pendingCount >= stableSamples;
    }
    if (settled) {
      _current = candidate;
      _clearPending();
    }
    return _current;
  }

  void _clearPending() {
    _pending = null;
    _pendingSince = null;
    _pendingCount = 0;
  }
}
