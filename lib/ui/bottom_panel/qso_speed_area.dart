import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ssb_runner/contest_run/contest_manager.dart';

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
            left: 60,
            right: 60,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '---qsos/h',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w300),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RunBtn extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.max,
      children: [
        Expanded(
          child: SizedBox(
            height: 74,
            child: FilledButton(
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadiusGeometry.circular(16.0),
                ),
              ),
              onPressed: () {
                // TODO: Start Run
                context.read<ContestManager>().startContest();
              },
              child: Text('RUN', style: theme.primaryTextTheme.headlineSmall),
            ),
          ),
        ),
      ],
    );
  }
}