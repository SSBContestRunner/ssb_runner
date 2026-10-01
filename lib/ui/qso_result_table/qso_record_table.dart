import 'package:flutter/material.dart';
import 'package:ssb_runner/ui/qso_result_table/qso_result_list/qso_result_list.dart';

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
                  Expanded(child: _headerCell('UTC', textStyle)),
                  Expanded(child: _headerCell('Call', textStyle)),
                  Expanded(child: _headerCell('Rst', textStyle)),
                  Expanded(child: _headerCell('Exchange', textStyle)),
                  Expanded(child: _headerCell('Corrections', textStyle)),
                ],
              ),
            ),

            Divider(thickness: 1),
            Expanded(child: QsoRecordList()),
          ],
        ),
      ),
    );
  }

  /// Header labels use the same fixed five-column layout as the rows; keep them
  /// from overflowing when a locale/fallback font measures them wider.
  Widget _headerCell(String label, TextStyle? textStyle) {
    return Text(
      label,
      style: textStyle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
