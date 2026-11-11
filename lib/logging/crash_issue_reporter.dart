import 'package:catcher_2/model/platform_type.dart';
import 'package:catcher_2/model/report.dart';
import 'package:catcher_2/model/report_handler.dart';
import 'package:flutter/widgets.dart';
import 'package:ssb_runner/logging/crash_result.dart';
import 'package:ssb_runner/platform/crash/crash_reporter.dart' as platform;

export 'crash_payload.dart';
export 'crash_result.dart';

/// Whether this build can publish crash reports.
///
/// Desktop builds require a build-time token; web builds require a proxy route.
bool get crashIssueReportingEnabled => platform.crashIssueReportingEnabled;

/// Catcher2 handler that files the accepted crash report through the platform
/// transport (GitHub directly on desktop, a Worker proxy on the web).
///
/// Catcher2 only invokes handlers when the user accepts the report page, so
/// nothing is sent unless the user explicitly confirms.
class CrashIssueReporter extends ReportHandler {
  CrashIssueReporter({this.onResult});

  /// Called after a submission attempt so the UI can show feedback. The
  /// handler never throws into Catcher2, regardless of network failures.
  final void Function(CrashReportOutcome outcome, Uri? issueUrl)? onResult;

  @override
  Future<bool> handle(Report report, BuildContext? context) async {
    final result = await platform.submitCrashReport(report);
    _notify(result.outcome, result.issueUrl);
    return result.outcome == CrashReportOutcome.created ||
        result.outcome == CrashReportOutcome.duplicate;
  }

  @override
  List<PlatformType> getSupportedPlatforms() => PlatformType.values;

  void _notify(CrashReportOutcome outcome, Uri? issueUrl) {
    final callback = onResult;
    if (callback == null) {
      return;
    }

    try {
      callback(outcome, issueUrl);
    } on Object {
      // Feedback must never turn a handled crash into a second failure.
    }
  }
}
