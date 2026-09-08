import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_motion.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';

/// Where an engagement bar is drawn, which decides its foreground and density.
///
/// [rail] sits on Reel artwork of unknown luminance, so every control is a
/// fixed 72 % black plate with a white glyph and a dark focus-ring companion.
/// [panel] sits on an ordinary app surface in the wide layout and uses
/// semantic palette roles plus written labels, because a pointer-first screen
/// has room to say the words.
enum ReelEngagementBarVariant { rail, panel }

/// The overlay plate every control on a Reel frame sits on. Black literals,
/// not palette tokens: the plate must read the same over any footage in both
/// appearances, and a white glyph on it clears 3:1 even on a pure-white frame.
const Color reelOverlayPlateColor = Color(0xB8000000);
const Color reelOverlayPlateHoverColor = Color(0xD6000000);

/// Shadows behind every piece of white text laid directly on artwork.
const List<Shadow> reelOverlayTextShadows = <Shadow>[
  Shadow(color: Color(0x8C000000), blurRadius: 8),
  Shadow(color: Color(0x59000000), blurRadius: 2),
];

/// 2400 → "2.4K".
///
/// Deliberately local to Reels: Home owns an identical helper inside its own
/// presentation layer, and importing one feature's widget file into another to
/// share eight lines would couple the two features far more than it saves.
/// The exact number always remains available in the semantic label.
String reelCompactCount(int count) {
  if (count < 1000) return '$count';
  final thousands = count / 1000;
  final text = thousands >= 10
      ? thousands.round().toString()
      : thousands.toStringAsFixed(1);
  return '${text.endsWith('.0') ? text.substring(0, text.length - 2) : text}K';
}

/// The like and comment controls for one Reel.
///
/// Counts are server-owned aggregates; this widget only renders what it is
/// given. It never derives a count locally, so an optimistic like that the
/// server later refuses reverts to the truth instead of drifting.
class ReelEngagementBar extends StatelessWidget {
  const ReelEngagementBar({
    required this.likeCount,
    required this.commentCount,
    required this.liked,
    required this.onLike,
    required this.onComments,
    this.likePending = false,
    this.commentsOpen = false,
    this.variant = ReelEngagementBarVariant.rail,
    this.railAxis = Axis.vertical,
    this.railTrailing,
    super.key,
  });

  final int likeCount;
  final int commentCount;
  final bool liked;

  /// Null only when there is no viewer to act as. An unverified account keeps
  /// a live control that explains the gate — a dead button teaches nothing.
  final VoidCallback? onLike;
  final VoidCallback? onComments;
  final bool likePending;

  /// True while the wide layout is already showing this Reel's thread, so the
  /// control reads as a selected toggle rather than a repeatable action.
  final bool commentsOpen;
  final ReelEngagementBarVariant variant;

  /// Rail only. A short media box (a phone with the dock and the header on
  /// screen) has no room for a column, so the same plates line up in a row
  /// with their counts beside them.
  final Axis railAxis;

  /// Rail only. The moderation control for this Reel — report, or delete on
  /// your own — laid out by the rail itself so the three plates share one
  /// wrapping run and can never overflow a very small frame.
  final Widget? railTrailing;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final likeAction = liked
        ? copy.text('Unlike', 'Cofnij polubienie')
        : copy.text('Like', 'Lubię to');
    final likeTotal = copy.template(
      'Likes: {count}',
      'Polubienia: {count}',
      values: <String, Object>{'count': likeCount},
    );
    final commentAction = copy.text('Open comments', 'Otwórz komentarze');
    final commentTotal = copy.template(
      'Comments: {count}',
      'Komentarze: {count}',
      values: <String, Object>{'count': commentCount},
    );
    // Screen readers get the action, the state and the exact total — the
    // compact "2.4K" is a visual affordance, not a fact.
    final likeLabel = '$likeAction. $likeTotal';
    final commentLabel = '$commentAction. $commentTotal';

