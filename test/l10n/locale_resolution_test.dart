import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/l10n/generated/app_localizations.dart';
import 'package:ssb_runner/l10n/locale_resolution.dart';
import 'package:ssb_runner/settings/app_settings.dart';

void main() {
  const simplified = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans');
  const traditional = Locale.fromSubtags(
    languageCode: 'zh',
    scriptCode: 'Hant',
  );
  final supported = AppLocalizations.supportedLocales;

  test('Chinese locales keep their script distinction', () {
    expect(
      resolveAppLocale([const Locale('zh', 'TW')], supported),
      traditional,
    );
    expect(
      resolveAppLocale([const Locale('zh', 'HK')], supported),
      traditional,
    );
    expect(
      resolveAppLocale([const Locale('zh', 'MO')], supported),
      traditional,
    );
    expect(resolveAppLocale([traditional], supported), traditional);

    expect(resolveAppLocale([const Locale('zh', 'CN')], supported), simplified);
    expect(resolveAppLocale([const Locale('zh', 'SG')], supported), simplified);
    expect(resolveAppLocale([const Locale('zh')], supported), simplified);
  });

  test(
    'Japanese and English are resolved, unsupported falls back to English',
    () {
      expect(
        resolveAppLocale([const Locale('ja', 'JP')], supported),
        const Locale('ja'),
      );
      expect(
        resolveAppLocale([const Locale('en', 'GB')], supported),
        const Locale('en'),
      );
      expect(
        resolveAppLocale([const Locale('fr', 'FR')], supported),
        const Locale('en'),
      );
      expect(resolveAppLocale(null, supported), const Locale('en'));
    },
  );

  test('explicit language choices map to supported Locale values', () {
    expect(appLanguageLocale(AppLanguage.auto), isNull);
    expect(appLanguageLocale(AppLanguage.english), const Locale('en'));
    expect(appLanguageLocale(AppLanguage.simplifiedChinese), simplified);
    expect(appLanguageLocale(AppLanguage.traditionalChinese), traditional);
    expect(appLanguageLocale(AppLanguage.japanese), const Locale('ja'));
  });
}
