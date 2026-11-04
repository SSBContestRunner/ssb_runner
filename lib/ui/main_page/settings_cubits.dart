import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ssb_runner/audio/accent_policy.dart';
import 'package:ssb_runner/audio/audio_loader.dart';
import 'package:ssb_runner/common/constants.dart';
import 'package:ssb_runner/contest_run/new/contest_manager.dart';
import 'package:ssb_runner/contest_type/contest_definition.dart';
import 'package:ssb_runner/l10n/generated/app_localizations.dart';
import 'package:ssb_runner/logging/app_logger.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/training/training_profile.dart';
import 'package:toastification/toastification.dart';

/// Whether a session is running. Every settings section uses this single
/// switch so the read-only state cannot drift between panels.
class MainSettingsCubit extends Cubit<bool> {
  MainSettingsCubit({required ContestManager contestManager})
    : super(contestManager.isContestRunning) {
    _subscription = contestManager.isContestRunningStream.listen(emit);
  }

  late final StreamSubscription<bool> _subscription;

  @override
  Future<void> close() {
    _subscription.cancel();
    return super.close();
  }
}

/// Projects the effective contest (armed replay wins on standby). Any write
/// that bypasses the cubits bumps [AppSettings.settingsRevision], so the
/// projection can never lag behind the value the next run will use.
class ContestSettingCubit extends Cubit<ContestDefinition> {
  final AppSettings _appSettings;

  ContestSettingCubit({required AppSettings appSettings})
    : _appSettings = appSettings,
      super(ContestRegistry.byId(appSettings.effectiveContestId)) {
    _appSettings.settingsRevision.addListener(_syncFromSettings);
  }

  void _syncFromSettings() {
    final contest = ContestRegistry.byId(_appSettings.effectiveContestId);
    if (!identical(contest, state)) emit(contest);
  }

  void changeContest(String contestId) {
    // Locked while a replay is armed: the only exit is cancelling it, never
    // changing the contest underneath the recording.
    if (_appSettings.pendingReplay != null) {
      log.warn(
        'contest change rejected while a replay is armed',
        tag: 'settings',
        fields: {'requestedContestId': contestId},
      );
      return;
    }
    _appSettings.contestId = contestId;
    _syncFromSettings();
  }

  @override
  Future<void> close() {
    _appSettings.settingsRevision.removeListener(_syncFromSettings);
    return super.close();
  }
}

class StationCallsignCubit extends Cubit<String> {
  final AppSettings _appSettings;

  StationCallsignCubit({required AppSettings appSettings})
    : _appSettings = appSettings,
      super(appSettings.stationCallsign) {
    _appSettings.settingsRevision.addListener(_syncFromSettings);
  }

  void _syncFromSettings() {
    final callSign = _appSettings.stationCallsign;
    if (callSign != state) emit(callSign);
  }

  void onCallSignChange(String callSign) {
    _appSettings.stationCallsign = callSign;
    _syncFromSettings();
  }

  @override
  Future<void> close() {
    _appSettings.settingsRevision.removeListener(_syncFromSettings);
    return super.close();
  }
}

class TrainingOptions {
  const TrainingOptions({
    required this.mode,
    required this.duration,
    required this.phonicType,
    required this.incomingAccent,
    required this.difficulty,
    required this.volume,
  });

  final TrainingMode mode;
  final int duration;
  final PhonicType phonicType;
  final IncomingAccent incomingAccent;
  final TrainingDifficulty difficulty;
  final double volume;

  bool sameAs(TrainingOptions other) =>
      mode == other.mode &&
      duration == other.duration &&
      phonicType == other.phonicType &&
      incomingAccent == other.incomingAccent &&
      difficulty == other.difficulty &&
      volume == other.volume;
}

/// UI state for the Training/Audio tabs and the topbar metadata.
class TrainingOptionsCubit extends Cubit<TrainingOptions> {
  TrainingOptionsCubit(this._settings) : super(_readOptions(_settings)) {
    durationController = TextEditingController(text: state.duration.toString());
    durationFocusNode = FocusNode()..addListener(_handleDurationFocusChange);
    _settings.settingsRevision.addListener(_syncFromSettings);
  }

  final AppSettings _settings;

  // Owned by the cubit so the field widget stays stateless while keeping its
  // editing state and focus stable across rebuilds.
  late final TextEditingController durationController;
  late final FocusNode durationFocusNode;

  static TrainingOptions _readOptions(AppSettings settings) => TrainingOptions(
    mode: TrainingMode.fromId(settings.effectiveModeId),
    duration: settings.contestDuration,
    phonicType: settings.phonicType,
    incomingAccent: settings.incomingAccent,
    difficulty: TrainingDifficulty.fromId(settings.effectiveDifficultyId),
    volume: settings.audioVolume,
  );

  void _syncFromSettings() {
    final next = _readOptions(_settings);
    if (next.duration != state.duration && !durationFocusNode.hasFocus) {
      final text = next.duration.toString();
      if (durationController.text != text) {
        durationController.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      }
    }
    _emitIfChanged(next);
  }

  void _emitIfChanged(TrainingOptions next) {
    if (state.sameAs(next)) return;
    emit(next);
  }

  bool get _isReplayArmed => _settings.pendingReplay != null;

  void _handleDurationFocusChange() {
    if (durationFocusNode.hasFocus) return;
    // An empty box stays empty while it has focus; only fall back to the stored
    // value once focus leaves, so the field never displays a blank duration.
    if (durationController.text.isEmpty) {
      durationController.text = state.duration.toString();
    }
  }

  void setMode(TrainingMode? value) {
    if (value == null) return;
    if (_isReplayArmed) {
      log.warn(
        'mode change rejected while a replay is armed',
        tag: 'settings',
        fields: {'requestedModeId': value.id},
      );
      return;
    }
    _settings.contestModeId = value.id;
    _syncFromSettings();
  }

  void setDifficulty(TrainingDifficulty? value) {
    if (value == null) return;
    if (_isReplayArmed) {
      log.warn(
        'difficulty change rejected while a replay is armed',
        tag: 'settings',
        fields: {'requestedDifficultyId': value.id},
      );
      return;
    }
    _settings.difficulty = value;
    _syncFromSettings();
  }

  void setDuration(String input, AppLocalizations l10n) {
    final parsed = int.tryParse(input);
    if (parsed != null && parsed > maxDurationInMinutesPerRun) {
      toastification.show(
        title: Text(l10n.maxDurationWarning(maxDurationInMinutesPerRun)),
        autoCloseDuration: const Duration(seconds: 2),
        type: ToastificationType.warning,
        style: ToastificationStyle.fillColored,
      );
    }
    final value = (parsed ?? 0).clamp(0, maxDurationInMinutesPerRun).toInt();
    _settings.contestDuration = value;
    _syncFromSettings();

    // Show the clamped value immediately, e.g. typing 999 becomes 120.
    if (parsed != null && parsed > maxDurationInMinutesPerRun) {
      final text = value.toString();
      durationController.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
  }

  void setPhonic(PhonicType? value) {
    if (value == null) return;
    _settings.phonicType = value;
    _syncFromSettings();
  }

  void setIncomingAccent(IncomingAccent? value) {
    if (value == null) return;
    _settings.incomingAccent = value;
    _syncFromSettings();
  }

  void setVolume(double value) {
    _settings.audioVolume = value;
    _syncFromSettings();
  }

  @override
  Future<void> close() {
    _settings.settingsRevision.removeListener(_syncFromSettings);
    durationFocusNode
      ..removeListener(_handleDurationFocusChange)
      ..dispose();
    durationController.dispose();
    return super.close();
  }
}
