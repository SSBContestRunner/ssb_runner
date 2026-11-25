import 'dart:ui';

import 'package:flutter/widgets.dart' show LocalizationsDelegate;
import 'package:material_ui/material_ui.dart' show GlobalMaterialLocalizations;
import 'package:ssb_runner/l10n/generated/app_localizations.dart';

/// Localization delegates for the app's strings plus the material_ui and
/// cupertino_ui widget sets.
///
/// The generated `AppLocalizations.localizationsDelegates` is built against
/// `package:flutter_localizations`, whose delegates provide the SDK's
/// `MaterialLocalizations`/`CupertinoLocalizations`. Flutter 3.50 moved the
/// widget sets to material_ui/cupertino_ui, and those widgets require the
/// localizations from their own packages instead.
const List<LocalizationsDelegate<dynamic>> appLocalizationsDelegates =
    <LocalizationsDelegate<dynamic>>[
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ];

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
