import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/moments/data/models/moment_chain.dart';
import 'package:yovoice/features/profile/data/models/follow_user.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_expiry_accessibility.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/shared/widgets/identity/official_role_badge.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// "Moments from your circle" — the desktop Home strip that sits between
/// the greeting and Live around you.
///
/// DATA: [HomeFeedService.watchSocialMoments] — the same stream the
/// Moments destination and mobile Home already read. It emits published
/// Voice Moments newest first. Presentation then keeps only the signed-in
/// user and followed authors with playable audio. Friend data contributes
/// a verified online dot only; it never creates a story tile.
///
/// One tile per PERSON (their newest Moment), so a prolific poster cannot
/// push everyone else out of the strip.
///
/// STATE HONESTY: `voiceMoments` documents carry no per-viewer "seen"
/// flag, and a Moment is recorded audio — it is never "live". So the ring
/// and the "New" label both mean exactly one thing the data can prove:
/// posted in the last 24 hours. Everything older shows its real duration
/// instead. See docs/Decisions.md ADR-036.
class DesktopMomentsStrip extends StatefulWidget {
  const DesktopMomentsStrip({
    required this.onOpenMoment,
    required this.onCreateMoment,
    required this.onSeeAll,
    this.onOpenChain,
    this.profile,
    this.feedService,
    this.friendService,
    this.followService,
    this.currentUserId,
    this.expiryClock,
    super.key,
  });

  /// Opens ONE Moment in the player, the same surface mobile Home and the
  /// Moments destination open. It used to open the comments screen, which
  /// has no player at all — so tapping a face on Home was the one place in
  /// the app where you could not hear the Moment you tapped.
  final ValueChanged<VoiceMoment> onOpenMoment;

  /// Opens the signed-in user's whole ACTIVE chain in the story viewer —
  /// every live Moment, oldest first, not just the newest. Optional so
  /// existing callers keep working; when null the tile falls back to
  /// [onOpenMoment] with the newest.
  final ValueChanged<List<VoiceMoment>>? onOpenChain;

  /// The existing Moment creation flow (RecordVoiceMomentScreen).
  final VoidCallback onCreateMoment;

  /// Moments, inside the fixed desktop shell (content slot, not a route).
  final VoidCallback onSeeAll;

  /// The signed-in profile, shared with the rest of Home rather than
  /// opening a second listener for one avatar.
  final Stream<UserProfile>? profile;

  final HomeFeedService? feedService;

  /// Presence for followed authors who are also friends. Friend edges never
  /// create a tile on their own.
  final FriendService? friendService;

  /// The relationship gate for this rail. The strip does not mutate follows.
  final FollowService? followService;

  /// The signed-in uid, used to read who this account already follows.
  final String? currentUserId;

  /// Uses the same instant as an injected [HomeFeedService] in widget tests.
  final DateTime Function()? expiryClock;

  /// A Moment counts as "new" for a day after it is posted.
  static const Duration newWindow = Duration(hours: 24);

  @override
  State<DesktopMomentsStrip> createState() => _DesktopMomentsStripState();
}

class _DesktopMomentsStripState extends State<DesktopMomentsStrip> {
  Stream<List<VoiceMoment>>? _moments;
  Stream<List<FriendUser>>? _friends;
  Stream<List<FollowUser>>? _following;

  static const double _tileGap = 14;

