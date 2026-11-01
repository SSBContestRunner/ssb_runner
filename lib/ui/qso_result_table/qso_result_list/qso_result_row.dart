import 'package:flutter/material.dart';
import 'package:ssb_runner/ui/qso_result_table/qso_result_list/qso_result.dart';
import 'package:ssb_runner/ui/theme/app_theme.dart';

/// Column metrics shared by the log header and every row so the labels stay
/// aligned with the data.
///
/// A full HH:MM:SS timestamp at 13px needs 54px of Iosevka advance plus the
/// 2 × [qsoCellPadding] cell padding; 84 leaves enough slack that it does not
/// ellipsise.
const double qsoUtcColumnWidth = 84;
const double qsoCallColumnFlex = 105;
const double qsoRstColumnWidth = 52;
const double qsoExchangeColumnFlex = 100;
const double qsoCorrectionsColumnWidth = 132;
const double qsoCellPadding = 10;

/// A single row of the QSO result table.
///
/// Long callsigns, corrections, or fallback glyphs must ellipsise instead of
/// overflowing the row.
class QsoRecordRow extends StatelessWidget {
  const QsoRecordRow({super.key, required this.item, this.isLatest = false});

  final QsoResult item;

  /// The newest record gets a weak primary-container highlight.
  final bool isLatest;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final baseStyle = AppDataText.style(context, fontSize: 14);
    final mutedStyle = AppDataText.style(
      context,
      fontSize: 13,
      color: scheme.onSurfaceVariant,
    );
    final callStyle = AppDataText.style(
      context,
      fontSize: 15,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.6,
      color: item.call.isCorrect ? scheme.onSurface : scheme.error,
    );
    final exchangeStyle = AppDataText.style(
      context,
      fontSize: 15,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.6,
      color: item.exchange.isCorrect ? scheme.onSurface : scheme.error,
    );
    final correctionsStyle = AppDataText.style(
      context,
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: item.corrections.isEmpty ? scheme.outline : scheme.onSurface,
    );
    final highlight = Color.alphaBlend(
      scheme.primaryContainer.withValues(alpha: 0.48),
      scheme.surfaceContainerLow,
    );

    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: isLatest ? highlight : Colors.transparent,
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.55),
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          SizedBox(
            width: qsoUtcColumnWidth,
            child: _cell(item.utc, mutedStyle),
          ),
          Expanded(
            flex: qsoCallColumnFlex.toInt(),
            child: _cell(item.call.data, callStyle),
          ),
          SizedBox(
            width: qsoRstColumnWidth,
            child: _cell(
              item.rst,
              baseStyle.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            flex: qsoExchangeColumnFlex.toInt(),
            child: _cell(item.exchange.data, exchangeStyle),
          ),
          SizedBox(
            width: qsoCorrectionsColumnWidth,
            child: _cell(
              item.corrections.isEmpty ? '—' : item.corrections,
              correctionsStyle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell(String text, TextStyle textStyle) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: qsoCellPadding),
      child: Text(
        text,
        style: textStyle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
