import 'package:drift/drift.dart' show LazyDatabase;
import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/db/app_database.dart';
import 'package:ssb_runner/dxcc/dxcc_manager.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/settings/settings_issue.dart';
import 'package:ssb_runner/settings/settings_readiness.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// Shared by every fake so the process only ever holds one database instance.
final AppDatabase _unusedDatabase = AppDatabase(
  LazyDatabase(
    () async => throw StateError('The DXCC table must not be touched here.'),
  ),
);

class _FakeDxccManager extends DxccManager {
  _FakeDxccManager({this.cqZone = 24}) : super(database: _unusedDatabase);

  final int? cqZone;

  @override
  int? findCallsignCqZone(String callsign) => cqZone;

  @override
  int? findCallsignItuZone(String callsign) => null;

  // Not Japan and not W/VE, so contest definitions pick the DX-side field.
  @override
  int findCallsignDxccId(String callsign) => 318;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test(
    'empty callsign and zero duration block the run without noise',
    () async {
      final settings = await _settings();
      final issues = checkSettingsReadiness(
        settings: settings,
        dxccManager: _FakeDxccManager(),
      );

      expect(issues, hasLength(2));
      expect(issues.first.kind, SettingsIssueKind.callsignMissing);
      expect(issues.first.tab, SettingsTab.contestStation);
      expect(issues.first.focusKey, SettingsFocusKeys.stationCallsign);
      expect(issues.last.kind, SettingsIssueKind.durationMissing);
      expect(issues.last.tab, SettingsTab.training);
    },
  );

  test('a complete CQ WW station is ready', () async {
    final settings = await _settings();
    settings
      ..contestId = 'CQ-WW-SSB'
      ..stationCallsign = 'BI1QJQ'
      ..contestDuration = 30;

    expect(
      checkSettingsReadiness(
        settings: settings,
        dxccManager: _FakeDxccManager(),
      ),
      isEmpty,
    );
  });

  test('a missing CQ zone is reported as an exchange issue', () async {
    final settings = await _settings();
    settings
      ..contestId = 'CQ-WW-SSB'
      ..stationCallsign = 'BI1QJQ'
      ..contestDuration = 30;

    final issues = checkSettingsReadiness(
      settings: settings,
      dxccManager: _FakeDxccManager(cqZone: null),
    );

    expect(issues, hasLength(1));
    expect(issues.single.kind, SettingsIssueKind.exchangeMissing);
    expect(issues.single.fieldId, 'cqZone');
    expect(issues.single.focusKey, 'exchange:cqZone');
    expect(issues.single.sectionId, 'myStation');
  });

  test(
    'an out-of-range zone carries the bounds and the current value',
    () async {
      final settings = await _settings();
      settings
        ..contestId = 'CQ-WW-SSB'
        ..stationCallsign = 'BI1QJQ'
        ..contestDuration = 30
        ..setStationExchangeValue('CQ-WW-SSB', 'cqZone', '99');

      final issues = checkSettingsReadiness(
        settings: settings,
        dxccManager: _FakeDxccManager(cqZone: null),
      );

      final issue = issues.single;
      expect(issue.kind, SettingsIssueKind.exchangeOutOfRange);
      expect(issue.min, 1);
      expect(issue.max, 40);
      expect(issue.currentValue, '99');
    },
  );

  test('CQ WPX needs no exchange field', () async {
    final settings = await _settings();
    settings
      ..contestId = 'CQ-WPX'
      ..stationCallsign = 'BI1QJQ'
      ..contestDuration = 30;

    expect(
      checkSettingsReadiness(
        settings: settings,
        dxccManager: _FakeDxccManager(),
      ),
      isEmpty,
    );
  });

  test('issues are grouped per drawer tab', () async {
    final settings = await _settings();
    settings.contestId = 'CQ-WW-SSB';

    final issues = checkSettingsReadiness(
      settings: settings,
      dxccManager: _FakeDxccManager(),
    );

    expect(settingsIssueCountsByTab(issues), {
      SettingsTab.contestStation: 1,
      SettingsTab.training: 1,
    });
  });
}

Future<AppSettings> _settings() async {
  final prefs = await SharedPreferencesWithCache.create(
    cacheOptions: const SharedPreferencesWithCacheOptions(),
  );
  return AppSettings(prefs: prefs);
}
