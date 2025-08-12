import 'package:catcher_2/catcher_2.dart';
import 'package:flutter/material.dart';
import 'package:logger/web.dart';
import 'package:ssb_runner/error_handling.dart';
import 'package:ssb_runner/ui/main_app/main_app.dart';

final logger = Logger(printer: PrettyPrinter(methodCount: 5));
const seedColor = Color(0xFF0059BA);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final (debugOptions, releaseOptions) = await initErrorHandling();

  Catcher2(
    rootWidget: MainApp(),
    debugConfig: debugOptions,
    releaseConfig: releaseOptions,
  );

  Catcher2.sendTestException();
}
