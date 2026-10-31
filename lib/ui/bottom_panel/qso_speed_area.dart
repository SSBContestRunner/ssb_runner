import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ssb_runner/contest_run/new/contest_manager.dart';
import 'package:ssb_runner/contest_run/new/contest_timer.dart';
import 'package:ssb_runner/contest_type/contest_definition.dart';
import 'package:ssb_runner/contest_type/station_exchange.dart';
import 'package:ssb_runner/dxcc/dxcc_manager.dart';
import 'package:ssb_runner/l10n/domain_l10n.dart';
import 'package:ssb_runner/l10n/generated/app_localizations.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:toastification/toastification.dart';

class QsoSpeedArea extends StatelessWidget {
  const QsoSpeedArea({super.key});

  @override
  Widget build(BuildContext context) {
    return Flex(
      direction: Axis.vertical,
      spacing: 24,
      children: [_QsoRecordSpeed(), _RunBtn()],
    );
  }
}

/// Speed readout rendered inside the QSO records panel.
///
/// The panel is a fixed 240 px wide and the 40 px insets on both sides leave
/// 160 px for this label. Long localised units such as the Simplified/
/// Traditional Chinese "QSO/小时" make a numeric reading wider than that slot,
/// which used to overflow the row (crash log: "overflowed by 4.7 pixels on the
/// right"). Scaling the label down keeps the unit visible instead of clipping
/// it, and leaves the English/Japanese text untouched because scaleDown never
/// enlarges.
class QsoSpeedReadout extends StatelessWidget {
  const QsoSpeedReadout({super.key, required this.speed, required this.unit});

  /// QSOs per hour, or `null` while no interval has been measured yet.
  final double? speed;

  /// Localised unit appended after the value, e.g. "QSO/小时".
  final String unit;

  @override
  Widget build(BuildContext context) {
    final value = speed;
    final text = value == null
        ? '--- $unit'
        : '${value.toStringAsFixed(1)} $unit';

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              text,
              maxLines: 1,
              softWrap: false,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w300),
            ),
          ),
        ),
      ],
    );
  }
}

class _QsoRecordSpeedCubit extends Cubit<double?> {
  final ContestTimer _contestTimer;
  final ContestManager _contestManager;

  _QsoRecordSpeedCubit({
    required ContestTimer contestTimer,
    required ContestManager contestManager,
  }) : _contestTimer = contestTimer,
       _contestManager = contestManager,
       super(null) {
    _contestTimer.elapseTimeStream.listen((elapseTime) {
      _updateQsoSpeed(elapseTime);
    });
  }

  void _updateQsoSpeed(Duration elapseTime) async {
    final totalSeconds = elapseTime.inSeconds;

    if (totalSeconds == 0) {
      emit(null);
      return;
    }

    final qsoTimes = await _contestManager.recentCurrentRunQsoTimes();
    final qsoCount = qsoTimes.length;
    if (qsoCount == 0) {
      emit(null);
      return;
    }
    // The first contacts use elapsed practice time. Once five intervals exist,
    // display a rolling five-QSO rate rather than a diluted session rate.
    final measuredSeconds = qsoCount >= 6
        ? qsoTimes.last - qsoTimes.first
        : totalSeconds;
    if (measuredSeconds <= 0) return;
    final measuredQsos = qsoCount >= 6 ? 5 : qsoCount;
    final qsoSpeed = measuredQsos / measuredSeconds * 3600;

    emit(qsoSpeed);
  }
}

