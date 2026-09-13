import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_motion.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';
import 'package:yovoice/shared/widgets/overlays/immersive_overlay_atoms.dart';

/// Where an engagement bar is drawn, which decides its foreground and density.
///
/// [rail] sits on Reel artwork of unknown luminance, so every control is a
/// fixed 72 % black plate with a white glyph and a dark focus-ring companion.
/// [panel] sits on an ordinary app surface in the wide layout and uses
/// semantic palette roles plus written labels, because a pointer-first screen
/// has room to say the words.
///
/// [footer] is the horizontal bar of board 08's card footer: the same actions
/// on the card's own surface, under the media rather than over it — icon,
/// count, and nothing else, so ♡ 💬 ↗ ⋯ read as one row of four.
enum ReelEngagementBarVariant { rail, panel, footer }

/// These atoms moved to `shared/widgets/overlays/immersive_overlay_atoms.dart`
/// because the immersive Voice/Reels chrome paints the same plates. The names
/// below are kept verbatim so no Reels call site — or test that finds one by
/// type — had to change.
const Color reelOverlayPlateColor = overlayPlateColor;
const Color reelOverlayPlateHoverColor = overlayPlateHoverColor;
const List<Shadow> reelOverlayTextShadows = overlayTextShadows;

typedef ReelOverlayPlateButton = OverlayPlateButton;

