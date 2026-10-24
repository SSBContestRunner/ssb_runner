import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ssb_runner/logging/app_logger.dart';
import 'package:ssb_runner/logging/log_export.dart';
import 'package:toastification/toastification.dart';

/// Copies the diagnostic summary to the clipboard and confirms it in a toast.
Future<void> copyDiagnosticSummary(BuildContext context) async {
  final summary = await diagnosticSummary();
  await Clipboard.setData(ClipboardData(text: summary));
  if (!context.mounted) {
    return;
  }

  _showToast(
    'Diagnostics copied',
    ToastificationType.success,
    const Duration(seconds: 2),
  );
}

/// Lets the user save a zip with the logs and copies its path to the clipboard.
Future<void> exportDiagnosticArchive(BuildContext context) async {
  try {
    final file = await exportLogArchive();
    if (!context.mounted || file == null) {
      return;
    }

    await Clipboard.setData(ClipboardData(text: file.path));
    if (!context.mounted) {
      return;
    }

    _showToast(
      'Exported to ${file.path}',
      ToastificationType.success,
      const Duration(seconds: 4),
    );
  } catch (error, stackTrace) {
    log.error(
      'log export failed',
      tag: 'crash',
      error: error,
      stackTrace: stackTrace,
    );
    if (!context.mounted) {
      return;
    }

    _showToast(
      'Log export failed',
      ToastificationType.warning,
      const Duration(seconds: 4),
    );
  }
}

void _showToast(
  String message,
  ToastificationType type,
  Duration autoCloseDuration,
) {
  toastification.show(
    title: Text(message),
    autoCloseDuration: autoCloseDuration,
    type: type,
    style: ToastificationStyle.fillColored,
  );
}
