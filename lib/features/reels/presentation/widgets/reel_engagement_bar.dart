import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';

/// Where an engagement bar is drawn, which decides its foreground and density.
///
/// [overlay] sits on Reel artwork of unknown luminance, so it paints its own
/// contrast plate and a dark focus-ring companion. [panel] sits on an ordinary
/// app surface in the wide layout and uses semantic palette roles plus written
/// labels, because a pointer-first screen has room to say the words.
enum ReelEngagementBarVariant { overlay, panel }

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
    this.variant = ReelEngagementBarVariant.overlay,
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

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final overlay = variant == ReelEngagementBarVariant.overlay;
    final foreground = overlay ? Colors.white : palette.textSecondary;
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

    return Wrap(
      spacing: overlay ? 4 : 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        _EngagementAction(
          actionKey: const ValueKey<String>('reel-like-action'),
          icon: liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          // Tint carries state, never meaning: the count keeps the readable
          // foreground so it never depends on the accent for legibility.
          iconColor: liked ? AppColors.secondary : foreground,
          foreground: foreground,
          value: reelCompactCount(likeCount),
          // Screen readers get the action, the state and the exact total —
          // the compact "2.4K" is a visual affordance, not a fact.
          semanticLabel: '$likeAction. $likeTotal',
          selected: liked,
          busy: likePending,
          overlay: overlay,
          onTap: onLike,
        ),
        _EngagementAction(
          actionKey: const ValueKey<String>('reel-comments-action'),
          icon: Icons.mode_comment_outlined,
          iconColor: foreground,
          foreground: foreground,
          value: reelCompactCount(commentCount),
          semanticLabel: '$commentAction. $commentTotal',
          selected: commentsOpen,
          busy: false,
          overlay: overlay,
          onTap: onComments,
        ),
      ],
    );
  }
}

class _EngagementAction extends StatelessWidget {
  const _EngagementAction({
    required this.actionKey,
    required this.icon,
    required this.iconColor,
    required this.foreground,
    required this.value,
    required this.semanticLabel,
    required this.selected,
    required this.busy,
    required this.overlay,
    required this.onTap,
  });

  final Key actionKey;
  final IconData icon;
  final Color iconColor;
  final Color foreground;
  final String value;
  final String semanticLabel;
  final bool selected;
  final bool busy;
  final bool overlay;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AccessibleTapRegion(
      key: actionKey,
      onTap: busy ? null : onTap,
      semanticLabel: semanticLabel,
      tooltip: semanticLabel,
      selected: selected,
      borderRadius: 24,
      minimumSize: const Size(48, 48),
      // Artwork behind the overlay variant can be any luminance, so the
      // focus ring gets a dark companion edge and stays visible on both.
      focusContrastColor: overlay ? Colors.black : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // While the call is in flight the control keeps the state the tap
            // just produced. Swapping the heart for a spinner would take back
            // the very feedback the optimistic update exists to give, and a
            // perpetual animation in a feed never settles. `busy` still
            // removes the action, so the button reads as disabled to
            // assistive technology and a second tap cannot race the first.
            SizedBox.square(
              dimension: 22,
              child: Icon(icon, size: 22, color: iconColor),
            ),
            const SizedBox(width: 6),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
