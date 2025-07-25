import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ssb_runner/contest_run/contest_manager.dart';
import 'package:ssb_runner/db/app_database.dart';
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

class _QsoRecordSpeedCubit extends Cubit<String> {
  final ContestManager _contestManager;

  static const unit = 'QSOs/h';

  _QsoRecordSpeedCubit({required ContestManager contestManager})
    : _contestManager = contestManager,
      super('--- $unit') {
    _contestManager.elapseTimeStream.listen((elapseTime) {
      _updateQsoSpeed(elapseTime);
    });
  }

  void _updateQsoSpeed(Duration elapseTime) async {
    final totalSeconds = elapseTime.inSeconds;

    if (totalSeconds == 0) {
      emit('--- $unit');
      return;
    }

    final qsoCount = await _contestManager.countCurrentRunQso();

    final qsoSpeed = qsoCount / totalSeconds * 3600;

    emit('${qsoSpeed.toStringAsFixed(1)} $unit');
  }
}

class _QsoRecordSpeed extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            child: Text('QSO Records', style: theme.textTheme.titleMedium),
          ),

          Positioned(
            top: 46,
            left: 40,
            right: 40,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                BlocProvider(
                  create: (context) =>
                      _QsoRecordSpeedCubit(contestManager: context.read()),
                  child: BlocBuilder<_QsoRecordSpeedCubit, String>(
                    builder: (context, speedText) {
                      return Text(
                        speedText,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w300,
                        ),
                      );
                    },
                  ),
                ),
              ],
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

  _RunBtnCubit({
    required ContestManager contestManager,
    required AppSettings appSettings,
  }) : _contestManager = contestManager,
       _appSettings = appSettings,
       super(contestManager.isContestRunning) {
    contestManager.isContestRunningStream.listen((isContestRunning) {
      emit(isContestRunning);
    });
  }

  void toggleContestRunning() {
    final errorMessage = _checkSettingComplete();

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

  String _checkSettingComplete() {
    if (_appSettings.stationCallsign.isEmpty) {
      return 'Please set station callsign';
    }

    if (_appSettings.contestDuration <= 0) {
      return 'Duration must be set and greater than 0';
    }

    return '';
  }
}

class _RunBtn extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BlocProvider(
      create: (context) => _RunBtnCubit(
        contestManager: context.read(),
        appSettings: context.read(),
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
                      context.read<_RunBtnCubit>().toggleContestRunning();
                    },
                    child: Text(
                      isContestRunning ? 'STOP' : 'RUN',
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
