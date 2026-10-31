import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssb_runner/audio/accent_policy.dart';
import 'package:ssb_runner/audio/audio_loader.dart';
import 'package:ssb_runner/common/constants.dart';
import 'package:ssb_runner/contest_type/contest_definition.dart';
import 'package:ssb_runner/contest_type/station_exchange.dart';
import 'package:ssb_runner/logging/app_logger.dart';
import 'package:ssb_runner/training/session_review.dart';
import 'package:ssb_runner/training/training_profile.dart';

class AppSettings {
  final SharedPreferencesWithCache _prefs;

  /// Owned by [MainApp], which listens to it to rebuild [MaterialApp.locale].
  /// AppSettings never disposes it.
  final ValueNotifier<AppLanguage> languageNotifier;

  /// Owned by [MainApp], which listens to it to rebuild the theme mode.
  /// AppSettings never disposes it.
  final ValueNotifier<ThemeMode> themeModeNotifier;

  /// Bumped when the F1–F12 bindings change so the console and the keyboard
  /// reference refresh while they stay open.
  final ValueNotifier<int> functionKeysRevision = ValueNotifier(0);

  AppSettings({
    required SharedPreferencesWithCache prefs,
    ValueNotifier<AppLanguage>? languageNotifier,
    ValueNotifier<ThemeMode>? themeModeNotifier,
  }) : _prefs = prefs,
       languageNotifier =
           languageNotifier ??
           ValueNotifier(AppLanguage.fromId(prefs.getString(_settingLanguage))),
       themeModeNotifier =
           themeModeNotifier ??
           ValueNotifier(_themeModeFromId(prefs.getString(_settingThemeMode))) {
    this.languageNotifier.value = AppLanguage.fromId(
      prefs.getString(_settingLanguage),
    );
    this.themeModeNotifier.value = _themeModeFromId(
      prefs.getString(_settingThemeMode),
    );
  }

  AppLanguage get language => languageNotifier.value;

  set language(AppLanguage value) {
    _prefs.setString(_settingLanguage, value.id);
    languageNotifier.value = value;
  }

  ThemeMode get themeMode => themeModeNotifier.value;

  set themeMode(ThemeMode value) {
    _prefs.setString(_settingThemeMode, value.name);
    themeModeNotifier.value = value;
  }

  String get contestId =>
      _prefs.getString(_settingContestId) ?? ContestRegistry.all.first.id;

  set contestId(String value) => _prefs.setString(_settingContestId, value);

  String get contestModeId =>
      _prefs.getString(_settingContestMode) ?? TrainingMode.run.id;

  set contestModeId(String value) =>
      _prefs.setString(_settingContestMode, value);

  String get stationCallsign => _prefs.getString(_settingStationCallsign) ?? '';

  set stationCallsign(String value) =>
      _prefs.setString(_settingStationCallsign, value);

  /// Per-contest station exchange values. Only values the operator entered are
  /// stored; derived defaults are resolved at use time (design 3.3).
  StationExchangeConfig stationExchangeConfig(String contestId) {
    final raw = _prefs.getString('$_settingStationExchangePrefix$contestId');
    if (raw == null || raw.isEmpty) return StationExchangeConfig.empty;
    try {
      return StationExchangeConfig.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return StationExchangeConfig.empty;
    }
  }

  void setStationExchangeValue(
    String contestId,
    String fieldId,
    String? value,
  ) {
    final updated = stationExchangeConfig(contestId).withValue(fieldId, value);
    _prefs.setString(
      '$_settingStationExchangePrefix$contestId',
      jsonEncode(updated.toJson()),
    );
  }

  int get contestDuration {
    final durationInMinutes = _prefs.getInt(_settingContestDuration) ?? 0;
    return _limitContestDuration(durationInMinutes);
  }

  set contestDuration(int value) =>
      _prefs.setInt(_settingContestDuration, _limitContestDuration(value));

