import 'dart:ui';

import 'package:ssb_runner/settings/app_settings.dart';

/// Locale for an explicit language choice; `auto` leaves resolution to the
/// platform (`MaterialApp.locale == null`).
Locale? appLanguageLocale(AppLanguage language) => switch (language) {
  AppLanguage.auto => null,
  AppLanguage.english => const Locale('en'),
  AppLanguage.simplifiedChinese => const Locale.fromSubtags(
    languageCode: 'zh',
    scriptCode: 'Hans',
  ),
  AppLanguage.traditionalChinese => const Locale.fromSubtags(
    languageCode: 'zh',
    scriptCode: 'Hant',
  ),
  AppLanguage.japanese => const Locale('ja'),
};

/// Resolves the system locale list to one of the app's supported locales.
///
/// Flutter's default algorithm matches only by language when the system
/// locale has no script code, which would turn `zh_TW` into Simplified
/// Chinese. This resolver keeps the script/country distinction:
/// Traditional for `Hant` / TW / HK / MO, Simplified for every other `zh`.
Locale resolveAppLocale(List<Locale>? preferred, Iterable<Locale> supported) {
  final supportedList = supported.toList();
  if (supportedList.isEmpty) return const Locale('en');

  for (final locale in preferred ?? const <Locale>[]) {
    switch (locale.languageCode) {
      case 'ja':
        return _match(supportedList, const Locale('ja')) ??
            _fallbackEnglish(supportedList);
      case 'zh':
        final traditional =
            locale.scriptCode == 'Hant' ||
            const {'TW', 'HK', 'MO'}.contains(locale.countryCode);
        final target = Locale.fromSubtags(
          languageCode: 'zh',
          scriptCode: traditional ? 'Hant' : 'Hans',
        );
        return _match(supportedList, target) ??
            _match(supportedList, const Locale('zh')) ??
            _fallbackEnglish(supportedList);
      case 'en':
        return _match(supportedList, const Locale('en')) ??
            _fallbackEnglish(supportedList);
    }
  }

  return _fallbackEnglish(supportedList);
}

Locale? _match(List<Locale> supported, Locale target) {
  for (final locale in supported) {
    if (locale.languageCode == target.languageCode &&
        locale.scriptCode == target.scriptCode) {
      return locale;
    }
  }
  return null;
}

Locale _fallbackEnglish(List<Locale> supported) => supported.firstWhere(
  (locale) => locale.languageCode == 'en',
  orElse: () => supported.first,
);
