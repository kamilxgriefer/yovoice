import 'package:flutter/material.dart';

import '../../../achievements/data/achievement_catalog.dart';
import '../../../achievements/data/models/achievement_definition.dart';
import '../../../achievements/data/services/achievement_service.dart';
import '../../../achievements/presentation/screens/achievements_screen.dart';
import '../../../achievements/presentation/widgets/title_badge.dart';
import '../../../auth/data/auth_service.dart';
import '../../data/models/user_profile.dart';
import '../../data/services/profile_service.dart';
import 'edit_profile_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _profileService = ProfileService();
  final _achievementService = AchievementService();
  final _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _profileService.ensureProfile();
    await _achievementService.refreshUnlockedTitles();
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

        return Scaffold(
          backgroundColor: const Color(0xFF09050F),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final content = _ProfileContent(
                profile: profile,
                onEdit: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => EditProfileScreen(profile: profile),
                  ),
                ),
                onAchievements: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AchievementsScreen(profile: profile),
                  ),
                ),
                onLogout: _authService.signOut,
              );

              if (constraints.maxWidth >= 1100) {
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: content,
                  ),
                );
              }
              return content;
            },
          ),
        );
      },
    );
  }
}

class _ProfileContent extends StatelessWidget {
  const _ProfileContent({
    required this.profile,
    required this.onEdit,
    required this.onAchievements,
    required this.onLogout,
  });

