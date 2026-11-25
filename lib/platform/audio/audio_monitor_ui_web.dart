import 'package:material_ui/material_ui.dart';

/// The browser has no system audio endpoint to monitor, so the badge, the
/// toaster and the run pre-flight are all inert.
Widget wrapWithAudioMonitor(Widget child) => child;

Widget buildAudioStatusBadge() => const SizedBox.shrink();

Widget buildAudioAlertToaster() => const SizedBox.shrink();

void startAudioMonitor() {}

void stopAudioMonitor() {}

void disposeAudioMonitor() {}

Future<bool> confirmRunAudioPreflight(BuildContext context) async => true;
