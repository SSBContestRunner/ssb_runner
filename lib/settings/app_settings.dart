import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssb_runner/common/constants.dart';
import 'package:ssb_runner/contest_run/contests.dart';

class AppSettings {
  final SharedPreferencesWithCache _prefs;

  AppSettings({required SharedPreferencesWithCache prefs}) : _prefs = prefs;

  String get contestId =>
      _prefs.getString(_settingContestId) ?? supportedContests.first.id;
  set contestId(String value) => _prefs.setString(_settingContestId, value);

  String get contestModeId =>
      _prefs.getString(_settingContestMode) ?? supportedContestModes.first.id;
  set contestModeId(String value) =>
      _prefs.setString(_settingContestMode, value);

  String get stationCallsign => _prefs.getString(_settingStationCallsign) ?? '';
  set stationCallsign(String value) =>
      _prefs.setString(_settingStationCallsign, value);

  int get contestDuration {
    final durationInMinutes = _prefs.getInt(_settingContestDuration) ?? 0;
    return _limitContestDuration(durationInMinutes);
  }

  set contestDuration(int value) =>
      _prefs.setInt(_settingContestDuration, _limitContestDuration(value));

  int _limitContestDuration(int durationInMinutes) {
    return min(durationInMinutes, maxDurationInMinutesPerRun);
  }
}

const _settingContestId = 'setting_contest_id';
const _settingContestMode = 'setting_contest_mode';
const _settingStationCallsign = 'setting_station_callsign';
const _settingContestDuration = 'setting_contest_duration';
