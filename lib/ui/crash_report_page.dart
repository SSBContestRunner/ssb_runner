import 'dart:async';

import 'package:catcher_2/catcher_2.dart';
import 'package:catcher_2/model/platform_type.dart';
import 'package:flutter/material.dart';
import 'package:ssb_runner/ui/diagnostics_actions.dart';

/// Error text that routes a checked error to [CrashReportMode] through
/// Catcher2's explicit report mode map.
const String crashReportPreviewMarker = 'ssb-runner-crash-preview';

/// Release report mode that shows a full error page with recovery actions
/// instead of Catcher2's bare default page.
class CrashReportMode extends ReportMode {
  CrashReportMode({required this.canSendReport, this.onReport});

  /// Whether the build can publish the report to the issue tracker.
  final bool canSendReport;

  /// Called as soon as a report reaches the mode, before the page opens, so
  /// the crash is persisted independently of what the user does next.
  final void Function(Report report)? onReport;

  bool _pageVisible = false;

  @override
  void requestAction(Report report, BuildContext? context) {
    onReport?.call(report);

    if (context == null || _pageVisible) {
      return;
    }

    // Catcher2 can raise errors during a build, when pushing a route is not
    // allowed yet.
    _pageVisible = true;
    unawaited(
      Future<void>.delayed(Duration.zero, () async {
        if (!context.mounted) {
          _pageVisible = false;
          return;
        }

        await Navigator.of(context, rootNavigator: true).push<void>(
          MaterialPageRoute<void>(
            builder: (context) => CrashReportPage(
              report: report,
              canSendReport: canSendReport,
              onSendReport: () => onActionConfirmed(report),
              onClose: () => onActionRejected(report),
            ),
          ),
        );
        _pageVisible = false;
      }),
    );
  }

  @override
  bool isContextRequired() => true;

  @override
  List<PlatformType> getSupportedPlatforms() => PlatformType.values;
}

/// Full-screen error page shown when an unhandled error reaches Catcher2.
class CrashReportPage extends StatelessWidget {
  const CrashReportPage({
    required this.report,
    required this.canSendReport,
    required this.onSendReport,
    required this.onClose,
    super.key,
  });

  final Report report;
  final bool canSendReport;
  final VoidCallback onSendReport;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final error = report.error ?? report.errorDetails?.exception;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'SSB Runner hit an unexpected error',
                    style: textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'The current run may have been interrupted. Export the logs '
                    'or copy the diagnostic summary so the problem can be '
                    'investigated.',
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      error?.toString() ?? 'Unknown error',
                      style: textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: [
                      if (canSendReport)
                        FilledButton.icon(
                          onPressed: () => _sendReport(context),
                          icon: const Icon(Icons.upload_file),
                          label: const Text('Send report'),
                        ),
                      FilledButton.tonalIcon(
                        onPressed: () => exportDiagnosticArchive(context),
                        icon: const Icon(Icons.download),
                        label: const Text('Export logs'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => copyDiagnosticSummary(context),
                        icon: const Icon(Icons.copy),
                        label: const Text('Copy diagnostics'),
                      ),
                      TextButton(
                        onPressed: () => _close(context),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _sendReport(BuildContext context) {
    onSendReport();
    Navigator.of(context, rootNavigator: true).pop();
  }

  void _close(BuildContext context) {
    onClose();
    Navigator.of(context, rootNavigator: true).pop();
  }
}
