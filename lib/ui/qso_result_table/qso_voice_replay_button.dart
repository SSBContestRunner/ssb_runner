import 'package:flutter/material.dart';
import 'package:ssb_runner/ui/theme/app_theme.dart';

/// 48 dp wide hit area around a 40 dp circle. The table row limits the height
/// to 42 dp; the dialog rows can use the full 48 dp.
class QsoVoiceReplayButton extends StatelessWidget {
  const QsoVoiceReplayButton({
    super.key,
    required this.isPlaying,
    required this.isDone,
    required this.isInterrupted,
    required this.onTap,
    this.hitHeight = 42,
  });

  final bool isPlaying;
  final bool isDone;
  final bool isInterrupted;
  final VoidCallback onTap;
  final double hitHeight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final semantic = context.semanticColors;

    final Color background;
    final Color foreground;
    final IconData icon;
    if (isPlaying) {
      background = scheme.primary;
      foreground = scheme.onPrimary;
      icon = Icons.graphic_eq_rounded;
    } else if (isDone) {
      background = semantic.successContainer;
      foreground = semantic.success;
      icon = Icons.check_rounded;
    } else if (isInterrupted) {
      background = scheme.errorContainer;
      foreground = scheme.onErrorContainer;
      icon = Icons.close_rounded;
    } else {
      background = scheme.primaryContainer.withValues(alpha: 0.42);
      foreground = scheme.primary;
      icon = Icons.replay_rounded;
    }

    return SizedBox(
      width: 48,
      height: hitHeight,
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        containedInkWell: true,
        highlightShape: BoxShape.circle,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: background,
            ),
            child: Icon(icon, size: 20, color: foreground),
          ),
        ),
      ),
    );
  }
}
