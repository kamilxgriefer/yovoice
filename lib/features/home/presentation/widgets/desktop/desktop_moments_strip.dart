import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/home/presentation/widgets/mobile/mobile_home_sections.dart';
import 'package:yovoice/features/moments/data/models/moment_chain.dart';
import 'package:yovoice/features/moments/data/services/moment_views_service.dart';
import 'package:yovoice/features/profile/data/models/follow_user.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_expiry_accessibility.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_story_tile.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';

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
/// STATE HONESTY: the ring is the caller's OWN viewed state, read from
/// `users/{uid}/momentViews` through [MomentViewsService] — a brand
/// gradient while something in the chain is unheard, a flat quiet line
/// once every link was heard. Unknown viewed state renders as unheard.
/// The caption keeps the separate fact it has always carried: `New` for
/// the first 24 hours, otherwise the recording's real duration
/// (docs/Decisions.md ADR-036). A Moment is recorded audio — it is never
/// "live" — and there is still no global view counter anywhere.
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
    this.isVisible,
    this.avatarOnly = false,
    this.contentBuilder,
    this.viewsService,
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

  /// Test seam for the caller's own viewed-Moment ids. Production
  /// constructs one inside [MomentViewedIds].
  final MomentViewsService? viewsService;

  /// A rising edge replaces the completed v2 feed stream with a fresh one.
  final ValueListenable<bool>? isVisible;

  /// Home can compose its responsive overview from this same resolved feed;
  /// neither the circle recap nor the new layout opens another subscription.
  final bool avatarOnly;
  final Widget Function(
    BuildContext context,
    Widget rail,
    List<VoiceMoment> visibleMoments,
  )?
  contentBuilder;

  /// A Moment counts as "new" for a day after it is posted.
  static const Duration newWindow = Duration(hours: 24);

  @override
  State<DesktopMomentsStrip> createState() => _DesktopMomentsStripState();
}

class _DesktopMomentsStripState extends State<DesktopMomentsStrip> {
  Stream<List<VoiceMoment>>? _moments;
  HomeFeedService? _feedSource;
  Stream<List<FriendUser>>? _friends;
  Stream<List<FollowUser>>? _following;

  static const double _tileGap = 14;

  @override
  void initState() {
    super.initState();
    _loadMoments();
    widget.isVisible?.addListener(_handleVisibility);
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

  void _loadMoments() {
    try {
      _feedSource ??= widget.feedService ?? HomeFeedService();
      _moments = _feedSource!.watchSocialMoments();
    } catch (_) {
      // No session (or a preview harness): the strip renders its empty
      // state rather than throwing inside the shell.
      _moments = null;
    }
  }

  void _handleVisibility() {
    if (!mounted || widget.isVisible?.value != true) return;
    setState(_loadMoments);
  }

  @override
  void didUpdateWidget(covariant DesktopMomentsStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isVisible != widget.isVisible) {
      oldWidget.isVisible?.removeListener(_handleVisibility);
      widget.isVisible?.addListener(_handleVisibility);
    }
    if (oldWidget.feedService != widget.feedService) {
      _feedSource = null;
      setState(_loadMoments);
    }
  }

