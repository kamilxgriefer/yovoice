import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/features/achievements/data/achievement_catalog.dart';
import 'package:yovoice/features/achievements/data/models/achievement_definition.dart';
import 'package:yovoice/features/achievements/data/services/achievement_service.dart';
import 'package:yovoice/features/achievements/presentation/screens/achievements_screen.dart';
import 'package:yovoice/features/achievements/presentation/widgets/title_badge.dart';
import 'package:yovoice/features/auth/data/auth_service.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/rooms/presentation/screens/room_entry_screen.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/profile/presentation/screens/edit_profile_screen.dart';
import 'package:yovoice/features/profile/presentation/screens/follow_list_screen.dart';
import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/features/clubs/presentation/screens/club_overview_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _profileService = ProfileService();
  final _achievementService = AchievementService();
  final _authService = AuthService();
  final _roomService = RoomService();
  final _clubService = ClubService();
  final _firebaseAuth = FirebaseAuth.instance;
  final _firebaseFunctions = FirebaseFunctions.instanceFor(
    region: 'europe-west1',
  );

  bool _isActivatingSuperAdmin = false;
  String _currentRole = 'user';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _profileService.ensureProfile();
    await _achievementService.refreshUnlockedTitles();
    await _refreshCurrentRole();
  }

  bool get _isOwnerAccount {
    return _firebaseAuth.currentUser?.email?.trim().toLowerCase() ==
        'grieferxgriefer@gmail.com';
  }

  Future<void> _refreshCurrentRole() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) return;

    try {
      final tokenResult = await user.getIdTokenResult();
      if (!mounted) return;

      setState(() {
        _currentRole = tokenResult.claims?['role']?.toString() ?? 'user';
      });
    } catch (_) {
      // The profile remains usable even if the token cannot be read.
    }
  }

  Future<void> _activateSuperAdmin() async {
    if (_isActivatingSuperAdmin) return;

    final user = _firebaseAuth.currentUser;
    if (user == null) {
      _showMessage('You must be signed in first.', isError: true);
      return;
    }

    if (!_isOwnerAccount) {
      _showMessage(
        'Only grieferxgriefer@gmail.com can activate SuperAdmin.',
        isError: true,
      );
      return;
    }

    setState(() => _isActivatingSuperAdmin = true);

    try {
      final callable = _firebaseFunctions.httpsCallable(
        'bootstrapSuperAdmin',
      );

      await callable.call<void>();
      await user.getIdTokenResult(true);

      if (!mounted) return;

      setState(() {
        _currentRole = 'superAdmin';
      });

      _showMessage(
        'SuperAdmin activated successfully. Your permissions are ready.',
      );
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;

      _showMessage(
        error.message ?? 'Could not activate SuperAdmin.',
        isError: true,
      );
    } catch (error) {
      if (!mounted) return;

      _showMessage(
        'Could not activate SuperAdmin: $error',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _isActivatingSuperAdmin = false);
      }
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor:
              isError ? const Color(0xFF9E244D) : const Color(0xFF4B1671),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<UserProfile>(
      stream: _profileService.watchCurrentProfile(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _ErrorView(message: snapshot.error.toString());
        }
        final profile = snapshot.data;
        if (profile == null) {
          return const Scaffold(
            backgroundColor: Color(0xFF09050F),
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return StreamBuilder<List<VoiceRoom>>(
          stream: _roomService.watchMyCommunities(),
          builder: (context, communitiesSnapshot) {
            final communities = communitiesSnapshot.data ?? const <VoiceRoom>[];
            return StreamBuilder<List<Club>>(
              stream: _clubService.watchMyClubs(),
              builder: (context, clubsSnapshot) {
                final clubs = clubsSnapshot.data ?? const <Club>[];
                return Scaffold(
                  backgroundColor: const Color(0xFF09050F),
                  body: _ProfileContent(
                    profile: profile,
                    communities: communities,
                    clubs: clubs,
                    communitiesLoading:
                        communitiesSnapshot.connectionState ==
                            ConnectionState.waiting ||
                        clubsSnapshot.connectionState ==
                            ConnectionState.waiting,
                    onEdit: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => EditProfileScreen(profile: profile),
                    ),
                  );
                },
                onAchievements: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AchievementsScreen(profile: profile),
                    ),
                  );
                },
                    onOpenCommunity: (room) {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => RoomEntryScreen(room: room),
                        ),
                      );
                    },
                    onOpenClub: (club) {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ClubOverviewScreen(clubId: club.id),
                        ),
                      );
                    },
                    showSuperAdminActivation: _isOwnerAccount,
                    isActivatingSuperAdmin: _isActivatingSuperAdmin,
                    currentRole: _currentRole,
                    onActivateSuperAdmin: _activateSuperAdmin,
                    onLogout: _authService.signOut,
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _ProfileContent extends StatelessWidget {
  const _ProfileContent({
    required this.profile,
    required this.communities,
    required this.clubs,
    required this.communitiesLoading,
    required this.onEdit,
    required this.onAchievements,
    required this.onOpenCommunity,
    required this.onOpenClub,
    required this.showSuperAdminActivation,
    required this.isActivatingSuperAdmin,
    required this.currentRole,
    required this.onActivateSuperAdmin,
    required this.onLogout,
  });

  final UserProfile profile;
  final List<VoiceRoom> communities;
  final List<Club> clubs;
  final bool communitiesLoading;
  final VoidCallback onEdit;
  final VoidCallback onAchievements;
  final ValueChanged<VoiceRoom> onOpenCommunity;
  final ValueChanged<Club> onOpenClub;
  final bool showSuperAdminActivation;
  final bool isActivatingSuperAdmin;
  final String currentRole;
  final Future<void> Function() onActivateSuperAdmin;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    final title = AchievementCatalog.byId(profile.selectedTitleId);
    final unlocked = profile.unlockedTitleIds
        .map(AchievementCatalog.byId)
        .whereType<AchievementDefinition>()
        .toList(growable: false)
      ..sort((a, b) => b.rarity.index.compareTo(a.rarity.index));

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _ProfileHero(profile: profile, title: title, onEdit: onEdit),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 124),
          sliver: SliverList.list(
            children: [
              _SocialStats(
                profile: profile,
                onFollowers: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => FollowListScreen(
                      userId: profile.uid,
                      type: FollowListType.followers,
                    ),
                  ),
                ),
                onFollowing: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => FollowListScreen(
                      userId: profile.uid,
                      type: FollowListType.following,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _VoiceIdentity(profile: profile),
              const SizedBox(height: 14),
              _JourneyCard(profile: profile, communitiesCount: communities.length + clubs.length),
              const SizedBox(height: 14),
              _CommunitiesCard(
                communities: communities,
                clubs: clubs,
                isLoading: communitiesLoading,
                onOpen: onOpenCommunity,
                onOpenClub: onOpenClub,
              ),
              const SizedBox(height: 14),
              _AchievementsCard(
                profile: profile,
                unlocked: unlocked,
                onTap: onAchievements,
              ),
              const SizedBox(height: 14),
              _AccountCard(
                onEdit: onEdit,
                showSuperAdminActivation: showSuperAdminActivation,
                isActivatingSuperAdmin: isActivatingSuperAdmin,
                currentRole: currentRole,
                onActivateSuperAdmin: onActivateSuperAdmin,
                onLogout: onLogout,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({required this.profile, required this.title, required this.onEdit});

  final UserProfile profile;
  final AchievementDefinition? title;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final avatar = profile.photoUrl?.trim();
    final banner = profile.bannerUrl?.trim();
    return SizedBox(
      height: 320,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                image: banner?.isNotEmpty == true
                    ? DecorationImage(image: NetworkImage(banner!), fit: BoxFit.cover)
                    : null,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF53108C), Color(0xFF21102E), Color(0xFF09050F)],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withValues(alpha: .05), const Color(0xFF09050F)],
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Profile', style: TextStyle(color: Colors.white, fontSize: 31, fontWeight: FontWeight.w900)),
                  ),
                  IconButton.filled(
                    onPressed: onEdit,
                    style: IconButton.styleFrom(backgroundColor: const Color(0xFFAE22FF)),
                    icon: const Icon(Icons.edit_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 20,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [Color(0xFF6A00FF), Color(0xFFD12CFF)]),
                  ),
                  child: CircleAvatar(
                    radius: 55,
                    backgroundColor: const Color(0xFF281133),
                    backgroundImage: avatar?.isNotEmpty == true ? NetworkImage(avatar!) : null,
                    child: avatar?.isNotEmpty == true
                        ? null
                        : Text(
                            profile.displayName.isEmpty ? '?' : profile.displayName[0].toUpperCase(),
                            style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w900),
                          ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          profile.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 29, fontWeight: FontWeight.w900),
                        ),
                        if (profile.username.isNotEmpty)
                          Text(
                            '@${profile.username.replaceAll(' ', '').toLowerCase()}',
                            style: const TextStyle(color: Color(0xFFB8ADC1), fontSize: 15),
                          ),
                        if (title != null) ...[
                          const SizedBox(height: 8),
                          TitleBadge(achievement: title!),
                        ],
                      ],
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