  PhonicType get phonicType =>
      _parsePhonicType(_prefs.getInt(_settingPhonicType));

  set phonicType(PhonicType value) =>
      _prefs.setInt(_settingPhonicType, value.index);

  IncomingAccent get incomingAccent =>
      IncomingAccent.fromId(_prefs.getString(_settingIncomingAccent));

  set incomingAccent(IncomingAccent value) =>
      _prefs.setString(_settingIncomingAccent, value.id);

  TrainingDifficulty get difficulty =>
      TrainingDifficulty.fromId(_prefs.getString(_settingDifficulty));

  set difficulty(TrainingDifficulty value) =>
      _prefs.setString(_settingDifficulty, value.id);

  /// Effects only affect incoming stations; the operator's own CQ and messages
  /// remain clear.
  double get audioVolume => _prefs.getDouble(_settingAudioVolume) ?? 1.0;

  set audioVolume(double value) =>
      _prefs.setDouble(_settingAudioVolume, value.clamp(0.2, 1.2).toDouble());

  /// Function key bindings are key-centric: every key F1–F12 always exists and
  /// may map to an [OperationAction] or to Spare (`action == null`).
  List<FunctionKeyBinding> get functionKeyBindings {
    final values = <FunctionKey, OperationAction?>{};
    var hasNewSettings = false;
    for (final key in FunctionKey.values) {
      final raw = _prefs.getString('$_settingFunctionKeyPrefix${key.label}');
      if (raw != null) hasNewSettings = true;
      values[key] = _actionForStoredValue(raw, fallback: key.defaultAction);
    }

    if (hasNewSettings) {
      return [
        for (final key in FunctionKey.values)
          FunctionKeyBinding(key, values[key]),
      ];
    }

    final migrated = _migrateLegacyBindings();
    if (migrated.isNotEmpty) _persistFunctionKeyBindings(migrated);
    return migrated;
  }

  Future<void> setFunctionKeyBindings(List<FunctionKeyBinding> bindings) async {
    await Future.wait([
      for (final binding in bindings)
        _prefs.setString(
          '$_settingFunctionKeyPrefix${binding.key.label}',
          binding.action?.id ?? _spareValue,
        ),
    ]);
    functionKeysRevision.value++;
  }

  void _persistFunctionKeyBindings(List<FunctionKeyBinding> bindings) {
    for (final binding in bindings) {
      _prefs.setString(
        '$_settingFunctionKeyPrefix${binding.key.label}',
        binding.action?.id ?? _spareValue,
      );
    }
  }

  OperationAction? _actionForStoredValue(
    String? raw, {
    required OperationAction? fallback,
  }) {
    if (raw == null) return fallback;
    if (raw == _spareValue) return null;
    return OperationAction.fromId(raw) ?? fallback;
  }

  /// One-time migration from the old action-centric settings. The new default
  /// table is the base; each action the operator had customised moves to its
  /// stored key. A displaced action becomes Spare (user customisation wins).
  List<FunctionKeyBinding> _migrateLegacyBindings() {
    final defaults = [
      for (final key in FunctionKey.values)
        FunctionKeyBinding(key, key.defaultAction),
    ];

    final legacy = <OperationAction, FunctionKey>{};
    for (final action in OperationAction.values) {
      final label = _prefs.getString('$_settingKeyBindingPrefix${action.id}');
      if (label == null) continue;
      final key = FunctionKey.fromLabel(label);
      if (key != null) legacy[action] = key;
    }

    if (legacy.isEmpty) return defaults;

    for (final entry in legacy.entries) {
      for (var index = 0; index < defaults.length; index++) {
        if (defaults[index].action == entry.key) {
          defaults[index] = FunctionKeyBinding(defaults[index].key, null);
        }
      }

      final targetIndex = defaults.indexWhere(
        (binding) => binding.key == entry.value,
      );
      final displaced = defaults[targetIndex].action;
      defaults[targetIndex] = FunctionKeyBinding(entry.value, entry.key);

      if (displaced != null && displaced != entry.key) {
        log.warn(
          'function key binding conflict during migration',
          tag: 'settings',
          fields: {
            'key': entry.value.label,
            'action': entry.key.id,
            'displaced': displaced.id,
          },
        );
      }
    }

    return defaults;
  }

