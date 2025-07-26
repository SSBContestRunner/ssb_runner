import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

class CrashLogger {
  static const String _logFileName = 'scr_crash.log';
  late File _logFile;

  Future<void> initialize() async {
    final directory = await getApplicationDocumentsDirectory();
    _logFile = File('${directory.path}/$_logFileName');

    // 清理过大的日志文件 (可选)
    if (await _logFile.exists() &&
        (await _logFile.length()) > 20 * 1024 * 1024) {
      await _logFile.writeAsString(''); // 清空文件
    }
  }

  Future<void> logCrash(String error, StackTrace? stack) async {
    final logEntry =
        '''
===== CRASH REPORT =====
Timestamp: ${DateTime.now().toIso8601String()}
Error: $error
Stack Trace:
${stack.toString()}
===== END REPORT =====

''';

    try {
      // 追加写入日志文件
      await _logFile.writeAsString(logEntry, mode: FileMode.append);
    } catch (e) {
      debugPrint('Failed to write crash log: $e');
    }
  }
}
