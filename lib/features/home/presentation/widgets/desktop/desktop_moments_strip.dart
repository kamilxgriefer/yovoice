import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/profile/data/models/follow_user.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/shared/widgets/identity/official_role_badge.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// "Moments from your circle" — the desktop Home strip that sits between
/// the greeting and Live around you.
///
/// DATA: [HomeFeedService.watchSocialMoments] — the same stream the
/// Moments destination and mobile Home already read. It emits published
/// Voice Moments whose author is the signed-in user, one of their
/// friends (`users/{uid}/friends`) or someone they follow
/// (`users/{uid}/following`), newest first. Nothing here queries anything
/// else, and nobody is shown who is not in one of those three sets.
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
    required this.onDiscover,
    this.profile,
    this.feedService,
    this.friendService,
    this.followService,
    this.onOpenProfile,
    this.currentUserId,
    super.key,
  });

  /// Opens the existing Moment viewer (MomentCommentsScreen), the same
  /// one mobile Home and the Moments destination open.
  final ValueChanged<VoiceMoment> onOpenMoment;

  /// The existing Moment creation flow (RecordVoiceMomentScreen).
  final VoidCallback onCreateMoment;

  /// Moments, inside the fixed desktop shell (content slot, not a route).
  final VoidCallback onSeeAll;

  /// Empty state's single action — Discover, also a content slot.
  final VoidCallback onDiscover;

  /// The signed-in profile, shared with the rest of Home rather than
  /// opening a second listener for one avatar.
  final Stream<UserProfile>? profile;

  final HomeFeedService? feedService;

  /// Presence and the people this account already knows — the source for
  /// both the online dots and the follow segment.
  final FriendService? friendService;

  /// The existing follow service. The rail never writes a follow itself;
  /// it calls the same service the profile screens do.
  final FollowService? followService;

  /// Opens someone's profile preview. Optional: without it a person tile
  /// still shows, it just does not navigate.
  final ValueChanged<String>? onOpenProfile;

  /// The signed-in uid, used to read who this account already follows.
  final String? currentUserId;

  /// A Moment counts as "new" for a day after it is posted.
  static const Duration newWindow = Duration(hours: 24);

  @override
  State<DesktopMomentsStrip> createState() => _DesktopMomentsStripState();
}

