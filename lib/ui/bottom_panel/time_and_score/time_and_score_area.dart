import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ssb_runner/common/time_format.dart';
import 'package:ssb_runner/contest_run/new/contest_timer.dart';
import 'package:ssb_runner/ui/bottom_panel/time_and_score/score_area/score_area.dart';

class TimeAndScoreArea extends StatelessWidget {
  const TimeAndScoreArea({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Flex(
      direction: Axis.vertical,
      spacing: 15,
      children: [
        _TimeArea(),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: ScoreArea(),
          ),
        ),
      ],
    );
  }
}

class _TimeAreaCubit extends Cubit<Duration> {
  _TimeAreaCubit({required ContestTimer contestTimer}) : super(Duration.zero) {
    contestTimer.elapseTimeStream.listen((duration) {
      emit(duration);
    });
  }
}

class _TimeArea extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: 54,
      child: Container(
        color: theme.colorScheme.inverseSurface,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            BlocProvider(
              create: (context) {
                return _TimeAreaCubit(contestTimer: context.read());
              },
              child: BlocBuilder<_TimeAreaCubit, Duration>(
                builder: (context, duration) {
                  return Text(
                    formatDuration(duration),
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: theme.colorScheme.onInverseSurface,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
