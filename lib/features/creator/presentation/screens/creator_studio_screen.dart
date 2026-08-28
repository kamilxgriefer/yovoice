import 'package:flutter/material.dart';

import 'package:yovoice/features/premium/premium_gates.dart';
import 'package:yovoice/features/premium/data/models/subscription_entitlements.dart';
import 'package:yovoice/features/premium/data/services/entitlement_service.dart';
import 'package:yovoice/features/premium/presentation/screens/premium_screen.dart';
import 'package:share_plus/share_plus.dart';

import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/features/clubs/presentation/screens/create_club_screen.dart';
import 'package:yovoice/features/creator/presentation/screens/creator_analytics_screen.dart';
import 'package:yovoice/features/creator/presentation/screens/creator_pinned_posts_screen.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/presentation/screens/record_voice_moment_screen.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_expiry_accessibility.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_expiry_boundary.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/profile/presentation/screens/edit_profile_screen.dart';
import 'package:yovoice/features/profile/presentation/screens/follow_list_screen.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/rooms/presentation/screens/room_entry_screen.dart';
import 'package:yovoice/features/rooms/presentation/screens/room_type_selector_screen.dart';
import 'package:yovoice/shared/widgets/buttons/yo_icon_button.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';

const _background = Color(0xFF09050F);
const _surface = Color(0xFF17101F);
const _border = Color(0xFF3C2C45);
const _muted = Color(0xFFA99DB3);
const _accent = Color(0xFFB932FF);

class CreatorStudioScreen extends StatefulWidget {
  const CreatorStudioScreen({this.isRootTab = false, super.key});

  /// True when this screen IS the shell's current content (a desktop
  /// content slot) rather than a pushed route — the same flag
  /// FriendsScreen uses, so a root tab never renders a back button that
  /// has nothing to pop.
  final bool isRootTab;

  @override
  State<CreatorStudioScreen> createState() => _CreatorStudioScreenState();
}

class _CreatorStudioScreenState extends State<CreatorStudioScreen> {
  final _profileService = ProfileService();
  final _roomService = RoomService();
  final _clubService = ClubService();
  final _momentService = MomentService();

  // Created once instead of inline in build() -- see ADR-018 for why a
  // fresh watchX() call inside a StreamBuilder's `stream:` argument tears
  // down and re-registers a live Firestore listener on every rebuild.
  late final Stream<UserProfile> _profile;
  late final Stream<List<VoiceRoom>> _rooms;
  late final Stream<List<Club>> _clubs;
  late final Stream<List<VoiceMoment>> _moments;
  final FocusNode _expiryRecoveryFocus = FocusNode(
    debugLabel: 'Creator Studio heading after expiry',
  );
  final MomentExpiryAnnouncer _expiryAnnouncer = MomentExpiryAnnouncer();

  @override
  void initState() {
    super.initState();
    _profile = _profileService.watchCurrentProfile();
    _rooms = _roomService.watchOwnedRooms();
    _clubs = _clubService.watchMyClubs();
    _moments = _momentService.watchMyMoments();
  }

  @override
  void dispose() {
    _expiryRecoveryFocus.dispose();
    super.dispose();
  }

