import 'package:flutter/material.dart';
import 'package:ssb_runner/common/constants.dart';
import 'package:ssb_runner/ui/qso_result_table/qso_result_list/qso_result.dart';

/// A single row of the QSO result table.
///
/// The five columns are fixed-width [Expanded] slots. Text that is wider than
/// its slot (long callsigns, corrections, or fallback glyphs from the subsetted
/// monospace font) must ellipsise instead of overflowing the row.
class QsoRecordRow extends StatelessWidget {
  const QsoRecordRow({
    super.key,
    required this.item,
    required this.isAlternate,
  });

  final QsoResult item;

  /// Whether this row is one of the shaded rows.
  final bool isAlternate;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final qsoItemTextStyle = TextStyle(
      fontSize: 14,
      fontFamily: qsoFontFamily,
      letterSpacing: 1,
      height: 1.4,
    );

    return SizedBox(
      height: 20,
      child: Container(
        color: isAlternate
            ? colorScheme.surfaceContainerHighest
            : Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Expanded(child: _cell(item.utc, qsoItemTextStyle)),
              Expanded(
                child: _cell(
                  item.call.data,
                  _bodyTextStyle(
                    colorScheme,
                    qsoItemTextStyle,
                    item.call.isCorrect,
                  ),
                ),
              ),
              Expanded(
                child: _cell(
                  item.rst,
                  _bodyTextStyle(colorScheme, qsoItemTextStyle, true),
                ),
              ),
              Expanded(
                child: _cell(
                  item.exchange.data,
                  _bodyTextStyle(
                    colorScheme,
                    qsoItemTextStyle,
                    item.exchange.isCorrect,
                  ),
                ),
              ),
              Expanded(child: _cell(item.corrections, qsoItemTextStyle)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cell(String text, TextStyle textStyle) {
    return Text(
      text,
      style: textStyle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  TextStyle _bodyTextStyle(
    ColorScheme colorScheme,
    TextStyle textStyle,
    bool isCorrect,
  ) {
    return textStyle.copyWith(
      color: isCorrect ? colorScheme.onSurface : colorScheme.error,
    );
  }
}
