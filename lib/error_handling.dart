import 'dart:io';

import 'package:catcher_2/handlers/console_handler.dart';
import 'package:catcher_2/handlers/file_handler.dart';
import 'package:catcher_2/mode/dialog_report_mode.dart';
import 'package:catcher_2/model/catcher_2_options.dart';
import 'package:intl/intl.dart';
import 'package:ssb_runner/common/dirs.dart';

Future<(Catcher2Options, Catcher2Options)> initErrorHandling() async {
  final appLogDirPath = '${await getAppDirectory()}/$dirLog';

  final fileHandler = FileHandler(
    File(''), // This file is no effect since we use fileSupplier
    fileSupplier: (report) {
      return _supplyLogFile(appLogDirPath);
    },
    printLogs: true,
  );

  final debugOptions = Catcher2Options(DialogReportMode(), [
    ConsoleHandler(),
    fileHandler,
  ]);

  final releaseOptions = Catcher2Options(DialogReportMode(), [fileHandler]);

  return (debugOptions, releaseOptions);
}

Future<void> _clearOutdatedLogs(String appLogDirPath) async {
  final appLogDir = Directory(appLogDirPath);
  await appLogDir
      .list()
      .where((fileEntry) {
        if (fileEntry is! File) {
          return false;
        }

        final lastModifiedTime = fileEntry
            .lastModifiedSync()
            .millisecondsSinceEpoch;

        final outdatedThreshold = DateTime.now()
            .subtract(Duration(days: 5))
            .millisecondsSinceEpoch;

        return lastModifiedTime < outdatedThreshold;
      })
      .forEach((fileEntry) {
        fileEntry.delete();
      });
}

File _supplyLogFile(String appLogDir) {
  final logFileName = '${_today()}.log';
  final logFile = File('$appLogDir/$logFileName');

  if (!logFile.existsSync()) {
    logFile.createSync(recursive: true);
  }

  return logFile;
}

String _today() {
  return DateFormat('yyyy-MM-dd').format(DateTime.now());
}
