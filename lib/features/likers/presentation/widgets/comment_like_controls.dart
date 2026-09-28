import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_motion.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_sizing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/likers/data/models/comment_like.dart';
import 'package:yovoice/features/likers/presentation/likers_copy.dart';
import 'package:yovoice/shared/widgets/overlays/immersive_overlay_atoms.dart'
    show compactCount;

/// The comment heart of owner variant B (spec §5.1, §13): "♡ 3" inline in
/// a comment's action line, the same on Voice Moment and Yeel comments.
///
/// Two targets, never one:
///
/// - **The heart** only toggles (`{keyPrefix}-like-{id}`). Liked is a filled
///   heart in [AppColors.secondary]; the glyph pops once on a like, snapped
///   instead under Reduce Motion ([AppMotion.decorative]). Its spoken label
///   carries the verb and the count.
/// - **The count** (`{keyPrefix}-likers-{id}`, only when there are likes)
///   opens "See who liked"; the flow behind it shows the list to Premium /
///   VIP viewers and the upsell to everyone else. For a viewer the pre-gate
///   already knows can see likers, the same control also reads
///   "Kto polubił" (`{keyPrefix}-who-liked-{id}`): one target with one
///   action, rather than two tab stops that open the same list.
///
/// Both hit regions are at least [AppSizing.minimumTouchTarget] wide and
/// [height] tall; only the glyphs are small. The heart glyph is centred in
/// its target and grows with the reader's text size (up to 1.5×); a host
/// that wants the glyph under the first letter of its text (the Yeel row,
/// with no "Reply" before it) starts this control [glyphInset] earlier than
/// the text, inside its own bounds, so the whole target stays tappable.
///
/// Keyboard focus is a 2 px `palette.focus` ring on each target (the theme's
/// focus tint alone measures about 1.28:1, docs/UI.md): drawn here for the
/// heart, and by the theme's TextButton `side` for the count.
class CommentLikeControls extends StatefulWidget {
  const CommentLikeControls({
    required this.commentId,
    required this.keyPrefix,
    required this.state,
    required this.onToggle,
    required this.onShowLikers,
    this.showWhoLiked = false,
    this.height = AppSizing.standardControlHeight,
    this.dense = false,
    super.key,
  });

  final String commentId;

  /// `moment-comment` or `reel-comment`; the keys are built from it.
  final String keyPrefix;
  final CommentLikeState state;

  /// Null draws the heart disabled (present, not removed), e.g. while the
  /// Yeel row is busy with a delete or report.
  final VoidCallback? onToggle;

  /// Opens "See who liked"; it receives the count's own focus node, so the
  /// flow can hand keyboard focus back to it when it closes. Null draws the
  /// count as plain text.
  final ValueChanged<FocusNode>? onShowLikers;

  /// The viewer may open likers lists: the count also reads "Kto polubił".
  final bool showWhoLiked;
  final double height;
  final bool dense;

  /// The heart glyph at the reader's text size: 18 or 19 px at 1×, scaled
  /// with the text up to 1.5× so it does not shrink beside 200 % words.
  static double glyphSize(BuildContext context, {required bool dense}) {
    final base = dense ? 18.0 : 19.0;
    return MediaQuery.textScalerOf(
      context,
    ).scale(base).clamp(base, base * 1.5).toDouble();
  }

  /// The space between the heart target's start edge and its glyph.
  static double glyphInset(BuildContext context, {required bool dense}) =>
      (AppSizing.minimumTouchTarget - glyphSize(context, dense: dense)) / 2;

  /// The width this control lays out at in [context] (text scale and
  /// locale included), so a host can decide whether its action line fits on
  /// one row before it lays it out.
  static double estimatedWidth(
    BuildContext context, {
    required CommentLikeState state,
    required bool interactive,
    bool showWhoLiked = false,
    bool dense = false,
  }) {
    final style = dense ? AppTypography.labelMedium : AppTypography.labelLarge;
    var width = AppSizing.minimumTouchTarget;
    if (state.likeCount <= 0) return width;
    var count = measureLabel(context, compactCount(state.likeCount), style) + 8;
    if (interactive && showWhoLiked) {
      count +=
          12 +
          measureLabel(
            context,
            LikersCopy(AppLocalizations.of(context)).whoLiked,
            style,
          );
    }
    if (interactive && count < AppSizing.minimumTouchTarget) {
      count = AppSizing.minimumTouchTarget;
    }
    return width + count;
  }

