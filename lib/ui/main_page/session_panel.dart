import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ssb_runner/common/time_format.dart';
import 'package:ssb_runner/contest_run/data/score_data.dart';
import 'package:ssb_runner/contest_run/new/contest_manager.dart';
import 'package:ssb_runner/contest_run/new/contest_timer.dart';
import 'package:ssb_runner/contest_run/score_manager.dart';
import 'package:ssb_runner/contest_type/contest_definition.dart';
import 'package:ssb_runner/contest_type/station_exchange.dart';
import 'package:ssb_runner/dxcc/dxcc_manager.dart';
import 'package:ssb_runner/l10n/domain_l10n.dart';
import 'package:ssb_runner/l10n/generated/app_localizations.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/ui/main_page/settings_cubits.dart';
import 'package:ssb_runner/ui/qso_result_table/qso_result_list/qso_result_list_cubit.dart';
import 'package:ssb_runner/ui/theme/app_theme.dart';
import 'package:toastification/toastification.dart';

class SessionPanel extends StatelessWidget {
  const SessionPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (context) => _ScoreCubit(context: context)),
        BlocProvider(
          create: (context) => _TimerCubit(contestTimer: context.read()),
        ),
        BlocProvider(
          create: (context) => _QsoSpeedCubit(
            contestTimer: context.read(),
            contestManager: context.read(),
          ),
        ),
        BlocProvider(
          create: (context) => _RunBtnCubit(
            contestManager: context.read(),
            appSettings: context.read(),
            dxccManager: context.read(),
          ),
        ),
      ],
      child: const _SessionCard(),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final contest = context.watch<ContestSettingCubit>().state;
    final options = context.watch<TrainingOptionsCubit>().state;
    final isCompact = MediaQuery.sizeOf(context).height <= 700;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SizedBox(
            height: 56,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.sessionTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 1),
                        Text(
                          '${contest.name} · ${options.duration} '
                          '${l10n.durationUnit}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const _StatusChip(),
                ],
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TimerBlock(compact: isCompact),
                  const SizedBox(height: 10),
                  _ProgressBlock(duration: options.duration),
                  const SizedBox(height: 14),
                  const _ScoreBlock(),
                  const SizedBox(height: 14),
                  const _StatGrid(),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
            child: Column(
              children: const [_RunButton(), SizedBox(height: 8), _RunNote()],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final semantic = context.semanticColors;

    return BlocBuilder<_RunBtnCubit, bool>(
      builder: (context, isRunning) {
        return Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: isRunning
                ? semantic.successContainer
                : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isRunning
                      ? semantic.onSuccessContainer
                      : scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                isRunning ? l10n.sessionStatusRunning : l10n.sessionStatusIdle,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: isRunning
                      ? semantic.onSuccessContainer
                      : scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TimerBlock extends StatelessWidget {
  const _TimerBlock({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final options = context.watch<TrainingOptionsCubit>().state;

    return BlocBuilder<_TimerCubit, Duration>(
      builder: (context, elapsed) {
        final remaining = Duration(
          seconds: (options.duration * 60 - elapsed.inSeconds).clamp(
            0,
            options.duration * 60,
          ),
        );

        final metaStyle = AppDataText.style(
          context,
          fontSize: 11,
          color: scheme.onSurfaceVariant,
        );

        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              flex: 3,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  formatDuration(elapsed),
                  maxLines: 1,
                  style: AppDataText.style(
                    context,
                    fontSize: compact ? 34 : 42,
                    height: compact ? 40 / 34 : 48 / 42,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${l10n.elapsedLabel} ${formatDuration(elapsed)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: metaStyle,
                    ),
                    Text(
                      '${l10n.remainingLabel} ${formatDuration(remaining)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: metaStyle,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ProgressBlock extends StatelessWidget {
  const _ProgressBlock({required this.duration});

  final int duration;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return BlocBuilder<_TimerCubit, Duration>(
      builder: (context, elapsed) {
        final totalSeconds = duration * 60;
        final progress = totalSeconds <= 0
            ? 0.0
            : (elapsed.inSeconds / totalSeconds).clamp(0.0, 1.0);
        final metaStyle = AppDataText.style(
          context,
          fontSize: 11,
          color: scheme.onSurfaceVariant,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(value: progress, minHeight: 6),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('0 ${l10n.durationUnit}', style: metaStyle),
                Text('$duration ${l10n.durationUnit}', style: metaStyle),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _ScoreBlock extends StatelessWidget {
  const _ScoreBlock();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final corrections = context
        .watch<QsoRecordListCubit>()
        .state
        .where((qso) => qso.corrections.isNotEmpty)
        .length;

    return BlocBuilder<_ScoreCubit, _ScoreData>(
      builder: (context, data) {
        final score = data.verifiedScore;
        final raw = data.rawScore;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.emoji_events_outlined,
                  size: 16,
                  color: scheme.tertiary,
                ),
                const SizedBox(width: 6),
                Text(
                  l10n.verifiedScoreLabel,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(letterSpacing: 0.4),
                ),
              ],
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _formatNumber(score.score),
                      maxLines: 1,
                      style: AppDataText.style(
                        context,
                        fontSize: 42,
                        height: 50 / 42,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    l10n.scoreUnit,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Text(
                  l10n.rawScoreValue(_formatNumber(raw.score)),
                  style: AppDataText.style(
                    context,
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                Container(
                  width: 1,
                  height: 12,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  color: scheme.outlineVariant,
                ),
                Expanded(
                  child: Text(
                    l10n.correctionsSummary(corrections, score.multiple),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppDataText.style(
                      context,
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _StatGrid extends StatelessWidget {
  const _StatGrid();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return BlocBuilder<_ScoreCubit, _ScoreData>(
      builder: (context, data) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: scheme.outlineVariant),
              bottom: BorderSide(color: scheme.outlineVariant),
            ),
          ),
          child: Row(
            children: [
              _StatCell(
                label: l10n.statQsos,
                value: _formatNumber(data.verifiedScore.count),
                first: true,
              ),
              _StatCell(
                label: l10n.statMultiplier,
                value: _formatNumber(data.verifiedScore.multiple),
              ),
              BlocBuilder<_QsoSpeedCubit, double?>(
                builder: (context, speed) => _StatCell(
                  label: l10n.statRate,
                  value: speed == null ? '---' : speed.toStringAsFixed(1),
                  suffix: speed == null ? null : l10n.rateSuffix,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.label,
    required this.value,
    this.suffix,
    this.first = false,
  });

  final String label;
  final String value;
  final String? suffix;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Expanded(
      child: Container(
        padding: const EdgeInsets.only(left: 10),
        decoration: BoxDecoration(
          border: first
              ? null
              : Border(left: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 10,
                letterSpacing: 0.5,
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppDataText.style(
                      context,
                      fontSize: 19,
                      height: 26 / 19,
                    ),
                  ),
                ),
                if (suffix != null)
                  Text(
                    suffix!,
                    style: AppDataText.style(
                      context,
                      fontSize: 10,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RunButton extends StatelessWidget {
  const _RunButton();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: BlocBuilder<_RunBtnCubit, bool>(
        builder: (context, isRunning) {
          return FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.primary,
              foregroundColor: scheme.onPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontSize: 15,
                letterSpacing: 0.5,
              ),
            ),
            onPressed: () {
              context.read<_RunBtnCubit>().toggleContestRunning(l10n);
            },
            icon: Icon(
              isRunning ? Icons.stop_circle_outlined : Icons.play_arrow,
              size: 20,
            ),
            label: Text(isRunning ? l10n.stopTraining : l10n.startTraining),
          );
        },
      ),
    );
  }
}

class _RunNote extends StatelessWidget {
  const _RunNote();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return BlocBuilder<_RunBtnCubit, bool>(
      builder: (context, isRunning) {
        return Text(
          isRunning ? l10n.sessionRunningNote : l10n.sessionIdleNote,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        );
      },
    );
  }
}

class _ScoreData {
  const _ScoreData({required this.rawScore, required this.verifiedScore});

  final ScoreData rawScore;
  final ScoreData verifiedScore;

  _ScoreData copyWith({ScoreData? rawScore, ScoreData? verifiedScore}) {
    return _ScoreData(
      rawScore: rawScore ?? this.rawScore,
      verifiedScore: verifiedScore ?? this.verifiedScore,
    );
  }
}

class _ScoreCubit extends Cubit<_ScoreData> {
  StreamSubscription<ScoreData>? _rawScoreDataSubscription;
  StreamSubscription<ScoreData>? _verifiedScoreDataSubscription;
  ScoreManager? _subscribedScoreManager;
  late final StreamSubscription<String> _runSubscription;

  _ScoreCubit({required BuildContext context})
    : super(
        _ScoreData(
          rawScore: ScoreData.initial(),
          verifiedScore: ScoreData.initial(),
        ),
      ) {
    final contestManager = context.read<ContestManager>();
    _runSubscription = contestManager.contestRunIdStream.listen((_) {
      _unsubscribeScoreUpdate();
      emit(
        _ScoreData(
          rawScore: ScoreData.initial(),
          verifiedScore: ScoreData.initial(),
        ),
      );

      final contestRunningManager = contestManager.contestRunningManager;

      if (contestRunningManager == null) {
        return;
      }

      _subscribeScoreUpdate(contestRunningManager.scoreManager);
    });
  }

  void _subscribeScoreUpdate(ScoreManager scoreManager) {
    if (identical(_subscribedScoreManager, scoreManager)) {
      return;
    }
    _unsubscribeScoreUpdate();
    _subscribedScoreManager = scoreManager;

    _rawScoreDataSubscription = scoreManager.rawScoreDataStream.stream.listen((
      scoreData,
    ) {
      emit(state.copyWith(rawScore: scoreData));
    });

    _verifiedScoreDataSubscription = scoreManager.verifiedScoreDataStream.stream
        .listen((scoreData) {
          emit(state.copyWith(verifiedScore: scoreData));
        });
  }

  void _unsubscribeScoreUpdate() {
    _rawScoreDataSubscription?.cancel();
    _verifiedScoreDataSubscription?.cancel();
    _rawScoreDataSubscription = null;
    _verifiedScoreDataSubscription = null;
    _subscribedScoreManager = null;
  }

  @override
  Future<void> close() {
    _runSubscription.cancel();
    _unsubscribeScoreUpdate();
    return super.close();
  }
}

class _TimerCubit extends Cubit<Duration> {
  late final StreamSubscription<Duration> _subscription;

  _TimerCubit({required ContestTimer contestTimer}) : super(Duration.zero) {
    _subscription = contestTimer.elapseTimeStream.listen(emit);
  }

  @override
  Future<void> close() {
    _subscription.cancel();
    return super.close();
  }
}

class _QsoSpeedCubit extends Cubit<double?> {
  final ContestTimer _contestTimer;
  final ContestManager _contestManager;
  late final StreamSubscription<Duration> _subscription;

  _QsoSpeedCubit({
    required ContestTimer contestTimer,
    required ContestManager contestManager,
  }) : _contestTimer = contestTimer,
       _contestManager = contestManager,
       super(null) {
    _subscription = _contestTimer.elapseTimeStream.listen(_updateQsoSpeed);
  }

  Future<void> _updateQsoSpeed(Duration elapseTime) async {
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

  @override
  Future<void> close() {
    _subscription.cancel();
    return super.close();
  }
}

class _RunBtnCubit extends Cubit<bool> {
  final ContestManager _contestManager;
  final AppSettings _appSettings;
  final DxccManager _dxccManager;
  late final StreamSubscription<bool> _subscription;

  _RunBtnCubit({
    required ContestManager contestManager,
    required AppSettings appSettings,
    required DxccManager dxccManager,
  }) : _contestManager = contestManager,
       _appSettings = appSettings,
       _dxccManager = dxccManager,
       super(contestManager.isContestRunning) {
    _subscription = contestManager.isContestRunningStream.listen(emit);
  }

  void toggleContestRunning(AppLocalizations l10n) {
    final errorMessage = _checkSettingComplete(l10n);

    if (errorMessage.isNotEmpty) {
      toastification.show(
        title: Text(errorMessage),
        autoCloseDuration: const Duration(seconds: 5),
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

  @override
  Future<void> close() {
    _subscription.cancel();
    return super.close();
  }
}

String _formatNumber(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(digits[index]);
  }
  return value < 0 ? '-$buffer' : buffer.toString();
}