class _SocialStats extends StatelessWidget {
  const _SocialStats({
    required this.profile,
    required this.onFollowers,
    required this.onFollowing,
  });

  final UserProfile profile;
  final VoidCallback onFollowers;
  final VoidCallback onFollowing;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
      child: Row(
        children: [
          _Stat(value: profile.friendCount, label: 'Friends'),
          const _Divider(),
          _Stat(
            value: profile.followerCount,
            label: 'Followers',
            onTap: onFollowers,
          ),
          const _Divider(),
          _Stat(
            value: profile.followingCount,
            label: 'Following',
            onTap: onFollowing,
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.onTap});
  final int value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              Text('$value', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
              const SizedBox(height: 3),
              Text(label, style: const TextStyle(color: Color(0xFFA99DB3), fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) => Container(width: 1, height: 34, color: const Color(0xFF3A2B43));
}

class _VoiceIdentity extends StatelessWidget {
  const _VoiceIdentity({required this.profile});
  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final hasIdentity = profile.bio.isNotEmpty ||
        profile.country.isNotEmpty ||
        profile.nativeLanguage.isNotEmpty ||
        profile.spokenLanguages.isNotEmpty ||
        profile.learningLanguages.isNotEmpty;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Header(icon: Icons.language_rounded, title: 'Voice identity'),
          const SizedBox(height: 13),
          if (!hasIdentity)
            const Text('Add your bio and languages so people know your vibe.', style: TextStyle(color: Color(0xFFA99DB3)))
          else ...[
            if (profile.bio.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 13),
                child: Text(profile.bio, style: const TextStyle(color: Color(0xFFD9D1DE), height: 1.4)),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (profile.country.isNotEmpty) _Chip(profile.country, Icons.public_rounded),
                if (profile.nativeLanguage.isNotEmpty) _Chip('Native: ${profile.nativeLanguage}', Icons.record_voice_over_rounded),
                ...profile.spokenLanguages.map((item) => _Chip(item, Icons.translate_rounded)),
                ...profile.learningLanguages.map((item) => _Chip('Learning $item', Icons.school_rounded)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _JourneyCard extends StatelessWidget {
  const _JourneyCard({required this.profile, required this.communitiesCount});
  final UserProfile profile;
  final int communitiesCount;

  @override
  Widget build(BuildContext context) {
    final items = [
      _JourneyItem(Icons.hub_rounded, '$communitiesCount', 'Communities'),
      _JourneyItem(Icons.forum_rounded, '${profile.messageCount}', 'Messages'),
      _JourneyItem(Icons.graphic_eq_rounded, _voiceTime(profile.voiceMinutes), 'Voice time'),
      _JourneyItem(Icons.meeting_room_rounded, '${profile.roomCount}', 'Rooms created'),
    ];
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Header(icon: Icons.auto_awesome_rounded, title: 'Your YoVoice journey'),
          const SizedBox(height: 10),
          GridView.builder(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 2.7,
            ),
            itemBuilder: (context, index) {
              final item = items[index];
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF150C1D),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF382741)),
                ),
                child: Row(
                  children: [
                    Icon(item.icon, color: const Color(0xFFB833FF), size: 21),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17)),
                          Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFA99DB3), fontSize: 11)),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  static String _voiceTime(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? '${hours}h' : '${hours}h ${rest}m';
  }
}

class _JourneyItem {
  const _JourneyItem(this.icon, this.value, this.label);
  final IconData icon;
  final String value;
  final String label;
}

class _CommunitiesCard extends StatelessWidget {
  const _CommunitiesCard({
    required this.communities,
    required this.clubs,
    required this.isLoading,
    required this.onOpen,
    required this.onOpenClub,
  });

