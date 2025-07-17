import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/dxcc/dxcc_manager.dart';

void main() {
  test('load dxcc from xml', () {
    final xmlString = File('assets/dxcc/cty.xml').readAsStringSync();
    final prefixes = parseDxccXml(xmlString);
    expect(prefixes.isNotEmpty, true);
  });
}
