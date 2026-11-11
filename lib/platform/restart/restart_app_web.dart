import 'package:web/web.dart' as web;

/// Reloads the page, which re-runs storage probing and database opening.
Future<void> restartApplication() async {
  web.window.location.reload();
}