  final List<VoiceRoom> communities;
  final List<Club> clubs;
  final bool isLoading;
  final ValueChanged<VoiceRoom> onOpen;
  final ValueChanged<Club> onOpenClub;

  @override
  Widget build(BuildContext context) {
    final total = communities.length + clubs.length;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(
            icon: Icons.hub_rounded,
            title: 'My communities',
            action: total == 0 ? null : '$total',
          ),
          const SizedBox(height: 14),
          if (isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(),
              ),
            )
          else if (total == 0)
            const Text(
              'Your communities and clubs will appear here after you join or create one.',
              style: TextStyle(color: Color(0xFFA99DB3), height: 1.4),
            )
          else
            SizedBox(
              height: 124,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  ...clubs.map(
                    (club) => Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: _CommunityTile(
                        name: club.name,
                        imageUrl: club.avatarUrl,
                        subtitle: '${club.memberCount} members',
                        badge: 'CLUB',
                        onTap: () => onOpenClub(club),
                      ),
                    ),
                  ),
                  ...communities.map(
                    (room) => Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: _CommunityTile(
                        name: room.name,
                        imageUrl: room.imageUrl,
                        subtitle: room.isLive
                            ? '${room.participantCount} live now'
                            : '${room.memberCount} members',
                        badge: room.isLive ? 'LIVE' : 'ROOM',
                        onTap: () => onOpen(room),
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

class _CommunityTile extends StatelessWidget {
  const _CommunityTile({
    required this.name,
    required this.imageUrl,
    required this.subtitle,
    required this.badge,
    required this.onTap,
  });

  final String name;
  final String? imageUrl;
  final String subtitle;
  final String badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl?.trim().isNotEmpty == true;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        width: 154,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF150C1D),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF473052)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: const Color(0xFF6D1CAB),
                  backgroundImage: hasImage ? NetworkImage(imageUrl!) : null,
                  child: hasImage
                      ? null
                      : Text(
                          name.isEmpty ? '?' : name[0].toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B174F),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    badge,
                    style: const TextStyle(
                      color: Color(0xFFD67BFF),
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: const TextStyle(
                color: Color(0xFFA99DB3),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AchievementsCard extends StatelessWidget {
  const _AchievementsCard({required this.profile, required this.unlocked, required this.onTap});
  final UserProfile profile;
  final List<AchievementDefinition> unlocked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final next = AchievementCatalog.all.where((item) => !profile.unlockedTitleIds.contains(item.id)).firstOrNull;
    final progress = next == null ? 1.0 : ((profile.achievementStats[next.metric] ?? 0) / next.threshold).clamp(0.0, 1.0);
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: _Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(icon: Icons.workspace_premium_rounded, title: 'Titles & achievements', action: '${unlocked.length} unlocked'),
            const SizedBox(height: 14),
            if (unlocked.isNotEmpty)
              Wrap(spacing: 8, runSpacing: 8, children: unlocked.take(4).map((item) => TitleBadge(achievement: item, compact: true)).toList())
            else if (next != null) ...[
              Text('Next: ${next.title}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(value: progress, minHeight: 8, backgroundColor: const Color(0xFF2C2033)),
              ),
              const SizedBox(height: 7),
              Text('${profile.achievementStats[next.metric] ?? 0} / ${next.threshold} • ${next.description}', style: const TextStyle(color: Color(0xFFA99DB3), fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.onEdit,
    required this.showSuperAdminActivation,
    required this.isActivatingSuperAdmin,
    required this.currentRole,
    required this.onActivateSuperAdmin,
    required this.onLogout,
  });

  final VoidCallback onEdit;
  final bool showSuperAdminActivation;
  final bool isActivatingSuperAdmin;
  final String currentRole;
  final Future<void> Function() onActivateSuperAdmin;
  final Future<void> Function() onLogout;

  bool get _isSuperAdmin => currentRole == 'superAdmin';

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _Option(
            icon: Icons.edit_outlined,
            title: 'Edit profile',
            onTap: onEdit,
          ),
          if (showSuperAdminActivation)
            _SuperAdminOption(
              isActivated: _isSuperAdmin,
              isLoading: isActivatingSuperAdmin,
              currentRole: currentRole,
              onTap: onActivateSuperAdmin,
            ),
          _Option(
            icon: Icons.logout_rounded,
            title: 'Log out',
            destructive: true,
            showDivider: false,
            onTap: () async {
              final shouldLogout = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Log out?'),
                  content: const Text(
                    'You will need to sign in again to use YoVoice.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Log out'),
                    ),
                  ],
                ),
              );
              if (shouldLogout == true) await onLogout();
            },
          ),
        ],
      ),
    );
  }
}

