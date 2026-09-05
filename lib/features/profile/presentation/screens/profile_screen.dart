import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:yovoice/shared/widgets/backgrounds/yo_page_background.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
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
import 'package:yovoice/features/profile/presentation/widgets/profile_header.dart';
import 'package:yovoice/features/profile/presentation/widgets/profile_journey_card.dart';
import 'package:yovoice/features/profile/presentation/widgets/profile_vibe_headline.dart';
import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/features/clubs/presentation/screens/club_overview_screen.dart';
import 'package:yovoice/features/creator/presentation/widgets/creator_pinned_moment_card.dart';
import 'package:yovoice/features/creator/presentation/screens/creator_pinned_moment_screen.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';

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
      _showMessage(
        AppLocalizations.of(
          context,
        ).text('You must be signed in first.', 'Najpierw się zaloguj.'),
        isError: true,
      );
      return;
    }

    if (!_isOwnerAccount) {
      _showMessage(
        AppLocalizations.of(context).text(
          'Only grieferxgriefer@gmail.com can activate SuperAdmin.',
          'Tylko grieferxgriefer@gmail.com może aktywować rolę SuperAdmin.',
        ),
        isError: true,
      );
      return;
    }

    setState(() => _isActivatingSuperAdmin = true);

    try {
      final callable = _firebaseFunctions.httpsCallable('bootstrapSuperAdmin');

      await callable.call<void>();
      await user.getIdTokenResult(true);

      if (!mounted) return;

      setState(() {
        _currentRole = 'superAdmin';
      });

      _showMessage(
        AppLocalizations.of(context).text(
          'SuperAdmin activated successfully. Your permissions are ready.',
          'Rola SuperAdmin została aktywowana. Uprawnienia są gotowe.',
        ),
      );
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      final copy = AppLocalizations.of(context);

      _showMessage(
        friendlyErrorMessage(
          error,
          fallback: copy.text(
            'Could not activate SuperAdmin.',
            'Nie udało się aktywować roli SuperAdmin.',
          ),
          copy: copy,
        ),
        isError: true,
      );
    } catch (error) {
      if (!mounted) return;
      final copy = AppLocalizations.of(context);

      _showMessage(
        friendlyErrorMessage(
          error,
          fallback: copy.text(
            'Could not activate SuperAdmin.',
            'Nie udało się aktywować roli SuperAdmin.',
          ),
          copy: copy,
        ),
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
    final colors = Theme.of(context).colorScheme;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? colors.error : colors.primary,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return StreamBuilder<UserProfile>(
      stream: _profileService.watchCurrentProfile(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _ErrorView(
            message: copy.text(
              friendlyErrorMessage(snapshot.error!),
              'Nie udało się wczytać profilu. Spróbuj ponownie.',
            ),
          );
        }
        final profile = snapshot.data;
        if (profile == null) {
          return Scaffold(
            body: YoPageBackground(
              child: Semantics(
                liveRegion: true,
                label: copy.text('Loading profile', 'Wczytywanie profilu'),
                child: const ExcludeSemantics(
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
            ),
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
                  backgroundColor: context.appPalette.background,
                  body: YoPageBackground(
                    child: ResponsiveContentFrame(
                      width: ResponsiveContentWidth.feed,
                      child: _ProfileContent(
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
                              builder: (_) =>
                                  EditProfileScreen(profile: profile),
                            ),
                          );
                        },
                        onAchievements: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  AchievementsScreen(profile: profile),
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
                              builder: (_) =>
                                  ClubOverviewScreen(clubId: club.id),
                            ),
                          );
                        },
                        showSuperAdminActivation: _isOwnerAccount,
                        isActivatingSuperAdmin: _isActivatingSuperAdmin,
                        currentRole: _currentRole,
                        onActivateSuperAdmin: _activateSuperAdmin,
                        onLogout: _authService.signOut,
                      ),
                    ),
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
    final unlocked =
        profile.unlockedTitleIds
            .map(AchievementCatalog.byId)
            .whereType<AchievementDefinition>()
            .toList(growable: false)
          ..sort((a, b) => b.rarity.index.compareTo(a.rarity.index));

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: ProfileHeader(profile: profile, title: title, onEdit: onEdit),
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
              ProfileVoiceIdentityCard(profile: profile),
              if (profile.accountType != AccountType.personal)
                CreatorPinnedMomentCard(
                  creatorId: profile.uid,
                  outerPadding: const EdgeInsets.only(top: 14),
                  onOpen: (moment) => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => CreatorPinnedMomentScreen(moment: moment),
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              ProfileJourneyCard(
                communitiesCount: communities.length + clubs.length,
                messageCount: profile.messageCount,
                voiceMinutes: profile.voiceMinutes,
                roomCount: profile.roomCount,
              ),
              const SizedBox(height: 14),
              _CommunitiesCard(
                communities: communities,
                clubs: clubs,
                currentUid: profile.uid,
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
    final copy = AppLocalizations.of(context);
    return _Panel(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
      child: Row(
        children: [
          _Stat(value: profile.friendCount, label: copy.friends),
          const _Divider(),
          _Stat(
            value: profile.followerCount,
            label: copy.text('Followers', 'Obserwujący'),
            onTap: onFollowers,
          ),
          const _Divider(),
          _Stat(
            value: profile.followingCount,
            label: copy.text('Following', 'Obserwowani'),
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

  /// Compact display for large counts (1.8K / 1.2M) — board screen 5.
  static String compact(int value) {
    String fmt(double v) {
      final d = (v * 10).truncate() / 10;
      return d == d.truncateToDouble() ? '${d.truncate()}' : '$d';
    }

    if (value >= 1000000) return '${fmt(value / 1000000)}M';
    if (value >= 1000) return '${fmt(value / 1000)}K';
    return '$value';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              Text(
                compact(value),
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(color: palette.textSecondary, fontSize: 13),
              ),
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
  Widget build(BuildContext context) =>
      Container(width: 1, height: 34, color: context.appPalette.border);
}

/// The complete Voice identity card rendered on the member's profile.
///
/// Public so the developer preview and layout tests exercise the exact widget
/// used by [ProfileScreen]. Keeping this as a real shared surface prevents a
/// saved profile field from being present in the editor/model but absent from
/// the rendered profile again.
class ProfileVoiceIdentityCard extends StatelessWidget {
  const ProfileVoiceIdentityCard({required this.profile, super.key});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final vibe = profile.statusMessage.trim();
    final bio = profile.bio.trim();
    final hasIdentity =
        vibe.isNotEmpty ||
        bio.isNotEmpty ||
        profile.country.trim().isNotEmpty ||
        profile.website.trim().isNotEmpty ||
        profile.nativeLanguage.trim().isNotEmpty ||
        profile.spokenLanguages.isNotEmpty ||
        profile.learningLanguages.isNotEmpty;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(
            icon: Icons.language_rounded,
            title: copy.text('Voice identity', 'Tożsamość głosowa'),
          ),
          const SizedBox(height: 13),
          if (!hasIdentity)
            Text(
              copy.text(
                'Add your vibe, bio or languages so people know you.',
                'Dodaj swój Vibe, opis lub języki, aby inni mogli Cię lepiej poznać.',
              ),
              style: TextStyle(color: palette.textSecondary),
            )
          else ...[
            if (vibe.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 13),
                child: ProfileVibeHeadline(
                  key: const ValueKey('profile-vibe'),
                  vibe: vibe,
                ),
              ),
            if (bio.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 13),
                child: Text(
                  bio,
                  style: TextStyle(color: palette.textSecondary, height: 1.4),
                ),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (profile.country.isNotEmpty)
                  _Chip(
                    profile.country,
                    Icons.public_rounded,
                    tone: _IdentityChipTone.external,
                  ),
                if (profile.website.isNotEmpty)
                  _Chip(
                    profile.website,
                    Icons.link_rounded,
                    tone: _IdentityChipTone.external,
                  ),
                if (profile.nativeLanguage.isNotEmpty)
                  _Chip(
                    copy.text(
                      'Native: ${profile.nativeLanguage}',
                      'Ojczysty: ${profile.nativeLanguage}',
                    ),
                    Icons.record_voice_over_rounded,
                    tone: _IdentityChipTone.voice,
                  ),
                ...profile.spokenLanguages.map(
                  (item) => _Chip(
                    item,
                    Icons.translate_rounded,
                    tone: _IdentityChipTone.voice,
                  ),
                ),
                ...profile.learningLanguages.map(
                  (item) => _Chip(
                    copy.text('Learning $item', 'Uczę się: $item'),
                    Icons.school_rounded,
                    tone: _IdentityChipTone.learning,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CommunitiesCard extends StatelessWidget {
  const _CommunitiesCard({
    required this.communities,
    required this.clubs,
    required this.currentUid,
    required this.isLoading,
    required this.onOpen,
    required this.onOpenClub,
  });

  final List<VoiceRoom> communities;
  final List<Club> clubs;
  final String currentUid;
  final bool isLoading;
  final ValueChanged<VoiceRoom> onOpen;
  final ValueChanged<Club> onOpenClub;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final total = communities.length + clubs.length;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(
            icon: Icons.hub_rounded,
            title: copy.text('My communities', 'Moje społeczności'),
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
            Text(
              copy.text(
                'Your communities and clubs will appear here after you join or create one.',
                'Społeczności i kluby pojawią się tutaj, gdy do nich dołączysz lub je utworzysz.',
              ),
              style: TextStyle(color: palette.textSecondary, height: 1.4),
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
                        subtitle:
                            '${_memberCount(copy, club.memberCount)}'
                            '${club.ownerId == currentUid ? copy.text(' · Owner', ' · Właściciel') : ''}',
                        badge: copy.text('CLUB', 'KLUB'),
                        isOwner: club.ownerId == currentUid,
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
                            ? _liveCount(copy, room.participantCount)
                            : _memberCount(copy, room.memberCount),
                        badge: room.isLive
                            ? copy.text('LIVE', 'NA ŻYWO')
                            : copy.text('ROOM', 'POKÓJ'),
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

  String _memberCount(AppLocalizations copy, int count) =>
      copy.text('$count members', count == 1 ? '1 członek' : '$count członków');

  String _liveCount(AppLocalizations copy, int count) {
    final polish = count == 1
        ? '1 osoba na żywo'
        : (count % 10 >= 2 &&
              count % 10 <= 4 &&
              (count % 100 < 12 || count % 100 > 14))
        ? '$count osoby na żywo'
        : '$count osób na żywo';
    return copy.text('$count live now', polish);
  }
}

class _CommunityTile extends StatelessWidget {
  const _CommunityTile({
    required this.name,
    required this.imageUrl,
    required this.subtitle,
    required this.badge,
    required this.onTap,
    this.isOwner = false,
  });

  final String name;
  final String? imageUrl;
  final String subtitle;
  final String badge;
  final VoidCallback onTap;

  /// Marks a club the member OWNS (board screen 5's crown) — driven by
  /// the club's real ownerId, never a guess.
  final bool isOwner;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final hasImage = imageUrl?.trim().isNotEmpty == true;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        width: 154,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: colors.primary,
                  backgroundImage: hasImage ? NetworkImage(imageUrl!) : null,
                  child: hasImage
                      ? null
                      : Text(
                          name.isEmpty ? '?' : name[0].toUpperCase(),
                          style: TextStyle(
                            color: colors.onPrimary,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                ),
                const Spacer(),
                if (isOwner)
                  const Padding(
                    padding: EdgeInsets.only(right: 5),
                    child: Icon(
                      Icons.workspace_premium_rounded,
                      size: 15,
                      color: AppColors.vipGold,
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      color: colors.onPrimaryContainer,
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
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: TextStyle(color: palette.textSecondary, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _AchievementsCard extends StatelessWidget {
  const _AchievementsCard({
    required this.profile,
    required this.unlocked,
    required this.onTap,
  });
  final UserProfile profile;
  final List<AchievementDefinition> unlocked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final next = AchievementCatalog.all
        .where((item) => !profile.unlockedTitleIds.contains(item.id))
        .firstOrNull;
    final progress = next == null
        ? 1.0
        : ((profile.achievementStats[next.metric] ?? 0) / next.threshold).clamp(
            0.0,
            1.0,
          );
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: _Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(
              icon: Icons.workspace_premium_rounded,
              title: copy.text('Titles & achievements', 'Tytuły i osiągnięcia'),
              action: copy.text(
                '${unlocked.length} unlocked',
                '${unlocked.length} odblokowanych',
              ),
            ),
            const SizedBox(height: 14),
            if (unlocked.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: unlocked
                    .take(4)
                    .map((item) => TitleBadge(achievement: item, compact: true))
                    .toList(),
              )
            else if (next != null) ...[
              Text(
                copy.text('Next: ${next.title}', 'Następny: ${next.title}'),
                style: TextStyle(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: palette.surfaceSunken,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                copy.text(
                  '${profile.achievementStats[next.metric] ?? 0} / ${next.threshold} • ${next.description}',
                  '${profile.achievementStats[next.metric] ?? 0} / ${next.threshold} • Postęp do następnego osiągnięcia',
                ),
                style: TextStyle(color: palette.textSecondary, fontSize: 12),
              ),
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
    final copy = AppLocalizations.of(context);
    return _Panel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _Option(
            icon: Icons.edit_outlined,
            title: copy.text('Edit profile', 'Edytuj profil'),
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
            title: copy.text('Log out', 'Wyloguj się'),
            destructive: true,
            showDivider: false,
            onTap: () async {
              final shouldLogout = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(copy.text('Log out?', 'Wylogować się?')),
                  content: Text(
                    copy.text(
                      'You will need to sign in again to use YO Voice.',
                      'Aby ponownie korzystać z YO Voice, trzeba będzie się zalogować.',
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(copy.text('Cancel', 'Anuluj')),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(copy.text('Log out', 'Wyloguj się')),
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
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        ListTile(
          onTap: isActivated || isLoading ? null : onTap,
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [colors.primary, colors.secondary],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.admin_panel_settings_rounded,
              color: colors.onPrimary,
              size: 22,
            ),
          ),
          title: Text(
            isActivated
                ? copy.text('SuperAdmin active', 'SuperAdmin aktywny')
                : copy.text('Activate SuperAdmin', 'Aktywuj SuperAdmin'),
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
          subtitle: Text(
            isActivated
                ? copy.text('Role: $currentRole', 'Rola: $currentRole')
                : copy.text(
                    'Securely activate the owner role for this account.',
                    'Bezpiecznie aktywuj rolę właściciela dla tego konta.',
                  ),
            style: TextStyle(color: palette.textSecondary, fontSize: 12),
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
                      ? Theme.of(context).colorScheme.primary
                      : palette.textTertiary,
                ),
        ),
        Divider(height: 1, indent: 58, endIndent: 16, color: palette.border),
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
    final palette = context.appPalette;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: palette.border),
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
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, color: colors.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        if (action != null)
          Text(
            action!,
            style: TextStyle(
              color: colors.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
      ],
    );
  }
}

enum _IdentityChipTone { external, voice, learning }

class _Chip extends StatelessWidget {
  const _Chip(this.label, this.icon, {required this.tone});
  final String label;
  final IconData icon;
  final _IdentityChipTone tone;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final theme = Theme.of(context);
    final colors = Theme.of(context).colorScheme;
    final accent = switch (tone) {
      _IdentityChipTone.external => colors.tertiary,
      _IdentityChipTone.voice => palette.interactiveForeground,
      _IdentityChipTone.learning =>
        theme.brightness == Brightness.dark
            ? AppColors.vipGold
            : Color.lerp(AppColors.vipGold, palette.textPrimary, .62)!,
    };
    final surface = Color.alphaBlend(
      accent.withValues(
        alpha: theme.brightness == Brightness.dark ? .055 : .03,
      ),
      palette.surfaceRaised,
    );
    final border = Color.alphaBlend(
      accent.withValues(alpha: theme.brightness == Brightness.dark ? .18 : .12),
      palette.border,
    );
    final usesLargeText = MediaQuery.textScalerOf(context).scale(12.5) >= 18;
    return Container(
      key: ValueKey('profile-identity-chip-$label'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            key: ValueKey('profile-identity-chip-icon-$label'),
            color: accent,
            size: 16,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: usesLargeText ? 2 : 1,
              overflow: usesLargeText
                  ? TextOverflow.visible
                  : TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.icon,
    required this.title,
    required this.onTap,
    this.destructive = false,
    this.showDivider = true,
  });
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool destructive;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final color = destructive ? colors.error : palette.textPrimary;
    return Column(
      children: [
        ListTile(
          onTap: onTap,
          leading: Icon(
            icon,
            color: destructive ? colors.error : colors.primary,
          ),
          title: Text(
            title,
            style: TextStyle(color: color, fontWeight: FontWeight.w800),
          ),
          trailing: Icon(
            Icons.chevron_right_rounded,
            color: palette.textTertiary,
          ),
        ),
        if (showDivider)
          Divider(height: 1, indent: 58, endIndent: 16, color: palette.border),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Scaffold(
      backgroundColor: palette.background,
      body: YoPageBackground(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.textPrimary),
            ),
          ),
        ),
      ),
    );
  }
}