    if (variant == ReelEngagementBarVariant.panel) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          _PanelPill(
            actionKey: const ValueKey<String>('reel-like-action'),
            icon: liked
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            iconColor: liked ? AppColors.secondary : null,
            value: reelCompactCount(likeCount),
            label: copy.text('likes', 'polubienia'),
            semanticLabel: likeLabel,
            selected: liked,
            highlighted: false,
            onTap: likePending ? null : onLike,
          ),
          _PanelPill(
            actionKey: const ValueKey<String>('reel-comments-action'),
            icon: commentsOpen
                ? Icons.mode_comment_rounded
                : Icons.mode_comment_outlined,
            value: reelCompactCount(commentCount),
            label: copy.text('comments', 'komentarze'),
            semanticLabel: commentLabel,
            selected: commentsOpen,
            highlighted: commentsOpen,
            onTap: onComments,
          ),
        ],
      );
    }

    final horizontal = railAxis == Axis.horizontal;
    final trailing = railTrailing;
    List<Widget> actionsFor({required bool showCounts}) => <Widget>[
      _RailAction(
        actionKey: const ValueKey<String>('reel-like-action'),
        icon: liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        // Tint carries state, never meaning: the count keeps the readable
        // foreground so it never depends on the accent for legibility.
        iconColor: liked ? AppColors.secondary : Colors.white,
        value: reelCompactCount(likeCount),
        semanticLabel: likeLabel,
        // The semantic state is the fill plus "Unlike"; a ring on top of it
        // was the one asymmetric control on the frame.
        selected: liked,
        selectedRing: Colors.transparent,
        popOnSelect: true,
        busy: likePending,
        horizontal: horizontal,
        showCount: showCounts,
        onTap: onLike,
      ),
      _RailAction(
        actionKey: const ValueKey<String>('reel-comments-action'),
        icon: Icons.mode_comment_outlined,
        iconColor: Colors.white,
        value: reelCompactCount(commentCount),
        semanticLabel: commentLabel,
        selected: commentsOpen,
        selectedRing: Colors.white,
        popOnSelect: false,
        busy: false,
        horizontal: horizontal,
        showCount: showCounts,
        onTap: onComments,
      ),
      ?trailing,
    ];
    if (!horizontal) {
      final actions = actionsFor(showCounts: true);
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          for (var index = 0; index < actions.length; index++) ...<Widget>[
            if (index > 0) const SizedBox(height: 14),
            actions[index],
          ],
        ],
      );
    }
    // A frame short enough to fold the rail into a row can also be too narrow
    // to hold three labelled plates side by side. Measure first: keep the
    // counts while they fit, drop them to plates when they do not, and wrap
    // only as the last resort — the 48 px target never shrinks, and the exact
    // totals stay in every control's spoken label either way.
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = 2 + (trailing == null ? 0 : 1);
        final labelled =
            constraints.hasBoundedWidth &&
            constraints.maxWidth >=
                count * _labelledRailItemWidth + 10 * (count - 1);
        return Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 8,
          children: actionsFor(showCounts: labelled),
        );
      },
    );
  }
}

/// A horizontal rail item that still shows its count: the 48 px plate, the
/// gap, room for a four-character total such as "1.2K", and the trailing gap
/// that keeps two of them apart.
const double _labelledRailItemWidth = 48 + 6 + 32 + 8;

/// One 48 px overlay plate with a white glyph: the atom every control on a
/// Reel frame is made of, so report/delete look exactly like like/comment.
class ReelOverlayPlateButton extends StatefulWidget {
  const ReelOverlayPlateButton({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
    this.tooltip,
    this.glyphColor = Colors.white,
    super.key,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onTap;
  final String? tooltip;
  final Color glyphColor;

  @override
  State<ReelOverlayPlateButton> createState() => _ReelOverlayPlateButtonState();
}

class _ReelOverlayPlateButtonState extends State<ReelOverlayPlateButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return _PressScale(
      pressed: _pressed,
      enabled: widget.onTap != null,
      onPressedChanged: (value) => setState(() => _pressed = value),
      child: AccessibleTapRegion(
        onTap: widget.onTap,
        semanticLabel: widget.semanticLabel,
        tooltip: widget.tooltip ?? widget.semanticLabel,
        borderRadius: 24,
        minimumSize: const Size(48, 48),
        focusContrastColor: Colors.black,
        onHover: (value) => setState(() => _hovered = value),
        child: _Plate(
          icon: widget.icon,
          color: widget.onTap == null
              ? widget.glyphColor.withValues(alpha: .6)
              : widget.glyphColor,
          hovered: _hovered && widget.onTap != null,
        ),
      ),
    );
  }
}