  @override
  void dispose() {
    widget.isVisible?.removeListener(_handleVisibility);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MomentViewedIds(
    // ONE `momentViews` listener for the whole strip, fail-open: unknown
    // viewed state renders every ring as unheard rather than greying out
    // something this account never played.
    service: widget.viewsService,
    builder: _buildStrip,
  );

  Widget _buildStrip(BuildContext context, Set<String> viewedIds) {
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

                    if (widget.avatarOnly) {
                      final rail = MobileMomentsStrip(
                        expandedLabels: true,
                        moments: visibleMoments,
                        profile: profile,
                        currentUserId: ownUserId,
                        onOpenMoment: widget.onOpenMoment,
                        onOpenChain: widget.onOpenChain,
                        onCreateMoment: widget.onCreateMoment,
                        expiryClock: widget.expiryClock,
                        // Already resolved above; the rail must not open a
                        // second listener over the same subcollection.
                        viewedIds: viewedIds,
                      );
                      return widget.contentBuilder?.call(
                            context,
                            rail,
                            visibleMoments,
                          ) ??
                          rail;
                    }

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
                                final tileHeight =
                                    MomentStoryTile.heightFor(
                                      context,
                                      caption: true,
                                      expanded: true,
                                    );

                                final tiles = <Widget>[
                                  _YourMomentTile(
                                    profile: profile,
                                    mine:
                                        mine?.moments ?? const <VoiceMoment>[],
                                    seen:
                                        mine == null ||
                                        !mine.hasUnviewed(viewedIds),
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
                                      seen: !chain.hasUnviewed(viewedIds),
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
              semanticLabel: copy.yoMomentsFromYourCircle,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  copy.yoMomentsFromYourCircle,
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

/// One person's tile in the desktop rail: the shared story disc, their
/// name, and the quiet caption line this rail has always carried.
///
/// The RING means what the data can prove about THIS account — whether it
/// has heard everything in the chain. The caption keeps the separate,
/// older fact: `New` while the newest Moment is under a day old,
/// otherwise its real duration (ADR-036). Two facts, two marks.
class _MomentTile extends StatelessWidget {
  const _MomentTile({
    required this.moment,
    required this.seen,
    required this.focusNode,
    required this.onTap,
    this.chainLength = 1,
    this.online = false,
    super.key,
  });

  final VoiceMoment moment;
  final bool seen;
  final FocusNode focusNode;
  final VoidCallback onTap;
  final int chainLength;

  /// The author's own `isOnline`, for friends only — the rail never
  /// guesses presence for someone it cannot read it for.
  final bool online;

  bool get _isNew {
    final createdAt = moment.createdAt;
    if (createdAt == null) return false;
    return DateTime.now().difference(createdAt) < DesktopMomentsStrip.newWindow;
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final fresh = _isNew;

    return MomentStoryTile(
      name: moment.authorName,
      seen: seen,
      expandedLabel: true,
      count: chainLength,
      online: online,
      identityUid: moment.authorId,
      // Both are facts the document carries: freshly posted, or exactly
      // how long the recording runs.
      caption: fresh ? copy.text('New', 'Nowy') : moment.durationLabel,
      captionHighlighted: fresh,
      userId: moment.authorId,
      photoUrl: moment.authorPhotoUrl,
      displayName: moment.authorName,
      focusNode: focusNode,
      semanticLabel: chainLength == 1
          ? copy.template(
              'Play Voice Moment from {name}',
              'Odtwórz Voice Moment użytkownika {name}',
              values: {'name': moment.authorName},
            )
          : copy.template(
              'Play {count} Voice Moments from {name}',
              'Odtwórz {count} Voice Momentów użytkownika {name}',
              values: {'count': chainLength, 'name': moment.authorName},
            ),
      onTap: onTap,
    );
  }
}

/// The signed-in user's slot. Opens their ACTIVE CHAIN — every live
/// Moment, as a story — when they have any; the small plus always opens
/// the existing creation flow, with any number of Moments already live
/// (many active Moments per user is the product; the 10-at-once cap is
/// the server's rule, enforced at reserve time, never pre-guessed here).
///
/// THE WHOLE TILE is the target, not just the disc. Every other tile in
/// this rail already wrapped its column in one [InkWell], while this one
/// wrapped only the avatar: the name and the "New" / duration line under
/// it were dead pixels, so a click that landed a few pixels low did
/// nothing at all. That asymmetry is the reported "clicking my own avatar
/// does nothing" — reproduced in a widget test before it was changed, and
/// pinned by one after.
class _YourMomentTile extends StatelessWidget {
  const _YourMomentTile({
    required this.profile,
    required this.mine,
    required this.seen,
    required this.focusNode,
    required this.onCreate,
    required this.onOpen,
    required this.onOpenChain,
  });

  final UserProfile? profile;

  /// The signed-in user's live Moments, oldest first (story order).
  /// Empty when nothing is live right now.
  final List<VoiceMoment> mine;

  /// Your own chain counts as heard on exactly the same evidence as
  /// everyone else's — your own `momentViews` docs. Nothing is assumed
  /// about a Moment you posted but never played back.
  final bool seen;
  final FocusNode? focusNode;
  final VoidCallback onCreate;
  final ValueChanged<VoiceMoment> onOpen;
  final ValueChanged<List<VoiceMoment>>? onOpenChain;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final newest = mine.isEmpty ? null : mine.last;
    final fresh =
        newest?.createdAt != null &&
        DateTime.now().difference(newest!.createdAt!) <
            DesktopMomentsStrip.newWindow;

    return MomentStoryTile(
      key: const ValueKey('home-your-moment'),
      name: copy.moments,
      seen: seen,
      // Every tile in this rail gets the same width, so the own slot lines
      // up with the circle instead of standing out narrower.
      width: MomentStoryTile.widthFor(context, expanded: true),
      expandedLabel: true,
      showAdd: true,
      // The chain badge: how many of YOUR Moments are live right now — a
      // real count from the same stream that renders them.
      count: mine.length,
      countKey: const ValueKey('home-your-moment-count'),
      caption: newest == null
          ? copy.text('Record', 'Nagraj')
          : (mine.length > 1
                ? copy.template(
                    '{count} Moments',
                    _polishMomentCountLabel(mine.length),
                    values: {'count': mine.length},
                  )
                : (fresh ? copy.text('New', 'Nowy') : newest.durationLabel)),
      captionHighlighted: newest != null && fresh,
      userId: profile?.uid,
      photoUrl: profile?.photoUrl,
      mediaRevision: profile?.profileUpdatedAt,
      displayName: profile?.displayName,
      fallbackIcon: Icons.person_rounded,
      focusNode: focusNode,
      semanticLabel: newest == null
          ? copy.text(
              'Record your first Voice Moment',
              'Nagraj swój pierwszy Voice Moment',
            )
          : (mine.length > 1
                ? copy.template(
                    'Play your {count} Voice Moments',
                    _polishPlayOwnMomentsLabel(mine.length),
                    values: {'count': mine.length},
                  )
                : copy.text(
                    'Play your Voice Moment',
                    'Odtwórz swój Voice Moment',
                  )),
      onTap: newest == null
          ? onCreate
          : (onOpenChain != null
                ? () => onOpenChain!(mine)
                : () => onOpen(newest)),
      onAddTap: onCreate,
    );
  }
}

/// Polish templates, not finished strings: the count is substituted by
/// [AppLocalizations.template] AFTER localization, so English and Polish
/// keep the same `{count}` placeholder while Polish still picks the right
/// plural form for that number.
String _polishPlayOwnMomentsLabel(int count) {
  final form = _polishMomentNoun(count);
  final possessive = form == 'Momenty' ? 'swoje' : 'swoich';
  return 'Odtwórz $possessive {count} Voice $form';
}

String _polishMomentCountLabel(int count) =>
    '{count} ${_polishMomentNoun(count)}';

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
