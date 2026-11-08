import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/settings/app_settings.dart';

const _arbFiles = [
  'lib/l10n/app_en.arb',
  'lib/l10n/app_zh.arb',
  'lib/l10n/app_zh_Hans.arb',
  'lib/l10n/app_zh_Hant.arb',
  'lib/l10n/app_ja.arb',
];

/// Keys that guide the operator through a live QSO. They must name the action,
/// never a configurable key, because F1–F12 can be rebound at any time.
const _guidanceKeys = [
  'phaseHintListening',
  'phaseHintCallNotCopied',
  'phaseHintHeWantsSerial',
  'phaseHintReportSent',
  'phaseHintSpListening',
  'phaseHintSpHeAnswered',
  'abandonRound',
  'keyTipSendCallExchange',
];

/// The only string allowed to mention the configurable range: it is the
/// settings entry that opens the key editor.
const _functionKeyRange = 'settingsFunctionKeysRowSubtitle';

void main() {
  final functionKeyLiteral = RegExp(r'\bF(?:[1-9]|1[0-2])\b');
  final upperToken = RegExp(r'\b[A-Z]{2,4}\b');
  final actionLabels = {
    for (final action in OperationAction.values) action.label,
  };

  test('guidance strings never hardcode a configurable function key', () {
    for (final path in _arbFiles) {
      final strings = _readArb(path);
      for (final entry in strings.entries) {
        if (entry.key.startsWith('@') || entry.key == _functionKeyRange) {
          continue;
        }
        expect(
          functionKeyLiteral.hasMatch(entry.value),
          isFalse,
          reason: '${entry.key} in $path must name the action, not the key',
        );
      }
    }
  });

  test('the fixed Enter shortcut stays in the listening hint', () {
    for (final path in _arbFiles) {
      expect(
        _readArb(path)['phaseHintListening'],
        contains('Enter'),
        reason: 'Enter is a fixed shortcut and may be named in $path',
      );
    }
  });

  test('guidance only points at actions that render as buttons', () {
    for (final path in _arbFiles) {
      final strings = _readArb(path);
      for (final key in _guidanceKeys) {
        final hint = strings[key]!;
        for (final token in upperToken.allMatches(hint)) {
          final label = token.group(0)!;
          if (label == 'QSO') continue;
          expect(
            actionLabels,
            contains(label),
            reason: '$key in $path mentions "$label", which has no button',
          );
        }
      }
    }
  });
}

Map<String, String> _readArb(String path) {
  final map =
      json.decode(File(path).readAsStringSync()) as Map<String, dynamic>;
  return {
    for (final entry in map.entries)
      if (entry.value is String) entry.key: entry.value as String,
  };
}
