/// Removes callsigns that the DXCC prefix table cannot resolve.
///
/// Run after `tool/generate_callsign_pool.py`, which produces the SCP ∪ existing
/// union, and before the file is bundled:
///
///     python3 tool/generate_callsign_pool.py \
///         --scp /path/to/SCP.DB \
///         --existing assets/callsign/callsigns.txt \
///         --min-rate 100 --phone-only \
///         --out assets/callsign/callsigns.txt
///     dart run tool/prune_callsigns.dart assets/callsign/callsigns.txt
///
/// The lookup is [lookupCallsignPrefix], the same implementation the app's
/// `DxccManager` uses, so this stays in sync with runtime behaviour. Filtering
/// is idempotent: running it again on an already pruned pool removes nothing.
///
/// Usage: prune_callsigns.dart [input] [output]
/// (both default to assets/callsign/callsigns.txt)
library;

import 'dart:io';

import 'package:ssb_runner/dxcc/generated/prefix_data.g.dart';
import 'package:ssb_runner/dxcc/prefix_data.dart';
import 'package:ssb_runner/dxcc/prefix_row.dart';

void main(List<String> args) {
  final inputPath = args.isNotEmpty ? args[0] : 'assets/callsign/callsigns.txt';
  final outputPath = args.length > 1 ? args[1] : inputPath;

  final rows = parsePrefixRows(dxccPrefixTsv);
  final byCall = <String, PrefixRow>{for (final row in rows) row.call: row};

  final calls = File(inputPath)
      .readAsLinesSync()
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();

  final kept = <String>[];
  final removed = <String>[];
  for (final callsign in calls) {
    if (lookupCallsignPrefix(byCall, callsign) == null) {
      removed.add(callsign);
    } else {
      kept.add(callsign);
    }
  }

  File(outputPath).writeAsStringSync('${kept.join('\n')}\n');

  stdout.writeln(
    'kept ${kept.length}, removed ${removed.length} -> $outputPath',
  );
  for (final callsign in removed) {
    stdout.writeln('  removed: $callsign');
  }
}