class _DesktopMomentsStripState extends State<DesktopMomentsStrip> {
  Stream<List<VoiceMoment>>? _moments;
  Stream<List<FriendUser>>? _friends;
  Stream<List<FollowUser>>? _following;
  FollowService? _follow;

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
      _follow = widget.followService ?? FollowService();
      _following = _follow!.watchFollowing(widget.currentUserId ?? '');
    } catch (_) {
      _follow = null;
      _following = null;
    }
  }

  /// Newest Moment per author, newest author first — the signed-in user
  /// excluded, because they already own the leading "Your Moment" tile.
  List<VoiceMoment> _newestPerAuthor(List<VoiceMoment> moments, String? me) {
    final seen = <String>{};
    final result = <VoiceMoment>[];
    for (final moment in moments) {
      if (moment.authorId.isEmpty || moment.authorId == me) continue;
      if (!seen.add(moment.authorId)) continue;
      result.add(moment);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
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
                // The segment past the divider: people this account
                // already knows but has not followed yet. Real people
                // from a real edge — never an invented suggestion.
                final toFollow = friends
                    .where(
                      (friend) =>
                          friend.id != profile?.uid &&
                          !followed.contains(friend.id),
                    )
                    .take(2)
                    .toList(growable: false);

                return StreamBuilder<List<VoiceMoment>>(
                  stream: _moments,
                  builder: (context, snapshot) {
                    final all = snapshot.data ?? const <VoiceMoment>[];
                    final mine = all
                        .where((moment) => moment.authorId == profile?.uid)
                        .toList(growable: false);
                    final others = _newestPerAuthor(all, profile?.uid);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _StripHeading(
                          onSeeAll: widget.onSeeAll,
                          // Nothing to "see all" of until the circle has posted.
                          showSeeAll: others.isNotEmpty || mine.isNotEmpty,
                          onDiscover: widget.onDiscover,
                          showDiscover:
                              others.isNotEmpty || toFollow.isNotEmpty,
                        ),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final tileWidth = _MomentTile.widthFor(context);
                            final tileHeight = _MomentTile.heightFor(context);
                            // "Your Moment" always holds the first slot; the rest
                            // of the width decides how many people fit, capped at
                            // the 8 the composition is designed around.
                            final fits =
                                ((constraints.maxWidth + _tileGap) /
                                        (tileWidth + _tileGap))
                                    .floor();
                            final capacity = (fits - 1).clamp(0, 7);
                            final shown = others
                                .take(capacity)
                                .toList(growable: false);

                            final tiles = <Widget>[
                              _YourMomentTile(
                                profile: profile,
                                newest: mine.isEmpty ? null : mine.first,
                                onCreate: widget.onCreateMoment,
                                onOpen: widget.onOpenMoment,
                              ),
                              for (final moment in shown)
                                _MomentTile(
                                  moment: moment,
                                  onTap: () => widget.onOpenMoment(moment),
                                  online: online.contains(moment.authorId),
                                ),
                            ];

                            // Nothing from the circle and nobody to follow: the
                            // quiet state fills the band rather than leaving it
                            // blank.
                            if (others.isEmpty && toFollow.isEmpty) {
                              return SizedBox(
                                height: tileHeight,
                                child: Row(
                                  children: [
                                    tiles.first,
                                    const SizedBox(width: 14),
                                    Expanded(
                                      flex: 3,
                                      child: _CircleQuietState(
                                        onDiscover: widget.onDiscover,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            // ONE row, packed from the left: people you can hear,
                            // then the divider, then people you could follow. A
                            // Flexible list here let the follow segment drift to
                            // the far edge with a gap in the middle.
                            return SizedBox(
                              height: tileHeight,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    for (var i = 0; i < tiles.length; i++) ...[
                                      if (i > 0)
                                        const SizedBox(width: _tileGap),
                                      tiles[i],
                                    ],
                                    if (toFollow.isNotEmpty) ...[
                                      const _RailDivider(),
                                      for (
                                        var i = 0;
                                        i < toFollow.length;
                                        i++
                                      ) ...[
                                        if (i > 0)
                                          const SizedBox(width: _tileGap),
                                        _FollowablePersonTile(
                                          person: toFollow[i],
                                          follow: _follow,
                                          onOpenProfile: widget.onOpenProfile,
                                        ),
                                      ],
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
  }
}

/// The hairline between "people whose Moments you can hear" and "people
/// you could follow" — two different offers, one rail.
class _RailDivider extends StatelessWidget {
  const _RailDivider();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 52,
    margin: const EdgeInsets.symmetric(horizontal: 16),
    color: const Color(0xFF2E2140),
  );
}

class _StripHeading extends StatelessWidget {
  const _StripHeading({
    required this.onSeeAll,
    required this.showSeeAll,
    required this.onDiscover,
    required this.showDiscover,
  });

  final VoidCallback onSeeAll;
  final bool showSeeAll;

  final VoidCallback onDiscover;

  /// False only when the empty state is showing, which carries the same
  /// action itself — the rail must never offer `Find creators` twice.
  final bool showDiscover;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'People & Moments',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (showDiscover)
            TextButton(
              onPressed: onDiscover,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Find creators',
                    style: TextStyle(
                      color: Color(0xFFD3A5FF),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(width: 3),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: Color(0xFFD3A5FF),
                  ),
                ],
              ),
            ),
          if (showSeeAll)
            TextButton(
              onPressed: onSeeAll,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'See all',
                    style: TextStyle(
                      color: Color(0xFFD3A5FF),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(width: 3),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: Color(0xFFD3A5FF),
                  ),
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
            : Border.all(color: const Color(0xFF2E2140), width: 1.4),
      ),
      child: Container(
        padding: const EdgeInsets.all(2),
        clipBehavior: Clip.antiAlias,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFF0C0814),
        ),
        child: child,
      ),
    );
  }
}

class _MomentTile extends StatelessWidget {
  const _MomentTile({
    required this.moment,
    required this.onTap,
    this.online = false,
  });

  final VoiceMoment moment;
  final VoidCallback onTap;

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
    final fresh = _isNew;

    return SizedBox(
      width: widthFor(context),
      height: heightFor(context),
      child: InkWell(
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
                    fresh ? 'New' : moment.durationLabel,
                    maxLines: 1,
                    style: TextStyle(
                      color: fresh
                          ? const Color(0xFFE879F9)
                          : const Color(0xFF9A90AC),
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
          style: const TextStyle(
            color: Colors.white,
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
              border: Border.all(color: const Color(0xFF0C0814), width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

/// Someone this account already knows but has not followed yet.
///
/// The VIP mark reads `premiumIdentity` off their user document — the
/// server-written mirror Cloud Functions maintain, never a flag this
/// client decides. Following goes through the same [FollowService] the
/// profile screens use, so the write, its transaction and its rules are
/// the existing ones.
class _FollowablePersonTile extends StatefulWidget {
  const _FollowablePersonTile({
    required this.person,
    required this.follow,
    required this.onOpenProfile,
  });

  final FriendUser person;
  final FollowService? follow;
  final ValueChanged<String>? onOpenProfile;

  @override
  State<_FollowablePersonTile> createState() => _FollowablePersonTileState();
}

class _FollowablePersonTileState extends State<_FollowablePersonTile> {
  bool _busy = false;

  Future<void> _followThem() async {
    final service = widget.follow;
    if (service == null || _busy) return;
    setState(() => _busy = true);
    try {
      await service.follow(widget.person.id);
      // The following stream this rail reads drops the tile on its own.
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Could not follow just now.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final person = widget.person;
    return SizedBox(
      width: _MomentTile.widthFor(context),
      height: _MomentTile.heightFor(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: widget.onOpenProfile == null
                ? null
                : () => widget.onOpenProfile!(person.id),
            customBorder: const CircleBorder(),
            child: _PresenceDot(
              online: person.isOnline,
              child: _MomentRing(
                highlighted: false,
                child: UserAvatar(
                  radius: 25,
                  photoUrl: person.photoUrl,
                  displayName: person.displayName,
                  premium: person.premiumIdentity,
                ),
              ),
            ),
          ),
          const SizedBox(height: 5),
          _MomentNameLabel(name: person.displayName),
          const SizedBox(height: 2),
          SizedBox(
            height: _MomentTile.actionHeightFor(context),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                UserIdentityBadges(
                  uid: person.id,
                  variant: IdentityBadgeVariant.icon,
                ),
                const SizedBox(width: 4),
                OutlinedButton(
                  onPressed: _busy ? null : _followThem,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: const Color(0xFFD3A5FF),
                    side: BorderSide(
                      color: AppColors.primary.withValues(alpha: .5),
                    ),
                    shape: const StadiumBorder(),
                  ),
                  child: const Text(
                    'Follow',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The signed-in user's slot. The avatar opens their newest Moment when
/// they have one; the small plus always opens the existing creation flow
/// — the desktop entry point for recording, now that the rail's duplicate
/// action is gone.
class _YourMomentTile extends StatelessWidget {
  const _YourMomentTile({
    required this.profile,
    required this.newest,
    required this.onCreate,
    required this.onOpen,
  });

  final UserProfile? profile;
  final VoiceMoment? newest;
  final VoidCallback onCreate;
  final ValueChanged<VoiceMoment> onOpen;

  @override
  Widget build(BuildContext context) {
    final mine = newest;
    final fresh =
        mine?.createdAt != null &&
        DateTime.now().difference(mine!.createdAt!) <
            DesktopMomentsStrip.newWindow;

    return SizedBox(
      width: _MomentTile.widthFor(context),
      height: _MomentTile.heightFor(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              InkWell(
                onTap: mine == null ? onCreate : () => onOpen(mine),
                customBorder: const CircleBorder(),
                child: _MomentRing(
                  highlighted: fresh,
                  child: UserAvatar(
                    radius: 25,
                    photoUrl: profile?.photoUrl,
                    displayName: profile?.displayName,
                    fallbackIcon: Icons.person_rounded,
                  ),
                ),
              ),
              Positioned(
                right: -1,
                bottom: -1,
                child: Tooltip(
                  message: 'Record a Voice Moment',
                  child: InkWell(
                    onTap: onCreate,
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [AppColors.primary, AppColors.secondary],
                        ),
                        border: Border.all(
                          color: const Color(0xFF0C0814),
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
            ],
          ),
          const SizedBox(height: 7),
          const _MomentNameLabel(name: 'Your Moment'),
          const SizedBox(height: 2),
          SizedBox(
            height: _MomentTile.actionHeightFor(context),
            child: Center(
              child: Text(
                mine == null ? 'Record' : (fresh ? 'New' : mine.durationLabel),
                maxLines: 1,
                style: TextStyle(
                  color: mine == null || !fresh
                      ? const Color(0xFF9A90AC)
                      : const Color(0xFFE879F9),
                  fontSize: 10.5,
                  fontWeight: fresh ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown beside "Your Moment" when nobody in the circle has posted —
/// one line and one existing action, not a full-width blank panel.
class _CircleQuietState extends StatelessWidget {
  const _CircleQuietState({required this.onDiscover});

  final VoidCallback onDiscover;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white.withValues(alpha: .02),
        border: Border.all(color: const Color(0xFF241A33)),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'No Moments from your circle yet — follow a few voices and '
              'their latest lands here.',
              style: TextStyle(
                color: Color(0xFF9A90AC),
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: onDiscover,
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppColors.primary.withValues(alpha: .45)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
              // Wider than the label strictly needs: at 14pt the text sat
              // hard against the pill's radius. Still a secondary action —
              // outlined, not filled, and nowhere near full width.
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 10),
              minimumSize: const Size(150, 40),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Find creators',
              style: TextStyle(
                color: Color(0xFFD3A5FF),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
