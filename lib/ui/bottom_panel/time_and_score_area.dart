import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ssb_contest_runner/contest_run/contest_manager.dart';

class TimeAndScoreArea extends StatelessWidget {
  const TimeAndScoreArea({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Flex(
      direction: Axis.vertical,
      spacing: 20,
      children: [
        _TimeArea(),

        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Stack(
            // TODO: 绘制表格
          ),
        ),
      ],
    );
  }
}

class _TimeAreaCubit extends Cubit<Duration> {
  _TimeAreaCubit({required ContestManager contestManager})
    : super(Duration.zero) {
    contestManager.elapseTimeStream.listen((duration) {
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
              create: (context) =>
                  _TimeAreaCubit(contestManager: context.read()),
              child: BlocBuilder<_TimeAreaCubit, Duration>(
                builder: (context, duration) {
                  return Text(
                    _formatDuration(duration),
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

  String _formatDuration(Duration duration) {
    final negativeSign = duration.isNegative ? '-' : '';

    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60).abs());
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60).abs());

    return "$negativeSign${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }
}
