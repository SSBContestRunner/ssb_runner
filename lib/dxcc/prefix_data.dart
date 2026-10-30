import 'dart:convert';

import 'package:ssb_runner/dxcc/prefix_row.dart';

/// Version of the prefix data compiled into this build.
///
/// Compared against the backend manifest once hot updates land.
const int dxccBundledDataVersion = 1;

/// Parses the `#dxcc-tsv v1` payload.
///
/// The payload is line based: the first line is the header (any line starting
/// with `#` is a comment), every other line is `call|adif|cont|cqz|ituz`, with
/// empty `cqz` / `ituz` meaning null. The same parser reads the bundled seed
/// and, later, downloaded updates.
List<PrefixRow> parsePrefixRows(String tsv) {
  final rows = <PrefixRow>[];

  for (final line in const LineSplitter().convert(tsv)) {
    if (line.isEmpty || line.startsWith('#')) {
      continue;
    }

    final fields = line.split('|');
    if (fields.length < 5) {
      throw FormatException('Malformed dxcc row', line);
    }

    rows.add(
      PrefixRow(
        call: fields[0],
        dxccId: int.parse(fields[1]),
        continent: fields[2],
        cqz: int.tryParse(fields[3]),
        ituz: int.tryParse(fields[4]),
      ),
    );
  }

  return rows;
}
