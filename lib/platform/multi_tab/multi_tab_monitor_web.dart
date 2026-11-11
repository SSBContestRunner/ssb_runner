import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'multi_tab_status.dart';

const String _channelName = 'ssb_runner_tabs';

/// Detects a second open tab through `BroadcastChannel`.
///
/// Two tabs can write the same database, so the UI warns once instead of
/// pretending concurrent writes are a normal case. The JS API is optional;
/// browsers without it simply never report a second tab.
void startMultiTabMonitor() {
  try {
    final channel = web.BroadcastChannel(_channelName);
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    var reported = false;

    void report() {
      if (reported) {
        return;
      }
      reported = true;
      multiTabRevision.value++;
    }

    channel.onmessage = ((web.MessageEvent event) {
      final data = event.data.dartify();
      if (data is! Map) {
        return;
      }

      final sender = data['id'];
      if (sender == id) {
        return;
      }

      if (data['type'] == 'hello') {
        // Answer once so the tab that just opened also learns about this one.
        channel.postMessage(
          <String, Object?>{'type': 'here', 'id': id}.jsify(),
        );
        return;
      }

      report();
    }).toJS;

    channel.postMessage(<String, Object?>{'type': 'hello', 'id': id}.jsify());
  } catch (_) {
    // BroadcastChannel is unavailable or blocked; multi-tab detection is a
    // best-effort warning, not a requirement.
  }
}