class _RailAction extends StatefulWidget {
  const _RailAction({
    required this.actionKey,
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.semanticLabel,
    required this.selected,
    required this.selectedRing,
    required this.popOnSelect,
    required this.busy,
    required this.horizontal,
    required this.showCount,
    required this.onTap,
  });

  final Key actionKey;
  final IconData icon;
  final Color iconColor;
  final String value;
  final String semanticLabel;
  final bool selected;
  final Color selectedRing;
  final bool popOnSelect;
  final bool busy;
  final bool horizontal;

  /// False only on a frame too narrow to place a total beside its plate. The
  /// number never disappears from the semantic label.
  final bool showCount;
  final VoidCallback? onTap;

  @override
  State<_RailAction> createState() => _RailActionState();
}

class _RailActionState extends State<_RailAction>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  late final Animation<double> _scale =
      TweenSequence<double>(<TweenSequenceItem<double>>[
        TweenSequenceItem<double>(
          tween: Tween<double>(
            begin: 1,
            end: 1.25,
          ).chain(CurveTween(curve: Curves.easeOut)),
          weight: 45,
        ),
        TweenSequenceItem<double>(
          tween: Tween<double>(
            begin: 1.25,
            end: 1,
          ).chain(CurveTween(curve: Curves.easeOutBack)),
          weight: 55,
        ),
      ]).animate(_pop);
  bool _hovered = false;
  bool _pressed = false;

  @override
  void didUpdateWidget(covariant _RailAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    // One pop on the liked transition only; never on unlike, never on a
    // server reconciliation that leaves the state as it was.
    if (widget.popOnSelect && widget.selected && !oldWidget.selected) {
      _pop.duration = AppMotion.resolve(
        context,
        const Duration(milliseconds: 220),
      );
      _pop.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // While the call is in flight the control keeps the state the tap just
    // produced. Swapping the heart for a spinner would take back the very
    // feedback the optimistic update exists to give, and a perpetual
    // animation in a feed never settles. `busy` still removes the action, so
    // the button reads as disabled to assistive technology and a second tap
    // cannot race the first.
    final enabled = widget.onTap != null;
    // Signed out: the counts stay readable, the glyph steps back, no ring.
    final glyph = enabled || widget.busy
        ? widget.iconColor
        : widget.iconColor.withValues(alpha: .6);
    final count = Text(
      widget.value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 13,
        fontWeight: FontWeight.w700,
        height: 1.2,
        shadows: reelOverlayTextShadows,
      ),
    );
    final plate = ScaleTransition(
      scale: _scale,
      child: _Plate(
        icon: widget.icon,
        color: glyph,
        hovered: _hovered && enabled && !widget.busy,
        ring: widget.selected ? widget.selectedRing : null,
      ),
    );
    return _PressScale(
      pressed: _pressed,
      enabled: enabled && !widget.busy,
      onPressedChanged: (value) => setState(() => _pressed = value),
      child: AccessibleTapRegion(
        key: widget.actionKey,
        onTap: widget.busy ? null : widget.onTap,
        semanticLabel: widget.semanticLabel,
        tooltip: widget.semanticLabel,
        selected: widget.selected,
        // The state is drawn on the plate; the region keeps only the semantic
        // fact of being selected.
        selectedBorderColor: Colors.transparent,
        // A stadium around a 48-wide, 68-tall control would curve straight
        // through the count sitting at its bottom; the hover and focus rings
        // this radius shapes have to clear it.
        borderRadius: widget.horizontal ? 24 : 12,
        minimumSize: widget.horizontal
            ? const Size(48, 48)
            : const Size(48, 68),
        // Artwork behind the rail can be any luminance, so the focus ring
        // gets a dark companion edge and stays visible on both.
        focusContrastColor: Colors.black,
        onHover: (value) => setState(() => _hovered = value),
        child: widget.horizontal
            ? widget.showCount
                  ? Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          plate,
                          const SizedBox(width: 6),
                          count,
                        ],
                      ),
                    )
                  : plate
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[plate, const SizedBox(height: 4), count],
              ),
      ),
    );
  }
}

