import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_gradients.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/moments/data/models/moment_chain.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_story_tile.dart';
import 'package:yovoice/shared/widgets/interactions/yo_press_feedback.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// The Głos author strip (G4): one circle per author of the list being
/// shown, led by "Nagraj" — the viewer's own face with a `+`.
///
/// It lists EXACTLY the authors of the loaded, active, unblocked, playable
/// list (one chain per author, newest first — `buildMomentChains`), and the
/// unheard/heard fact comes from the caller's own `momentViews` set. Nothing
/// is invented: no author outside the list, no order beyond the chains'.
///
/// THE RING IS THE STATE, drawn by the one seen-avatar definition
/// ([MomentSeenAvatar], ADR-155): the logo's gradient, 3 px, while the
/// author's chain still holds something this account has not heard; a 1 px
/// `border` line and a dimmed face once every link was heard. Under high
/// contrast the unheard ring is a solid primary band and the heard one a
/// `borderStrong` line — no gradient, no glow. The face keeps one diameter
/// in both states, so nothing moves when a chain flips.
///
/// The viewer's own chain stays in the strip (it is how you reach your own
/// Moments) as "Ty" / "You", and is never marked unheard.
class MomentCirclesStrip extends StatelessWidget {
  const MomentCirclesStrip({
    required this.chains,
    required this.viewedIds,
    required this.onOpenChain,
    required this.gutter,
    this.onRecord,
    this.viewerUid,
    this.viewerName,
    super.key,
  });

  final List<MomentChain> chains;
  final Set<String> viewedIds;
  final ValueChanged<MomentChain> onOpenChain;

  /// The page gutter: the first circle's edge lines up with it and the
  /// strip still scrolls full-bleed.
  final double gutter;

  /// The existing record-a-Voice-Moment flow. Absent, no "Nagraj" circle is
  /// drawn — never a dead control.
  final VoidCallback? onRecord;
  final String? viewerUid;
  final String? viewerName;

  static const double topPadding = AppRhythm.item;
  static const double bottomPadding = AppRhythm.item;
  static const double itemGap = AppRhythm.tight;
  static const double nameGap = 6;
  static const double nameSize = 12;
  static const double _nameLineHeight = 1.2;

  /// The strip's height at the reader's text size: ~110 at 100 %. Two
  /// pixels of slack keep a name's rounded line box from overflowing.
  static double heightFor(BuildContext context) =>
      topPadding +
      MomentCircle.circle +
      nameGap +
      MediaQuery.textScalerOf(context).scale(nameSize) * _nameLineHeight +
      2 +
      bottomPadding;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final record = onRecord;
    final offset = record == null ? 0 : 1;
    final edge =
        gutter - (MomentCircle.itemWidthFor(context) - MomentCircle.circle) / 2;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: copy.text("Authors' Moments", 'Momenty autorów'),
      child: SizedBox(
        height: heightFor(context),
        child: ListView.separated(
          key: const ValueKey<String>('moments-author-circles'),
          scrollDirection: Axis.horizontal,
          padding: EdgeInsetsDirectional.only(
            start: edge < 0 ? 0 : edge,
            end: edge < 0 ? 0 : edge,
            top: topPadding,
            bottom: bottomPadding,
          ),
          itemCount: chains.length + offset,
          separatorBuilder: (context, index) => const SizedBox(width: itemGap),
          itemBuilder: (context, index) {
            if (record != null && index == 0) {
              return MomentRecordCircle(
                key: const ValueKey<String>('moments-circle-record'),
                onTap: record,
                viewerUid: viewerUid,
                viewerName: viewerName,
              );
            }
            final chain = chains[index - offset];
            final own = viewerUid != null && chain.authorId == viewerUid;
            if (own) {
              return MomentCircle(
                key: ValueKey<String>('moments-circle-${chain.authorId}'),
                name: copy.text('You', 'Ty'),
                seen: true,
                own: true,
                userId: chain.authorId,
                photoUrl: chain.authorPhotoUrl,
                semanticLabel: chain.length > 1
                    ? copy.template(
                        'Open your story chain, {count} Moments',
                        'Otwórz swoją relację, Momenty: {count}',
                        values: <String, Object>{'count': chain.length},
                      )
                    : copy.text(
                        'Open your story chain',
                        'Otwórz swoją relację',
                      ),
                onTap: () => onOpenChain(chain),
              );
            }
            final seen = !chain.hasUnviewed(viewedIds);
            return MomentCircle(
              key: ValueKey<String>('moments-circle-${chain.authorId}'),
              name: chain.authorName,
              seen: seen,
              userId: chain.authorId,
              photoUrl: chain.authorPhotoUrl,
              // The capsule's words, unchanged: the action, then the state.
              semanticLabel: chain.length > 1
                  ? copy.template(
                      'Open the story chain by {name}, {count} Moments',
                      'Otwórz relację użytkownika {name}, Momenty: {count}',
                      values: <String, Object>{
                        'name': chain.authorName,
                        'count': chain.length,
                      },
                    )
                  : copy.template(
                      'Open the story chain by {name}',
                      'Otwórz relację użytkownika {name}',
                      values: <String, Object>{'name': chain.authorName},
                    ),
              onTap: () => onOpenChain(chain),
            );
          },
        ),
      ),
    );
  }
}

