import 'dart:math';

import 'package:flutter/material.dart';
import 'package:ssb_contest_runner/db/app_database.dart';

class QsoRecordTable extends StatelessWidget {
  const QsoRecordTable({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final textStyle = TextTheme.of(
      context,
    ).bodyMedium?.copyWith(color: colorScheme.primary);

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.secondary, width: 1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Row(children: [Text('UTC', style: textStyle)]),
                  ),
                  Expanded(
                    child: Row(children: [Text('Call', style: textStyle)]),
                  ),
                  Expanded(
                    child: Row(children: [Text('Rst', style: textStyle)]),
                  ),
                  Expanded(
                    child: Row(children: [Text('Exchange', style: textStyle)]),
                  ),
                  Expanded(
                    child: Row(
                      children: [Text('Corrections', style: textStyle)],
                    ),
                  ),
                ],
              ),
            ),

            Divider(thickness: 1),
            Expanded(child: _QsoRecordList()),
          ],
        ),
      ),
    );
  }
}

class _QsoRecordList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final qsos = _bulidList();

    final surfaceContainerHighest = ColorScheme.of(
      context,
    ).surfaceContainerHighest;

    return ListView.separated(
      itemBuilder: (context, index) {
        final item = qsos[index];

        bool isCorrect = true;
        final textStyle = _obtainBodyTextStyle(context, isCorrect);

        return SizedBox(
          height: 20,
          child: Container(
            color: index % 2 == 0
                ? Colors.transparent
                : surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Row(children: [Text('00:00:00', style: textStyle)]),
                  ),
                  Expanded(
                    child: Row(children: [Text(item.callsign, style: textStyle)]),
                  ),
                  Expanded(
                    child: Row(
                      children: [Text(item.rstRecv.toString(), style: textStyle)],
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [Text(item.exchangeRecv, style: textStyle)],
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [Text('BI1QJQ 59 001', style: textStyle)],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      separatorBuilder: (context, index) => SizedBox(height: 4),
      itemCount: qsos.length,
    );
  }

  List<QsoTableData> _bulidList() {
    final random = Random();
    final id = random.nextInt(2147483647);

    return List.generate(30, (index) {
      return QsoTableData(
        id: id,
        runId: '',
        callsign: 'JJ0JJJ',
        stationCallsign: 'BI1QJQ',
        exchangeRecv: '2',
        exchangeSent: '99',
        rstSent: 59,
        rstRecv: 59,
      );
    });
  }

  TextStyle? _obtainBodyTextStyle(BuildContext context, bool isCorrect) {
    final colorScheme = ColorScheme.of(context);
    final onSurface = colorScheme.onSurface;
    final error = colorScheme.error;

    final color = isCorrect ? onSurface : error;
    return TextTheme.of(context).bodySmall?.copyWith(color: color);
  }
}
