import 'package:catcher_2/handlers/console_handler.dart';
import 'package:catcher_2/mode/dialog_report_mode.dart';
import 'package:catcher_2/model/catcher_2_options.dart';
import 'package:catcher_2/model/platform_type.dart';
import 'package:catcher_2/model/report.dart';
import 'package:catcher_2/model/report_handler.dart';
import 'package:flutter/widgets.dart';
import 'package:ssb_runner/logging/app_logger.dart';
import 'package:ssb_runner/logging/crash_issue_reporter.dart';
import 'package:ssb_runner/ui/crash_report_page.dart';
import 'package:toastification/toastification.dart';

/// Builds the Catcher2 configurations used for debug and release builds.
///
/// Reports are written to the shared log file so unhandled exceptions and
/// ordinary progress records end up interleaved in a single timeline. Debug
/// builds log through [_LoggingReportHandler] and show a dialog; release
/// builds log as soon as the error page opens and additionally file accepted
/// reports as GitHub issues through [CrashIssueReporter].
Future<(Catcher2Options, Catcher2Options)> initErrorHandling() async {
  final logHandler = _LoggingReportHandler();
  final issueReporter = CrashIssueReporter(onResult: _showReportResult);

  final debugOptions = Catcher2Options(DialogReportMode(), <ReportHandler>[
    ConsoleHandler(),
    logHandler,
  ]);

  final releaseOptions = Catcher2Options(
    CrashReportMode(
      canSendReport: crashIssueReportingEnabled,
      onReport: _logCrashReport,
    ),
    <ReportHandler>[issueReporter],
    handlerTimeout: 30000,
  );

  log.info('error handling ready', tag: 'crash');

  return (debugOptions, releaseOptions);
}

class _LoggingReportHandler extends ReportHandler {
  @override
  List<PlatformType> getSupportedPlatforms() => PlatformType.values;

  /// Persist the error even when the user dismisses the report page. Logging
  /// must not depend on the crash being submitted.
  @override
  bool shouldHandleWhenRejected() => true;

  @override
  Future<bool> handle(Report report, BuildContext? context) async {
    _logCrashReport(report);
    return true;
  }
}

/// Writes the report into the shared log so the crash survives dismissal and
/// is included in copied/exported diagnostics.
void _logCrashReport(Report report) {
  final stackTrace = report.stackTrace;

  log.error(
    'Unhandled error',
    tag: 'crash',
    fields: <String, Object?>{
      'error_type': '${report.error.runtimeType}',
      'platform': '${report.platformType}',
      'device': safeDeviceParameters(report.deviceParameters),
      'application': report.applicationParameters,
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

  final failed = outcome == CrashReportOutcome.failed;
  final Widget? description;
  if (failed) {
    description = const Text(
      'Export logs from Settings and attach them manually.',
    );
  } else if (issueUrl != null) {
    description = Text(issueUrl.toString());
  } else {
    description = null;
  }

  toastification.show(
    title: Text(switch (outcome) {
      CrashReportOutcome.created => 'Crash report submitted',
      CrashReportOutcome.duplicate => 'Crash report added to an existing issue',
      CrashReportOutcome.failed => 'Crash report could not be sent',
      CrashReportOutcome.disabled => '',
    }),
    description: description,
    type: failed ? ToastificationType.warning : ToastificationType.success,
    style: ToastificationStyle.fillColored,
    autoCloseDuration: Duration(seconds: failed ? 6 : 5),
  );
}