  @override
  void initState() {
    super.initState();
    try {
      _moments = (widget.feedService ?? HomeFeedService()).watchSocialMoments();
    } catch (_) {
      // No session (or a preview harness): the strip renders its empty
      // state rather than throwing inside the shell.
    }
    try {
      _friends = (widget.friendService ?? FriendService()).watchFriends();
    } catch (_) {
      _friends = null;
    }
    try {
      final follow = widget.followService ?? FollowService();
      _following = follow.watchFollowing(widget.currentUserId ?? '');
    } catch (_) {
      _following = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return StreamBuilder<UserProfile>(
      stream: widget.profile,
      builder: (context, profileSnapshot) {
        final profile = profileSnapshot.data;

        return StreamBuilder<List<FriendUser>>(
          stream: _friends,
          builder: (context, friendSnapshot) {
            final friends = friendSnapshot.data ?? const <FriendUser>[];
            // Presence is the friend document's own `isOnline`; nobody
            // gets a dot who is not actually marked online.
            final online = {
              for (final friend in friends)
                if (friend.isOnline) friend.id,
            };

            return StreamBuilder<List<FollowUser>>(
              stream: _following,
              builder: (context, followingSnapshot) {
                final followed = {
                  for (final user
                      in followingSnapshot.data ?? const <FollowUser>[])
                    user.uid,
                };
                return StreamBuilder<List<VoiceMoment>>(
                  stream: _moments,
                  builder: (context, snapshot) {
                    final all = snapshot.data ?? const <VoiceMoment>[];
                    final playable = all
                        .where((moment) => moment.hasMediaReference)
                        .toList(growable: false);
                    final chains = buildMomentChains(playable);
                    final explicitUserId = widget.currentUserId?.trim();
                    final ownUserId = explicitUserId?.isNotEmpty == true
                        ? explicitUserId!
                        : (profile?.uid ?? '');
                    MomentChain? mine;
                    for (final chain in chains) {
                      if (chain.authorId == ownUserId) {
                        mine = chain;
                        break;
                      }
                    }
                    final others = chains
                        .where(
                          (chain) =>
                              chain.authorId != ownUserId &&
                              followed.contains(chain.authorId),
                        )
                        .toList(growable: false);
                    final shown = others.take(7).toList(growable: false);
                    final visibleMoments = <VoiceMoment>[
                      ...?mine?.moments,
                      for (final chain in shown) ...chain.moments,
                    ];

                    return MomentExpiryListTransition(
                      // Expiry announcements and focus recovery must describe
                      // only tiles that are actually present in this rail.
                      moments: visibleMoments,
                      clock: widget.expiryClock ?? DateTime.now,
                      transitionScope: 'desktop-home-moments',
                      announcementBuilder: (count) => count == 1
                          ? copy.text(
                              'One Voice Moment expired and was removed from Home.',
                              'Jeden Voice Moment wygasł i został usunięty ze strony głównej.',
                            )
                          : copy.text(
                              '$count Voice Moments expired and were removed from Home.',
                              '$count Voice Momentów wygasło i zostało usuniętych ze strony głównej.',
                            ),
                      builder: (context, recoveryFocus, tileFocusNode) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _StripHeading(
                              expiryRecoveryFocus: recoveryFocus,
                              onSeeAll: widget.onSeeAll,
                              // Nothing to "see all" of until the circle has posted.
                              showSeeAll: others.isNotEmpty || mine != null,
                            ),
                            LayoutBuilder(
                              builder: (context, _) {
                                final tileHeight = _MomentTile.heightFor(
                                  context,
                                );

                                final tiles = <Widget>[
                                  _YourMomentTile(
                                    profile: profile,
                                    mine:
                                        mine?.moments ?? const <VoiceMoment>[],
                                    focusNode: mine == null
                                        ? null
                                        : tileFocusNode(mine.moments.last.id),
                                    onCreate: widget.onCreateMoment,
                                    onOpen: widget.onOpenMoment,
                                    onOpenChain: widget.onOpenChain,
                                  ),
                                  for (final chain in shown)
                                    _MomentTile(
                                      key: ValueKey(
                                        'desktop-home-moment-${chain.moments.last.id}',
                                      ),
                                      moment: chain.moments.last,
                                      chainLength: chain.length,
                                      focusNode: tileFocusNode(
                                        chain.moments.last.id,
                                      ),
                                      onTap: widget.onOpenChain == null
                                          ? () => widget.onOpenMoment(
                                              chain.moments.last,
                                            )
                                          : () => widget.onOpenChain!(
                                              chain.moments,
                                            ),
                                      online: online.contains(chain.authorId),
                                    ),
                                ];

                                // One compact story rail. Every avatar after the
                                // signed-in user is followed and has playable audio.
                                return SizedBox(
                                  height: tileHeight,
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      children: [
                                        for (
                                          var i = 0;
                                          i < tiles.length;
                                          i++
                                        ) ...[
                                          if (i > 0)
                                            const SizedBox(width: _tileGap),
                                          tiles[i],
                                        ],
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class _StripHeading extends StatelessWidget {
  const _StripHeading({
    required this.expiryRecoveryFocus,
    required this.onSeeAll,
    required this.showSeeAll,
  });

  final FocusNode expiryRecoveryFocus;
  final VoidCallback onSeeAll;
  final bool showSeeAll;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: MomentExpiryFocusTarget(
              key: const ValueKey('desktop-home-moments-heading'),
              focusNode: expiryRecoveryFocus,
              semanticLabel: copy.text(
                'Moments from your circle',
                'Momenty z Twojego kręgu',
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  copy.text(
                    'Moments from your circle',
                    'Momenty z Twojego kręgu',
                  ),
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
          if (showSeeAll)
            TextButton(
              onPressed: onSeeAll,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(44, 44),
                tapTargetSize: MaterialTapTargetSize.padded,
                foregroundColor: colors.primary,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    copy.text('See all', 'Zobacz wszystkie'),
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 3),
                  const Icon(Icons.chevron_right_rounded, size: 16),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The violet→magenta ring that marks a Moment posted in the last day.
/// Unringed avatars are not "seen" — they are simply older; the schema
/// has no viewed state to draw.
class _MomentRing extends StatelessWidget {
  const _MomentRing({required this.child, required this.highlighted});

  final Widget child;
  final bool highlighted;

  /// Sized to the 25pt avatars the strip uses, plus the ring and its
  /// inset — one constant so every tile lines up.
  static const double size = 58;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Container(
      width: size + 8,
      height: size + 8,
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: highlighted
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primary, AppColors.secondary],
              )
            : null,
        border: highlighted
            ? null
            : Border.all(color: palette.border, width: 1.4),
      ),
      child: Container(
        padding: const EdgeInsets.all(2),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: palette.surfaceSunken,
        ),
        child: child,
      ),
    );
  }
}

class _MomentTile extends StatelessWidget {
  const _MomentTile({
    required this.moment,
    required this.focusNode,
    required this.onTap,
    this.chainLength = 1,
    this.online = false,
    super.key,
  });

  final VoiceMoment moment;
  final FocusNode focusNode;
  final VoidCallback onTap;
  final int chainLength;

  /// The author's own `isOnline`, for friends only — the rail never
  /// guesses presence for someone it cannot read it for.
  final bool online;

  /// Names get the full width of the tile and can wrap to two lines. The
  /// tile also grows with accessibility text scaling instead of forcing a
  /// larger label back into the old compact geometry.
  static double _textScale(BuildContext context) =>
      (MediaQuery.textScalerOf(context).scale(11.5) / 11.5).clamp(1, 2);

  static double widthFor(BuildContext context) =>
      136 + ((_textScale(context) - 1) * 40);

  static double heightFor(BuildContext context) =>
      128 + ((_textScale(context) - 1) * 40);

  static double nameHeightFor(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(11.5) * 1.08 * 2 + 4;

  static double actionHeightFor(BuildContext context) =>
      (MediaQuery.textScalerOf(context).scale(10.5) * 1.25 + 4).clamp(20, 34);

  bool get _isNew {
    final createdAt = moment.createdAt;
    if (createdAt == null) return false;
    return DateTime.now().difference(createdAt) < DesktopMomentsStrip.newWindow;
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final fresh = _isNew;
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;

    return SizedBox(
      width: widthFor(context),
      height: heightFor(context),
      child: Semantics(
        button: true,
        excludeSemantics: true,
        label: chainLength == 1
            ? copy.text(
                'Play Voice Moment from ${moment.authorName}',
                'Odtwórz Voice Moment użytkownika ${moment.authorName}',
              )
            : copy.text(
                'Play $chainLength Voice Moments from ${moment.authorName}',
                'Odtwórz $chainLength Voice Momentów użytkownika ${moment.authorName}',
              ),
        child: InkWell(
          focusNode: focusNode,
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PresenceDot(
                online: online,
                child: _MomentRing(
                  highlighted: fresh,
                  child: UserAvatar(
                    radius: 25,
                    userId: moment.authorId,
                    photoUrl: moment.authorPhotoUrl,
                    displayName: moment.authorName,
                  ),
                ),
              ),
              const SizedBox(height: 7),
              _MomentNameLabel(name: moment.authorName),
              const SizedBox(height: 2),
              SizedBox(
                height: actionHeightFor(context),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    UserIdentityBadges(
                      uid: moment.authorId,
                      variant: IdentityBadgeVariant.icon,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      // Both are facts the document carries: freshly posted,
                      // or exactly how long the recording runs.
                      fresh ? copy.text('New', 'Nowy') : moment.durationLabel,
                      maxLines: 1,
                      style: TextStyle(
                        color: fresh ? colors.secondary : palette.textSecondary,
                        fontSize: 10.5,
                        fontWeight: fresh ? FontWeight.w800 : FontWeight.w600,
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

/// A stable two-line name slot shared by Moment and follow suggestions.
/// Keeping the identity mark out of this row means ordinary full names no
/// longer lose a quarter of their width to a badge.
class _MomentNameLabel extends StatelessWidget {
  const _MomentNameLabel({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return SizedBox(
      width: double.infinity,
      height: _MomentTile.nameHeightFor(context),
      child: Center(
        child: Text(
          name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          softWrap: true,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: palette.textPrimary,
            fontSize: 11.5,
            height: 1.08,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// A green dot on the ring, and only when presence says so.
class _PresenceDot extends StatelessWidget {
  const _PresenceDot({required this.child, required this.online});

  final Widget child;
  final bool online;

  @override
  Widget build(BuildContext context) {
    if (!online) return child;
    final palette = context.appPalette;
    return Stack(
      children: [
        child,
        Positioned(
          right: 3,
          bottom: 3,
          child: Container(
            width: 13,
            height: 13,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF22C55E),
              border: Border.all(color: palette.surfaceSunken, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

/// The signed-in user's slot. Opens their ACTIVE CHAIN — every live
/// Moment, as a story — when they have any; the small plus always opens
/// the existing creation flow, with any number of Moments already live
/// (many active Moments per user is the product; the 10-at-once cap is
/// the server's rule, enforced at reserve time, never pre-guessed here).
///
/// THE WHOLE TILE is the target, not just the 66 pt disc. Every other
/// tile in this rail already wrapped its column in one [InkWell], while
/// this one wrapped only the avatar: the name "Your Moment" and the
/// "New" / duration line under it were dead pixels, so a click that
/// landed a few pixels low did nothing at all. That asymmetry is the
/// reported "clicking my own avatar does nothing" — reproduced in a
/// widget test before it was changed, and pinned by one after.
class _YourMomentTile extends StatelessWidget {
  const _YourMomentTile({
    required this.profile,
    required this.mine,
    required this.focusNode,
    required this.onCreate,
    required this.onOpen,
    required this.onOpenChain,
  });

  final UserProfile? profile;

  /// The signed-in user's live Moments, oldest first (story order).
  /// Empty when nothing is live right now.
  final List<VoiceMoment> mine;
  final FocusNode? focusNode;
  final VoidCallback onCreate;
  final ValueChanged<VoiceMoment> onOpen;
  final ValueChanged<List<VoiceMoment>>? onOpenChain;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final newest = mine.isEmpty ? null : mine.last;
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final fresh =
        newest?.createdAt != null &&
        DateTime.now().difference(newest!.createdAt!) <
            DesktopMomentsStrip.newWindow;

    return SizedBox(
      width: _MomentTile.widthFor(context),
      height: _MomentTile.heightFor(context),
      child: Semantics(
        button: true,
        label: newest == null
            ? copy.text(
                'Record your first Voice Moment',
                'Nagraj swój pierwszy Voice Moment',
              )
            : (mine.length > 1
                  ? copy.text(
                      'Play your ${mine.length} Voice Moments',
                      _polishPlayOwnMomentsLabel(mine.length),
                    )
                  : copy.text(
                      'Play your Voice Moment',
                      'Odtwórz swój Voice Moment',
                    )),
        child: InkWell(
          key: const ValueKey('home-your-moment'),
          focusNode: focusNode,
          onTap: newest == null
              ? onCreate
              : (onOpenChain != null
                    ? () => onOpenChain!(mine)
                    : () => onOpen(newest)),
          borderRadius: BorderRadius.circular(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 99,
                height: _MomentRing.size + 8,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _MomentRing(
                        highlighted: fresh,
                        child: UserAvatar(
                          radius: 25,
                          userId: profile?.uid,
                          photoUrl: profile?.photoUrl,
                          mediaRevision: profile?.profileUpdatedAt,
                          displayName: profile?.displayName,
                          fallbackIcon: Icons.person_rounded,
                        ),
                      ),
                    ),
                    // The chain badge: how many of YOUR Moments are live
                    // right now — a real count from the same stream that
                    // renders them, never an estimate.
                    if (mine.length > 1)
                      Positioned(
                        left: -1,
                        top: -1,
                        child: Container(
                          key: const ValueKey('home-your-moment-count'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            gradient: LinearGradient(
                              colors: [colors.primary, colors.secondary],
                            ),
                            border: Border.all(
                              color: palette.surfaceSunken,
                              width: 2,
                            ),
                          ),
                          child: Text(
                            '${mine.length}',
                            style: TextStyle(
                              color: colors.onPrimary,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    // Nested inside the tile's own InkWell on purpose: the
                    // innermost recognizer wins the tap, so the plus still
                    // means "record" while every other pixel of the tile
                    // means "play mine".
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Tooltip(
                        message: copy.text(
                          'Record a Voice Moment',
                          'Nagraj Voice Moment',
                        ),
                        child: InkWell(
                          key: const ValueKey('home-record-moment'),
                          onTap: onCreate,
                          customBorder: const CircleBorder(),
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: Align(
                              alignment: Alignment.bottomLeft,
                              child: Container(
                                width: 22,
                                height: 22,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: const LinearGradient(
                                    colors: [
                                      AppColors.primary,
                                      AppColors.secondary,
                                    ],
                                  ),
                                  border: Border.all(
                                    color: palette.surfaceSunken,
                                    width: 2,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.add_rounded,
                                  size: 13,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 7),
              _MomentNameLabel(name: copy.text('Your Moment', 'Twój Moment')),
              const SizedBox(height: 2),
              SizedBox(
                height: _MomentTile.actionHeightFor(context),
                child: Center(
                  child: Text(
                    newest == null
                        ? copy.text('Record', 'Nagraj')
                        : (mine.length > 1
                              ? copy.text(
                                  '${mine.length} Moments',
                                  _polishMomentCountLabel(mine.length),
                                )
                              : (fresh
                                    ? copy.text('New', 'Nowy')
                                    : newest.durationLabel)),
                    maxLines: 1,
                    style: TextStyle(
                      color: newest == null || !fresh
                          ? palette.textSecondary
                          : colors.secondary,
                      fontSize: 10.5,
                      fontWeight: fresh ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _polishPlayOwnMomentsLabel(int count) {
  final form = _polishMomentNoun(count);
  final possessive = form == 'Momenty' ? 'swoje' : 'swoich';
  return 'Odtwórz $possessive $count Voice $form';
}

String _polishMomentCountLabel(int count) =>
    '$count ${_polishMomentNoun(count)}';

String _polishMomentNoun(int count) {
  if (count == 1) return 'Moment';
  final lastTwoDigits = count % 100;
  final lastDigit = count % 10;
  if (lastDigit >= 2 &&
      lastDigit <= 4 &&
      (lastTwoDigits < 12 || lastTwoDigits > 14)) {
    return 'Momenty';
  }
  return 'Momentów';
}
