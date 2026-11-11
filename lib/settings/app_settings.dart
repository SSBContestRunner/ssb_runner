import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssb_runner/audio/accent_policy.dart';
import 'package:ssb_runner/audio/audio_loader.dart';
import 'package:ssb_runner/common/constants.dart';
import 'package:ssb_runner/contest_run/new/run_plan.dart';
import 'package:ssb_runner/contest_type/contest_definition.dart';
import 'package:ssb_runner/contest_type/station_exchange.dart';
import 'package:ssb_runner/logging/app_logger.dart';
import 'package:ssb_runner/training/pending_replay.dart';
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

  /// Bumped when a persisted setting that affects whether a run can start
  /// changes. Station exchange values are written straight to storage without a
  /// cubit, so the readiness views need their own signal to stay in sync.
  final ValueNotifier<int> settingsRevision = ValueNotifier(0);

  /// Installed by [ContestManager] so arming a replay can be refused while a
  /// session is already running. AppSettings does not own the manager.
  bool Function()? contestRunningCheck;

  /// Set once per instance when a stored F1–F12 table had to be repaired, so
  /// the warning is logged and the notice queued exactly once.
  bool _functionKeyRepairReported = false;

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

  set contestId(String value) {
    if (_hasArmedReplay) {
      _rejectArmedWrite(_settingContestId, value);
      return;
    }
    _prefs.setString(_settingContestId, value);
    _bumpSettingsRevision();
  }

  String get contestModeId =>
      _prefs.getString(_settingContestMode) ?? TrainingMode.run.id;

  set contestModeId(String value) {
    if (_hasArmedReplay) {
      _rejectArmedWrite(_settingContestMode, value);
      return;
    }
    _prefs.setString(_settingContestMode, value);
    _bumpSettingsRevision();
  }

  String get stationCallsign => _prefs.getString(_settingStationCallsign) ?? '';

  set stationCallsign(String value) {
    _prefs.setString(_settingStationCallsign, value);
    _bumpSettingsRevision();
  }

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
    _bumpSettingsRevision();
  }

  int get contestDuration {
    final durationInMinutes = _prefs.getInt(_settingContestDuration) ?? 0;
    return _limitContestDuration(durationInMinutes);
  }

  set contestDuration(int value) {
    _prefs.setInt(_settingContestDuration, _limitContestDuration(value));
    _bumpSettingsRevision();
  }

  PhonicType get phonicType =>
      _parsePhonicType(_prefs.getInt(_settingPhonicType));

  set phonicType(PhonicType value) {
    _prefs.setInt(_settingPhonicType, value.index);
    _bumpSettingsRevision();
  }

  IncomingAccent get incomingAccent =>
      IncomingAccent.fromId(_prefs.getString(_settingIncomingAccent));

  set incomingAccent(IncomingAccent value) {
    _prefs.setString(_settingIncomingAccent, value.id);
    _bumpSettingsRevision();
  }

  TrainingDifficulty get difficulty =>
      TrainingDifficulty.fromId(_prefs.getString(_settingDifficulty));

  set difficulty(TrainingDifficulty value) {
    if (_hasArmedReplay) {
      _rejectArmedWrite(_settingDifficulty, value.id);
      return;
    }
    _prefs.setString(_settingDifficulty, value.id);
    _bumpSettingsRevision();
  }

  /// Effects only affect incoming stations; the operator's own CQ and messages
  /// remain clear.
  double get audioVolume => _prefs.getDouble(_settingAudioVolume) ?? 1.0;

  set audioVolume(double value) =>
      _prefs.setDouble(_settingAudioVolume, value.clamp(0.2, 1.2).toDouble());

  /// Function key bindings are key-centric: every key F1–F12 always exists and
  /// may map to an [OperationAction] or to Spare (`action == null`).
  ///
  /// Stored values are normalized on read. A value that is not a known action
  /// id becomes Spare, and when one action appears on several keys the lowest
  /// F number keeps it while the later keys become Spare. A repair is
  /// persisted once and announced through [takeFunctionKeyRepairNotice].
  List<FunctionKeyBinding> get functionKeyBindings {
    final candidates = <FunctionKeyBinding>[];
    final invalidKeys = <FunctionKey>[];
    var hasNewSettings = false;

    for (final key in FunctionKey.values) {
      final raw = _prefs.getString('$_settingFunctionKeyPrefix${key.label}');
      if (raw != null) hasNewSettings = true;
      if (raw == null) {
        candidates.add(FunctionKeyBinding(key, key.defaultAction));
        continue;
      }
      if (raw == _spareValue) {
        candidates.add(FunctionKeyBinding(key, null));
        continue;
      }
      final action = OperationAction.fromId(raw);
      if (action == null) invalidKeys.add(key);
      candidates.add(FunctionKeyBinding(key, action));
    }

    if (!hasNewSettings) {
      final normalized = normalizeFunctionKeyBindings(_migrateLegacyBindings());
      _persistFunctionKeyBindings(normalized.bindings);
      _reportFunctionKeyRepair(normalized.issues);
      return normalized.bindings;
    }

    final normalized = normalizeFunctionKeyBindings(candidates);
    final issues = [
      for (final key in invalidKeys)
        FunctionKeyIssue(type: FunctionKeyIssueType.invalidActionId, key: key),
      ...normalized.issues,
    ];
    if (issues.isEmpty) return normalized.bindings;

    _persistFunctionKeyBindings(normalized.bindings);
    _reportFunctionKeyRepair(issues);
    return normalized.bindings;
  }

  /// Persists the complete F1–F12 table.
  ///
  /// Returns `false` and writes nothing when the table is incomplete or binds
  /// one action to more than one key, so a caller can never turn a valid
  /// configuration into a conflicting one.
  Future<bool> setFunctionKeyBindings(List<FunctionKeyBinding> bindings) async {
    final normalized = normalizeFunctionKeyBindings(bindings);
    final keys = bindings.map((binding) => binding.key).toSet();
    final complete =
        bindings.length == FunctionKey.values.length &&
        keys.length == FunctionKey.values.length &&
        FunctionKey.values.every(keys.contains);

    if (!normalized.isClean || !complete) {
      log.warn(
        'function key bindings rejected',
        tag: 'settings',
        fields: {
          'issueCount': normalized.issues.length,
          'bindingCount': bindings.length,
          'keyCount': keys.length,
        },
      );
      return false;
    }

    await Future.wait([
      for (final binding in normalized.bindings)
        _prefs.setString(
          '$_settingFunctionKeyPrefix${binding.key.label}',
          binding.action?.id ?? _spareValue,
        ),
    ]);
    functionKeysRevision.value++;
    return true;
  }

  void _persistFunctionKeyBindings(List<FunctionKeyBinding> bindings) {
    for (final binding in bindings) {
      _prefs.setString(
        '$_settingFunctionKeyPrefix${binding.key.label}',
        binding.action?.id ?? _spareValue,
      );
    }
  }

  /// True while an automatically repaired F1–F12 table has not been shown yet.
  bool get functionKeyRepairNoticePending =>
      _prefs.getBool(_settingFunctionKeyRepairNotice) ?? false;

  /// Consumes the one-shot repair notice so it is shown at most once, even
  /// across restarts.
  bool takeFunctionKeyRepairNotice() {
    if (!functionKeyRepairNoticePending) return false;
    _prefs.remove(_settingFunctionKeyRepairNotice);
    return true;
  }

  /// Logs a one-off repair and leaves a persisted flag so the UI can tell the
  /// operator once. Repeated reads in one session must not re-report.
  void _reportFunctionKeyRepair(List<FunctionKeyIssue> issues) {
    if (issues.isEmpty || _functionKeyRepairReported) return;
    _functionKeyRepairReported = true;
    log.warn(
      'function key bindings repaired',
      tag: 'settings',
      fields: {
        'duplicateActions': [
          for (final issue in issues)
            if (issue.type == FunctionKeyIssueType.duplicateAction)
              '${issue.action!.label}:${issue.winner!.label}->${issue.key.label}',
        ],
        'invalidActionKeys': [
          for (final issue in issues)
            if (issue.type == FunctionKeyIssueType.invalidActionId)
              issue.key.label,
        ],
      },
    );
    _prefs.setBool(_settingFunctionKeyRepairNotice, true);
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

  /// The next session's replay snapshot (design §7.1/§7.2).
  ///
  /// If the v2 key is absent, the legacy `pendingReplayRunId` is assembled
  /// from the matching session-history entry. A run id without history stays
  /// explicitly unknown; the resolver aborts instead of guessing.
  PendingReplay? get pendingReplay {
    final raw = _prefs.getString(_settingPendingReplayV2);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          return PendingReplay.fromJson(decoded);
        }
      } catch (error) {
        log.warn(
          'unreadable pending replay snapshot',
          tag: 'settings',
          fields: {'error': '$error'},
        );
      }
    }
    return _pendingReplayFromLegacy();
  }

  PendingReplay? _pendingReplayFromLegacy() {
    final runId = _prefs.getString(_settingPendingReplayRunId);
    if (runId == null || runId.isEmpty) return null;
    for (final review in sessionHistory) {
      if (review.metadata.runId == runId) {
        return PendingReplay.fromReview(review, armedAtUtc: review.endedAt);
      }
    }
    // The resolver reports this once at run start; logging here would fire on
    // every UI rebuild because the snapshot is read during layout.
    return PendingReplay(
      runId: runId,
      contestId: unknownReplayField,
      contestName: unknownReplayField,
      modeId: unknownReplayField,
      difficultyId: unknownReplayField,
      questionSeed: 0,
      audioSeed: 0,
      armedAtUtc: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  /// Arms the next-session replay without touching the ordinary settings.
  /// Cancelling or a failed start therefore leaves the operator exactly where
  /// they were before arming.
  void armReplay(PendingReplay replay) {
    if (contestRunningCheck?.call() ?? false) {
      log.warn(
        'settings.replay',
        tag: 'settings',
        fields: {'action': 'rejected-running', 'runId': replay.runId},
      );
      return;
    }
    final replacing = pendingReplay != null;
    _prefs.setString(_settingPendingReplayV2, replay.encode());
    _prefs.remove(_settingPendingReplayRunId);
    _bumpSettingsRevision();
    log.info(
      'settings.replay',
      tag: 'settings',
      fields: {
        'action': replacing ? 'replace' : 'arm',
        'runId': replay.runId,
        'contestId': replay.contestId,
        'modeId': replay.modeId,
        'difficultyId': replay.difficultyId,
      },
    );
  }

  void clearPendingReplay() {
    final armed = pendingReplay != null;
    _prefs.remove(_settingPendingReplayV2);
    _prefs.remove(_settingPendingReplayRunId);
    _bumpSettingsRevision();
    if (armed) {
      log.info(
        'settings.replay',
        tag: 'settings',
        fields: {'action': 'cancel'},
      );
    }
  }

  /// Commits a verified run plan immediately before the session starts. This
  /// is the only place arming turns into ordinary settings; one revision bump
  /// covers the three values and the cleared snapshot.
  void commitRunSpec(RunPlan plan) {
    _prefs
      ..setString(_settingContestId, plan.contestId)
      ..setString(_settingContestMode, plan.modeId)
      ..setString(_settingDifficulty, plan.difficultyId)
      ..remove(_settingPendingReplayV2)
      ..remove(_settingPendingReplayRunId);
    _bumpSettingsRevision();
  }

  /// Values displayed on standby. An armed replay wins so the whole UI shows
  /// the session that is about to run; they are not used while a run is live.
  String get effectiveContestId {
    final replay = pendingReplay;
    if (replay != null && replay.hasKnownContest) {
      return ContestRegistry.canonicalId(replay.contestId) ?? replay.contestId;
    }
    return contestId;
  }

  String get effectiveModeId {
    final replay = pendingReplay;
    if (replay != null && replay.hasKnownMode) return replay.modeId;
    return contestModeId;
  }

  String get effectiveDifficultyId {
    final replay = pendingReplay;
    if (replay != null && replay.hasKnownDifficulty) {
      return replay.difficultyId;
    }
    return difficulty.id;
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

  /// The last normal-state *content* size, or null when it was never saved.
  ///
  /// One `"WxH"` string means a single write cannot leave a half-updated
  /// width/height pair behind.
  Size? get windowContentSize {
    final raw = _prefs.getString(_settingWindowContentSize);
    if (raw == null) return null;
    final parts = raw.split('x');
    if (parts.length != 2) return null;
    final width = double.tryParse(parts[0]);
    final height = double.tryParse(parts[1]);
    if (width == null || height == null) return null;
    if (!width.isFinite || !height.isFinite) return null;
    if (width <= 0 || height <= 0) return null;
    return Size(width, height);
  }

  void saveWindowContentSize(Size size) {
    _prefs.setString(
      _settingWindowContentSize,
      '${size.width.toStringAsFixed(1)}x${size.height.toStringAsFixed(1)}',
    );
  }

  void _bumpSettingsRevision() => settingsRevision.value++;

  /// Cheap lock check used by the setters: the snapshot is read on every
  /// layout pass, so avoiding the full parse here keeps rebuilds cheap.
  bool get _hasArmedReplay =>
      (_prefs.getString(_settingPendingReplayV2)?.isNotEmpty ?? false) ||
      (_prefs.getString(_settingPendingReplayRunId)?.isNotEmpty ?? false);

  void _rejectArmedWrite(String key, String value) {
    log.warn(
      'setting write rejected while a replay is armed',
      tag: 'settings',
      fields: {'key': key, 'value': value},
    );
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
const _settingWindowContentSize = 'setting_window_content_size';

/// Legacy, action-centric key bindings. Kept only for migration; never written.
const _settingKeyBindingPrefix = 'setting_key_binding_';
const _settingFunctionKeyPrefix = 'setting_function_key_';
const _settingFunctionKeyRepairNotice = 'setting_function_key_repair_notice';
const _spareValue = 'spare';
const _settingSessionHistory = 'setting_session_history';
const _settingQuestionSeed = 'setting_question_seed';
const _settingAudioSeed = 'setting_audio_seed';
const _settingPendingQuestionSeed = 'setting_pending_question_seed';
const _settingPendingAudioSeed = 'setting_pending_audio_seed';
const _settingPendingReplayRunId = 'setting_pending_replay_run_id';
const _settingPendingReplayV2 = 'setting_pending_replay_v2';
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

/// Why one F-key could not keep its stored action.
enum FunctionKeyIssueType {
  /// The stored value is not a known [OperationAction] id.
  invalidActionId,

  /// The same action was claimed by an earlier key in the table.
  duplicateAction,
}

/// One normalization problem.
///
/// [key] is the key that loses its action and becomes Spare. For
/// [FunctionKeyIssueType.duplicateAction], [winner] is the lowest-numbered key
/// that keeps [action]. [action] is null for
/// [FunctionKeyIssueType.invalidActionId] because the id could not be resolved.
class FunctionKeyIssue {
  const FunctionKeyIssue({
    required this.type,
    required this.key,
    this.action,
    this.winner,
  });

  final FunctionKeyIssueType type;
  final FunctionKey key;
  final OperationAction? action;
  final FunctionKey? winner;
}

/// A complete, conflict-free table plus the problems that had to be repaired
/// to reach it.
class FunctionKeyNormalization {
  const FunctionKeyNormalization({
    required this.bindings,
    required this.issues,
  });

  final List<FunctionKeyBinding> bindings;
  final List<FunctionKeyIssue> issues;

  bool get isClean => issues.isEmpty;
}

/// Enforces one action per table and one binding per key.
///
/// The result always follows [FunctionKey.values] order. When an action
/// appears on several keys the lowest F number keeps it and every later key
/// becomes Spare, which is the single rule shared by the loader and the
/// settings dialog.
FunctionKeyNormalization normalizeFunctionKeyBindings(
  List<FunctionKeyBinding> bindings,
) {
  final actionByKey = {
    for (final binding in bindings) binding.key: binding.action,
  };
  final normalized = <FunctionKeyBinding>[];
  final issues = <FunctionKeyIssue>[];
  final owner = <OperationAction, FunctionKey>{};

  for (final key in FunctionKey.values) {
    final action = actionByKey[key];
    if (action == null) {
      normalized.add(FunctionKeyBinding(key, null));
      continue;
    }

    final winner = owner[action];
    if (winner != null) {
      issues.add(
        FunctionKeyIssue(
          type: FunctionKeyIssueType.duplicateAction,
          key: key,
          action: action,
          winner: winner,
        ),
      );
      normalized.add(FunctionKeyBinding(key, null));
      continue;
    }

    owner[action] = key;
    normalized.add(FunctionKeyBinding(key, action));
  }

  return FunctionKeyNormalization(bindings: normalized, issues: issues);
}
