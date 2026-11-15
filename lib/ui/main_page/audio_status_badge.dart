import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ssb_runner/audio/audio_alert_state.dart';
import 'package:ssb_runner/audio/audio_output_monitor.dart';
import 'package:ssb_runner/audio/audio_output_probe.dart';
import 'package:ssb_runner/l10n/generated/app_localizations.dart';

/// Topbar indicator for an unusable audio output (design §4.4).
///
/// Hidden while everything is healthy, so it costs no space on the normal path.
/// Its appearance shifts the settings button by one 40 dp slot, which the
/// design accepts in exchange for a clean topbar.
class AudioStatusBadge extends StatelessWidget {
  const AudioStatusBadge({super.key});

  @override
  Widget build(BuildContext context) {
    // Nullable lookup: tests and previews may build the page without a monitor.
    final monitor = context.watch<AudioOutputMonitor?>();
    if (monitor == null) return const SizedBox.shrink();

    return ValueListenableBuilder<AudioMonitorSnapshot>(
      valueListenable: monitor.snapshot,
      builder: (context, snapshot, _) {
        if (!snapshot.hasAlert) return const SizedBox.shrink();
        return _AlertBadge(snapshot: snapshot);
      },
    );
  }
}

class _AlertBadge extends StatelessWidget {
  const _AlertBadge({required this.snapshot});

  final AudioMonitorSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final message = audioAlertTooltip(l10n, snapshot);

    return Semantics(
      liveRegion: true,
      label: message,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            key: const Key('audioStatusBadge'),
            tooltip: message,
            onPressed: () => _showDetails(context, snapshot),
            style: IconButton.styleFrom(
              minimumSize: const Size(40, 40),
              fixedSize: const Size(40, 40),
              foregroundColor: scheme.error,
            ),
            icon: Icon(audioAlertIcon(snapshot.reason), size: 20),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: IgnorePointer(
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.error,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showDetails(
    BuildContext context,
    AudioMonitorSnapshot snapshot,
  ) async {
    final l10n = AppLocalizations.of(context);
    final percent = snapshot.volume == null
        ? null
        : (snapshot.volume! * 100).round();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          icon: Icon(audioAlertIcon(snapshot.reason), color: scheme.error),
          title: Text(audioAlertTooltip(l10n, snapshot)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (percent != null)
                Text(l10n.audioBadgeVolumeLabel(percent)),
              if (snapshot.deviceName != null)
                Text(snapshot.deviceName!, style: Theme.of(dialogContext).textTheme.bodySmall),
            ],
          ),
          actions: [
            if (snapshot.reason != AudioAlertReason.engineDown)
              TextButton(
                onPressed: openSystemSoundSettings,
                child: Text(l10n.audioBadgeOpenSoundSettings),
              ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.close),
            ),
          ],
        );
      },
    );
  }
}

/// Badge and dialog glyph for [reason].
///
/// A low volume keeps a speaker with a single wave, so it never reads as the
/// crossed-out speaker that stands for a mute or a missing device.
IconData audioAlertIcon(AudioAlertReason reason) {
  return reason == AudioAlertReason.low
      ? Icons.volume_down_outlined
      : Icons.volume_off_outlined;
}

/// Tooltip / dialog headline for [snapshot].
String audioAlertTooltip(AppLocalizations l10n, AudioMonitorSnapshot snapshot) {
  switch (snapshot.reason) {
    case AudioAlertReason.muted:
      return l10n.audioBadgeMutedTooltip;
    case AudioAlertReason.low:
      final percent = ((snapshot.volume ?? 0) * 100).round();
      return l10n.audioBadgeLowTooltip(percent);
    case AudioAlertReason.noDevice:
      return l10n.audioBadgeNoDeviceTooltip;
    case AudioAlertReason.engineDown:
      return l10n.audioBadgeEngineDownTooltip;
    case AudioAlertReason.none:
      return '';
  }
}