class _Plate extends StatelessWidget {
  const _Plate({
    required this.icon,
    required this.color,
    required this.hovered,
    this.ring,
  });

  final IconData icon;
  final Color color;
  final bool hovered;

  /// Drawn on the plate rather than around the whole control: a rail item is
  /// a circle with a number under it, and a ring that enclosed both would run
  /// straight through the number.
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    final ringColor = ring;
    return AnimatedContainer(
      duration: AppMotion.resolve(context, AppMotion.quick),
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: hovered ? reelOverlayPlateHoverColor : reelOverlayPlateColor,
        shape: BoxShape.circle,
        border: ringColor == null || ringColor.a == 0
            ? null
            : Border.all(color: ringColor, width: 2),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 24, color: color),
    );
  }
}

/// Pressed feedback without a second gesture arena: a raw pointer listener
/// shrinks the control to .94 and lets the tap region keep the tap.
class _PressScale extends StatelessWidget {
  const _PressScale({
    required this.pressed,
    required this.enabled,
    required this.onPressedChanged,
    required this.child,
  });

  final bool pressed;
  final bool enabled;
  final ValueChanged<bool> onPressedChanged;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: enabled ? (_) => onPressedChanged(true) : null,
      onPointerUp: (_) => onPressedChanged(false),
      onPointerCancel: (_) => onPressedChanged(false),
      child: AnimatedScale(
        scale: pressed && enabled ? .94 : 1,
        duration: AppMotion.resolve(context, AppMotion.quick),
        curve: AppMotion.standardCurve,
        child: child,
      ),
    );
  }
}

class _PanelPill extends StatelessWidget {
  const _PanelPill({
    required this.actionKey,
    required this.icon,
    required this.value,
    required this.label,
    required this.semanticLabel,
    required this.selected,
    required this.highlighted,
    required this.onTap,
    this.iconColor,
  });

  final Key actionKey;
  final IconData icon;
  final Color? iconColor;
  final String value;
  final String label;
  final String semanticLabel;

  /// Reported to assistive technology.
  final bool selected;

  /// Painted as the primary-container fill: the thread toggle while its
  /// thread is open. A liked heart carries its own state in the tint.
  final bool highlighted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final foreground = highlighted
        ? colors.onPrimaryContainer
        : palette.textPrimary;
    final secondary = highlighted
        ? colors.onPrimaryContainer
        : palette.textSecondary;
    return AccessibleTapRegion(
      key: actionKey,
      onTap: onTap,
      semanticLabel: semanticLabel,
      tooltip: semanticLabel,
      selected: selected,
      // The fill is the state; a ring around a filled pill reads as focus.
      selectedBorderColor: Colors.transparent,
      borderRadius: 999,
      minimumSize: const Size(48, 44),
      child: AnimatedContainer(
        duration: AppMotion.resolve(context, AppMotion.quick),
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: highlighted ? colors.primaryContainer : palette.surfaceMuted,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: highlighted ? colors.primary : palette.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 20, color: iconColor ?? secondary),
            const SizedBox(width: 8),
            // The count stays the first text so a reader (or a test) that
            // asks for "the number in this pill" gets the number.
            Text(
              value,
              maxLines: 1,
              style: TextStyle(
                color: foreground,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              maxLines: 1,
              style: TextStyle(
                color: secondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
