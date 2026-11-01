/// Which settings drawer tab an issue belongs to. The declaration order must
/// match the `TabBar` order, because it is used as the tab index.
enum SettingsTab { contestStation, training, audio, system }

/// Why a setting blocks the next run. Each value maps to an existing l10n key
/// so the copy does not have to be rewritten per language.
enum SettingsIssueKind {
  callsignMissing,
  durationMissing,
  exchangeMissing,
  exchangeInvalid,
  exchangeOutOfRange,
}

/// Stable widget keys used to scroll to and focus the offending field when the
/// settings drawer opens from an issue. They must not depend on the callsign or
/// the contest, otherwise the target moves while the user edits.
abstract final class SettingsFocusKeys {
  static const stationCallsign = 'station-callsign';
  static const trainingDuration = 'training-duration';

  static String exchangeField(String fieldId) => 'exchange:$fieldId';
}

/// One actionable reason that blocks starting a run.
///
/// Localized text is resolved in the UI layer; this model only carries stable
/// ids so it can be produced and asserted without a `BuildContext`.
class SettingsIssue {
  const SettingsIssue({
    required this.kind,
    required this.tab,
    required this.fieldId,
    required this.fieldLabel,
    required this.focusKey,
    this.sectionId,
    this.min,
    this.max,
    this.currentValue,
  });

  final SettingsIssueKind kind;
  final SettingsTab tab;

  /// Section inside the tab, e.g. `myStation`; null when the field lives at the
  /// top of the tab.
  final String? sectionId;

  /// Stable field id, e.g. `cqZone` / `power` / `stationCallsign`.
  final String fieldId;

  /// Untranslated fallback label, localized through `stationFieldLabel`.
  final String fieldLabel;

  final String focusKey;

  /// Range bounds, only set for [SettingsIssueKind.exchangeOutOfRange].
  final int? min;
  final int? max;

  /// The value that failed validation, shown so the user knows what to change.
  final String? currentValue;
}