  List<TrainingRunReview> get sessionHistory =>
      (_prefs.getStringList(_settingSessionHistory) ?? const [])
          .map(TrainingRunReview.decode)
          .toList();

  void saveSessionReview(TrainingRunReview review) {
    final history = [
      review,
      ...sessionHistory,
    ].take(30).map((item) => item.encode()).toList();
    _prefs.setStringList(_settingSessionHistory, history);
  }

  /// Pinned seeds. When the matching lock is on, the pinned value is reused
  /// for every session; otherwise a fresh seed is drawn per session.
  int? get questionSeed => _prefs.getInt(_settingQuestionSeed);

  set questionSeed(int? value) => _setOptionalInt(_settingQuestionSeed, value);

  int? get audioSeed => _prefs.getInt(_settingAudioSeed);

  set audioSeed(int? value) => _setOptionalInt(_settingAudioSeed, value);

  /// One-shot seeds consumed by the next [ContestManager.startContest] call
  /// (used by "Replay this session" and the session-history list).
  int? get pendingQuestionSeed => _prefs.getInt(_settingPendingQuestionSeed);

  set pendingQuestionSeed(int? value) =>
      _setOptionalInt(_settingPendingQuestionSeed, value);

  int? get pendingAudioSeed => _prefs.getInt(_settingPendingAudioSeed);

  set pendingAudioSeed(int? value) =>
      _setOptionalInt(_settingPendingAudioSeed, value);

  /// Short label for the settings button: `q12 / a34` when the two seeds differ.
  String get practiceSeedSummary {
    final question = questionSeed;
    final audio = audioSeed;
    if (question == null) return '';
    if (audio == null || audio == question) return '$question';
    return 'q$question / a$audio';
  }

  /// Run id whose recorded event log should be replayed by the next session.
  String? get pendingReplayRunId =>
      _prefs.getString(_settingPendingReplayRunId);

  set pendingReplayRunId(String? value) {
    if (value == null) {
      _prefs.remove(_settingPendingReplayRunId);
    } else {
      _prefs.setString(_settingPendingReplayRunId, value);
    }
  }

  bool get lockQuestionSeed =>
      _prefs.getBool(_settingLockQuestionSeed) ?? false;

  set lockQuestionSeed(bool value) =>
      _prefs.setBool(_settingLockQuestionSeed, value);

  bool get lockAudioSeed => _prefs.getBool(_settingLockAudioSeed) ?? false;

  set lockAudioSeed(bool value) => _prefs.setBool(_settingLockAudioSeed, value);

  void _setOptionalInt(String key, int? value) {
    if (value == null) {
      _prefs.remove(key);
    } else {
      _prefs.setInt(key, value);
    }
  }

  bool get verboseLogging => _prefs.getBool(_settingVerboseLogging) ?? false;

  set verboseLogging(bool value) {
    _prefs.setBool(_settingVerboseLogging, value);
    log.setVerbose(value);
  }

  int _limitContestDuration(int durationInMinutes) {
    return min(durationInMinutes, maxDurationInMinutesPerRun);
  }

  PhonicType _parsePhonicType(int? value) {
    switch (value) {
      case 0:
        return PhonicType.standard;
      case 1:
        return PhonicType.location;
      case 2:
        return PhonicType.mixed;
      default:
        return PhonicType.standard;
    }
  }
}

