import 'dart:convert';

import 'package:ssb_runner/common/extract_prefix.dart';
import 'package:ssb_runner/dxcc/prefix_row.dart';

/// Version of the prefix data compiled into this build.
///
/// Compared against the backend manifest once hot updates land.
const int dxccBundledDataVersion = 2;

/// Parses the `#dxcc-tsv v2` payload.
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

/// Resolves the prefix table row for [callsign].
///
/// A call containing `/` is looked up from the part before the first slash
/// first, because that segment carries the station's own prefix: `9A/DF2AJ`
/// is in Croatia and `PY0F/AA4NC` is on Fernando de Noronha. Suffixes such as
/// `/P`, `/M`, `/MM`, `/QRP` and call-area digits never decide the country by
/// themselves; only the leading segment does. If that segment has no row the
/// legacy whole-call extraction is used as a fallback.
///
/// Two details matter:
/// * A leading segment that is an exact table token (`PY0F`, `CE0Y`, `4W`)
///   wins outright; the old regex would truncate `PY0F` to `PY0`.
/// * Only a single-digit suffix (`R9XC/1`) makes the deeper token walk
///   (`R9XC` -> `R9X`) meaningful. With `/P` and friends the call keeps the
///   shorter regex prefix, so portable Russians do not change CQ/ITU zone.
///
/// As a last resort, when every rule above misses, the whole call is walked
/// back to the longest table token (of at least three characters) that
/// prefixes it. Some entities exist only as four-letter tokens (`VP2E`,
/// `VP2M`, `VP2V`) and the regex reads `VP2EAD` as `VP2`, which has no row.
///
/// A call that equals a table token exactly is answered before any regex
/// work, so a bare `PY0F` is Fernando de Noronha rather than Brazil.
///
/// Both [parsePrefixRows] and a database snapshot feed the same map shape, so
/// this stays the single implementation of the matching rule.
PrefixRow? lookupCallsignPrefix(
  Map<String, PrefixRow> byCall,
  String callsign,
) {
  // A call that is itself a table token is that token, full stop: bare `PY0F`
  // is Fernando de Noronha, not the `PY0` regex match (Brazil). This is the
  // only exact-equality shortcut; shorter tokens still never override a
  // regex match, which would move hundred-odd calls.
  final whole = byCall[callsign];
  if (whole != null) {
    return whole;
  }

  final slash = callsign.indexOf('/');
  if (slash > 0) {
    final main = callsign.substring(0, slash);
    final suffix = callsign.substring(slash + 1);

    final exact = byCall[main];
    if (exact != null) {
      return exact;
    }

    // Letter-only segments such as `RA` or `F` carry no digit for the regex,
    // so walk the segment itself.
    if (!_hasDigit(main)) {
      final prefixMatch = _walkBack(byCall, main);
      if (prefixMatch != null) {
        return prefixMatch;
      }
    }

    // A call-area digit is not a country hint on its own, but it does select
    // the area token (R9XC/1 -> R9X -> European Russia).
    if (_areaDigit.hasMatch(suffix)) {
      final areaMatch = _walkBack(byCall, main);
      if (areaMatch != null) {
        return areaMatch;
      }
    }

    final mainMatch = _walkBack(byCall, extractPrefix(main));
    if (mainMatch != null) {
      return mainMatch;
    }
  }

  final legacy = _walkBack(byCall, extractPrefix(callsign));
  if (legacy != null) {
    return legacy;
  }

  // Last resort: the longest table token that prefixes the whole call. Tokens
  // shorter than three characters are too coarse to identify a call area
  // (`4G` would swallow `4GRID`, `7Q` would swallow `7QAA`).
  return _walkBack(byCall, callsign, minLength: 3);
}

final RegExp _areaDigit = RegExp(r'^[0-9]$');

bool _hasDigit(String value) => value.codeUnits.any((c) => c >= 48 && c <= 57);

/// Walks a prefix back one character at a time until a row matches.
///
/// Stops early when the remaining prefix is shorter than [minLength].
PrefixRow? _walkBack(
  Map<String, PrefixRow> byCall,
  String prefix, {
  int minLength = 1,
}) {
  var checked = prefix;
  while (checked.length >= minLength) {
    final match = byCall[checked];
    if (match != null) {
      return match;
    }
    checked = checked.substring(0, checked.length - 1);
  }
  return null;
}
