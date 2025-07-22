import 'dart:convert';

import 'package:flutter/services.dart';

class CallsignLoader {
  final List<String> callSigns = [];

  Future<void> loadCallsigns() async {
    final callsigns = await rootBundle.loadString('assets/callsign/callsigns.txt');

    for (final callsign in LineSplitter.split(callsigns)) {
      callSigns.add(callsign);
    }
  }
}
