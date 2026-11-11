import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ssb_runner/audio/audio_output_monitor.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/ui/main_app/window_visibility.dart';
import 'package:ssb_runner/ui/main_page/audio_alert_toaster.dart';
import 'package:ssb_runner/ui/main_page/audio_preflight_dialog.dart';
import 'package:ssb_runner/ui/main_page/audio_status_badge.dart';

/// Resident monitor, created on first use and shared for the process lifetime.
AudioOutputMonitor? _monitor;

AudioOutputMonitor _sharedMonitor() =>
    _monitor ??= AudioOutputMonitor(
      visibilityFactory: WindowManagerVisibility.attach,
    );

/// Exposes the output monitor to the badge, the toaster and the run pre-flight.
///
/// The monitor reads CoreAudio/WASAPI/pactl, so it only exists on desktop.
Widget wrapWithAudioMonitor(Widget child) {
  return RepositoryProvider<AudioOutputMonitor>.value(
    value: _sharedMonitor(),
    child: child,
  );
}

/// Topbar badge that only appears while the output cannot be heard.
Widget buildAudioStatusBadge() => const AudioStatusBadge();

/// Repeats a running session's audio problem as a non-modal toast.
Widget buildAudioAlertToaster() => const AudioAlertToaster();

void startAudioMonitor() => _sharedMonitor().start();

void stopAudioMonitor() => _monitor?.stop();

void disposeAudioMonitor() {
  _monitor?.dispose();
  _monitor = null;
}

/// Blocking pre-flight in front of RUN; true when the session may start.
Future<bool> confirmRunAudioPreflight(BuildContext context) {
  final monitor = context.read<AudioOutputMonitor?>();
  if (monitor == null) {
    return Future<bool>.value(true);
  }
  return confirmAudioPreflight(
    context: context,
    monitor: monitor,
    settings: context.read<AppSettings>(),
  );
}
