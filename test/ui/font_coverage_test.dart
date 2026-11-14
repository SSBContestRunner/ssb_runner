import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// Fonts are shipped subsetted (see tool/build_fonts.py). If a UI string uses a
/// character outside the subsets, the engine falls back to a platform font for
/// that glyph only. On Windows that is normally Microsoft YaHei, which has a
/// different design and no Medium weight, so a label like "结束本局" ends up as
/// two typefaces and two weights on one line. This test fails as soon as a new
/// string (or a new hard-coded literal) leaves the subset behind.
void main() {
  test('bundled font subsets cover every character the UI can render', () {
    final inventory = _uiCharacters();
    final cmaps = {
      for (final path in _fonts) path: _readCmap(File(path).readAsBytesSync()),
    };

    final latin = cmaps[_iosevka]!;
    final notoWeights = [
      cmaps[_notoSansScRegular]!,
      cmaps[_notoSansScMedium]!,
      cmaps[_notoSansScBold]!,
    ];

    // The data face owns printable ASCII; anything else drifts to the CJK face
    // and its different advance widths.
    final ascii = {for (var c = 0x20; c <= 0x7e; c++) c};
    expect(
      ascii.difference(latin),
      isEmpty,
      reason: 'Iosevka subset is missing ASCII characters',
    );

    // CJK text is rendered at every weight the theme asks for (labelLarge is
    // w500, titles are w600, all of which resolve to Medium or Bold), so each
    // weight must carry the full CJK inventory.
    final cjk = inventory.where((c) => c >= 0x2e80).toSet();
    for (final (name, cmap) in [
      ('NotoSansSC-Regular', notoWeights[0]),
      ('NotoSansSC-Medium', notoWeights[1]),
      ('NotoSansSC-Bold', notoWeights[2]),
    ]) {
      expect(
        cjk.difference(cmap),
        isEmpty,
        reason:
            '$name subset is missing CJK characters: '
            '${_describe(cjk.difference(cmap))}',
      );
    }

    final shipped = <int>{for (final cmap in cmaps.values) ...cmap};
    final uncovered = inventory.difference(shipped).toList()..sort();
    expect(
      uncovered,
      isEmpty,
      reason:
          'No bundled font covers these characters, so they will fall back '
          'to a platform font: ${_describe(uncovered.toSet())}. '
          'Regenerate the subsets with tool/build_fonts.py.',
    );
  });
}

const _iosevka = 'fonts/Iosevka-Regular-sub.ttf';
const _notoSansScRegular = 'fonts/NotoSansSC-Regular-sub.otf';
const _notoSansScMedium = 'fonts/NotoSansSC-Medium-sub.otf';
const _notoSansScBold = 'fonts/NotoSansSC-Bold-sub.otf';

const _fonts = [
  _iosevka,
  _notoSansScRegular,
  _notoSansScMedium,
  _notoSansScBold,
];

/// Every character the UI can ask the text engine to render.
///
/// Whole Dart files are scanned instead of parsed string literals: a few extra
/// characters from comments cost a couple of hundred bytes, while a missed
/// literal costs a rendering defect on Windows.
Set<int> _uiCharacters() {
  final chars = <int>{for (var c = 0x20; c <= 0x7e; c++) c};

  for (final entity in Directory('lib/l10n').listSync()) {
    if (entity is File && entity.path.endsWith('.arb')) {
      _collectStrings(jsonDecode(entity.readAsStringSync()), chars);
    }
  }
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      chars.addAll(entity.readAsStringSync().runes.where((r) => r > 0x7f));
    }
  }
  chars.removeWhere((c) => c < 0x20 || (c >= 0x7f && c <= 0x9f));
  return chars;
}

void _collectStrings(Object? node, Set<int> chars) {
  switch (node) {
    case String value:
      chars.addAll(value.runes);
    case Map<Object?, Object?> map:
      for (final value in map.values) {
        _collectStrings(value, chars);
      }
    case List<Object?> list:
      for (final value in list) {
        _collectStrings(value, chars);
      }
  }
}

String _describe(Set<int> codepoints) {
  final sorted = codepoints.toList()..sort();
  return sorted
      .map(
        (c) =>
            '${String.fromCharCode(c)} (U+${c.toRadixString(16).toUpperCase().padLeft(4, '0')})',
      )
      .join(', ');
}

/// Minimal SFNT cmap reader (formats 4 and 12), enough to check coverage
/// without pulling a font parsing dependency into the project.
Set<int> _readCmap(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final numTables = data.getUint16(4);
  int? cmapOffset;
  for (var i = 0; i < numTables; i++) {
    final record = 12 + i * 16;
    final tag = String.fromCharCodes(bytes.sublist(record, record + 4));
    if (tag == 'cmap') {
      cmapOffset = data.getUint32(record + 8);
      break;
    }
  }
  if (cmapOffset == null) {
    throw StateError('Font has no cmap table');
  }

  final result = <int>{};
  final subtableCount = data.getUint16(cmapOffset + 2);
  for (var i = 0; i < subtableCount; i++) {
    final record = cmapOffset + 4 + i * 8;
    final platformId = data.getUint16(record);
    final encodingId = data.getUint16(record + 2);
    final isUnicode =
        platformId == 0 ||
        (platformId == 3 && (encodingId == 1 || encodingId == 10));
    if (!isUnicode) continue;

    final subtable = cmapOffset + data.getUint32(record + 4);
    switch (data.getUint16(subtable)) {
      case 4:
        _readFormat4(data, subtable, result);
      case 12:
        _readFormat12(data, subtable, result);
    }
  }
  return result;
}

void _readFormat4(ByteData data, int offset, Set<int> out) {
  final segCount = data.getUint16(offset + 6) ~/ 2;
  final endCodes = offset + 14;
  final startCodes = endCodes + segCount * 2 + 2;
  final deltas = startCodes + segCount * 2;
  final rangeOffsets = deltas + segCount * 2;

  for (var i = 0; i < segCount; i++) {
    final end = data.getUint16(endCodes + i * 2);
    final start = data.getUint16(startCodes + i * 2);
    if (start == 0xffff) continue;
    final delta = data.getUint16(deltas + i * 2);
    final rangeOffset = data.getUint16(rangeOffsets + i * 2);

    for (var c = start; c <= end; c++) {
      final int glyph;
      if (rangeOffset == 0) {
        glyph = (c + delta) & 0xffff;
      } else {
        final address = rangeOffsets + i * 2 + rangeOffset + (c - start) * 2;
        final raw = data.getUint16(address);
        if (raw == 0) continue;
        glyph = (raw + delta) & 0xffff;
      }
      if (glyph != 0) out.add(c);
    }
  }
}

void _readFormat12(ByteData data, int offset, Set<int> out) {
  final groups = data.getUint32(offset + 12);
  for (var i = 0; i < groups; i++) {
    final group = offset + 16 + i * 12;
    final start = data.getUint32(group);
    final end = data.getUint32(group + 4);
    for (var c = start; c <= end; c++) {
      out.add(c);
    }
  }
}
