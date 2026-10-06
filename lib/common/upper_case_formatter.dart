import 'package:flutter/services.dart';

/// Uppercases text only after the IME has committed it.
///
/// Flutter applies input formatters to uncommitted composing text as well
/// (see `EditableText._formatAndSetValue`). Rebuilding the value while
/// [TextEditingValue.composing] is active makes the platform IME believe the
/// composition has ended, so on Windows a Chinese/Japanese IME commits the raw
/// phonetic letters instead of a candidate character (typing pinyin spills a
/// string of stray letters into the field). Leaving text under composition
/// untouched keeps the input method working; the conversion happens once the
/// composing range collapses.
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.composing.isCollapsed) {
      return newValue;
    }

    final upperCased = newValue.text.toUpperCase();
    if (upperCased == newValue.text) {
      return newValue;
    }

    return newValue.copyWith(text: upperCased);
  }
}