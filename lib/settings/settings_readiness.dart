import 'package:ssb_runner/contest_type/contest_definition.dart';
import 'package:ssb_runner/contest_type/station_exchange.dart';
import 'package:ssb_runner/dxcc/dxcc_manager.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/settings/settings_issue.dart';

/// Single source of truth for "can this run start?".
///
/// Both the start button and the settings drawer look it up, so the gate can
/// never drift between the two surfaces. The result is ordered: callsign,
/// duration, then station exchange fields.
List<SettingsIssue> checkSettingsReadiness({
  required AppSettings settings,
  required DxccManager dxccManager,
}) {
  final issues = <SettingsIssue>[];
  final callsign = settings.stationCallsign;

  if (callsign.isEmpty) {
    issues.add(
      SettingsIssue(
        kind: SettingsIssueKind.callsignMissing,
        tab: SettingsTab.contestStation,
        sectionId: 'myStation',
        fieldId: 'stationCallsign',
        fieldLabel: 'Callsign',
        focusKey: SettingsFocusKeys.stationCallsign,
      ),
    );
  }

  if (settings.contestDuration <= 0) {
    issues.add(
      const SettingsIssue(
        kind: SettingsIssueKind.durationMissing,
        tab: SettingsTab.training,
        fieldId: 'duration',
        fieldLabel: 'Duration',
        focusKey: SettingsFocusKeys.trainingDuration,
      ),
    );
  }

  // Without a callsign the exchange values cannot be derived, so reporting
  // them would only add noise on top of the callsign issue.
  if (callsign.isEmpty) return issues;

  final definition = ContestRegistry.byId(settings.contestId);
  final config = settings.stationExchangeConfig(definition.id);
  final plan = definition.myExchangePlan(
    stationCallsign: callsign,
    dxccManager: dxccManager,
  );

  for (final error in validateStationExchangeAll(
    plan: plan,
    config: config,
    stationCallsign: callsign,
    dxccManager: dxccManager,
  )) {
    final field = error.field;
    issues.add(
      SettingsIssue(
        kind: switch (error) {
          StationExchangeMissing() => SettingsIssueKind.exchangeMissing,
          StationExchangeInvalid() => SettingsIssueKind.exchangeInvalid,
          StationExchangeOutOfRange() => SettingsIssueKind.exchangeOutOfRange,
        },
        tab: SettingsTab.contestStation,
        sectionId: 'myStation',
        fieldId: field.id,
        fieldLabel: field.label,
        focusKey: SettingsFocusKeys.exchangeField(field.id),
        min: error is StationExchangeOutOfRange ? error.min : null,
        max: error is StationExchangeOutOfRange ? error.max : null,
        currentValue: resolveExchangeValue(
          field,
          config,
          callsign,
          dxccManager,
        ),
      ),
    );
  }

  return issues;
}

/// Groups issues by drawer tab so the tab bar can badge the pages that still
/// need work.
Map<SettingsTab, int> settingsIssueCountsByTab(List<SettingsIssue> issues) {
  final counts = <SettingsTab, int>{};
  for (final issue in issues) {
    counts[issue.tab] = (counts[issue.tab] ?? 0) + 1;
  }
  return counts;
}
