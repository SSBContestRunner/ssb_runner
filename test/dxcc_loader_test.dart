import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/dxcc/dxcc_manager.dart';

void main() {
  test('load dxcc from xml', () {
    // The DXCC table is shipped compressed (assets/dxcc/cty.xml.gz) and decoded
    // at runtime in DxccManager.loadDxcc(), so decode it here the same way.
    final bytes = File('assets/dxcc/cty.xml.gz').readAsBytesSync();
    final xmlString = utf8.decode(GZipDecoder().decodeBytes(bytes));
    final prefixes = parseDxccXml(xmlString);
    expect(prefixes.isNotEmpty, true);
  });

  test('load dxcc from gz', () {
    final bytes = File('assets/dxcc/cty.xml.gz').readAsBytesSync();
    final archiveBytes = GZipDecoder().decodeBytes(bytes);

    final xmlString = utf8.decode(archiveBytes);

    expect(xmlString.isNotEmpty, true);
  });
}
