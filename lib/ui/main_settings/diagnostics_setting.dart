import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ssb_runner/logging/app_logger.dart';
import 'package:ssb_runner/logging/log_export.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:toastification/toastification.dart';

/// Settings section exposing the log level switch and the diagnostic export.
class DiagnosticsSetting extends StatefulWidget {
  const DiagnosticsSetting({super.key});

  @override
  State<DiagnosticsSetting> createState() => _DiagnosticsSettingState();
}

class _DiagnosticsSettingState extends State<DiagnosticsSetting> {
  late bool _verbose;

  @override
  void initState() {
    super.initState();
    _verbose = context.read<AppSettings>().verboseLogging;
  }

  @override
  Widget build(BuildContext context) {
    return Flex(
      direction: Axis.vertical,
      spacing: 12,
      children: [
        // SettingItem paints a colored DecoratedBox behind its content.
        // Give the ListTile its own transparent Material so its background
        // and ink splashes are not hidden (and so Flutter stops reporting the
        // "ListTile wrapped in a DecoratedBox" error).
        Material(
          type: MaterialType.transparency,
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _verbose,
            title: const Text('Verbose logging'),
            subtitle: const Text('Record debug details for troubleshooting'),
            onChanged: (value) {
              context.read<AppSettings>().verboseLogging = value;
              setState(() => _verbose = value);
            },
          ),
        ),
        Flex(
          direction: Axis.horizontal,
          spacing: 12,
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _copySummary,
                icon: const Icon(Icons.copy),
                label: const Text('Copy diagnostics'),
              ),
            ),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _exportLogs,
                icon: const Icon(Icons.archive_outlined),
                label: const Text('Export logs'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _copySummary() async {
    final summary = await diagnosticSummary();
    await Clipboard.setData(ClipboardData(text: summary));
    if (!mounted) {
      return;
    }

    toastification.show(
      title: const Text('Diagnostics copied'),
      autoCloseDuration: const Duration(seconds: 2),
      type: ToastificationType.success,
      style: ToastificationStyle.fillColored,
    );
  }

  Future<void> _exportLogs() async {
    try {
      final file = await exportLogArchive();
      await Clipboard.setData(ClipboardData(text: file.path));
      if (!mounted) {
        return;
      }

      toastification.show(
        title: Text('Exported to ${file.path}'),
        autoCloseDuration: const Duration(seconds: 4),
        type: ToastificationType.success,
        style: ToastificationStyle.fillColored,
      );
    } catch (error, stackTrace) {
      log.error(
        'log export failed',
        tag: 'crash',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
