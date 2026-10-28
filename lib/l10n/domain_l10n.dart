import 'package:ssb_runner/audio/accent_policy.dart';
import 'package:ssb_runner/audio/audio_loader.dart';
import 'package:ssb_runner/l10n/generated/app_localizations.dart';
import 'package:ssb_runner/training/training_profile.dart';

/// Localized labels for domain enums and station/contest metadata.
///
/// Domain objects keep their stable ids so persisted history and settings stay
/// valid; only the display text is resolved through these extensions.
extension DomainL10n on AppLocalizations {
  String trainingModeLabel(TrainingMode mode) => switch (mode) {
    TrainingMode.run => modeRun,
    TrainingMode.searchAndPounce => modeSearchAndPounce,
    TrainingMode.pileup => modePileup,
  };

  String trainingModeLabelById(String? id) =>
      trainingModeLabel(TrainingMode.fromId(id));

  String trainingDifficultyLabel(TrainingDifficulty difficulty) =>
      switch (difficulty) {
        TrainingDifficulty.beginner => difficultyBeginner,
        TrainingDifficulty.standard => difficultyStandard,
        TrainingDifficulty.advanced => difficultyAdvanced,
      };

  String trainingDifficultyLabelById(String? id) =>
      trainingDifficultyLabel(TrainingDifficulty.fromId(id));

  String phonicTypeLabel(PhonicType type) => switch (type) {
    PhonicType.standard => phonicStandard,
    PhonicType.location => phonicLocation,
    PhonicType.mixed => phonicMixed,
  };

  String incomingAccentLabel(IncomingAccent accent) => switch (accent) {
    IncomingAccent.auto => accentAuto,
    IncomingAccent.us => accentUs,
    IncomingAccent.uk => accentUk,
    IncomingAccent.japan => accentJapan,
    IncomingAccent.russia => accentRussia,
    IncomingAccent.india => accentIndiaSea,
  };

  /// [fallback] keeps unknown/new contest fields readable if a translation is
  /// missing.
  String stationFieldLabel(String id, String fallback) => switch (id) {
    'cqZone' => fieldCqZone,
    'ituZone' => fieldItuZone,
    'stateProvince' => fieldStateProvince,
    'power' => fieldPower,
    'prefecture' => fieldPrefecture,
    _ => fallback,
  };

  String? stationFieldHelper(String id) => switch (id) {
    'stateProvince' => helperStateProvince,
    'power' => helperPower,
    'prefecture' => helperPrefecture,
    _ => null,
  };

  String contestExchangeLabel(String contestId, String fallback) =>
      switch (contestId) {
        'CQ-WPX' => contestExchangeCqWpx,
        'CQ-WW-SSB' => contestExchangeCqWw,
        'ARRL-DX' => contestExchangeArrlDx,
        'IARU-HF' => contestExchangeIaruHf,
        'JIDX-SSB' => contestExchangeJidx,
        _ => fallback,
      };
}
