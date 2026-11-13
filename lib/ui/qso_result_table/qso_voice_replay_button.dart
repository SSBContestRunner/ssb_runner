import 'package:flutter/material.dart';

/// 48 dp wide hit area around a 40 dp circle. The table row limits the height
/// to 42 dp; the dialog rows can use the full 48 dp.
class QsoVoiceReplayButton extends StatelessWidget {
  const QsoVoiceReplayButton({
    super.key,
    required this.isPlaying,
    required this.onTap,
    this.hitHeight = 42,
  });

  final bool isPlaying;
  final VoidCallback onTap;
  final double hitHeight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = isPlaying
        ? scheme.primary
        : scheme.primaryContainer.withValues(alpha: 0.42);
    final foreground = isPlaying ? scheme.onPrimary : scheme.primary;
    final icon = isPlaying ? Icons.graphic_eq_rounded : Icons.replay_rounded;

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
