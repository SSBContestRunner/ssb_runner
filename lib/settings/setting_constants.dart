import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssb_contest_runner/contest_run/contests.dart';

class AppSettings {
  final SharedPreferencesWithCache _prefs;

  AppSettings({required SharedPreferencesWithCache prefs}) : _prefs = prefs;

  String get contestId =>
      _prefs.getString(_settingContestId) ?? supportedContest.first.id;
  set contestId(String value) => _prefs.setString(_settingContestId, value);

  String get contestModeId =>
      _prefs.getString(_settingContestMode) ?? supportedContestModes.first.id;
  set contestModeId(String value) =>
      _prefs.setString(_settingContestMode, value);

  String get stationCallsign => _prefs.getString(_settingStationCallsign) ?? '';
  set stationCallsign(String value) =>
      _prefs.setString(_settingStationCallsign, value);

  int get contestDuration => _prefs.getInt(_settingContestDuration) ?? 0;
}

const _settingContestId = 'setting_contest_id';
const _settingContestMode = 'setting_contest_mode';
const _settingStationCallsign = 'setting_station_callsign';
const _settingContestDuration = 'setting_contest_duration';
