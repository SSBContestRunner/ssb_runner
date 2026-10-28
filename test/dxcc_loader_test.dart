import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/dxcc/cty_xml.dart';
import 'package:ssb_runner/dxcc/generated/prefix_data.g.dart';
import 'package:ssb_runner/dxcc/prefix_data.dart';

void main() {
  // The XML is only a build-time input now; the app ships the generated TSV.
  final xmlRows = parseDxccXml(
    utf8.decode(
      GZipDecoder().decodeBytes(
        File('assets/dxcc/cty.xml.gz').readAsBytesSync(),
      ),
    ),
  );

  test('load dxcc from gz', () {
    expect(xmlRows, isNotEmpty);
  });

  test('bundled prefix data matches the cty asset', () {
    final bundledRows = parsePrefixRows(dxccPrefixTsv);

    expect(bundledRows.length, xmlRows.length);
    for (var i = 0; i < xmlRows.length; i++) {
      final bundled = bundledRows[i];
      final xml = xmlRows[i];

      expect(bundled.call, xml.call);
      expect(bundled.dxccId, xml.dxccId);
      expect(bundled.continent, xml.continent);
      expect(bundled.cqz, xml.cqz);
      expect(bundled.ituz, xml.ituz);
    }
  });
}
