import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssb_runner/audio/audio_loader.dart';
import 'package:ssb_runner/common/constants.dart';
import 'package:ssb_runner/contest_type/contest_definition.dart';
import 'package:ssb_runner/contest_type/station_exchange.dart';
import 'package:ssb_runner/logging/app_logger.dart';
import 'package:ssb_runner/training/session_review.dart';
import 'package:ssb_runner/training/training_profile.dart';

class AppSettings {
  final SharedPreferencesWithCache _prefs;

  AppSettings({required SharedPreferencesWithCache prefs}) : _prefs = prefs;

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

  TrainingDifficulty get difficulty =>
      TrainingDifficulty.fromId(_prefs.getString(_settingDifficulty));

  set difficulty(TrainingDifficulty value) =>
      _prefs.setString(_settingDifficulty, value.id);

  /// Effects only affect incoming stations; the operator's own CQ and messages
  /// remain clear.
  double get audioVolume => _prefs.getDouble(_settingAudioVolume) ?? 1.0;

  set audioVolume(double value) =>
      _prefs.setDouble(_settingAudioVolume, value.clamp(0.2, 1.2).toDouble());

  String binding(OperationAction action) =>
      _prefs.getString('$_settingKeyBindingPrefix${action.id}') ??
      action.defaultKey;

  Future<void> setBinding(OperationAction action, String key) =>
      _prefs.setString('$_settingKeyBindingPrefix${action.id}', key);

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

const _settingContestId = 'setting_contest_id';
const _settingContestMode = 'setting_contest_mode';
const _settingStationCallsign = 'setting_station_callsign';
const _settingStationExchangePrefix = 'setting_station_exchange_';
const _settingContestDuration = 'setting_contest_duration';
const _settingPhonicType = 'setting_phonic_type';
const _settingVerboseLogging = 'setting_verbose_logging';
const _settingDifficulty = 'setting_difficulty';
const _settingAudioVolume = 'setting_audio_volume';
const _settingKeyBindingPrefix = 'setting_key_binding_';
const _settingSessionHistory = 'setting_session_history';
const _settingQuestionSeed = 'setting_question_seed';
const _settingAudioSeed = 'setting_audio_seed';
const _settingPendingQuestionSeed = 'setting_pending_question_seed';
const _settingPendingAudioSeed = 'setting_pending_audio_seed';
const _settingPendingReplayRunId = 'setting_pending_replay_run_id';
const _settingLockQuestionSeed = 'setting_lock_question_seed';
const _settingLockAudioSeed = 'setting_lock_audio_seed';

enum OperationAction {
  cq('cq', 'CQ', 'F1'),
  exchange('exchange', 'EXCH', 'F2'),
  tu('tu', 'TU', 'F3'),
  myCall('my-call', '<my>', 'F4'),
  hisCall('his-call', '<his>', 'F5'),
  before('before', 'B4', 'F6'),
  again('again', 'AGN', 'F7'),
  noCopy('no-copy', 'NIL', 'F8');

  const OperationAction(this.id, this.label, this.defaultKey);
  final String id;
  final String label;
  final String defaultKey;
}
