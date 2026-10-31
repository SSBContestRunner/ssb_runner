import 'package:catcher_2/handlers/console_handler.dart';
import 'package:catcher_2/model/catcher_2_options.dart';
import 'package:catcher_2/model/report.dart';
import 'package:catcher_2/model/report_handler.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:ssb_runner/l10n/app_l10n.dart';
import 'package:ssb_runner/logging/app_logger.dart';
import 'package:ssb_runner/logging/crash_issue_reporter.dart';
import 'package:ssb_runner/ui/crash_report_page.dart';
import 'package:toastification/toastification.dart';

/// Builds the Catcher2 configurations used for debug and release builds.
///
/// Both builds show the same full-screen [CrashReportPage] and log the report
/// to the shared log file as soon as the page opens, so unhandled exceptions
/// and ordinary progress records end up interleaved in a single timeline.
/// Only release builds can file the accepted report as a GitHub issue through
/// [CrashIssueReporter], and only when a build token is configured.
Future<(Catcher2Options, Catcher2Options)> initErrorHandling() async {
  final issueReporter = CrashIssueReporter(onResult: _showReportResult);

  final debugOptions = _buildOptions(
    canSendReport: false,
    handlers: <ReportHandler>[ConsoleHandler()],
  );

  final releaseOptions = _buildOptions(
    canSendReport: crashIssueReportingEnabled,
    handlers: <ReportHandler>[issueReporter],
  );

  log.info('error handling ready', tag: 'crash');

  return (debugOptions, releaseOptions);
}

Catcher2Options _buildOptions({
  required bool canSendReport,
  required List<ReportHandler> handlers,
}) {
  return Catcher2Options(
    CrashReportMode(canSendReport: canSendReport, onReport: _logCrashReport),
    handlers,
    handlerTimeout: 30000,
  );
}

/// Writes the report into the shared log so the crash survives dismissal and
/// is included in copied/exported diagnostics.
void _logCrashReport(Report report) {
  final stackTrace = report.stackTrace;
  final details = report.errorDetails;

  log.error(
    'Unhandled error',
    tag: 'crash',
    fields: <String, Object?>{
      'error_type': '${report.error.runtimeType}',
      'platform': '${report.platformType}',
      'device': safeDeviceParameters(report.deviceParameters),
      'application': report.applicationParameters,
      // Layout errors (e.g. RenderFlex overflow) carry no stack trace; the
      // widget/file that caused them only lives in the details diagnostics
      // (debugCreator). Without it a report cannot be traced to the widget
      // that overflowed. Debug only: the creator chain is unavailable in
      // release anyway and its dump would bloat the report.
      if (kDebugMode && details != null) 'error_details': details.toString(),
    },
    error: report.error,
    stackTrace: stackTrace is StackTrace ? stackTrace : null,
  );
}

/// Feedback shown after the report page has already closed.
void _showReportResult(CrashReportOutcome outcome, Uri? issueUrl) {
  if (outcome == CrashReportOutcome.disabled) {
    return;
  }

  final l10n = AppL10n.current;
  final failed = outcome == CrashReportOutcome.failed;
  final Widget? description;
  if (failed) {
    description = Text(l10n.crashReportManualLogs);
  } else if (issueUrl != null) {
    description = Text(issueUrl.toString());
  } else {
    description = null;
  }

  toastification.show(
    title: Text(switch (outcome) {
      CrashReportOutcome.created => l10n.crashReportSubmitted,
      CrashReportOutcome.duplicate => l10n.crashReportDuplicate,
      CrashReportOutcome.failed => l10n.crashReportFailed,
      CrashReportOutcome.disabled => '',
    }),
    description: description,
    type: failed ? ToastificationType.warning : ToastificationType.success,
    style: ToastificationStyle.fillColored,
    autoCloseDuration: Duration(seconds: failed ? 6 : 5),
  );
}
