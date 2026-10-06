import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/common/upper_case_formatter.dart';

void main() {
  final formatter = UpperCaseTextFormatter();

  test('does not touch text while the IME is composing', () {
    // "ni" is uncommitted pinyin: composing covers the whole text. Rewriting
    // the value here would make the IME commit the letters instead of a
    // candidate character, which is what leaked "a bunch of letters" into the
    // field on Windows.
    const composing = TextEditingValue(
      text: 'ni',
      selection: TextSelection.collapsed(offset: 2),
      composing: TextRange(start: 0, end: 2),
    );

    final result = formatter.formatEditUpdate(
      TextEditingValue.empty,
      composing,
    );

    expect(result, composing);
    expect(result.composing, const TextRange(start: 0, end: 2));
  });

  test('uppercases committed text and keeps the selection', () {
    const committed = TextEditingValue(
      text: 'bd7abc',
      selection: TextSelection.collapsed(offset: 6),
    );

    final result = formatter.formatEditUpdate(
      TextEditingValue.empty,
      committed,
    );

    expect(result.text, 'BD7ABC');
    expect(result.selection, const TextSelection.collapsed(offset: 6));
    expect(result.composing.isCollapsed, isTrue);
  });
}