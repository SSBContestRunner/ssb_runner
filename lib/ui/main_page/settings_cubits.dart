import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ssb_runner/audio/accent_policy.dart';
import 'package:ssb_runner/audio/audio_loader.dart';
import 'package:ssb_runner/common/constants.dart';
import 'package:ssb_runner/contest_run/new/contest_manager.dart';
import 'package:ssb_runner/contest_type/contest_definition.dart';
import 'package:ssb_runner/l10n/generated/app_localizations.dart';
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

class ContestSettingCubit extends Cubit<ContestDefinition> {
  final AppSettings _appSettings;

  ContestSettingCubit({required AppSettings appSettings})
    : _appSettings = appSettings,
      super(ContestRegistry.byId(appSettings.contestId));

  void changeContest(String contestId) {
    final contest = ContestRegistry.byId(contestId);
    _appSettings.contestId = contestId;

    emit(contest);
  }
}

class StationCallsignCubit extends Cubit<String> {
  final AppSettings _appSettings;

  StationCallsignCubit({required AppSettings appSettings})
    : _appSettings = appSettings,
      super(appSettings.stationCallsign);

  void onCallSignChange(String callSign) {
    _appSettings.stationCallsign = callSign;
    emit(callSign);
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
}

/// UI state for the Training/Audio tabs and the topbar metadata.
class TrainingOptionsCubit extends Cubit<TrainingOptions> {
  TrainingOptionsCubit(this._settings)
    : super(
        TrainingOptions(
          mode: TrainingMode.fromId(_settings.contestModeId),
          duration: _settings.contestDuration,
          phonicType: _settings.phonicType,
          incomingAccent: _settings.incomingAccent,
          difficulty: _settings.difficulty,
          volume: _settings.audioVolume,
        ),
      ) {
    durationController = TextEditingController(text: state.duration.toString());
    durationFocusNode = FocusNode()..addListener(_handleDurationFocusChange);
  }

  final AppSettings _settings;

  // Owned by the cubit so the field widget stays stateless while keeping its
  // editing state and focus stable across rebuilds.
  late final TextEditingController durationController;
  late final FocusNode durationFocusNode;

  void _handleDurationFocusChange() {
    if (durationFocusNode.hasFocus) return;
    // An empty box stays empty while it has focus; only fall back to the stored
    // value once focus leaves, so the field never displays a blank duration.
    if (durationController.text.isEmpty) {
      durationController.text = state.duration.toString();
    }
  }

  void setMode(TrainingMode? value) {
    if (value != null) {
      _settings.contestModeId = value.id;
      _emit(mode: value);
    }
  }

  void setDifficulty(TrainingDifficulty? value) {
    if (value != null) {
      _settings.difficulty = value;
      _emit(difficulty: value);
    }
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
    _emit(duration: value);

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
    if (value != null) {
      _settings.phonicType = value;
      _emit(phonicType: value);
    }
  }

  void setIncomingAccent(IncomingAccent? value) {
    if (value != null) {
      _settings.incomingAccent = value;
      _emit(incomingAccent: value);
    }
  }

  void setVolume(double value) {
    _settings.audioVolume = value;
    _emit(volume: value);
  }

  @override
  Future<void> close() {
    durationFocusNode
      ..removeListener(_handleDurationFocusChange)
      ..dispose();
    durationController.dispose();
    return super.close();
  }

  void _emit({
    TrainingMode? mode,
    int? duration,
    PhonicType? phonicType,
    IncomingAccent? incomingAccent,
    TrainingDifficulty? difficulty,
    double? volume,
  }) => emit(
    TrainingOptions(
      mode: mode ?? state.mode,
      duration: duration ?? state.duration,
      phonicType: phonicType ?? state.phonicType,
      incomingAccent: incomingAccent ?? state.incomingAccent,
      difficulty: difficulty ?? state.difficulty,
      volume: volume ?? state.volume,
    ),
  );
}