  void _handleExpiryDeadline(DateTime deadline) {
    final previousFocus = FocusManager.instance.primaryFocus;
    final recoverFocus = momentExpiryFocusIsWithin(context, previousFocus);
    _expiryAnnouncer.announce(
      context,
      transition: 'creator-studio-${deadline.microsecondsSinceEpoch}',
      message: 'Voice Moment expired and was removed from Creator Studio.',
    );
    recoverMomentExpiryFocusAfterFrame(
      context: context,
      fallback: _expiryRecoveryFocus,
      previousFocus: recoverFocus ? previousFocus : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: ResponsiveContentFrame(
          width: ResponsiveContentWidth.dashboard,
          child: StreamBuilder<UserProfile>(
            stream: _profile,
            builder: (context, profileSnapshot) {
              final profile = profileSnapshot.data;
              if (profileSnapshot.hasError) {
                return _ErrorBody(message: '${profileSnapshot.error}');
              }
              if (profile == null) {
                return const Center(
                  child: CircularProgressIndicator(color: _accent),
                );
              }
              return StreamBuilder<List<VoiceRoom>>(
                stream: _rooms,
                builder: (context, roomsSnapshot) {
                  if (roomsSnapshot.hasError) {
                    return const _ErrorBody(
                      message: 'Your room data could not be loaded.',
                    );
                  }
                  if (!roomsSnapshot.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(color: _accent),
                    );
                  }
                  final rooms = roomsSnapshot.data!;
                  return StreamBuilder<List<Club>>(
                    stream: _clubs,
                    builder: (context, clubsSnapshot) {
                      if (clubsSnapshot.hasError) {
                        return const _ErrorBody(
                          message: 'Your club data could not be loaded.',
                        );
                      }
                      if (!clubsSnapshot.hasData) {
                        return const Center(
                          child: CircularProgressIndicator(color: _accent),
                        );
                      }
                      final clubs = clubsSnapshot.data!;
                      return StreamBuilder<List<VoiceMoment>>(
                        stream: _moments,
                        builder: (context, momentsSnapshot) {
                          if (momentsSnapshot.hasError) {
                            return const _ErrorBody(
                              message:
                                  'Your Voice Moments could not be loaded.',
                            );
                          }
                          if (!momentsSnapshot.hasData) {
                            return const Center(
                              child: CircularProgressIndicator(color: _accent),
                            );
                          }
                          final snapshotMoments = momentsSnapshot.data!;
                          return MomentExpiryListBuilder(
                            moments: snapshotMoments,
                            onDeadline: _handleExpiryDeadline,
                            builder: (context, now) {
                              final visibleMoments = snapshotMoments
                                  .where(
                                    (moment) =>
                                        !moment.isPublished ||
                                        moment.isActiveAt(now),
                                  )
                                  .toList(growable: false);
                              return _CreatorStudioContent(
                                profile: profile,
                                rooms: rooms,
                                clubs: clubs,
                                moments: visibleMoments,
                                isRootTab: widget.isRootTab,
                                expiryRecoveryFocus: _expiryRecoveryFocus,
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
          ),
        ),
      ),
    );
  }
}

class _CreatorStudioContent extends StatelessWidget {
  const _CreatorStudioContent({
    required this.profile,
    required this.rooms,
    required this.clubs,
    required this.moments,
    required this.expiryRecoveryFocus,
    this.isRootTab = false,
  });

  final UserProfile profile;
  final List<VoiceRoom> rooms;
  final List<Club> clubs;
  final List<VoiceMoment> moments;
  final FocusNode expiryRecoveryFocus;
  final bool isRootTab;

  @override
  Widget build(BuildContext context) {
    final publishedMoments = moments
        .where((item) => item.isPublished)
        .toList(growable: false);
    final draftMoments = moments
        .where((item) => !item.isPublished)
        .toList(growable: false);
    final liveRoomCount = rooms.where((item) => item.isLive).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 48),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 4, 0, 16),
          child: Row(
            children: [
              if (!isRootTab) ...[
                YoIconButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  iconSize: 18,
                  size: 40,
                  backgroundColor: _surface,
                  borderColor: _border,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: MomentExpiryFocusTarget(
                  focusNode: expiryRecoveryFocus,
                  semanticLabel: 'Creator Studio',
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Creator Studio',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                      Text(
                        'Your tools, your growth, your community.',
                        style: TextStyle(color: _muted, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        _ProfileOverviewCard(profile: profile, liveRoomCount: liveRoomCount),
        const SizedBox(height: 14),
        if (profile.accountType == AccountType.personal) ...[
          _PersonalAccountBanner(profile: profile),
          const SizedBox(height: 14),
        ],
        // Expiration policy (ADR-024): a Creator whose Premium lapsed
        // keeps every byte of Creator data — the paused banner explains
        // why premium tools are unavailable instead of hiding them.
        if (profile.accountType != AccountType.personal)
          StreamBuilder<SubscriptionEntitlements>(
            stream: EntitlementService().watchCurrentEntitlements(),
            builder: (context, snapshot) {
              final entitlements =
                  snapshot.data ?? SubscriptionEntitlements.free;
              if (!snapshot.hasData || entitlements.canUseCreator) {
                return const SizedBox.shrink();
              }
              return const Padding(
                padding: EdgeInsets.only(bottom: 14),
                child: _CreatorPausedBanner(),
              );
            },
          ),
        _QuickActionsRow(),
        const SizedBox(height: 24),

        // A slim, glanceable strip rather than a grid of tiles -- these
        // numbers matter, but they're context, not the main event.
        CreatorStudioStatStrip(
          items: [
            CreatorStudioStatItem(
              value: '${profile.followerCount}',
              label: 'Followers',
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => FollowListScreen(
                    userId: profile.uid,
                    type: FollowListType.followers,
                  ),
                ),
              ),
            ),
            CreatorStudioStatItem(
              value: '${profile.followingCount}',
              label: 'Following',
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => FollowListScreen(
                    userId: profile.uid,
                    type: FollowListType.following,
                  ),
                ),
              ),
            ),
            CreatorStudioStatItem(
              value: '${clubs.length}',
              label: 'Communities',
            ),
            CreatorStudioStatItem(
              value: _formatMinutes(profile.hostMinutes),
              label: 'Hosting time',
            ),
            CreatorStudioStatItem(
              value: _formatMinutes(profile.voiceMinutes),
              label: 'Speaking time',
            ),
          ],
        ),
        const SizedBox(height: 26),

        Row(
          children: [
            const Expanded(child: _SectionLabel('Your rooms')),
            Text(
              '${rooms.length} hosted',
              style: const TextStyle(color: _muted, fontSize: 12.5),
            ),
          ],
        ),
        const SizedBox(height: 10),
        rooms.isEmpty
            ? _EmptySection(
                icon: Icons.meeting_room_outlined,
                message: 'Host your first room to start building a stage.',
              )
            : CreatorStudioRoomsList(rooms: rooms),
        const SizedBox(height: 26),

        Row(
          children: [
            const Expanded(child: _SectionLabel('Voice Moments')),
            Text(
              '${publishedMoments.length} published · ${draftMoments.length} draft',
              style: const TextStyle(color: _muted, fontSize: 12.5),
            ),
          ],
        ),
        if (moments.isEmpty) ...[
          const SizedBox(height: 10),
          const _EmptySection(
            icon: Icons.mic_none_rounded,
            message:
                'Post a Voice Moment to give your audience something to react to.',
          ),
        ],
        const SizedBox(height: 26),

        const _SectionLabel('Recent activity'),
        const SizedBox(height: 10),
        _RecentActivityCard(rooms: rooms, moments: moments),
        const SizedBox(height: 26),

        const _SectionLabel('Creator tools'),
        const SizedBox(height: 10),
        CreatorStudioToolsRow(
          onAnalytics: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => CreatorAnalyticsScreen(
                profile: profile,
                rooms: rooms,
                clubs: clubs,
                moments: moments,
              ),
            ),
          ),
          onPinnedPosts: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => const CreatorPinnedPostsScreen(),
            ),
          ),
        ),
      ],
    );
  }

  String _formatMinutes(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? '${hours}h' : '${hours}h ${rest}m';
  }
}

class _ProfileOverviewCard extends StatelessWidget {
  const _ProfileOverviewCard({
    required this.profile,
    required this.liveRoomCount,
  });
  final UserProfile profile;
  final int liveRoomCount;