/// One author of [MomentCirclesStrip]: a 64 px circle — the ring, a 2 px
/// canvas gap, the avatar — over the name.
class MomentCircle extends StatefulWidget {
  const MomentCircle({
    required this.name,
    required this.seen,
    required this.semanticLabel,
    required this.onTap,
    this.own = false,
    this.userId,
    this.photoUrl,
    super.key,
  });

  final String name;

  /// True once every Moment in the author's chain carries the caller's own
  /// `momentViews` doc. Unknown viewed state arrives as unseen (fail open).
  final bool seen;

  /// What the circle DOES; the heard/unheard phrase is appended here, word
  /// for word the one every Moments surface speaks (not for [own]).
  final String semanticLabel;

  /// The viewer's own chain: "Ty", the quiet line, no heard/unheard state.
  final bool own;
  final VoidCallback onTap;
  final String? userId;
  final String? photoUrl;

  static const double itemWidth = 68;
  static const double circle = 64;
  static const double ringWidth = 3;
  static const double heardRingWidth = 1;
  static const double gap = 2;

  /// The avatar inside the ring: the same in both states (3 + 2 unheard,
  /// 1 + 4 heard).
  static const double avatarDiameter = circle - 2 * (ringWidth + gap);
  static const double heardGap = gap + ringWidth - heardRingWidth;

  /// The painted ring, so a test can read its decoration.
  @visibleForTesting
  static const Key ringKey = ValueKey<String>('moment-circle-ring');

  /// The keyboard focus ring: a 2 px rounded RECTANGLE around the whole
  /// item (circle and name), 2 px outside it — a shape no ring state uses,
  /// so a focused heard circle can never be read as an unheard one.
  static const double focusOutset = 2;
  static const double focusRadius = 16;

  @visibleForTesting
  static const Key focusRingKey = ValueKey<String>('moment-circle-focus');

  /// The item's width at the reader's text size: 68 at 100 %, widening
  /// with the name (92 at 200 %) so a short name still reads whole.
  static double itemWidthFor(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    return itemWidth + (scale - 1) * 24;
  }

  @override
  State<MomentCircle> createState() => _MomentCircleState();
}

class _MomentCircleState extends State<MomentCircle> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final seen = widget.seen || widget.own;
    // The one seen-avatar definition (ADR-155): the brand gradient band
    // (solid primary under high contrast) while unheard; the flat line and
    // a dimmed face once heard. The heard line is 1 px, so the gap inside it
    // grows by the difference and the face keeps its 54 px.
    final ring = MomentSeenAvatar(
      seen: seen,
      diameter: MomentCircle.circle,
      ringWidth: seen ? MomentCircle.heardRingWidth : MomentCircle.ringWidth,
      ringInset: seen ? MomentCircle.heardGap : MomentCircle.gap,
      ringKey: MomentCircle.ringKey,
      userId: widget.userId,
      photoUrl: widget.photoUrl,
      displayName: widget.name,
      fallbackIcon: Icons.person_rounded,
      finish: UserAvatarFinish.brand,
    );
    return _CircleItem(
      semanticLabel: widget.own
          ? widget.semanticLabel
          : '${widget.semanticLabel}, '
                '${MomentSeenAvatar.stateLabel(context, seen: seen)}',
      name: widget.name,
      nameStyle: AppTypography.labelMedium.copyWith(
        fontSize: MomentCirclesStrip.nameSize,
        height: MomentCirclesStrip._nameLineHeight,
        color: widget.own
            ? palette.textSecondary
            : seen
            ? palette.textTertiary
            : palette.textPrimary,
        fontWeight: seen ? FontWeight.w600 : FontWeight.w700,
      ),
      focused: _focused,
      onFocusChange: (value) {
        if (value != _focused) setState(() => _focused = value);
      },
      onTap: widget.onTap,
      circle: ring,
    );
  }
}

/// "Nagraj": the viewer's own face in a quiet hairline ring with the 22 px
/// gradient `+`, opening the existing record-a-Voice-Moment flow — the same
/// entry as the create sheet's "Nagraj Voice Moment".
class MomentRecordCircle extends StatefulWidget {
  const MomentRecordCircle({
    required this.onTap,
    this.viewerUid,
    this.viewerName,
    super.key,
  });

  final VoidCallback onTap;
  final String? viewerUid;
  final String? viewerName;