  final UserProfile profile;
  final VoidCallback onEdit;
  final VoidCallback onAchievements;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    final title = AchievementCatalog.byId(profile.selectedTitleId);
    final unlocked =
        profile.unlockedTitleIds
            .map(AchievementCatalog.byId)
            .whereType()
            .toList(growable: false)
          ..sort((a, b) => b.rarity.index.compareTo(a.rarity.index));

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _Hero(profile: profile, title: title, onEdit: onEdit),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 120),
          sliver: SliverList.list(
            children: [
              _StatsGrid(profile: profile),
              const SizedBox(height: 18),
              _VoiceIdentity(profile: profile),
              const SizedBox(height: 18),
              _AchievementsPreview(
                unlocked: unlocked,
                total: profile.unlockedTitleIds.length,
                onTap: onAchievements,
              ),
              const SizedBox(height: 18),
              _CommunityPreview(profile: profile),
              const SizedBox(height: 18),
              _SettingsCard(
                onEdit: onEdit,
                onAchievements: onAchievements,
                onLogout: onLogout,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.profile,
    required this.title,
    required this.onEdit,
  });

  final UserProfile profile;
  final AchievementDefinition? title;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final avatar = profile.photoUrl?.trim();
    final banner = profile.bannerUrl?.trim();

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          height: 275,
          decoration: BoxDecoration(
            image: banner?.isNotEmpty == true
                ? DecorationImage(
                    image: NetworkImage(banner!),
                    fit: BoxFit.cover,
                  )
                : null,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF4B0D7D), Color(0xFF1E0B37), Color(0xFF09050F)],
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: .08),
                  const Color(0xFF09050F).withValues(alpha: .92),
                ],
              ),
            ),
          ),
        ),
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Profile',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_rounded),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: 18,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFF6A00FF), Color(0xFFD12CFF)],
                  ),
                ),
                child: CircleAvatar(
                  radius: 56,
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
                            fontSize: 42,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 17),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 29,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (profile.username.isNotEmpty)
                        Text(
                          '@${profile.username.replaceAll(' ', '').toLowerCase()}',
                          style: const TextStyle(
                            color: Color(0xFFBEB2C8),
                            fontSize: 14,
                          ),
                        ),
                      const SizedBox(height: 8),
                      if (title != null) TitleBadge(achievement: title),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final stats = [
      ('Friends', profile.friendCount, Icons.people_alt_rounded),
      ('Followers', profile.followerCount, Icons.auto_awesome_rounded),
      ('Communities', profile.communityCount, Icons.hub_rounded),
      ('Voice hours', profile.voiceMinutes ~/ 60, Icons.graphic_eq_rounded),
    ];

    return GridView.builder(
      itemCount: stats.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 310,
        mainAxisExtent: 112,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemBuilder: (context, index) {
        final stat = stats[index];
        return _Panel(
          child: Row(
            children: [
              CircleAvatar(
                radius: 23,
                backgroundColor: const Color(0xFF32133E),
                child: Icon(stat.$3, color: const Color(0xFFB63EFF)),
              ),
              const SizedBox(width: 13),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${stat.$2}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    stat.$1,
                    style: const TextStyle(color: Color(0xFF9D92A7)),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _VoiceIdentity extends StatelessWidget {
  const _VoiceIdentity({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Icons.language_rounded,
            title: 'Voice identity',
          ),
          const SizedBox(height: 14),
          if (profile.bio.isNotEmpty) ...[
            Text(
              profile.bio,
              style: const TextStyle(color: Color(0xFFD6CEDC), height: 1.45),
            ),
            const SizedBox(height: 15),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (profile.country.isNotEmpty)
                _Chip(label: profile.country, icon: Icons.public_rounded),
              if (profile.nativeLanguage.isNotEmpty)
                _Chip(
                  label: 'Native: ${profile.nativeLanguage}',
                  icon: Icons.record_voice_over_rounded,
                ),
              ...profile.spokenLanguages.map(
                (language) =>
                    _Chip(label: language, icon: Icons.translate_rounded),
              ),
              ...profile.learningLanguages.map(
                (language) => _Chip(
                  label: 'Learning $language',
                  icon: Icons.school_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AchievementsPreview extends StatelessWidget {
  const _AchievementsPreview({
    required this.unlocked,
    required this.total,
    required this.onTap,
  });

  final List<AchievementDefinition> unlocked;
  final int total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.workspace_premium_rounded,
            title: 'Titles & achievements',
            action: '$total/100',
            onTap: onTap,
          ),
          const SizedBox(height: 15),
          if (unlocked.isEmpty)
            const Text(
              'Your first titles will appear as you use YoVoice.',
              style: TextStyle(color: Color(0xFF9D92A7)),
            )
          else
            Wrap(
              spacing: 9,
              runSpacing: 9,
              children: unlocked
                  .take(8)
                  .map((item) => TitleBadge(achievement: item, compact: true))
                  .toList(growable: false),
            ),
        ],
      ),
    );
  }
}

class _CommunityPreview extends StatelessWidget {
  const _CommunityPreview({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Icons.hub_rounded,
            title: 'My communities',
          ),
          const SizedBox(height: 14),
          Text(
            profile.communityCount == 0
                ? 'Create or join a community to see it here.'
                : '${profile.communityCount} communities connected to this profile.',
            style: const TextStyle(color: Color(0xFFB4A8BD)),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.onEdit,
    required this.onAchievements,
    required this.onLogout,
  });

  final VoidCallback onEdit;
  final VoidCallback onAchievements;
  final Future<void> Function() onLogout;

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
          _Option(
            icon: Icons.workspace_premium_outlined,
            title: 'Titles and achievements',
            onTap: onAchievements,
          ),
          _Option(
            icon: Icons.notifications_outlined,
            title: 'Notifications',
            onTap: () {},
          ),
          _Option(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy and safety',
            onTap: () {},
          ),
          _Option(
            icon: Icons.logout_rounded,
            title: 'Log out',
            danger: true,
            showDivider: false,
            onTap: () {
              onLogout();
            },
          ),
        ],
      ),
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
        border: Border.all(color: const Color(0xFF392A45)),
      ),
      child: child,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    this.action,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFFB63EFF)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        if (action != null) TextButton(onPressed: onTap, child: Text(action!)),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF24162E),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: const Color(0xFF463253)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: const Color(0xFFC052FF)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFE0D7E6),
              fontSize: 12,
              fontWeight: FontWeight.w700,
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
    this.danger = false,
    this.showDivider = true,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool danger;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          onTap: onTap,
          leading: Icon(
            icon,
            color: danger ? const Color(0xFFFF6685) : const Color(0xFFB63EFF),
          ),
          title: Text(
            title,
            style: TextStyle(
              color: danger ? const Color(0xFFFF879D) : Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          trailing: const Icon(
            Icons.chevron_right_rounded,
            color: Color(0xFF81758F),
          ),
        ),
        if (showDivider)
          const Divider(height: 1, indent: 58, color: Color(0xFF302338)),
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
          child: Text(message, style: const TextStyle(color: Colors.white)),
        ),
      ),
    );
  }
}
