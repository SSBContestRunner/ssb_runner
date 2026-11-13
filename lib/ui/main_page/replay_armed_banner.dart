import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ssb_runner/l10n/domain_l10n.dart';
import 'package:ssb_runner/l10n/generated/app_localizations.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/training/pending_replay.dart';
import 'package:ssb_runner/ui/theme/app_theme.dart';
import 'package:toastification/toastification.dart';

/// Cancels an armed replay and offers an undo in the toast.
///
/// Both the settings drawer banner and the session-card popover use this so the
/// two cancel paths behave the same: the ordinary settings were never touched,
/// so arming the same snapshot again is the complete undo.
void cancelReplayWithUndo(BuildContext context, PendingReplay pending) {
  final l10n = AppLocalizations.of(context);
  final settings = context.read<AppSettings>();
  final onSuccess = context.semanticColors.onSuccess;
  settings.clearPendingReplay();

  late final ToastificationItem item;
  item = toastification.show(
    title: Row(
      children: [
        Expanded(child: Text(l10n.replayCancelledToast)),
        const SizedBox(width: 8),
        TextButton(
          key: const Key('replayUndoAction'),
          onPressed: () {
            toastification.dismiss(item);
            settings.armReplay(pending);
          },
          style: TextButton.styleFrom(
            foregroundColor: onSuccess,
            minimumSize: const Size(0, 32),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(l10n.undoCancelReplay),
        ),
      ],
    ),
    autoCloseDuration: const Duration(seconds: 5),
    type: ToastificationType.success,
    style: ToastificationStyle.fillColored,
    pauseOnHover: true,
  );
}

String replayContestLabel(PendingReplay pending) =>
    pending.hasKnownContest ? pending.contestName : pending.contestId;

String replayModeLabel(AppLocalizations l10n, PendingReplay pending) =>
    pending.hasKnownMode
    ? l10n.trainingModeLabelById(pending.modeId)
    : pending.modeId;

String replayDifficultyLabel(AppLocalizations l10n, PendingReplay pending) =>
    pending.hasKnownDifficulty
    ? l10n.trainingDifficultyLabelById(pending.difficultyId)
    : pending.difficultyId;

/// "Armed at" moment, never a scheduled start time.
String formatReplayArmedAt(BuildContext context, DateTime armedAtUtc) {
  final local = armedAtUtc.toLocal();
  final material = MaterialLocalizations.of(context);
  return '${material.formatMediumDate(local)} '
      '${material.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
}

String formatReplayArmedTimeOnly(BuildContext context, DateTime armedAtUtc) {
  final local = armedAtUtc.toLocal();
  return MaterialLocalizations.of(context)
      .formatTimeOfDay(TimeOfDay.fromDateTime(local));
}

/// The settings drawer banner.
///
/// The session card no longer reserves a strip for this: the header capsule and
/// its anchored popover replaced it. The drawer keeps the full explanation
/// because it also carries the lock hint.
class ReplayArmedBanner extends StatelessWidget {
  const ReplayArmedBanner({
    super.key,
    required this.pending,
    this.showLockHint = false,
  });

  final PendingReplay pending;

  /// The settings drawer also explains that contest/mode/difficulty are locked.
  final bool showLockHint;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final contest = replayContestLabel(pending);
    final mode = replayModeLabel(l10n, pending);
    final difficulty = replayDifficultyLabel(l10n, pending);
    final time = formatReplayArmedAt(context, pending.armedAtUtc);

    return Container(
      key: const Key('replayArmedBanner'),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          scheme.primaryContainer.withValues(alpha: 0.38),
          scheme.surface,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Color.alphaBlend(
            scheme.primary.withValues(alpha: 0.22),
            scheme.outlineVariant,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.replay_outlined, size: 16, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.replayArmedTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(color: scheme.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            l10n.replayArmedDetail(contest, mode, difficulty),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 2),
          Text(
            l10n.replayArmedAt(time),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 2),
          Text(
            l10n.replayArmedStationHint,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (showLockHint) ...[
            const SizedBox(height: 2),
            Text(
              l10n.replayLockedHint,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => cancelReplayWithUndo(context, pending),
              icon: const Icon(Icons.close, size: 16),
              label: Text(l10n.cancelReplay),
              style: TextButton.styleFrom(
                foregroundColor: scheme.primary,
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Header capsule that opens the anchored replay-details popover.
///
/// The card reserves no body height: the popover lives in the [Overlay] and is
/// positioned below the capsule, so opening it never moves the timer.
class ReplayStatusCapsule extends StatefulWidget {
  const ReplayStatusCapsule({
    super.key,
    required this.pending,
    required this.duration,
    this.showTime = true,
  });

  final PendingReplay pending;
  final int duration;

  /// False when the header row cannot fit the armed-at time.
  final bool showTime;

  static const double padH = 9;
  static const double iconSize = 13;
  static const double iconGap = 4;
  static const double timeGap = 2;
  static const double chevronSize = 13;
  static const double chevronGap = 2;

  static TextStyle? labelStyleOf(BuildContext context) =>
      Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      );

  static TextStyle? timeStyleOf(BuildContext context) => Theme.of(context)
      .textTheme
      .labelSmall
      ?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        letterSpacing: 0.2,
      );

  /// Intrinsic width of the capsule, including the optional armed-at time.
  static double measureWidth({
    required TextStyle? labelStyle,
    required TextStyle? timeStyle,
    required TextScaler textScaler,
    required TextDirection textDirection,
    required String label,
    String? time,
  }) {
    final labelWidth = measureText(
      label,
      labelStyle,
      textScaler,
      textDirection,
    );
    final timeWidth = time == null
        ? 0
        : timeGap + measureText(time, timeStyle, textScaler, textDirection);
    return padH * 2 +
        iconSize +
        iconGap +
        labelWidth +
        timeWidth +
        chevronGap +
        chevronSize;
  }

  @override
  State<ReplayStatusCapsule> createState() => _ReplayStatusCapsuleState();
}

class _ReplayStatusCapsuleState extends State<ReplayStatusCapsule> {
  final OverlayPortalController _portal = OverlayPortalController();
  final LayerLink _link = LayerLink();
  final Object _tapGroup = Object();
  final FocusNode _capsuleFocus = FocusNode(debugLabel: 'replayCapsule');
  final FocusNode _panelFocus = FocusNode(debugLabel: 'replayPanel');
  bool _open = false;
  bool _showFocusRing = false;

  /// Hover/press drive the *pill* highlight. The 48dp InkWell stays the gesture
  /// and hit target; its own ink surfaces are transparent so the highlight
  /// cannot spill over the taller hit band.
  bool _hovered = false;
  bool _pressed = false;

  /// Anchor rect captured when the panel opens, in overlay coordinates. The
  /// overlay gives us tight screen-sized constraints, so the panel clamps its
  /// own width/height/dx against these numbers instead of trusting layout.
  Rect? _anchorRect;

  @override
  void initState() {
    super.initState();
    _capsuleFocus.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _capsuleFocus
      ..removeListener(_handleFocusChange)
      ..dispose();
    _panelFocus.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (_showFocusRing == _capsuleFocus.hasFocus) return;
    setState(() => _showFocusRing = _capsuleFocus.hasFocus);
  }

  void _toggle() {
    if (_open) {
      _close();
    } else {
      _openPanel();
    }
  }

  void _openPanel() {
    if (_open) return;
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      _anchorRect = box.localToGlobal(Offset.zero) & box.size;
    }
    setState(() => _open = true);
    _portal.show();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _open) _panelFocus.requestFocus();
    });
  }

  void _close({bool restoreFocus = true}) {
    if (!_open) return;
    setState(() => _open = false);
    _portal.hide();
    if (restoreFocus) _capsuleFocus.requestFocus();
  }

  /// Cancelling removes the armed snapshot, so the capsule disappears with the
  /// panel; do not push focus back to a node that is about to be disposed.
  void _cancel() {
    if (!_open) return;
    setState(() => _open = false);
    _portal.hide();
    cancelReplayWithUndo(context, widget.pending);
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _close();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final contest = replayContestLabel(widget.pending);
    final mode = replayModeLabel(l10n, widget.pending);
    final difficulty = replayDifficultyLabel(l10n, widget.pending);
    final time = widget.showTime
        ? formatReplayArmedTimeOnly(context, widget.pending.armedAtUtc)
        : null;
    final hovered = _hovered;
    final pressed = _pressed;
    final baseColor = scheme.surfaceContainerHigh;
    final pillColor = pressed
        ? Color.alphaBlend(scheme.primary.withValues(alpha: 0.16), baseColor)
        : hovered
        ? Color.alphaBlend(scheme.primary.withValues(alpha: 0.08), baseColor)
        : baseColor;

    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: _buildPanel,
        child: TapRegion(
          groupId: _tapGroup,
          child: Tooltip(
            message: l10n.replayDetailTitle,
            child: Semantics(
              button: true,
              label:
                  '${l10n.replayStatusChip} · $contest · $mode · $difficulty',
              excludeSemantics: true,
              child: SizedBox(
                height: 48,
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    key: const Key('replayStatusCapsule'),
                    focusNode: _capsuleFocus,
                    onTap: _toggle,
                    onHover: (value) {
                      if (_hovered != value) setState(() => _hovered = value);
                    },
                    onHighlightChanged: (value) {
                      if (_pressed != value) setState(() => _pressed = value);
                    },
                    borderRadius: BorderRadius.circular(8),
                    // The pill paints its own hover/press tint: the InkWell
                    // spans the whole 48dp hit band, so its built-in highlight
                    // would look like a 48dp rectangle around a 26dp pill.
                    hoverColor: Colors.transparent,
                    highlightColor: Colors.transparent,
                    splashColor: Colors.transparent,
                    focusColor: Colors.transparent,
                    child: Center(
                      widthFactor: 1,
                      child: Container(
                        key: const Key('replayStatusCapsulePill'),
                        height: 26,
                        padding: const EdgeInsets.symmetric(
                          horizontal: ReplayStatusCapsule.padH,
                        ),
                        decoration: BoxDecoration(
                          color: pillColor,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _showFocusRing
                                ? scheme.primary
                                : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.replay_outlined,
                              size: ReplayStatusCapsule.iconSize,
                              color: scheme.primary,
                            ),
                            const SizedBox(width: ReplayStatusCapsule.iconGap),
                            Text(
                              l10n.replayStatusChip,
                              maxLines: 1,
                              style: ReplayStatusCapsule.labelStyleOf(context),
                            ),
                            if (time != null) ...[
                              const SizedBox(
                                width: ReplayStatusCapsule.timeGap,
                              ),
                              Text(
                                l10n.replayArmedAt(time),
                                maxLines: 1,
                                style: ReplayStatusCapsule.timeStyleOf(context),
                              ),
                            ],
                            const SizedBox(
                              width: ReplayStatusCapsule.chevronGap,
                            ),
                            Icon(
                              Icons.keyboard_arrow_down,
                              size: ReplayStatusCapsule.chevronSize,
                              color: scheme.primary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPanel(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final anchor = _anchorRect;
    const margin = 12.0;
    const gap = 6.0;
    final hasScreen = screen.width > 0 && screen.height > 0;

    final panelWidth = hasScreen
        ? math.min(320.0, screen.width - margin * 2)
        : 320.0;
    // Vertical room below the capsule, always leaving a bottom margin.
    final belowSpace = !hasScreen || anchor == null
        ? 440.0
        : math.max(0.0, screen.height - anchor.bottom - gap - margin);
    final panelMaxHeight = math.min(440.0, belowSpace);
    // Right-aligned to the capsule, shifted left just enough to keep the
    // horizontal margin on both sides.
    final dx = !hasScreen || anchor == null
        ? 0.0
        : math.max(
            math.min(0.0, screen.width - margin - anchor.right),
            margin + panelWidth - anchor.right,
          );

    // The Overlay lays every entry out with tight screen-sized constraints
    // (`_RenderTheater.performLayout`), so without this Align the follower and
    // every box below it would be stretched to the whole window.
    return Align(
      alignment: Alignment.topLeft,
      child: CompositedTransformFollower(
        link: _link,
        showWhenUnlinked: false,
        targetAnchor: Alignment.bottomRight,
        followerAnchor: Alignment.topRight,
        offset: Offset(dx, gap),
        child: TapRegion(
          groupId: _tapGroup,
          // Do not steal focus back from whatever the operator clicked.
          onTapOutside: (_) => _close(restoreFocus: false),
          child: Focus(
            focusNode: _panelFocus,
            autofocus: true,
            onKeyEvent: _handleKey,
            child: _ReplayDetailsPanel(
              pending: widget.pending,
              duration: widget.duration,
              width: panelWidth,
              maxHeight: panelMaxHeight,
              onCancel: _cancel,
              onClose: _close,
            ),
          ),
        ),
      ),
    );
  }
}

class _ReplayDetailsPanel extends StatelessWidget {
  const _ReplayDetailsPanel({
    required this.pending,
    required this.duration,
    required this.width,
    required this.maxHeight,
    required this.onCancel,
    required this.onClose,
  });

  final PendingReplay pending;
  final int duration;
  final double width;
  final double maxHeight;
  final VoidCallback onCancel;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final contest = replayContestLabel(pending);
    final mode = replayModeLabel(l10n, pending);
    final difficulty = replayDifficultyLabel(l10n, pending);
    final time = formatReplayArmedAt(context, pending.armedAtUtc);

    Widget field(String label, String value) {
      return Container(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              style: textTheme.labelSmall?.copyWith(
                fontSize: 10.5,
                letterSpacing: 0.4,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              maxLines: 2,
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return Material(
      key: const Key('replayDetailPanel'),
      elevation: 12,
      color: scheme.surfaceContainerLow,
      shadowColor: scheme.shadow,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: SizedBox(
        width: width,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              l10n.replayDetailTitle,
                              style: textTheme.titleSmall?.copyWith(
                                color: scheme.primary,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: onClose,
                            tooltip: l10n.replayPanelCollapse,
                            icon: const Icon(Icons.close, size: 18),
                            color: scheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: field(l10n.settingsContest, contest)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: field(l10n.replayPanelModeLabel, mode),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: field(l10n.difficultyFieldLabel, difficulty),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: field(
                              l10n.durationLabel,
                              '$duration ${l10n.durationUnit}',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(
                            color: scheme.outlineVariant.withValues(alpha: 0.6),
                          ),
                        ),
                        child: Text(
                          l10n.replayArmedAt(time),
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.fromLTRB(9, 7, 9, 7),
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.06),
                          border: Border(
                            left: BorderSide(color: scheme.primary, width: 2),
                          ),
                          borderRadius: const BorderRadius.horizontal(
                            right: Radius.circular(7),
                          ),
                        ),
                        child: Text(
                          l10n.replayPanelTrigger,
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l10n.replayArmedStationHint,
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                  ),
                ),
              ),
              // The cancel path stays pinned to the bottom of the popover,
              // even when the details above ever need to scroll.
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: OutlinedButton.icon(
                          key: const Key('replayPanelCancel'),
                          onPressed: onCancel,
                          icon: const Icon(Icons.close, size: 16),
                          label: Text(l10n.cancelReplay),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: scheme.error,
                            backgroundColor: scheme.errorContainer,
                            side: BorderSide.none,
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 48,
                      child: TextButton(
                        key: const Key('replayPanelCollapse'),
                        onPressed: onClose,
                        style: TextButton.styleFrom(
                          foregroundColor: scheme.onSurfaceVariant,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        child: Text(l10n.replayPanelCollapse),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

double measureText(
  String text,
  TextStyle? style,
  TextScaler textScaler,
  TextDirection textDirection,
) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: textDirection,
    textScaler: textScaler,
    maxLines: 1,
  )..layout();
  return painter.width;
}