  static const double badge = 22;

  /// The `+` badge, so a test can read its fill.
  @visibleForTesting
  static const Key badgeKey = ValueKey<String>('moment-record-circle-badge');

  @override
  State<MomentRecordCircle> createState() => _MomentRecordCircleState();
}

class _MomentRecordCircleState extends State<MomentRecordCircle> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final highContrast = MediaQuery.highContrastOf(context);
    final circle = SizedBox.square(
      dimension: MomentCircle.circle,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Container(
            width: MomentCircle.circle,
            height: MomentCircle.circle,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: highContrast ? palette.borderStrong : palette.border,
              ),
            ),
            child: _CircleAvatar(
              userId: widget.viewerUid,
              photoUrl: null,
              displayName: widget.viewerName,
            ),
          ),
          PositionedDirectional(
            end: -2,
            bottom: -2,
            child: Container(
              key: MomentRecordCircle.badgeKey,
              width: MomentRecordCircle.badge,
              height: MomentRecordCircle.badge,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: highContrast ? colors.primary : null,
                gradient: highContrast ? null : AppGradients.primary,
                border: Border.all(color: palette.background, width: 2),
              ),
              child: Icon(Icons.add_rounded, size: 14, color: colors.onPrimary),
            ),
          ),
        ],
      ),
    );
    return _CircleItem(
      semanticLabel: copy.text('Record a Voice Moment', 'Nagraj Voice Moment'),
      name: copy.text('Record', 'Nagraj'),
      nameStyle: AppTypography.labelMedium.copyWith(
        fontSize: MomentCirclesStrip.nameSize,
        height: MomentCirclesStrip._nameLineHeight,
        color: palette.textSecondary,
        fontWeight: FontWeight.w600,
      ),
      focused: _focused,
      onFocusChange: (value) {
        if (value != _focused) setState(() => _focused = value);
      },
      onTap: widget.onTap,
      circle: circle,
    );
  }
}

/// The face inside a circle: the existing avatar resolved by uid, the one
/// letter-avatar fallback, drawn as a graphic that never scales with text.
class _CircleAvatar extends StatelessWidget {
  const _CircleAvatar({
    required this.userId,
    required this.photoUrl,
    required this.displayName,
  });

  final String? userId;
  final String? photoUrl;
  final String? displayName;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: UserAvatar(
        radius: MomentCircle.avatarDiameter / 2,
        userId: userId,
        photoUrl: photoUrl,
        displayName: displayName,
        fallbackIcon: Icons.person_rounded,
        finish: UserAvatarFinish.brand,
      ),
    );
  }
}

/// One strip item: the circle over its name, one atomic button.
class _CircleItem extends StatelessWidget {
  const _CircleItem({
    required this.semanticLabel,
    required this.name,
    required this.nameStyle,
    required this.focused,
    required this.onFocusChange,
    required this.onTap,
    required this.circle,
  });

  final String semanticLabel;
  final String name;
  final TextStyle nameStyle;
  final bool focused;
  final ValueChanged<bool> onFocusChange;
  final VoidCallback onTap;
  final Widget circle;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final width = MomentCircle.itemWidthFor(context);
    return Semantics(
      button: true,
      label: semanticLabel,
      onTap: onTap,
      focusable: true,
      focused: focused,
      excludeSemantics: true,
      child: YoPressFeedback(
        scale: YoPressFeedback.tile,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            onFocusChange: onFocusChange,
            borderRadius: const BorderRadius.all(Radius.circular(16)),
            splashFactory: NoSplash.splashFactory,
            overlayColor: WidgetStateProperty.resolveWith(
              (states) =>
                  states.contains(WidgetState.hovered) ||
                      states.contains(WidgetState.pressed)
                  ? palette.textPrimary.withValues(alpha: .04)
                  : Colors.transparent,
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                SizedBox(
                  width: width,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      SizedBox(
                        width: width,
                        height: MomentCircle.circle,
                        child: Center(child: circle),
                      ),
                      const SizedBox(height: MomentCirclesStrip.nameGap),
                      SizedBox(
                        width: width,
                        child: Text(
                          name,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: nameStyle,
                        ),
                      ),
                    ],
                  ),
                ),
                // The focus ring: a rounded rectangle around the circle AND
                // the name, 2 px outside the item — never another circle
                // next to the ring that carries the heard/unheard state.
                // Always in the tree, so focusing never re-parents the ink.
                Positioned(
                  left: -MomentCircle.focusOutset,
                  top: -MomentCircle.focusOutset,
                  right: -MomentCircle.focusOutset,
                  bottom: -MomentCircle.focusOutset,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      key: MomentCircle.focusRingKey,
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.all(
                          Radius.circular(MomentCircle.focusRadius),
                        ),
                        border: Border.all(
                          color: focused ? palette.focus : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
