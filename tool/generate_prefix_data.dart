import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:ssb_runner/dxcc/cty_xml.dart';
import 'package:ssb_runner/dxcc/prefix_data.dart';

/// Regenerates `lib/dxcc/generated/prefix_data.g.dart` from the cty asset.
///
/// Run after updating `assets/dxcc/cty.xml.gz`. `test/dxcc_loader_test.dart`
/// compares the generated rows against the XML source, so a stale file fails
/// the test suite.
Future<void> main() async {
  final source = File('assets/dxcc/cty.xml.gz');
  final rows = parseDxccXml(
    utf8.decode(GZipDecoder().decodeBytes(source.readAsBytesSync())),
  );

  final tsv = StringBuffer(
    '#dxcc-tsv v$dxccBundledDataVersion rows=${rows.length}\n',
  );
  for (final row in rows) {
    tsv.write(
      '${row.call}|${row.dxccId}|${row.continent}|'
      '${row.cqz ?? ''}|${row.ituz ?? ''}\n',
    );
  }

  final output = File('lib/dxcc/generated/prefix_data.g.dart');
  output.parent.createSync(recursive: true);
  output.writeAsStringSync(
    '// GENERATED CODE - DO NOT MODIFY BY HAND.\n'
    '// Regenerate: dart run tool/generate_prefix_data.dart\n'
    '// Source: assets/dxcc/cty.xml.gz\n'
    '//\n'
    '// test/dxcc_loader_test.dart compares this output against the source, so a\n'
    '// stale file fails the test suite.\n'
    "const String dxccPrefixTsv = r'''\n"
    '$tsv'
    "''';\n",
  );

  stdout.writeln('wrote ${rows.length} rows to ${output.path}');
}
