import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ssb_runner/ui/bottom_panel/time_and_score/score_area/score_area_cubit.dart';
import 'package:ssb_runner/ui/bottom_panel/time_and_score/score_area/score_area_data.dart';

class ScoreArea extends StatelessWidget {
  const ScoreArea({super.key});

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
            child: BlocProvider(
              create: (context) => ScoreAreaCubit(context: context),
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
                    child: BlocBuilder<ScoreAreaCubit, ScoreAreaData>(
                      buildWhen: (previous, current) {
                        return previous.rawScore != current.rawScore;
                      },
                      builder: (context, scoreAreaData) {
                        return Flex(
                          direction: Axis.vertical,
                          spacing: 5,
                          children: [
                            Text(
                              scoreAreaData.rawScore.count.toString(),
                              style: titleTextStyle,
                            ),
                            Text(
                              scoreAreaData.rawScore.multiple.toString(),
                              style: titleTextStyle,
                            ),
                            Text(
                              scoreAreaData.rawScore.score.toString(),
                              style: titleTextStyle,
                            ),
                          ],
                        );
                      },
                    ),
                  ),

                  Expanded(
                    child: BlocBuilder<ScoreAreaCubit, ScoreAreaData>(
                      buildWhen: (previous, current) =>
                          previous.verifiedScore != current.verifiedScore,
                      builder: (context, scoreAreaData) {
                        return Flex(
                          direction: Axis.vertical,
                          spacing: 5,
                          children: [
                            Text(
                              scoreAreaData.verifiedScore.count.toString(),
                              style: titleTextStyle,
                            ),
                            Text(
                              scoreAreaData.verifiedScore.multiple.toString(),
                              style: titleTextStyle,
                            ),
                            Text(
                              scoreAreaData.verifiedScore.score.toString(),
                              style: titleTextStyle,
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.only(left: 130),
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
