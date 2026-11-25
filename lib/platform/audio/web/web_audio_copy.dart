import 'package:material_ui/material_ui.dart';
import 'package:ssb_runner/l10n/generated/app_localizations.dart';

/// Glyph shown by the web badge and the web dialog.
///
/// The browser can only report "the engine is not usable", so there is no
/// low-volume variant on this platform.
IconData webAudioAlertIcon() => Icons.volume_off_outlined;

/// Tooltip and dialog headline for the web alert.
String webAudioAlertTooltip(AppLocalizations l10n) =>
    l10n.audioBadgeEngineBlockedTooltip;