  /// One line of [text] in [style] at the reader's text scale.
  static double measureLabel(
    BuildContext context,
    String text,
    TextStyle style,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  @override
  State<CommentLikeControls> createState() => _CommentLikeControlsState();
}

class _CommentLikeControlsState extends State<CommentLikeControls>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: AppMotion.release,
    value: 1,
  );
  late final Animation<double> _scale = Tween<double>(
    begin: 0.72,
    end: 1,
  ).animate(CurvedAnimation(parent: _pop, curve: AppMotion.releaseCurve));
  final FocusNode _countFocus = FocusNode(debugLabel: 'Comment likers');
  bool _heartFocused = false;

  @override
  void didUpdateWidget(covariant CommentLikeControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    final likedNow = widget.state.callerLiked && !oldWidget.state.callerLiked;
    if (likedNow &&
        widget.commentId == oldWidget.commentId &&
        AppMotion.decorative(context)) {
      _pop.forward(from: 0);
    } else if (!widget.state.callerLiked && !_pop.isCompleted) {
      _pop.value = 1;
    }
  }

  @override
  void dispose() {
    _pop.dispose();
    _countFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final likersCopy = LikersCopy(copy);
    final palette = context.appPalette;
    final state = widget.state;
    final id = widget.commentId;
    final glyph = CommentLikeControls.glyphSize(context, dense: widget.dense);
    final textStyle = widget.dense
        ? AppTypography.labelMedium
        : AppTypography.labelLarge;
    final toggle = widget.onToggle;

    final heart = Semantics(
      container: true,
      button: true,
      enabled: toggle != null,
      // On/off as state, not only through the verb in the label.
      toggled: state.callerLiked,
      label: likersCopy.commentHeart(
        liked: state.callerLiked,
        count: state.likeCount,
      ),
      child: InkResponse(
        key: ValueKey<String>('${widget.keyPrefix}-like-$id'),
        onTap: toggle,
        radius: AppSizing.minimumTouchTarget / 2,
        onFocusChange: (focused) {
          if (_heartFocused != focused) {
            setState(() => _heartFocused = focused);
          }
        },
        child: Container(
          key: ValueKey<String>('${widget.keyPrefix}-like-focus-$id'),
          width: AppSizing.minimumTouchTarget,
          height: widget.height,
          foregroundDecoration: BoxDecoration(
            shape: BoxShape.circle,
            border: _heartFocused
                ? Border.all(color: palette.focus, width: 2)
                : null,
          ),
          child: Center(
            child: ScaleTransition(
              scale: _scale,
              child: Icon(
                state.callerLiked
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                size: glyph,
                // Tint carries STATE; the count beside it stays
                // textSecondary for legibility at label size.
                color: toggle == null
                    ? palette.textTertiary
                    : state.callerLiked
                    ? AppColors.secondary
                    : palette.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );

    final count = state.likeCount;
    Widget? countControl;
    if (count > 0) {
      // Compact on screen (1.3K) so a busy comment keeps its action line;
      // the exact number is in the spoken labels.
      final countText = Text(
        compactCount(count),
        maxLines: 1,
        style: textStyle.copyWith(color: palette.textSecondary),
      );
      final open = widget.onShowLikers;
      if (open == null) {
        countControl = Padding(
          padding: const EdgeInsetsDirectional.only(end: 8),
          child: countText,
        );
      } else {
        countControl = TextButton(
          key: ValueKey<String>('${widget.keyPrefix}-likers-$id'),
          focusNode: _countFocus,
          onPressed: () => open(_countFocus),
          style: TextButton.styleFrom(
            foregroundColor: palette.interactiveForeground,
            minimumSize: Size(AppSizing.minimumTouchTarget, widget.height),
            padding: const EdgeInsetsDirectional.only(start: 0, end: 8),
            alignment: AlignmentDirectional.centerStart,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Semantics(
            // With "Kto polubił" on screen the spoken name starts with it
            // (label in name, WCAG 2.5.3).
            label: widget.showWhoLiked
                ? likersCopy.whoLikedCount(count)
                : likersCopy.seeWhoLikedCount(count),
            excludeSemantics: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                countText,
                if (widget.showWhoLiked) ...<Widget>[
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      likersCopy.whoLiked,
                      key: ValueKey<String>(
                        '${widget.keyPrefix}-who-liked-$id',
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textStyle.copyWith(
                        color: palette.interactiveForeground,
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

    return Row(
      key: ValueKey<String>('${widget.keyPrefix}-like-line-$id'),
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        heart,
        if (countControl != null) Flexible(child: countControl),
      ],
    );
  }
}
