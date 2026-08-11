import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
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

  /// A Moment counts as "new" for a day after it is posted.
  static const Duration newWindow = Duration(hours: 24);

  @override
  State<DesktopMomentsStrip> createState() => _DesktopMomentsStripState();
}

class _DesktopMomentsStripState extends State<DesktopMomentsStrip> {
  Stream<List<VoiceMoment>>? _moments;

  static const double _tileWidth = 74;
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
                ),
                LayoutBuilder(
                  builder: (context, constraints) {
                    // "Your Moment" always holds the first slot; the rest
                    // of the width decides how many people fit, capped at
                    // the 8 the composition is designed around.
                    final fits =
                        ((constraints.maxWidth + _tileGap) /
                                (_tileWidth + _tileGap))
                            .floor();
                    final capacity = (fits - 1).clamp(0, 7);
                    final shown = others.take(capacity).toList(growable: false);

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
                        ),
                    ];

                    return SizedBox(
                      height: _MomentTile.height,
                      child: Row(
                        children: [
                          // The strip itself scrolls only when the tiles
                          // genuinely do not fit; the page never does.
                          Flexible(
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              padding: EdgeInsets.zero,
                              itemCount: tiles.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: _tileGap),
                              itemBuilder: (context, index) => tiles[index],
                            ),
                          ),
                          if (others.isEmpty) ...[
                            const SizedBox(width: 14),
                            Expanded(
                              flex: 3,
                              child: _CircleQuietState(
                                onDiscover: widget.onDiscover,
                              ),
                            ),
                          ],
                        ],
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
  }
}

class _StripHeading extends StatelessWidget {
  const _StripHeading({required this.onSeeAll, required this.showSeeAll});

  final VoidCallback onSeeAll;
  final bool showSeeAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Moments from your circle',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16.5,
                fontWeight: FontWeight.w800,
              ),
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
  const _MomentTile({required this.moment, required this.onTap});

  final VoiceMoment moment;
  final VoidCallback onTap;

  static const double width = 74;

  /// Ring + label + state, with enough slack that a platform's font
  /// metrics cannot tip the column into a one-pixel overflow.
  static const double height = 112;

  bool get _isNew {
    final createdAt = moment.createdAt;
    if (createdAt == null) return false;
    return DateTime.now().difference(createdAt) <
        DesktopMomentsStrip.newWindow;
  }

  @override
  Widget build(BuildContext context) {
    final fresh = _isNew;

    return SizedBox(
      width: width,
      height: height,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MomentRing(
              highlighted: fresh,
              child: UserAvatar(
                radius: 25,
                photoUrl: moment.authorPhotoUrl,
                displayName: moment.authorName,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              moment.authorName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              // Both are facts the document carries: freshly posted, or
              // exactly how long the recording runs.
              fresh ? 'New' : moment.durationLabel,
              maxLines: 1,
              style: TextStyle(
                color: fresh ? const Color(0xFFE879F9) : const Color(0xFF9A90AC),
                fontSize: 10.5,
                fontWeight: fresh ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
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
      width: _MomentTile.width,
      height: _MomentTile.height,
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
          const Text(
            'Your Moment',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 1),
          Text(
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
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              minimumSize: Size.zero,
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