  @override
  Widget build(BuildContext context) {
    final avatar = profile.photoUrl?.trim();
    final verification = switch (profile.accountType) {
      AccountType.official => (
        'Officially verified',
        Icons.verified_rounded,
        const Color(0xFF4DA3FF),
      ),
      AccountType.creator => (
        'Creator account',
        Icons.auto_awesome_rounded,
        const Color(0xFFFFA52B),
      ),
      AccountType.personal => (
        'Personal account',
        Icons.person_rounded,
        _muted,
      ),
    };

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3A1160), Color(0xFF190B29)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF4B2C63)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFF6A00FF), Color(0xFFD12CFF)],
              ),
            ),
            child: CircleAvatar(
              radius: 30,
              backgroundColor: const Color(0xFF281133),
              backgroundImage: avatar?.isNotEmpty == true
                  ? NetworkImage(avatar!)
                  : null,
              child: avatar?.isNotEmpty == true
                  ? null
                  : Text(
                      profile.displayName.isEmpty
                          ? '?'
                          : profile.displayName[0].toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Icon(verification.$2, color: verification.$3, size: 14),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        verification.$1,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: verification.$3,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (liveRoomCount > 0) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFF335C),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    liveRoomCount > 1 ? '$liveRoomCount LIVE' : 'LIVE',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PersonalAccountBanner extends StatelessWidget {
  const _PersonalAccountBanner({required this.profile});
  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => EditProfileScreen(profile: profile),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _border),
          ),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome_rounded, color: Color(0xFFFFA52B)),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Switch to a Creator account to unlock the full creator toolkit.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: _muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActionsRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[
      _QuickAction(
        icon: Icons.meeting_room_rounded,
        label: 'Create Room',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const RoomTypeSelectorScreen(),
          ),
        ),
      ),
      _QuickAction(
        icon: Icons.hub_rounded,
        label: 'Create Club',
        onTap: () async {
          if (!await PremiumGates.ensureCanCreateClub(context)) return;
          if (!context.mounted) return;
          await Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const CreateClubScreen()),
          );
        },
      ),
      _QuickAction(
        icon: Icons.mic_rounded,
        label: 'Post Moment',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const RecordVoiceMomentScreen(),
          ),
        ),
      ),
      _QuickAction(
        icon: Icons.person_add_rounded,
        label: 'Invite',
        onTap: () => SharePlus.instance.share(
          ShareParams(
            text:
                'Join me on YO Voice — the app for live voice rooms and communities: https://yovoice.app/download',
          ),
        ),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(
          context,
        ).scale(1).clamp(1.0, 2.0);
        final minimumItemWidth = textScale > 1.4 ? 220.0 : 150.0;
        const gap = 10.0;
        final columns = constraints.maxWidth >= 900
            ? 4
            : constraints.maxWidth >= minimumItemWidth * 2 + gap
            ? 2
            : 1;
        final itemWidth =
            (constraints.maxWidth - (columns - 1) * gap) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final action in actions)
              SizedBox(width: itemWidth, child: action),
          ],
        );
      },
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _border),
          ),
          child: Column(
            children: [
              Icon(icon, color: _accent, size: 20),
              const SizedBox(height: 7),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 0, 10),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class CreatorStudioStatItem {
  const CreatorStudioStatItem({
    required this.value,
    required this.label,
    this.onTap,
  });
  final String value;
  final String label;
  final VoidCallback? onTap;
}

/// A glanceable strip, not a dashboard grid -- these numbers are context
/// for the creator, not the reason they opened this screen.
class CreatorStudioStatStrip extends StatelessWidget {
  const CreatorStudioStatStrip({required this.items, super.key});

  final List<CreatorStudioStatItem> items;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);

    return SizedBox(
      // A horizontal viewport still needs a finite cross-axis extent, but
      // that extent must grow with browser zoom / accessibility text.
      height: 62 + ((textScale - 1) * 44),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 22),
        itemBuilder: (context, index) {
          final item = items[index];
          return InkWell(
            onTap: item.onTap,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    item.value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 19,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.label,
                    style: const TextStyle(color: _muted, fontSize: 11.5),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _EmptySection extends StatelessWidget {
  const _EmptySection({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Icon(icon, color: _muted, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: _muted,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CreatorTool {
  const _CreatorTool(this.icon, this.title, this.subtitle, this.onTap);
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
}

/// Compact access to the Creator tools that actually exist. The cards use
/// the same responsive geometry on desktop and mobile and never advertise
/// unavailable features as if they were interactive.
class CreatorStudioToolsRow extends StatelessWidget {
  const CreatorStudioToolsRow({
    required this.onAnalytics,
    required this.onPinnedPosts,
    super.key,
  });

  final VoidCallback onAnalytics;
  final VoidCallback onPinnedPosts;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    final tools = [
      _CreatorTool(
        Icons.bar_chart_rounded,
        'Analytics',
        'See honest snapshots from your rooms, clubs and Voice Moments.',
        onAnalytics,
      ),
      _CreatorTool(
        Icons.push_pin_rounded,
        'Pinned post',
        'Put one published Voice Moment at the top of your profile.',
        onPinnedPosts,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 12.0;
        final columns = constraints.maxWidth >= 680 ? 2 : 1;
        final cardWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final tool in tools)
              SizedBox(
                width: cardWidth,
                child: _CreatorToolCard(
                  tool: tool,
                  minHeight: 112 + ((textScale - 1) * 54),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CreatorToolCard extends StatelessWidget {
  const _CreatorToolCard({required this.tool, required this.minHeight});

  final _CreatorTool tool;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Open ${tool.title}',
      child: Material(
        color: _surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: _border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: tool.onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: .13),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _accent.withValues(alpha: .38)),
                    ),
                    child: Icon(tool.icon, color: _accent, size: 22),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tool.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          tool.subtitle,
                          style: const TextStyle(
                            color: _muted,
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right_rounded, color: _muted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CreatorStudioRoomsList extends StatelessWidget {
  const CreatorStudioRoomsList({required this.rooms, super.key});

  final List<VoiceRoom> rooms;

  @override
  Widget build(BuildContext context) {
    final shown = rooms.take(5).toList(growable: false);
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    final usesLargeText = textScale > 1.4;

    return SizedBox(
      height: 96 + ((textScale - 1) * 100),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: shown.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final room = shown[index];
          final hasImage = room.imageUrl?.trim().isNotEmpty == true;
          return InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => RoomEntryScreen(room: room),
              ),
            ),
            child: Container(
              width: 168 + ((textScale - 1) * 72),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF150C1D),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFF382741)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: const Color(0xFF6D1CAB),
                        backgroundImage: hasImage
                            ? NetworkImage(room.imageUrl!)
                            : null,
                        child: hasImage
                            ? null
                            : Text(
                                room.name.isEmpty
                                    ? '?'
                                    : room.name[0].toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                      ),
                      const Spacer(),
                      if (room.isLive)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF335C),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: const Text(
                            'LIVE',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 8.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    room.name,
                    maxLines: usesLargeText ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    room.isLive
                        ? '${room.participantCount} listening'
                        : '${room.memberCount} members',
                    style: const TextStyle(color: _muted, fontSize: 10.5),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RecentActivityCard extends StatelessWidget {
  const _RecentActivityCard({required this.rooms, required this.moments});
  final List<VoiceRoom> rooms;
  final List<VoiceMoment> moments;

  @override
  Widget build(BuildContext context) {
    final events = <(IconData, String, String, DateTime)>[
      for (final room in rooms)
        if (room.createdAt != null)
          (
            Icons.meeting_room_rounded,
            'Created "${room.name}"',
            _relativeTime(room.createdAt!),
            room.createdAt!,
          ),
      for (final moment in moments)
        if (moment.createdAt != null && moment.isPublished)
          (
            Icons.mic_rounded,
            'Published a Voice Moment',
            _relativeTime(moment.createdAt!),
            moment.createdAt!,
          ),
    ]..sort((a, b) => b.$4.compareTo(a.$4));

    if (events.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF150C1D),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF382741)),
        ),
        child: const Text(
          'Host a room or publish a Voice Moment to see your creator activity here.',
          style: TextStyle(color: _muted, fontSize: 12.5, height: 1.4),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF150C1D),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF382741)),
      ),
      child: Column(
        children: [
          for (var index = 0; index < events.length.clamp(0, 6); index++) ...[
            if (index > 0)
              const Divider(
                height: 1,
                indent: 56,
                endIndent: 16,
                color: Color(0xFF382741),
              ),
            ListTile(
              leading: Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(events[index].$1, color: _accent, size: 17),
              ),
              title: Text(
                events[index].$2,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              trailing: Text(
                events[index].$3,
                style: const TextStyle(color: _muted, fontSize: 11),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _relativeTime(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'Now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    if (diff.inDays < 30) return '${diff.inDays}d';
    return '${diff.inDays ~/ 30}mo';
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}

/// Shown briefly when the local profile still says Creator after Premium has
/// lapsed. Studio data remains available, but Creator must be reactivated
/// explicitly after renewal.
class _CreatorPausedBanner extends StatelessWidget {
  const _CreatorPausedBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2A1A0E),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFFFB547).withValues(alpha: .35),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.pause_circle_outline_rounded,
            color: Color(0xFFFFB547),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Creator tools are paused — your Premium has ended. Your '
              'Studio data stays safe. Renew Premium, then reactivate '
              'Creator in Edit profile.',
              style: TextStyle(
                color: Color(0xFFF5D9A8),
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const PremiumScreen()),
            ),
            child: const Text(
              'Explore Premium',
              style: TextStyle(color: Color(0xFFFFB547), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
