import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_home.dart'
    show RoomVisual;
import 'package:yovoice/features/messages/data/models/global_message.dart';
import 'package:yovoice/features/messages/data/services/global_chat_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
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
    super.key,
  });

  final List<VoiceMoment> moments;
  final UserProfile? profile;
  final String currentUserId;
  final ValueChanged<VoiceMoment> onOpenMoment;
  final VoidCallback onCreateMoment;
  final VoidCallback onDiscover;

  static const double _tile = 66;

  @override
  Widget build(BuildContext context) {
    final others = moments
        .where((m) => m.authorId != currentUserId)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const MobileSectionHeader(title: 'Moments from your circle'),
        if (others.isEmpty)
          _EmptyMoments(onDiscover: onDiscover, onCreate: onCreateMoment)
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(
              children: [
                _MomentBubble(
                  label: 'Your Moment',
                  photoUrl: profile?.photoUrl,
                  displayName: profile?.displayName,
                  showAdd: true,
                  onTap: onCreateMoment,
                ),
                for (final moment in others.take(12)) ...[
                  const SizedBox(width: 12),
                  _MomentBubble(
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
  }
}

class _MomentBubble extends StatelessWidget {
  const _MomentBubble({
    required this.label,
    required this.onTap,
    this.photoUrl,
    this.displayName,
    this.showAdd = false,
  });

  final String label;
  final VoidCallback onTap;
  final String? photoUrl;
  final String? displayName;
  final bool showAdd;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
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
                  if (showAdd)
                    Positioned(
                      right: -2,
                      bottom: -2,
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
    required this.onDiscover,
    super.key,
  });

  final List<FollowUser> creators;
  final ValueChanged<FollowUser> onOpenCreator;
  final VoidCallback onViewAll;
  final VoidCallback onDiscover;

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
            const SizedBox(height: 10),
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
                'Discover creators',
                style: TextStyle(
                  color: Color(0xFFD3A5FF),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
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

/// `Global conversations` — a preview of the community channel and the
/// way into it.
///
/// Deliberately a PREVIEW and an entry point, not an embedded chat. A
/// live composer and an infinite list inside Home's own ListView would
/// mean nested scrolling, a second subscription to the same channel, and
/// two places competing to own unread state. The full experience stays
/// in [GlobalChatScreen], which hosts the same canonical panel.
///
/// Everything shown here comes from [GlobalChatService.watchMessages] —
/// the same `globalChat/main/messages` collection, the same moderation
/// state. Soft-deleted messages are dropped rather than previewed, so a
/// removed message cannot reappear here after a moderator takes it down.
///
/// ── PLANNED: Global Hubs (not implemented in this pass) ───────────────
/// The `Open Global Chat` action is the intended redirect point for a
/// future first-run onboarding, which is why it is a single callback
/// rather than a Navigator call baked into this widget:
///
///  - first Global entry asks ~10 quick tap-only preference questions;
///  - answers assign the account to a BOUNDED Global Hub, never a unique
///    channel per answer combination;
///  - primary routing axes: preferred language, main interest, broad
///    region. Secondary matching: conversation style, activity level,
///    group size, text/voice preference, active time;
///  - language and region PREFERENCE only — never precise location, and
///    never ethnicity or nationality;
///  - `Global / Any region` is always offered as a fallback, and
///    `General` serves accounts with no specialised hub active;
///  - preferences are resettable so someone can find another hub later;
///  - assignment must be server-authoritative and capacity-aware, since
///    a client-chosen hub could be forged or overfilled;
///  - legacy Global Chat stays reachable throughout any migration.
///
/// No schema, Rules, Functions or indexes exist for this yet, and none
/// should be added until that milestone.
class MobileGlobalConversations extends StatelessWidget {
  const MobileGlobalConversations({
    required this.feed,
    required this.onOpenGlobalChat,
    super.key,
  });

  /// The live feed snapshot, straight from `watchMessages`.
  final AsyncSnapshot<GlobalChatFeed> feed;

  /// Single entry point — and the seam the future Global Hub onboarding
  /// will wrap.
  final VoidCallback onOpenGlobalChat;

  @override
  Widget build(BuildContext context) {
    final data = feed.data;
    // Moderated-away messages never enter the preview.
    final messages = (data?.messages ?? const <GlobalMessage>[])
        .where((message) => !message.isDeleted)
        .take(3)
        .toList(growable: false);

    final waiting =
        feed.connectionState == ConnectionState.waiting && !feed.hasData;

    return Semantics(
      container: true,
      child: Container(
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
                const Icon(
                  Icons.public_rounded,
                  size: 17,
                  color: Color(0xFFD3A5FF),
                ),
                const SizedBox(width: 8),
                const Flexible(
                  child: Text(
                    'Global conversations',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (data?.isFromCache ?? false) ...[
                  const SizedBox(width: 8),
                  const _OfflineChip(),
                ],
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'One channel for the whole community — meet people across '
              'YO Voice.',
              style: TextStyle(
                color: Color(0xFF9A90AC),
                fontSize: 12,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            if (waiting)
              const _GlobalPreviewPlaceholder()
            else if (feed.hasError)
              const _MiniNote('Global chat is unavailable right now.')
            else if (messages.isEmpty)
              const _MiniNote('No messages yet — say the first thing.')
            else
              for (final message in messages)
                Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      UserAvatar(
                        radius: 13,
                        photoUrl: message.senderPhotoUrl,
                        displayName: message.senderName,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              message.senderName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFCFC6DC),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              message.content,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF9A90AC),
                                fontSize: 12,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: OutlinedButton(
                onPressed: onOpenGlobalChat,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: AppColors.primary.withValues(alpha: .45),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                child: const Text(
                  'Open Global Chat',
                  style: TextStyle(
                    color: Color(0xFFD3A5FF),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfflineChip extends StatelessWidget {
  const _OfflineChip();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(999),
      color: Colors.white.withValues(alpha: .05),
      border: Border.all(color: const Color(0xFF2E2140)),
    ),
    child: const Text(
      'Offline',
      style: TextStyle(
        color: Color(0xFF9A90AC),
        fontSize: 9,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _GlobalPreviewPlaceholder extends StatelessWidget {
  const _GlobalPreviewPlaceholder();

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var i = 0; i < 2; i++)
        Container(
          height: 34,
          margin: const EdgeInsets.only(bottom: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: Colors.white.withValues(alpha: .03),
          ),
        ),
    ],
  );
}
