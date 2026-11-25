import 'package:flutter/foundation.dart';
import 'package:ssb_runner/audio/audio_alert_state.dart';

/// The slice of the web monitor that the badge and the toaster consume.
///
/// Widget tests inject a fake implementation instead of driving the real
/// monitor, which keeps them independent of the browser and of timers.
abstract interface class WebAudioAlertSource {
  ValueListenable<AudioMonitorSnapshot> get snapshot;

  /// Asks the engine to start again and reports whether audio became usable.
  Future<bool> retry();
}
