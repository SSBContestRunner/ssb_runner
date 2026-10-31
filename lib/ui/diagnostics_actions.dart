import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ssb_runner/l10n/generated/app_localizations.dart';
import 'package:ssb_runner/logging/app_logger.dart';
import 'package:ssb_runner/logging/log_export.dart';
import 'package:toastification/toastification.dart';

/// Copies the diagnostic summary to the clipboard and confirms it in a toast.
Future<void> copyDiagnosticSummary(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final summary = await diagnosticSummary();
  await Clipboard.setData(ClipboardData(text: summary));
  if (!context.mounted) {
    return;
  }

  _showToast(
    l10n.diagnosticsCopied,
    ToastificationType.success,
    const Duration(seconds: 2),
  );
}

/// Lets the user save a zip with the logs and copies its path to the clipboard.
Future<void> exportDiagnosticArchive(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  try {
    final file = await exportLogArchive(fileTypeLabel: l10n.zipArchive);
    if (!context.mounted || file == null) {
      return;
    }

    await Clipboard.setData(ClipboardData(text: file.path));
    if (!context.mounted) {
      return;
    }

    _showToast(
      l10n.exportedTo(file.path),
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
      l10n.logExportFailed,
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
