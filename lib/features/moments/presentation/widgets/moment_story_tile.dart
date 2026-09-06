import 'dart:async';

import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_gradients.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/moments/data/services/moment_views_service.dart';
import 'package:yovoice/shared/widgets/identity/official_role_badge.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// The ONE compact Voice Moments story tile.
///
/// Every Moments rail draws this widget — the Moments feed's chain strip,
/// mobile Home and desktop Home — so the seen/unseen language cannot drift
/// between them again. Before this widget each surface carried its own
/// disc, ring, badge and label geometry, and the three rings meant three
/// different things.
///
/// THE RING IS THE STATE. A brand gradient means this account has not
/// heard everything in the chain yet; a flat, low-contrast line plus a
/// dimmed avatar means every link was heard. Both facts come from the
/// caller's own `users/{uid}/momentViews` docs through
/// [MomentViewsService] — there is no global "seen" counter anywhere in
/// the schema and none is invented here. Unknown viewed state renders as
/// UNSEEN (fail open): a missed listener must never quietly grey out
/// something the user has not actually heard.
///
/// The Moments ring is deliberately its own language, separate from the
/// thin availability/presence rings in `lib/shared/widgets/profile/`
/// (ADR-147): those describe a person right now, this one describes
/// unheard content.
class MomentStoryTile extends StatelessWidget {
  const MomentStoryTile({
    required this.name,
    required this.seen,
    required this.semanticLabel,
    required this.onTap,
    this.userId,
    this.photoUrl,
    this.mediaRevision,
    this.displayName,
    this.fallbackIcon,
    this.count,
    this.countKey,
    this.caption,
    this.captionHighlighted = false,
    this.identityUid,
    this.showAdd = false,
    this.onAddTap,
    this.online = false,
    this.focusNode,
    this.expandedLabel = false,
    this.width,
    super.key,
  });

  /// The label under the disc. One line, ellipsised, unless
  /// [expandedLabel] gives it the room for two.
  final String name;

  /// True once every Moment behind this tile carries the caller's own
  /// `momentViews` doc.
  final bool seen;

  /// What the tile DOES, for a screen reader. The heard/unheard state is
  /// appended to it here so no caller can forget it.
  final String semanticLabel;

  final VoidCallback onTap;
  final String? userId;
  final String? photoUrl;
  final Object? mediaRevision;
  final String? displayName;
  final IconData? fallbackIcon;

  /// A real chain length (> 1); null hides the badge. Never an estimate.
  final int? count;
  final Key? countKey;

  /// An optional quiet line under the name — the desktop rail's
  /// `New` / duration / chain-count caption.
  final String? caption;
  final bool captionHighlighted;

  /// Renders the authoritative identity badges beside [caption]. Only the
  /// surfaces that already showed them pass a uid.
  final String? identityUid;

  /// Draws the `+` record affordance over the disc's lower-right edge.
  final bool showAdd;
  final VoidCallback? onAddTap;

  /// The author's own `isOnline`, for friends only.
  final bool online;

  final FocusNode? focusNode;

  /// Gives the name two lines and a wider tile — the desktop rail, where
  /// full names are expected to fit rather than ellipsise.
  final bool expandedLabel;

  /// Overrides [widthFor] when a rail needs every tile the same width.
  final double? width;

  static const double _nameSize = 11;
  static const double _captionSize = 10.5;
  static const double _discGap = 6;
  static const double _captionGap = 2;
  static const double _ringWidth = 2.5;
  static const double _ringInset = 2;

  /// The `+` reserves its own 44 pt target beside the playback target;
  /// shrinking that hit area over the avatar's centre turns an ordinary
  /// "play mine" tap into a recording.
  static const double _addTarget = 44;
  static const double _addOverhang = _addTarget - 10;

  /// The ring container, so a widget test can read the painted gradient
  /// instead of eyeballing a screenshot.
  @visibleForTesting
  static const Key ringKey = ValueKey('moment-story-ring');

