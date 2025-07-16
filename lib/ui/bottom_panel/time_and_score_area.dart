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
      spacing: 15,
      children: [
        _TimeArea(),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: _ScoreArea(),
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

class _ScoreArea extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.shadow;
    final titleTextStyle = theme.textTheme.titleSmall;

    return ConstrainedBox(
      constraints: BoxConstraints.expand(),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 120, top: 3, bottom: 3),
            child: VerticalDivider(thickness: 2, color: color),
          ),

          Padding(
            padding: const EdgeInsets.only(top: 25, left: 3, right: 3),
            child: Divider(thickness: 2, color: color),
          ),

          Padding(
            padding: const EdgeInsets.only(left: 9, top: 38),
            child: Flex(
              direction: Axis.horizontal,
              children: [
                Expanded(
                  child: Flex(
                    direction: Axis.vertical,
                    spacing: 5,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Point', style: titleTextStyle),
                      Text('Mult', style: titleTextStyle),
                      Text('Score', style: titleTextStyle),
                    ],
                  ),
                ),

                Expanded(
                  child: Flex(
                    direction: Axis.vertical,
                    spacing: 5,
                    children: [
                      Text('1', style: titleTextStyle),
                      Text('2', style: titleTextStyle),
                      Text('3', style: titleTextStyle),
                    ],
                  ),
                ),

                Expanded(
                  child: Flex(
                    direction: Axis.vertical,
                    spacing: 5,
                    children: [
                      Text('4', style: titleTextStyle),
                      Text('5', style: titleTextStyle),
                      Text('6', style: titleTextStyle),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.only(left: 120),
            child: SizedBox(
              height: 38,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Raw',
                      style: titleTextStyle,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Verified',
                      style: titleTextStyle,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
