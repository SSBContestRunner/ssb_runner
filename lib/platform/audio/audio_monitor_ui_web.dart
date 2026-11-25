import 'package:material_ui/material_ui.dart';
import 'package:ssb_runner/platform/audio/audio_bootstrap_web.dart';
import 'package:ssb_runner/platform/audio/web/web_audio_alert_toaster.dart';
import 'package:ssb_runner/platform/audio/web/web_audio_monitor.dart';
import 'package:ssb_runner/platform/audio/web/web_audio_signals.dart';
import 'package:ssb_runner/platform/audio/web/web_audio_status_badge.dart';

/// Resident web monitor, created on first use and shared for the process
/// lifetime (design §5.1).
WebAudioMonitor? _monitor;

WebAudioMonitor _sharedMonitor() => _monitor ??= WebAudioMonitor(
  initState: audioInitState,
  engineInitialized: webAudioEngineInitialized,
  deviceState: webAudioDeviceState,
  audioContextState: webAudioContextState,
  isVisible: webAudioPageVisible,
  visibilityChanges: webAudioVisibilityChanges(),
  retryInitialization: retryAudioInitialized,
);

/// The web badge, toaster and monitor are wired directly, so no provider is
/// needed here.
Widget wrapWithAudioMonitor(Widget child) => child;

Widget buildAudioStatusBadge() => WebAudioStatusBadge(source: _sharedMonitor());

Widget buildAudioAlertToaster() =>
    WebAudioAlertToaster(source: _sharedMonitor());

void startAudioMonitor() => _sharedMonitor().start();

void stopAudioMonitor() => _monitor?.stop();

void disposeAudioMonitor() {
  _monitor?.dispose();
  _monitor = null;
}

/// A browser cannot guarantee audibility even when the context is running, so
/// the run pre-flight stays non-blocking (design §4.3).
Future<bool> confirmRunAudioPreflight(BuildContext context) async => true;
