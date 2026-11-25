import 'package:material_ui/material_ui.dart';
import 'package:ssb_runner/audio/audio_alert_state.dart';
import 'package:ssb_runner/l10n/generated/app_localizations.dart';
import 'package:ssb_runner/platform/audio/web/web_audio_alert_source.dart';
import 'package:ssb_runner/platform/audio/web/web_audio_copy.dart';
import 'package:toastification/toastification.dart';

/// Topbar indicator for a browser-blocked audio engine.
///
/// Same shape and same key as the desktop badge, but it is a web-specific
/// implementation: the desktop widget depends on `dart:io` types that cannot
/// be imported here (design §5.5, §9 R7).
class WebAudioStatusBadge extends StatelessWidget {
  const WebAudioStatusBadge({super.key, required this.source});

  final WebAudioAlertSource source;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AudioMonitorSnapshot>(
      valueListenable: source.snapshot,
      builder: (context, snapshot, _) {
        if (!snapshot.hasAlert) return const SizedBox.shrink();
        return _AlertBadge(source: source);
      },
    );
  }
}

class _AlertBadge extends StatelessWidget {
  const _AlertBadge({required this.source});

  final WebAudioAlertSource source;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final message = webAudioAlertTooltip(l10n);

    return Semantics(
      liveRegion: true,
      label: message,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            key: const Key('audioStatusBadge'),
            tooltip: message,
            onPressed: () => _showDetails(context),
            style: IconButton.styleFrom(
              minimumSize: const Size(40, 40),
              fixedSize: const Size(40, 40),
              foregroundColor: scheme.error,
            ),
            icon: Icon(webAudioAlertIcon(), size: 20),
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

  Future<void> _showDetails(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => _WebAudioDetailsDialog(source: source),
    );
  }
}

class _WebAudioDetailsDialog extends StatefulWidget {
  const _WebAudioDetailsDialog({required this.source});

  final WebAudioAlertSource source;

  @override
  State<_WebAudioDetailsDialog> createState() => _WebAudioDetailsDialogState();
}

class _WebAudioDetailsDialogState extends State<_WebAudioDetailsDialog> {
  bool _busy = false;

  Future<void> _enable() async {
    setState(() => _busy = true);
    final recovered = await widget.source.retry();
    if (!mounted) return;
    setState(() => _busy = false);

    if (recovered) {
      Navigator.of(context).pop();
      return;
    }

    final l10n = AppLocalizations.of(context);
    toastification.show(
      title: Text(l10n.audioUnavailable),
      autoCloseDuration: const Duration(seconds: 4),
      type: ToastificationType.warning,
      style: ToastificationStyle.fillColored,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      icon: Icon(webAudioAlertIcon(), color: scheme.error),
      title: Text(webAudioAlertTooltip(l10n)),
      content: Text(l10n.audioBadgeWebBlindSpotHint),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.close),
        ),
        FilledButton(
          key: const Key('webAudioEnableAudio'),
          onPressed: _busy ? null : _enable,
          child: Text(l10n.audioBadgeEnableAudio),
        ),
      ],
    );
  }
}