  /// The outer disc. 60 pt on an ordinary phone, 56 pt once the viewport
  /// is genuinely narrow — clearly smaller than the 66 pt discs these
  /// rails used to draw, and still comfortably inside a 44 pt target.
  static double discFor(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 360 ? 56 : 60;

  /// How much bigger the caller's text preference makes this tile.
  /// Capped at 2x: past that the rail scrolls instead of growing.
  static double textScaleOf(BuildContext context) =>
      (MediaQuery.textScalerOf(context).scale(_nameSize) / _nameSize).clamp(
        1,
        2,
      );

  static double nameHeightFor(BuildContext context, {bool expanded = false}) =>
      MediaQuery.textScalerOf(context).scale(_nameSize) *
          1.16 *
          (expanded ? 2 : 1) +
      2;

  /// At least the 16 pt identity badge, whatever the text scale is.
  static double captionHeightFor(BuildContext context) =>
      (MediaQuery.textScalerOf(context).scale(_captionSize) * 1.25 + 2).clamp(
        16,
        40,
      );

  static double widthFor(
    BuildContext context, {
    bool showAdd = false,
    bool expanded = false,
  }) {
    final grow = (textScaleOf(context) - 1);
    if (showAdd) return discFor(context) + _addOverhang + grow * 24;
    if (expanded) return 128 + grow * 52;
    return discFor(context) + 8 + grow * 24;
  }

  static double heightFor(
    BuildContext context, {
    bool caption = false,
    bool expanded = false,
  }) {
    var height =
        discFor(context) + _discGap + nameHeightFor(context, expanded: expanded);
    if (caption) height += _captionGap + captionHeightFor(context);
    return height;
  }

  /// The two ring stops for a given state — the single definition of the
  /// seen/unseen language, and what the widget tests assert on.
  static List<Color> ringColors(BuildContext context, {required bool seen}) {
    if (!seen) return const [AppColors.primary, AppColors.secondary];
    final quiet = AppPalette.of(context).border;
    return [quiet, quiet];
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final disc = discFor(context);
    final tileWidth =
        width ?? widthFor(context, showAdd: showAdd, expanded: expandedLabel);
    final areaWidth = showAdd ? disc + _addOverhang : disc;
    final discLeft = showAdd ? 0.0 : (areaWidth - disc) / 2;

    final state = seen
        ? copy.text('already heard', 'odsłuchane')
        : copy.text('not heard yet', 'nieodsłuchane');

    return SizedBox(
      width: tileWidth,
      height: heightFor(context, caption: caption != null, expanded: expandedLabel),
      child: Semantics(
        button: true,
        // A tile is one atomic action. The `+` is the exception: it
        // exposes a separate record action and must keep its own node.
        excludeSemantics: !showAdd,
        label: '$semanticLabel, $state',
        child: InkWell(
          focusNode: focusNode,
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: areaWidth,
                height: disc,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: discLeft,
                      top: 0,
                      width: disc,
                      height: disc,
                      child: _ring(context, disc),
                    ),
                    if (online && !showAdd)
                      Positioned(
                        left: discLeft + disc - 15,
                        top: disc - 15,
                        child: Container(
                          width: 13,
                          height: 13,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.success,
                            border: Border.all(
                              color: palette.surfaceSunken,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    if (count != null && count! > 1)
                      Positioned(
                        left: discLeft,
                        top: 0,
                        width: disc,
                        height: disc,
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: _CountBadge(count: count!, badgeKey: countKey),
                        ),
                      ),
                    if (showAdd)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: _AddMomentBadge(onTap: onAddTap),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: _discGap),
              SizedBox(
                width: double.infinity,
                height: nameHeightFor(context, expanded: expandedLabel),
                child: Center(
                  child: Text(
                    name,
                    maxLines: expandedLabel ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: expandedLabel,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      // Seen stays readable: it is quieter through the
                      // ring and the dimmed avatar, never through copy
                      // nobody can make out.
                      color: seen ? palette.textSecondary : palette.textPrimary,
                      fontSize: _nameSize,
                      height: 1.08,
                      fontWeight: seen ? FontWeight.w600 : FontWeight.w700,
                    ),
                  ),
                ),
              ),
              if (caption != null) ...[
                const SizedBox(height: _captionGap),
                SizedBox(
                  height: captionHeightFor(context),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (identityUid != null) ...[
                        UserIdentityBadges(
                          uid: identityUid!,
                          variant: IdentityBadgeVariant.icon,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Flexible(
                        child: Text(
                          caption!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: captionHighlighted
                                ? Theme.of(context).colorScheme.secondary
                                : palette.textSecondary,
                            fontSize: _captionSize,
                            fontWeight: captionHighlighted
                                ? FontWeight.w800
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _ring(BuildContext context, double disc) {
    final palette = context.appPalette;
    return Container(
      key: ringKey,
      width: disc,
      height: disc,
      padding: const EdgeInsets.all(_ringWidth),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // One gradient in both states so the geometry cannot shift when a
        // tile flips from unheard to heard; only the stops change.
        gradient: seen
            ? LinearGradient(colors: ringColors(context, seen: true))
            : AppGradients.primary,
      ),
      child: Container(
        padding: const EdgeInsets.all(_ringInset),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: palette.surfaceSunken,
        ),
        child: Opacity(
          opacity: seen ? .62 : 1,
          // The initial inside an avatar is a GRAPHIC sized off the disc,
          // not copy: at 200 % text it grew past the circle and was
          // clipped mid-glyph. The name under the tile and the semantic
          // label both scale normally, so nothing readable is lost.
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.noScaling),
            child: UserAvatar(
              radius: (disc - (_ringWidth + _ringInset) * 2) / 2,
              userId: userId,
              photoUrl: photoUrl,
              mediaRevision: mediaRevision,
              displayName: displayName,
              fallbackIcon: fallbackIcon,
            ),
          ),
        ),
      ),
    );
  }
}

/// A real chain length, never an estimate: how many live Moments this
/// author has behind one tile.
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, this.badgeKey});

  final int count;
  final Key? badgeKey;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: badgeKey,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: LinearGradient(colors: [colors.primary, colors.secondary]),
        border: Border.all(color: palette.surfaceSunken, width: 1.5),
      ),
      child: Text(
        '$count',
        maxLines: 1,
        // Barely scaled on purpose: the same count is spelled out in the
        // tile's semantic label, so the pill stays a mark on the disc
        // instead of swallowing the avatar at 200 % text.
        textScaler: MediaQuery.textScalerOf(
          context,
        ).clamp(maxScaleFactor: 1.2),
        style: TextStyle(
          color: colors.onPrimary,
          fontSize: 10,
          height: 1.1,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// The `+` on your own tile. A nested tap target inside the tile's own
/// InkWell: the innermost recognizer wins, so the badge means "record"
/// while every other pixel of the tile means "play mine".
class _AddMomentBadge extends StatelessWidget {
  const _AddMomentBadge({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final dot = Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppGradients.primary,
        border: Border.all(color: palette.surfaceSunken, width: 2),
      ),
      child: const Icon(Icons.add_rounded, size: 13, color: Colors.white),
    );
    if (onTap == null) {
      return SizedBox(
        width: MomentStoryTile._addTarget,
        height: MomentStoryTile._addTarget,
        child: Align(alignment: Alignment.bottomLeft, child: dot),
      );
    }
    final copy = AppLocalizations.of(context);
    final label = copy.text('Record a Voice Moment', 'Nagraj Voice Moment');
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: InkWell(
          key: const ValueKey('home-record-moment'),
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: MomentStoryTile._addTarget,
            height: MomentStoryTile._addTarget,
            child: Align(alignment: Alignment.bottomLeft, child: dot),
          ),
        ),
      ),
    );
  }
}

/// Supplies the caller's own viewed-Moment ids to a Moments rail.
///
/// ONE listener over `users/{uid}/momentViews`, exactly as
/// `MomentsFeedView` opens it, with the same fail-open contract: a service
/// that cannot be constructed, a stream that errors, or a signed-out
/// account all leave the set empty, so every tile reads as UNHEARD rather
/// than the rail going grey — or down — on a data failure.
///
/// Pass [viewedIds] when the surrounding surface already owns the set; the
/// builder then subscribes to nothing and no second listener is opened.
class MomentViewedIds extends StatefulWidget {
  const MomentViewedIds({
    required this.builder,
    this.service,
    this.viewedIds,
    super.key,
  });

