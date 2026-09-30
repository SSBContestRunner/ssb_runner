import 'package:catcher_2/handlers/console_handler.dart';
import 'package:catcher_2/mode/dialog_report_mode.dart';
import 'package:catcher_2/mode/page_report_mode.dart';
import 'package:catcher_2/model/catcher_2_options.dart';
import 'package:catcher_2/model/platform_type.dart';
import 'package:catcher_2/model/report.dart';
import 'package:catcher_2/model/report_handler.dart';
import 'package:flutter/widgets.dart';
import 'package:ssb_runner/logging/app_logger.dart';

/// Builds the Catcher2 configurations used for debug and release builds.
///
/// Reports are funnelled into the shared log file by [_LoggingReportHandler],
/// so unhandled exceptions and ordinary progress records end up interleaved in
/// a single timeline.
Future<(Catcher2Options, Catcher2Options)> initErrorHandling() async {
  final logHandler = _LoggingReportHandler();

  final debugOptions = Catcher2Options(DialogReportMode(), <ReportHandler>[
    ConsoleHandler(),
    logHandler,
  ]);

  final releaseOptions = Catcher2Options(
    PageReportMode(showStackTrace: false),
    <ReportHandler>[logHandler],
  );

  log.info('error handling ready', tag: 'crash');

  return (debugOptions, releaseOptions);
}

class _LoggingReportHandler extends ReportHandler {
  @override
  List<PlatformType> getSupportedPlatforms() => PlatformType.values;

  @override
  Future<bool> handle(Report report, BuildContext? context) async {
    final stackTrace = report.stackTrace;

    log.error(
      'Unhandled error',
      tag: 'crash',
      fields: <String, Object?>{
        'error_type': '${report.error.runtimeType}',
        'platform': '${report.platformType}',
        'device': report.deviceParameters,
        'application': report.applicationParameters,
      },
      error: report.error,
      stackTrace: stackTrace is StackTrace ? stackTrace : null,
    );

    return true;
  }
}