const _settingLanguage = 'setting_language';
const _settingThemeMode = 'setting_theme_mode';
const _settingContestId = 'setting_contest_id';
const _settingContestMode = 'setting_contest_mode';
const _settingStationCallsign = 'setting_station_callsign';
const _settingStationExchangePrefix = 'setting_station_exchange_';
const _settingContestDuration = 'setting_contest_duration';
const _settingPhonicType = 'setting_phonic_type';
const _settingIncomingAccent = 'setting_incoming_accent';
const _settingVerboseLogging = 'setting_verbose_logging';
const _settingDifficulty = 'setting_difficulty';
const _settingAudioVolume = 'setting_audio_volume';

/// Legacy, action-centric key bindings. Kept only for migration; never written.
const _settingKeyBindingPrefix = 'setting_key_binding_';
const _settingFunctionKeyPrefix = 'setting_function_key_';
const _spareValue = 'spare';
const _settingSessionHistory = 'setting_session_history';
const _settingQuestionSeed = 'setting_question_seed';
const _settingAudioSeed = 'setting_audio_seed';
const _settingPendingQuestionSeed = 'setting_pending_question_seed';
const _settingPendingAudioSeed = 'setting_pending_audio_seed';
const _settingPendingReplayRunId = 'setting_pending_replay_run_id';
const _settingLockQuestionSeed = 'setting_lock_question_seed';
const _settingLockAudioSeed = 'setting_lock_audio_seed';

/// Light is the historical look, so an absent value keeps the previous theme.
ThemeMode _themeModeFromId(String? id) {
  for (final mode in ThemeMode.values) {
    if (mode.name == id) {
      return mode;
    }
  }
  return ThemeMode.light;
}

enum AppLanguage {
  auto('auto'),
  english('en'),
  simplifiedChinese('zh_Hans'),
  traditionalChinese('zh_Hant'),
  japanese('ja');

  const AppLanguage(this.id);

  final String id;

  static AppLanguage fromId(String? id) =>
      values.firstWhere((it) => it.id == id, orElse: () => auto);
}

enum OperationAction {
  cq('cq', 'CQ'),
  exchange('exchange', 'EXCH'),
  tu('tu', 'TU'),
  myCall('my-call', '<my>'),
  hisCall('his-call', '<his>'),
  before('before', 'B4'),
  again('again', 'AGN'),
  noCopy('no-copy', 'NIL'),
  wipe('wipe', 'Wipe');

  const OperationAction(this.id, this.label);
  final String id;
  final String label;

  static OperationAction? fromId(String? id) {
    for (final action in values) {
      if (action.id == id) return action;
    }
    return null;
  }
}

/// The single source of the F1–F12 function keys. [defaultAction] is `null`
/// for Spare keys.
enum FunctionKey {
  f1('F1', LogicalKeyboardKey.f1, OperationAction.cq),
  f2('F2', LogicalKeyboardKey.f2, OperationAction.exchange),
  f3('F3', LogicalKeyboardKey.f3, OperationAction.tu),
  f4('F4', LogicalKeyboardKey.f4, OperationAction.myCall),
  f5('F5', LogicalKeyboardKey.f5, OperationAction.hisCall),
  f6('F6', LogicalKeyboardKey.f6, OperationAction.before),
  f7('F7', LogicalKeyboardKey.f7, OperationAction.again),
  f8('F8', LogicalKeyboardKey.f8, OperationAction.noCopy),
  f9('F9', LogicalKeyboardKey.f9, null),
  f10('F10', LogicalKeyboardKey.f10, null),
  f11('F11', LogicalKeyboardKey.f11, null),
  f12('F12', LogicalKeyboardKey.f12, OperationAction.wipe);

  const FunctionKey(this.label, this.logicalKey, this.defaultAction);

  final String label;
  final LogicalKeyboardKey logicalKey;
  final OperationAction? defaultAction;

  static FunctionKey? fromLabel(String label) {
    for (final key in values) {
      if (key.label == label) return key;
    }
    return null;
  }
}

class FunctionKeyBinding {
  const FunctionKeyBinding(this.key, this.action);

  final FunctionKey key;
  final OperationAction? action;

  bool get isSpare => action == null;
}