  final Widget Function(BuildContext context, Set<String> viewedIds) builder;

  /// Test seam; production passes nothing and one is constructed here.
  final MomentViewsService? service;

  /// An already-resolved set. Non-null disables the subscription.
  final Set<String>? viewedIds;

  @override
  State<MomentViewedIds> createState() => _MomentViewedIdsState();
}

class _MomentViewedIdsState extends State<MomentViewedIds> {
  StreamSubscription<Set<String>>? _subscription;
  Set<String> _viewedIds = const <String>{};

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant MomentViewedIds oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service ||
        (oldWidget.viewedIds == null) != (widget.viewedIds == null)) {
      unawaited(_subscription?.cancel());
      _subscription = null;
      _subscribe();
    }
  }

  void _subscribe() {
    if (widget.viewedIds != null) return;
    try {
      final service = widget.service ?? MomentViewsService();
      _subscription = service.watchViewedMomentIds().listen(
        (ids) {
          if (mounted) setState(() => _viewedIds = ids);
        },
        onError: (Object _) {
          // Unknown viewed state renders as unheard — strictly better
          // than greying out something nobody has played.
        },
      );
    } catch (_) {
      // No session, or a preview/test harness with no Firebase app: the
      // rail still renders, every tile unheard.
      _subscription = null;
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, widget.viewedIds ?? _viewedIds);
}
