import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ssb_runner/audio/audio_alert_state.dart';
import 'package:ssb_runner/contest_run/new/contest_manager.dart';
import 'package:ssb_runner/l10n/generated/app_localizations.dart';
import 'package:ssb_runner/platform/audio/web/web_audio_alert_source.dart';
import 'package:ssb_runner/platform/audio/web/web_audio_copy.dart';
import 'package:toastification/toastification.dart';

/// Repeats a browser-blocked audio engine as a non-modal toast while a session
/// runs (design §5.6).
///
/// Mirrors the desktop toaster's rule — one toast per reason per session,
/// recovery resets the allowance — but consumes the web monitor instead of the
/// `dart:io`-bound desktop one.
class WebAudioAlertToaster extends StatefulWidget {
  const WebAudioAlertToaster({
    super.key,
    required this.source,
    this.sessionRunning,
    this.phaseChanges,
  });

  final WebAudioAlertSource source;

  /// Test seam; production reads [ContestManager] from the widget tree.
  final bool Function()? sessionRunning;

  /// Test seam; production reads [ContestManager] from the widget tree.
  final Stream<ContestSessionPhase>? phaseChanges;

  @override
  State<WebAudioAlertToaster> createState() => _WebAudioAlertToasterState();
}

class _WebAudioAlertToasterState extends State<WebAudioAlertToaster> {
  late final bool Function() _isRunning;
  StreamSubscription<ContestSessionPhase>? _phaseSubscription;

  AudioAlertReason _last = AudioAlertReason.none;
  final WebAudioAlertAnnouncer _announcer = WebAudioAlertAnnouncer();

  @override
  void initState() {
    super.initState();

    final manager = widget.sessionRunning == null || widget.phaseChanges == null
        ? context.read<ContestManager>()
        : null;
    _isRunning =
        widget.sessionRunning ??
        () => manager!.sessionPhase == ContestSessionPhase.running;

    _phaseSubscription = (widget.phaseChanges ?? manager?.sessionPhaseStream)
        ?.listen((phase) {
          // A new session gets a fresh allowance.
          if (phase != ContestSessionPhase.running) _announcer.reset();
        });

    _last = widget.source.snapshot.value.reason;
    widget.source.snapshot.addListener(_onSnapshot);
  }

  @override
  void dispose() {
    widget.source.snapshot.removeListener(_onSnapshot);
    unawaited(_phaseSubscription?.cancel());
    super.dispose();
  }

  void _onSnapshot() {
    final snapshot = widget.source.snapshot.value;
    final previous = _last;
    _last = snapshot.reason;

    final announce = _announcer.shouldAnnounce(
      previous: previous,
      current: snapshot.reason,
      running: _isRunning(),
    );
    if (!announce || !mounted) return;

    final l10n = AppLocalizations.of(context);
    toastification.show(
      title: Text(webAudioAlertTooltip(l10n)),
      autoCloseDuration: const Duration(seconds: 4),
      type: ToastificationType.warning,
      style: ToastificationStyle.fillColored,
    );
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Web counterpart of the desktop `AudioAlertAnnouncer`, whose file cannot be
/// imported here.
class WebAudioAlertAnnouncer {
  final Set<AudioAlertReason> _announced = <AudioAlertReason>{};

  bool shouldAnnounce({
    required AudioAlertReason previous,
    required AudioAlertReason current,
    required bool running,
  }) {
    if (current == AudioAlertReason.none) {
      _announced.clear();
      return false;
    }
    if (!running) return false;
    if (previous != AudioAlertReason.none) return false;
    return _announced.add(current);
  }

  void reset() => _announced.clear();
}
