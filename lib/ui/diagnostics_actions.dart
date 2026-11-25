import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:ssb_runner/l10n/generated/app_localizations.dart';
import 'package:ssb_runner/logging/app_logger.dart';
import 'package:ssb_runner/logging/log_export.dart';
import 'package:toastification/toastification.dart';

/// Copies the diagnostic summary to the clipboard and confirms it in a toast.
///
/// Clipboard access can be denied in a browser; the summary is then shown in a
/// selectable dialog so it can still be copied by hand.
Future<void> copyDiagnosticSummary(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final summary = await diagnosticSummary();

  try {
    await Clipboard.setData(ClipboardData(text: summary));
    if (!context.mounted) {
      return;
    }

    _showToast(
      l10n.diagnosticsCopied,
      ToastificationType.success,
      const Duration(seconds: 2),
    );
  } catch (error, stackTrace) {
    log.warn(
      'clipboard unavailable',
      tag: 'crash',
      error: error,
      stackTrace: stackTrace,
    );
    if (!context.mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.copyDiagnosticsFailed),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(child: SelectableText(summary)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.close),
          ),
        ],
      ),
    );
  }
}

/// Lets the user save a zip with the logs and confirms where it went.
///
/// Desktop shows the full path; the browser shows the downloaded file name.
Future<void> exportDiagnosticArchive(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  try {
    final result = await exportLogArchive(fileTypeLabel: l10n.zipArchive);
    if (!context.mounted || result == null) {
      return;
    }

    try {
      await Clipboard.setData(
        ClipboardData(text: result.path ?? result.displayName),
      );
    } catch (_) {
      // The export itself succeeded; copying the location is a convenience.
    }
    if (!context.mounted) {
      return;
    }

    _showToast(
      l10n.exportedTo(result.displayName),
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