/// 2400 -> "2.4K". The exact number always stays in the semantic label.
///
/// This helper used to argue it was deliberately local to Reels. That
/// reasoning expired the moment a second feed shared the rail, so it now
/// delegates instead of keeping a second copy.
String reelCompactCount(int count) => compactCount(count);

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
    this.railAlignment = WrapAlignment.end,
    this.railTrailing,
    this.railAdditional = const [],
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

  /// Horizontal rail only. A bar that IS its own plate spreads its targets
  /// across it; a rail laid straight on the media hugs the trailing edge.
  final WrapAlignment railAlignment;

  /// Rail only. The moderation control for this Reel — report, or delete on
  /// your own — laid out by the rail itself so the three plates share one
  /// wrapping run and can never overflow a very small frame.
  final Widget? railTrailing;
  final List<Widget> railAdditional;

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

    if (variant == ReelEngagementBarVariant.footer) {
      // The card footer sits on `surface`, so the plate disappears and the
      // glyph takes the readable foreground. Everything else — the keys, the
      // spoken labels, the 48 px targets, the nullable onLike contract — is
      // the rail's, unchanged.
      //
      // The four totals STAY here at every size the card is drawn at. The
      // footer's height is budgeted as one control row
      // (`ReelStageFooterBar.heightFor`) and the frame above it is sized from
      // what that budget leaves, so a second run would be height the media
      // loses — but in the face the app ships the labelled row fits every
      // width and text size these boards use, and the card that cannot hold
      // it has already given way to the overlay composition
      // (`_minimumStackedFrameWidth`). The residual case — a reader-expanded
      // caption — is absorbed by the media band giving up WIDTH rather than
      // letterboxing against `surfaceSunken`.
      return Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppRhythm.tight,
        runSpacing: AppRhythm.hairline,
        children: <Widget>[
          ReelFooterAction(
            actionKey: const ValueKey<String>('reel-like-action'),
            icon: liked
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            iconColor: liked ? AppColors.secondary : null,
            value: reelCompactCount(likeCount),
            semanticLabel: likeLabel,
            selected: liked,
            onTap: likePending ? null : onLike,
          ),
          ReelFooterAction(
            actionKey: const ValueKey<String>('reel-comments-action'),
            icon: commentsOpen
                ? Icons.mode_comment_rounded
                : Icons.mode_comment_outlined,
            value: reelCompactCount(commentCount),
            semanticLabel: commentLabel,
            selected: commentsOpen,
            onTap: onComments,
          ),
          ...railAdditional,
          ?railTrailing,
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
      ...railAdditional,
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
        final plates = railAdditional.length + (trailing == null ? 0 : 1);
        // The two counted actions cost a plate plus their own digits; share
        // and the overflow are plates and cost nothing more. Budgeting every
        // item at the widest possible total is what made the counts
        // impossible on a phone: four worst-case items needed 406 px and a
        // 390 phone offers 358 inside its inset.
        //
        // The digits are MEASURED, not costed at a per-character constant:
        // that constant is wrong in every typeface but the one it was taken
        // from, and wrong by half at 200 % text. An underestimate here keeps
        // labels on a rail that cannot hold them, the rail wraps to a second
        // 48-px run, and on the stacked card the frame above it loses that
        // height — which is the ledge board 08's S13 named, arrived at from
        // the rail instead of from the budget.
        final needed =
            _labelledRailItemWidth(context, reelCompactCount(likeCount)) +
            _labelledRailItemWidth(context, reelCompactCount(commentCount)) +
            plates * 48 +
            10 * (1 + plates);
        final labelled =
            constraints.hasBoundedWidth && constraints.maxWidth >= needed;
        return Wrap(
          alignment: railAlignment,
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
/// 6 px gap, the digits that will actually be painted, and the trailing gap
/// that keeps two of them apart. Measured from the real total rather than
/// from "1.2K", because a worst case nobody is showing is still paid for by
/// everybody.
double _labelledRailItemWidth(BuildContext context, String value) =>
    48 + 6 + _countWidth(context, value, _railCountStyle) + 8;

/// The rail count's style, shared with the control that paints it so the
/// measurement and the painting cannot drift apart, and the footer count's
/// style beside it for the same reason.
const TextStyle _railCountStyle = TextStyle(
  fontSize: 13,
  fontWeight: FontWeight.w700,
  height: 1.2,
);
final TextStyle _footerCountStyle = AppTypography.labelLarge.copyWith(
  fontWeight: FontWeight.w700,
);

/// What [value] will really be wide in [style], at this reader's text size
/// and in the typeface the app actually loaded.
double _countWidth(BuildContext context, String value, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: value, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  return painter.width;
}

/// One action of the card footer: a 24 px glyph, its total beside it when it
/// has one, inside a 48 px target on the card's own surface.
///
/// Public so the card can build share and ⋯ with exactly this geometry — a
/// footer where two of the four controls were overlay plates would be four
/// controls in two vocabularies.
class ReelFooterAction extends StatelessWidget {
  const ReelFooterAction({
    required this.actionKey,
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
    this.value,
    this.iconColor,
    this.selected,
    super.key,
  });

  final Key actionKey;
  final IconData icon;

  /// Null for an action that counts nothing (share, ⋯).
  final String? value;
  final String semanticLabel;
  final Color? iconColor;
  final bool? selected;

  /// Null only when there is no viewer to act as. An unverified account keeps
  /// a live control that explains the gate — a dead button teaches nothing.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final enabled = onTap != null;
    final foreground = iconColor ?? palette.textPrimary;
    final total = value;
    return AccessibleTapRegion(
      key: actionKey,
      onTap: onTap,
      semanticLabel: semanticLabel,
      tooltip: semanticLabel,
      selected: selected,
      // The glyph already carries the state; a ring on top of it would be the
      // one asymmetric control in the row.
      selectedBorderColor: Colors.transparent,
      borderRadius: 24,
      minimumSize: const Size(48, 48),
      child: Padding(
        padding: EdgeInsetsDirectional.only(end: total == null ? 0 : 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              icon,
              size: 24,
              color: enabled ? foreground : foreground.withValues(alpha: .55),
            ),
            if (total != null) ...<Widget>[
              const SizedBox(width: 6),
              // The exact number is always in the spoken label, so the
              // visible total is the part that may be trimmed rather than
              // the 48 px target beside it.
              Flexible(
                child: Text(
                  total,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  // As on the rail: the measured style and the painted one
                  // are the same object.
                  style: _footerCountStyle.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
              ),
            ],
          ],
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
      // The same style the rail's own width measurement lays out, so what
      // decides whether the counts fit is what gets painted.
      style: _railCountStyle.copyWith(
        color: Colors.white,
        shadows: reelOverlayTextShadows,
      ),
    );
    final plate = ScaleTransition(
      scale: _scale,
      child: OverlayPlate(
        icon: widget.icon,
        color: glyph,
        hovered: _hovered && enabled && !widget.busy,
        ring: widget.selected ? widget.selectedRing : null,
      ),
    );
    return OverlayPressScale(
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
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: highlighted ? colors.primaryContainer : palette.surfaceMuted,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: highlighted ? colors.primary : palette.border,
          ),
        ),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Icon(icon, size: 20, color: iconColor ?? secondary),
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
            Text(
              label,
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