class _SuperAdminOption extends StatelessWidget {
  const _SuperAdminOption({
    required this.isActivated,
    required this.isLoading,
    required this.currentRole,
    required this.onTap,
  });

  final bool isActivated;
  final bool isLoading;
  final String currentRole;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          onTap: isActivated || isLoading ? null : onTap,
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF7A1BFF), Color(0xFFD12CFF)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.admin_panel_settings_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          title: Text(
            isActivated ? 'SuperAdmin active' : 'Activate SuperAdmin',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          subtitle: Text(
            isActivated
                ? 'Role: $currentRole'
                : 'Securely activate the owner role for this account.',
            style: const TextStyle(
              color: Color(0xFFA99DB3),
              fontSize: 12,
            ),
          ),
          trailing: isLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : Icon(
                  isActivated
                      ? Icons.verified_rounded
                      : Icons.chevron_right_rounded,
                  color: isActivated
                      ? const Color(0xFFD16CFF)
                      : const Color(0xFF8E8298),
                ),
        ),
        const Divider(
          height: 1,
          indent: 58,
          endIndent: 16,
          color: Color(0xFF33263B),
        ),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padding = const EdgeInsets.all(18)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xFF17101F),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF3C2C45)),
      ),
      child: child,
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.icon, required this.title, this.action});
  final IconData icon;
  final String title;
  final String? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFFBC39FF)),
        const SizedBox(width: 10),
        Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900))),
        if (action != null) Text(action!, style: const TextStyle(color: Color(0xFF9F2FFF), fontWeight: FontWeight.w800)),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, this.icon);
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(color: const Color(0xFF25142F), borderRadius: BorderRadius.circular(99), border: Border.all(color: const Color(0xFF492F58))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: const Color(0xFFC34BFF), size: 15), const SizedBox(width: 6), Text(label, style: const TextStyle(color: Color(0xFFE3D9E8), fontSize: 12))]),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({required this.icon, required this.title, required this.onTap, this.destructive = false, this.showDivider = true});
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool destructive;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? const Color(0xFFFF6F9C) : Colors.white;
    return Column(
      children: [
        ListTile(
          onTap: onTap,
          leading: Icon(icon, color: destructive ? const Color(0xFFFF6F9C) : const Color(0xFFB932FF)),
          title: Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w800)),
          trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFF8E8298)),
        ),
        if (showDivider) const Divider(height: 1, indent: 58, endIndent: 16, color: Color(0xFF33263B)),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF09050F),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
        ),
      ),
    );
  }
}
