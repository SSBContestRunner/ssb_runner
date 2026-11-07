import 'package:flutter/material.dart';
import 'package:ssb_runner/ui/qso_result_table/qso_result_list/qso_result.dart';
import 'package:ssb_runner/ui/qso_result_table/qso_voice_replay_button.dart';
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
const double qsoReplayColumnWidth = 48;
const double qsoCellPadding = 10;

/// Below this width the replay action is dropped so the data columns keep
/// their guaranteed widths instead of overflowing.
const double qsoReplayColumnMinWidth = 420;

/// A single row of the QSO result table.
///
/// Long callsigns, corrections, or fallback glyphs must ellipsise instead of
/// overflowing the row.
class QsoRecordRow extends StatelessWidget {
  const QsoRecordRow({
    super.key,
    required this.item,
    this.isLatest = false,
    this.isPlaying = false,
    this.isDone = false,
    this.isInterrupted = false,
    this.onReplay,
  });

  final QsoResult item;

  /// The newest record gets a weak primary-container highlight.
  final bool isLatest;

  /// Row-level replay playback state. Only one row can be playing at a time.
  final bool isPlaying;
  final bool isDone;
  final bool isInterrupted;
  final VoidCallback? onReplay;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showReplayColumn =
            constraints.maxWidth >= qsoReplayColumnMinWidth;
        final showReplayButton =
            showReplayColumn && item.canReplay && onReplay != null;
        return _buildRow(
          context,
          showReplayColumn: showReplayColumn,
          showReplayButton: showReplayButton,
        );
      },
    );
  }

  Widget _buildRow(
    BuildContext context, {
    required bool showReplayColumn,
    required bool showReplayButton,
  }) {
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

    return SizedBox(
      height: 42,
      child: DecoratedBox(
        // Two layers keep the cells centred:
        // 1. The Stack must stay `StackFit.passthrough`. Its default loose fit
        //    would give the Row a loose height constraint, so the Row collapses
        //    to its text height and pins to the top of the 42 dp row.
        // 2. The divider must not consume layout height: Container folds a
        //    decoration's border into its padding, leaving a 41 dp content box
        //    and pushing the centred text 1 dp off the row centre. Hence
        //    SizedBox + DecoratedBox instead of Container.
        decoration: BoxDecoration(
          color: isPlaying
              ? scheme.primaryContainer.withValues(alpha: 0.42)
              : isLatest
              ? highlight
              : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.55),
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              Row(
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
                  if (showReplayColumn)
                    SizedBox(
                      width: qsoReplayColumnWidth,
                      child: showReplayButton
                          ? Center(
                              child: QsoVoiceReplayButton(
                                isPlaying: isPlaying,
                                isDone: isDone,
                                isInterrupted: isInterrupted,
                                onTap: onReplay!,
                              ),
                            )
                          : null,
                    ),
                ],
              ),
              if (isPlaying)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 3,
                  child: ColoredBox(color: scheme.primary),
                ),
            ],
          ),
        ),
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
