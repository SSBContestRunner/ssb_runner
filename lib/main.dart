import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:logger/web.dart';
import 'package:ssb_runner/crash_repoter.dart';
import 'package:ssb_runner/ui/main_app/main_app.dart';

final logger = Logger(printer: PrettyPrinter(methodCount: 5));
final crashLogger = CrashLogger();
const seedColor = Color(0xFF0059BA);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(MainApp());
}

Future<void> initCrashHandling() async {
  // 初始化日志系统
  await crashLogger.initialize();

  // 设置全局异常处理
  FlutterError.onError = (FlutterErrorDetails details) {
    crashLogger.logCrash(details.exceptionAsString(), details.stack);
    FlutterError.presentError(details); // 保留默认错误显示
  };

  // 捕获异步异常
  PlatformDispatcher.instance.onError = (error, stack) {
    crashLogger.logCrash(error.toString(), stack);
    return true;
  };
}
