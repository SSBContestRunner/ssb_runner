import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ssb_runner/audio/audio_alert_state.dart';
import 'package:ssb_runner/audio/audio_output_monitor.dart';
import 'package:ssb_runner/contest_run/new/contest_manager.dart';
import 'package:ssb_runner/l10n/generated/app_localizations.dart';
import 'package:ssb_runner/ui/main_page/audio_status_badge.dart';
import 'package:toastification/toastification.dart';

/// Repeats an audio problem as a non-modal toast while a session is running
/// (design §5 E3).
///
/// The badge alone is easy to miss once the operator is heads-down, but a
/// running session must not be interrupted: the toast never pauses, blocks or
/// takes focus. One toast per reason per session; recovering resets the count.
class AudioAlertToaster extends StatefulWidget {
  const AudioAlertToaster({super.key});

  @override
  State<AudioAlertToaster> createState() => _AudioAlertToasterState();
}

class _AudioAlertToasterState extends State<AudioAlertToaster> {
  AudioOutputMonitor? _monitor;
  ContestManager? _manager;
  StreamSubscription<ContestSessionPhase>? _phaseSubscription;

  AudioAlertReason _last = AudioAlertReason.none;
  final AudioAlertAnnouncer _announcer = AudioAlertAnnouncer();

  @override
  void initState() {
    super.initState();
    _monitor = context.read<AudioOutputMonitor?>();
    _manager = context.read<ContestManager>();

    _last = _monitor?.snapshot.value.reason ?? AudioAlertReason.none;
    _monitor?.snapshot.addListener(_onSnapshot);
    _phaseSubscription = _manager?.sessionPhaseStream.listen((phase) {
      // A new session gets a fresh allowance.
      if (phase != ContestSessionPhase.running) _announcer.reset();
    });
  }

  @override
  void dispose() {
    _monitor?.snapshot.removeListener(_onSnapshot);
    unawaited(_phaseSubscription?.cancel());
    super.dispose();
  }

  void _onSnapshot() {
    final monitor = _monitor;
    if (monitor == null) return;

    final snapshot = monitor.snapshot.value;
    final previous = _last;
    _last = snapshot.reason;

    final announce = _announcer.shouldAnnounce(
      previous: previous,
      current: snapshot.reason,
      running: _manager?.sessionPhase == ContestSessionPhase.running,
    );
    if (!announce || !mounted) return;

    final l10n = AppLocalizations.of(context);
    toastification.show(
      title: Text(audioAlertTooltip(l10n, snapshot)),
      autoCloseDuration: const Duration(seconds: 4),
      type: ToastificationType.warning,
      style: ToastificationStyle.fillColored,
    );
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Decides which audio transition deserves a toast.
///
/// Kept separate from the widget so the "once per reason per session" rule is
/// directly testable (design §5 E3).
class AudioAlertAnnouncer {
  final Set<AudioAlertReason> _announced = <AudioAlertReason>{};

  /// Feeds one snapshot transition and returns whether it must be announced.
  bool shouldAnnounce({
    required AudioAlertReason previous,
    required AudioAlertReason current,
    required bool running,
  }) {
    if (current == AudioAlertReason.none) {
      // Recovering clears the allowance, so a later relapse announces again.
      _announced.clear();
      return false;
    }
    if (!running) return false;
    // Only the normal → abnormal edge, not a change between two faults.
    if (previous != AudioAlertReason.none) return false;
    return _announced.add(current);
  }

  /// A new session starts with an empty allowance.
  void reset() => _announced.clear();
}
