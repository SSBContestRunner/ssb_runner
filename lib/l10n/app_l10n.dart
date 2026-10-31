import 'dart:ui';

import 'package:ssb_runner/l10n/generated/app_localizations.dart';

/// Holds the active [AppLocalizations] for code paths without a [BuildContext],
/// such as the Catcher2 crash-report callback. Updated from the MaterialApp
/// builder whenever the locale changes.
class AppL10n {
  AppL10n._();

  static AppLocalizations? _current;

  static AppLocalizations get current =>
      _current ??= lookupAppLocalizations(const Locale('en'));

  static void update(AppLocalizations value) => _current = value;
}
