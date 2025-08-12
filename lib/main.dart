import 'dart:io';

import 'package:catcher_2/catcher_2.dart';
import 'package:flutter/material.dart';
import 'package:logger/web.dart';
import 'package:ssb_runner/common/dirs.dart';
import 'package:ssb_runner/ui/main_app/main_app.dart';

final logger = Logger(printer: PrettyPrinter(methodCount: 5));
const seedColor = Color(0xFF0059BA);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final debugOptions = Catcher2Options(DialogReportMode(), [ConsoleHandler()]);

  final file = File('${await getAppDirectory()}/$dirLog');

  final releaseOptions = Catcher2Options(DialogReportMode(), [
    EmailManualHandler(["bi1qjq@163.com"]),
    FileHandler(file),
  ]);

  Catcher2(
    rootWidget: MainApp(),
    debugConfig: debugOptions,
    releaseConfig: releaseOptions,
  );
}
