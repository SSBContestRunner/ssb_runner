import 'package:flutter/material.dart';
import 'package:ssb_runner/audio/audio_alert_state.dart';
import 'package:ssb_runner/audio/audio_output_monitor.dart';
import 'package:ssb_runner/audio/audio_output_probe.dart';
import 'package:ssb_runner/l10n/generated/app_localizations.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/ui/main_page/audio_status_badge.dart';

/// Blocking pre-flight check in front of RUN (design §5 E1).
///
/// Returns true when the session may start. Every abnormal state blocks; only
/// a low volume can be dismissed permanently through
/// [AppSettings.audioPreflightLowVolumeWarning] (decision D5).
Future<bool> confirmAudioPreflight({
  required BuildContext context,
  required AudioOutputMonitor monitor,
  required AppSettings settings,
}) async {
  final reason = monitor.snapshot.value.reason;
  if (reason == AudioAlertReason.none) return true;
  if (reason == AudioAlertReason.low &&
      !settings.audioPreflightLowVolumeWarning) {
    return true;
  }

  final result = await showDialog<bool>(
    context: context,
    builder: (_) => _AudioPreflightDialog(monitor: monitor, settings: settings),
  );
  return result ?? false;
}

class _AudioPreflightDialog extends StatefulWidget {
  const _AudioPreflightDialog({required this.monitor, required this.settings});

  final AudioOutputMonitor monitor;
  final AppSettings settings;

  @override
  State<_AudioPreflightDialog> createState() => _AudioPreflightDialogState();
}

class _AudioPreflightDialogState extends State<_AudioPreflightDialog> {
  bool _dontAskLowVolume = false;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    widget.monitor.snapshot.addListener(_onSnapshotChanged);
  }

  @override
  void dispose() {
    widget.monitor.snapshot.removeListener(_onSnapshotChanged);
    super.dispose();
  }

  /// A successful re-check resolves the block, so the session can start.
  void _onSnapshotChanged() {
    if (_closed || widget.monitor.snapshot.value.hasAlert) return;
    _closed = true;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return ValueListenableBuilder<AudioMonitorSnapshot>(
      valueListenable: widget.monitor.snapshot,
      builder: (context, snapshot, _) {
        final scheme = Theme.of(context).colorScheme;
        final percent = snapshot.volume == null
            ? null
            : (snapshot.volume! * 100).round();
        final isLow = snapshot.reason == AudioAlertReason.low;
        final isEngineDown = snapshot.reason == AudioAlertReason.engineDown;

        return AlertDialog(
          icon: Icon(Icons.volume_off_outlined, color: scheme.error),
          title: Text(audioAlertTooltip(l10n, snapshot)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (percent != null) Text(l10n.audioBadgeVolumeLabel(percent)),
              if (snapshot.deviceName != null)
                Text(
                  snapshot.deviceName!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              if (isLow)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _dontAskLowVolume,
                  title: Text(l10n.audioPreflightDontAskLowVolume),
                  onChanged: (value) {
                    setState(() => _dontAskLowVolume = value ?? false);
                  },
                ),
            ],
          ),
          actions: [
            if (!isEngineDown)
              TextButton(
                onPressed: openSystemSoundSettings,
                child: Text(l10n.audioBadgeOpenSoundSettings),
              ),
            TextButton(
              onPressed: () => widget.monitor.refresh(),
              child: Text(
                isEngineDown
                    ? l10n.audioPreflightRetry
                    : l10n.audioPreflightRecheck,
              ),
            ),
            FilledButton(
              onPressed: () {
                if (isLow && _dontAskLowVolume) {
                  widget.settings.audioPreflightLowVolumeWarning = false;
                }
                _closed = true;
                Navigator.of(context).pop(true);
              },
              child: Text(l10n.audioPreflightStartAnyway),
            ),
          ],
        );
      },
    );
  }
}
