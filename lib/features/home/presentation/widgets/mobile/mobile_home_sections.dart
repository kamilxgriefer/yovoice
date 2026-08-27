import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_home.dart'
    show RoomVisual;
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_expiry_accessibility.dart';
import 'package:yovoice/features/premium/data/premium_plans.dart';
import 'package:yovoice/features/profile/data/models/follow_user.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/shared/widgets/identity/official_role_badge.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// Mobile-native presentations of the desktop Home sections.
///
/// These are NOT the desktop cards. Those were built for a ~320pt column
/// inside a wide viewport and carry fixed heights and hard-coded row
/// widths, which overflow a phone. What is shared is what should be
/// shared — the services, models and callbacks — while the geometry here
/// is flexible: intrinsic heights, `Expanded`/`Flexible` rows, and text
/// that wraps or ellipsizes rather than pushing a row past the edge.
///
/// Every section is safe down to a 320pt viewport minus page padding.

/// Shared section heading. `See all` is optional and always a 44pt target.
class MobileSectionHeader extends StatelessWidget {
  const MobileSectionHeader({
    required this.title,
    this.live = false,
    this.onSeeAll,
    super.key,
  });

  final String title;
  final bool live;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.visible,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (live) ...[
            const SizedBox(width: 6),
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFFF7A93),
              ),
            ),
          ],
          if (onSeeAll != null) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: onSeeAll,
              style: TextButton.styleFrom(
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                foregroundColor: const Color(0xFFD3A5FF),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'View all',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(width: 2),
                  Icon(Icons.chevron_right_rounded, size: 18),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// `Moments from your circle` — your own tile first, then the circle's.
class MobileMomentsStrip extends StatelessWidget {
  const MobileMomentsStrip({
    required this.moments,
    required this.profile,
    required this.currentUserId,
    required this.onOpenMoment,
    required this.onCreateMoment,
    required this.onDiscover,
    this.onOpenOwnChain,
    this.expiryClock,
    super.key,
  });

  final List<VoiceMoment> moments;
  final UserProfile? profile;
  final String currentUserId;
  final ValueChanged<VoiceMoment> onOpenMoment;
  final VoidCallback onCreateMoment;
  final VoidCallback onDiscover;

  /// Opens the signed-in user's whole ACTIVE chain in the story viewer.
  /// Optional so existing callers keep working; when null the bubble
  /// falls back to [onOpenMoment] with the newest.
  final ValueChanged<List<VoiceMoment>>? onOpenOwnChain;

  /// Uses the same instant as an injected [HomeFeedService] in widget tests.
  final DateTime Function()? expiryClock;

  static const double _tile = 66;

  @override
  Widget build(BuildContext context) {
    final others = moments
        .where((m) => m.authorId != currentUserId)
        .toList(growable: false);
    // ALL of your own live Moments, newest first — the chain the bubble
    // opens. The bubble used to open the recorder unconditionally, so on
    // a phone there was no way to play back what you had already posted
    // from Home at all — and when nobody else had posted, your tile was
    // not even rendered.
    final mineAll = currentUserId.isEmpty
        ? const <VoiceMoment>[]
        : moments
              .where((m) => m.authorId == currentUserId)
              .toList(growable: false);
    final mine = mineAll.isEmpty ? null : mineAll.first;

    return MomentExpiryListTransition(
      moments: moments,
      clock: expiryClock ?? DateTime.now,
      transitionScope: 'mobile-home-moments',
      announcementBuilder: (count) => count == 1
          ? 'One Voice Moment expired and was removed from Home.'
          : '$count Voice Moments expired and were removed from Home.',
      builder: (context, recoveryFocus, tileFocusNode) {
        final yours = _MomentBubble(
          key: const ValueKey('home-your-moment'),
          focusNode: mine == null ? null : tileFocusNode(mine.id),
          label: 'Your Moment',
          photoUrl: mine?.authorPhotoUrl ?? profile?.photoUrl,
          displayName: profile?.displayName,
          showAdd: true,
          // A real count of YOUR live Moments — the chain badge.
          count: mineAll.length > 1 ? mineAll.length : null,
          semanticLabel: mine == null
              ? 'Record your first Voice Moment'
              : (mineAll.length > 1
                    ? 'Play your ${mineAll.length} Voice Moments'
                    : 'Play your Voice Moment'),
          onTap: mine == null
              ? onCreateMoment
              : (onOpenOwnChain != null
                    ? () => onOpenOwnChain!(mineAll)
                    : () => onOpenMoment(mine)),
          onAddTap: onCreateMoment,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            MomentExpiryFocusTarget(
              key: const ValueKey('mobile-home-moments-heading'),
              focusNode: recoveryFocus,
              semanticLabel: 'Moments from your circle',
              child: const MobileSectionHeader(
                title: 'Moments from your circle',
              ),
            ),
            if (others.isEmpty)
              // Your tile stays even when the circle is quiet: it is the one
              // real thing on the row, and hiding it was why a phone had no
              // entry point to your own Moment.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  yours,
                  const SizedBox(width: 12),
                  Expanded(
                    child: _EmptyMoments(
                      onDiscover: onDiscover,
                      onCreate: onCreateMoment,
                    ),
                  ),
                ],
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                child: Row(
                  children: [
                    yours,
                    for (final moment in others.take(12)) ...[
                      const SizedBox(width: 12),
                      _MomentBubble(
                        key: ValueKey('home-moment-${moment.id}'),
                        focusNode: tileFocusNode(moment.id),
                        label: moment.authorName,
                        photoUrl: moment.authorPhotoUrl,
                        displayName: moment.authorName,
                        onTap: () => onOpenMoment(moment),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MomentBubble extends StatelessWidget {
  const _MomentBubble({
    required this.label,
    required this.onTap,
    this.photoUrl,
    this.displayName,
    this.showAdd = false,
    this.count,
    this.semanticLabel,
    this.onAddTap,
    this.focusNode,
    super.key,
  });

  final String label;
  final VoidCallback onTap;
  final String? photoUrl;
  final String? displayName;
  final bool showAdd;

  /// A real chain count (own live Moments); null hides the badge.
  final int? count;

  /// What the bubble DOES, for a screen reader — "Your Moment" names the
  /// tile, it does not say whether tapping plays or records.
  final String? semanticLabel;

  /// The plus badge's own action. Without it the badge inherits [onTap],
  /// which is right for a person who has never posted and wrong for one
  /// who has.
  final VoidCallback? onAddTap;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel ?? label,
      child: InkWell(
        focusNode: focusNode,
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          width: 72,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [AppColors.primary, AppColors.secondary],
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF0C0814),
                      ),
                      child: UserAvatar(
                        radius: MobileMomentsStrip._tile / 2 - 9,
                        photoUrl: photoUrl,
                        displayName: displayName,
                        fallbackIcon: Icons.person_rounded,
                      ),
                    ),
                  ),
                  if (count != null)
                    Positioned(
                      left: -3,
                      top: -3,
                      child: Container(
                        key: const ValueKey('home-your-moment-count'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          gradient: const LinearGradient(
                            colors: [AppColors.primary, AppColors.secondary],
                          ),
                          border: Border.all(
                            color: const Color(0xFF0C0814),
                            width: 2,
                          ),
                        ),
                        child: Text(
                          '$count',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  if (showAdd)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: _AddMomentBadge(
                        onTap: onAddTap,
                        child: Container(
                          width: 22,
                          height: 22,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.primary,
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
                ],
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFCFC6DC),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The plus on your own bubble. A nested tap target inside the bubble's
/// InkWell: the innermost recognizer wins, so the badge means "record"
/// while the rest of the bubble means "play mine".
class _AddMomentBadge extends StatelessWidget {
  const _AddMomentBadge({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (onTap == null) return child;
    return Semantics(
      button: true,
      label: 'Record a Voice Moment',
      child: InkWell(
        key: const ValueKey('home-record-moment'),
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: child,
      ),
    );
  }
}

class _EmptyMoments extends StatelessWidget {
  const _EmptyMoments({required this.onDiscover, required this.onCreate});

  final VoidCallback onDiscover;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white.withValues(alpha: .02),
        border: Border.all(color: const Color(0xFF241A33)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'No Moments from your circle yet — follow a few voices and '
            'their latest lands here.',
            style: TextStyle(
              color: Color(0xFF9A90AC),
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          // Wrap, not Row: two buttons plus their labels do not fit a
          // 320pt phone side by side at larger text scales.
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton(
                onPressed: onDiscover,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: AppColors.primary.withValues(alpha: .45),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                  minimumSize: const Size(140, 44),
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
              TextButton(
                onPressed: onCreate,
                style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                child: const Text(
                  'Record a Moment',
                  style: TextStyle(
                    color: Color(0xFFD3A5FF),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// `Live around you` — a swipeable rail of compact room cards.
class MobileLiveRail extends StatelessWidget {
  const MobileLiveRail({
    required this.rooms,
    required this.onOpenRoom,
    required this.onSeeAll,
    super.key,
  });

  final List<VoiceRoom> rooms;
  final ValueChanged<VoiceRoom> onOpenRoom;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    if (rooms.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        // Two cards and a peek of the third, whatever the viewport is —
        // never a hard-coded card width.
        final cardWidth = (constraints.maxWidth - 22) / 2.35;
        final cover = cardWidth - 20;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            MobileSectionHeader(
              title: 'Live around you',
              live: true,
              onSeeAll: onSeeAll,
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              child: Row(
                children: [
                  for (final room in rooms.take(8)) ...[
                    if (room != rooms.first) const SizedBox(width: 11),
                    _MobileRoomCard(
                      room: room,
                      width: cardWidth,
                      cover: cover,
                      onTap: () => onOpenRoom(room),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MobileRoomCard extends StatelessWidget {
  const _MobileRoomCard({
    required this.room,
    required this.width,
    required this.cover,
    required this.onTap,
  });

  final VoiceRoom room;
  final double width;
  final double cover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${room.name}, live, ${room.participantCount} listening',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: width,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: const Color(0xFF12101D),
            border: Border.all(color: const Color(0xFF2C253B)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                children: [
                  // The SAME cover widget desktop uses: identical
                  // imageUrl handling and branded gradient fallback.
                  RoomVisual(room: room, size: cover, radius: 12),
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: Colors.black.withValues(alpha: .55),
                      ),
                      child: const Text(
                        'LIVE',
                        style: TextStyle(
                          color: Color(0xFFFF7A93),
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                room.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Row(
                children: [
                  const Icon(
                    Icons.graphic_eq_rounded,
                    size: 11,
                    color: Color(0xFF9D95AD),
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      '${room.participantCount}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF9D95AD),
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact `Voice Trending`: two live moments, up to two creators.
class MobileVoiceTrending extends StatelessWidget {
  const MobileVoiceTrending({
    required this.rooms,
    required this.creators,
    required this.onOpenRoom,
    required this.onOpenCreator,
    required this.onSeeAll,
    super.key,
  });

  final List<VoiceRoom> rooms;
  final List<FollowUser> creators;
  final ValueChanged<VoiceRoom> onOpenRoom;
  final ValueChanged<FollowUser> onOpenCreator;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final live = rooms.take(2).toList(growable: false);
    final people = creators.take(2).toList(growable: false);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: const Color(0xFF120C1D),
        border: Border.all(color: const Color(0xFF241A33)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Voice Trending',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          const _MiniLabel('Trending Moments'),
          const SizedBox(height: 6),
          if (live.isEmpty)
            const _MiniNote('No one is live right now.')
          else
            for (final room in live)
              _MiniRow(
                title: room.name,
                subtitle: room.description,
                trailing: const _MiniLivePill(),
                leading: RoomVisual(room: room, size: 34, radius: 10),
                onTap: () => onOpenRoom(room),
              ),
          const SizedBox(height: 12),
          const _MiniLabel('People to Follow'),
          const SizedBox(height: 6),
          if (people.isEmpty)
            const _MiniNote('No suggestions right now.')
          else
            for (final person in people)
              _MiniRow(
                title: person.displayName,
                titleBadge: UserIdentityBadges(
                  uid: person.uid,
                  variant: IdentityBadgeVariant.icon,
                ),
                subtitle: person.username.isEmpty
                    ? 'On YO Voice'
                    : '@${person.username}',
                leading: UserAvatar(
                  radius: 17,
                  photoUrl: person.photoUrl,
                  displayName: person.displayName,
                ),
                onTap: () => onOpenCreator(person),
              ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onSeeAll,
              style: TextButton.styleFrom(
                minimumSize: const Size(44, 44),
                padding: EdgeInsets.zero,
                foregroundColor: const Color(0xFFD3A5FF),
              ),
              child: const Text(
                'See all',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniLabel extends StatelessWidget {
  const _MiniLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: Color(0xFF9A90AC),
      fontSize: 11,
      fontWeight: FontWeight.w700,
    ),
  );
}

class _MiniNote extends StatelessWidget {
  const _MiniNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      text,
      style: const TextStyle(color: Color(0xFF7E7895), fontSize: 11.5),
    ),
  );
}

class _MiniLivePill extends StatelessWidget {
  const _MiniLivePill();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(999),
      color: AppColors.primary.withValues(alpha: .16),
    ),
    child: const Text(
      'Live',
      style: TextStyle(
        color: Color(0xFFD3A5FF),
        fontSize: 9,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _MiniRow extends StatelessWidget {
  const _MiniRow({
    required this.title,
    required this.subtitle,
    required this.leading,
    required this.onTap,
    this.trailing,
    this.titleBadge,
  });

  final String title;
  final String subtitle;
  final Widget leading;
  final Widget? trailing;
  final VoidCallback onTap;

  /// Identity badges rendered beside the title when the row is a person.
  final Widget? titleBadge;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (titleBadge != null) ...[
                        const SizedBox(width: 4),
                        titleBadge!,
                      ],
                    ],
                  ),
                  if (subtitle.trim().isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF7E7895),
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
      ),
    );
  }
}

/// Premium, mobile-shaped: benefits wrap instead of forcing three
/// columns into a phone, then the existing plans action.
class MobilePremiumCard extends StatelessWidget {
  const MobilePremiumCard({required this.onCheckPlans, super.key});

  final VoidCallback onCheckPlans;

  static const _icons = [
    (Icons.mic_rounded, Color(0xFFD3A5FF)),
    (Icons.workspace_premium_rounded, Color(0xFFFFC24D)),
    (Icons.auto_awesome_rounded, Color(0xFFE879F9)),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: const Color(0xFF120C1D).withValues(alpha: .9),
        border: Border.all(color: const Color(0xFF2E2140)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < PremiumPlans.benefits.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            Row(
              children: [
                Icon(_icons[i].$1, size: 20, color: _icons[i].$2),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        PremiumPlans.benefits[i].$1,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        PremiumPlans.benefits[i].$2,
                        style: const TextStyle(
                          color: Color(0xFF9A90AC),
                          fontSize: 11.5,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.secondary],
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: onCheckPlans,
                  child: const Center(
                    child: Text(
                      'Check plans  ›',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `Top creators you follow`, as compact rows.
class MobileTopCreators extends StatelessWidget {
  const MobileTopCreators({
    required this.creators,
    required this.onOpenCreator,
    required this.onViewAll,
    super.key,
  });

  final List<FollowUser> creators;
  final ValueChanged<FollowUser> onOpenCreator;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: const Color(0xFF120C1D),
        border: Border.all(color: const Color(0xFF241A33)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Flexible(
                child: Text(
                  'Top creators you follow',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              if (creators.isNotEmpty)
                TextButton(
                  onPressed: onViewAll,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(44, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    foregroundColor: const Color(0xFFD3A5FF),
                  ),
                  child: const Text(
                    'View all',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
          if (creators.isEmpty) ...[
            const SizedBox(height: 6),
            const Text(
              'You are not following anyone yet.',
              style: TextStyle(color: Color(0xFF7E7895), fontSize: 11.5),
            ),
          ] else
            for (final creator in creators.take(4))
              _MiniRow(
                title: creator.displayName,
                titleBadge: UserIdentityBadges(
                  uid: creator.uid,
                  variant: IdentityBadgeVariant.icon,
                ),
                subtitle: creator.username.isEmpty
                    ? 'On YO Voice'
                    : '@${creator.username}',
                leading: UserAvatar(
                  radius: 17,
                  photoUrl: creator.photoUrl,
                  displayName: creator.displayName,
                ),
                onTap: () => onOpenCreator(creator),
              ),
        ],
      ),
    );
  }
}