class _QsoRecordSpeed extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final surfaceVariant = theme.colorScheme.surfaceContainerHighest;

    return Container(
      width: double.infinity,
      height: 92.0,
      decoration: BoxDecoration(
        color: surfaceVariant,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 6,
            left: 16,
            child: Text(
              l10n.qsoRecordsTitle,
              style: theme.textTheme.titleMedium,
            ),
          ),

          Positioned(
            top: 46,
            left: 40,
            right: 40,
            child: BlocProvider(
              create: (context) => _QsoRecordSpeedCubit(
                contestManager: context.read(),
                contestTimer: context.read(),
              ),
              child: BlocBuilder<_QsoRecordSpeedCubit, double?>(
                builder: (context, speed) =>
                    QsoSpeedReadout(speed: speed, unit: l10n.qsoSpeedUnit),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RunBtnCubit extends Cubit<bool> {
  final ContestManager _contestManager;
  final AppSettings _appSettings;
  final DxccManager _dxccManager;

  _RunBtnCubit({
    required ContestManager contestManager,
    required AppSettings appSettings,
    required DxccManager dxccManager,
  }) : _contestManager = contestManager,
       _appSettings = appSettings,
       _dxccManager = dxccManager,
       super(contestManager.isContestRunning) {
    contestManager.isContestRunningStream.listen((isContestRunning) {
      emit(isContestRunning);
    });
  }

  void toggleContestRunning(AppLocalizations l10n) {
    final errorMessage = _checkSettingComplete(l10n);

    if (errorMessage.isNotEmpty) {
      toastification.show(
        title: Text(errorMessage),
        autoCloseDuration: Duration(seconds: 5),
        type: ToastificationType.error,
        style: ToastificationStyle.fillColored,
      );
      return;
    }

    final isRunning = state;
    if (isRunning) {
      _contestManager.stopContest();
    } else {
      _contestManager.startContest();
    }
  }

  String _checkSettingComplete(AppLocalizations l10n) {
    if (_appSettings.stationCallsign.isEmpty) {
      return l10n.callsignRequired;
    }

    if (_appSettings.contestDuration <= 0) {
      return l10n.durationRequired;
    }

    // Station exchange must be complete before a run starts (design 3.3/6.8).
    final definition = ContestRegistry.byId(_appSettings.contestId);
    final plan = definition.myExchangePlan(
      stationCallsign: _appSettings.stationCallsign,
      dxccManager: _dxccManager,
    );
    final exchangeError = validateStationExchange(
      plan: plan,
      config: _appSettings.stationExchangeConfig(definition.id),
      stationCallsign: _appSettings.stationCallsign,
      dxccManager: _dxccManager,
    );
    if (exchangeError != null) {
      final label = l10n.stationFieldLabel(
        exchangeError.field.id,
        exchangeError.field.label,
      );
      return switch (exchangeError) {
        StationExchangeMissing() => l10n.fieldRequired(label),
        StationExchangeInvalid() => l10n.fieldInvalid(label),
        StationExchangeOutOfRange(:final min, :final max) => l10n.fieldRange(
          label,
          min,
          max,
        ),
      };
    }

    return '';
  }
}

class _RunBtn extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return BlocProvider(
      create: (context) => _RunBtnCubit(
        contestManager: context.read(),
        appSettings: context.read(),
        dxccManager: context.read(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          Expanded(
            child: SizedBox(
              height: 74,
              child: BlocBuilder<_RunBtnCubit, bool>(
                builder: (context, isContestRunning) {
                  final shape = RoundedRectangleBorder(
                    borderRadius: BorderRadiusGeometry.circular(16.0),
                  );

                  final colorScheme = theme.colorScheme;

                  final buttonStyle = FilledButton.styleFrom(
                    backgroundColor: isContestRunning
                        ? colorScheme.error
                        : colorScheme.primary,
                    foregroundColor: isContestRunning
                        ? colorScheme.onError
                        : colorScheme.onPrimary,
                    shape: shape,
                  );

                  return FilledButton(
                    style: buttonStyle,
                    onPressed: () {
                      context.read<_RunBtnCubit>().toggleContestRunning(
                        AppLocalizations.of(context),
                      );
                    },
                    child: Text(
                      isContestRunning ? l10n.stopButton : l10n.runButton,
                      style: theme.primaryTextTheme.headlineSmall,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
