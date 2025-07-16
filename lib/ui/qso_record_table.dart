import 'package:flutter/material.dart';

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
    return Container(color: Colors.amber);
  }
}
