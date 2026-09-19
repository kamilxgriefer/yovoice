import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/creator/data/services/creator_audience_service.dart';
import 'package:yovoice/features/premium/data/models/subscription_entitlements.dart';
import 'package:yovoice/features/premium/data/services/entitlement_service.dart';
import 'package:yovoice/features/premium/presentation/screens/premium_screen.dart';
import 'package:share_plus/share_plus.dart';

import 'package:yovoice/features/creator/presentation/screens/creator_pinned_posts_screen.dart';
import 'package:yovoice/features/creator/presentation/widgets/creator_audience_setting.dart';
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
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/services/server_service.dart';
import 'package:yovoice/features/servers/presentation/screens/create_server_screen.dart';
import 'package:yovoice/features/servers/presentation/screens/server_workspace_screen.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';
import 'package:yovoice/features/servers/presentation/screens/servers_screen.dart';
import 'package:yovoice/shared/widgets/buttons/yo_icon_button.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/theme/yo_immersive_dark_surface.dart';

const _background = Color(0xFF09050F);
const _surface = Color(0xFF17101F);
const _border = Color(0xFF3C2C45);
const _muted = Color(0xFFA99DB3);
const _accent = Color(0xFFB932FF);

class CreatorStudioScreen extends StatefulWidget {
  const CreatorStudioScreen({
    this.isRootTab = false,
    this.profileService,
    this.serverRepository,
    this.momentService,
    this.creatorAudienceService,
    this.entitlementService,
    super.key,
  });

  /// True when this screen IS the shell's current content (a desktop
  /// content slot) rather than a pushed route — the same flag
  /// FriendsScreen uses, so a root tab never renders a back button that
  /// has nothing to pop.
  final bool isRootTab;
  final ProfileService? profileService;
  final ServerRepository? serverRepository;
  final MomentService? momentService;
  final CreatorAudienceService? creatorAudienceService;
  final EntitlementService? entitlementService;

  @override
  State<CreatorStudioScreen> createState() => _CreatorStudioScreenState();
}

class _CreatorStudioScreenState extends State<CreatorStudioScreen> {
  late final ProfileService _profileService;
  late final MomentService _momentService;
  late final CreatorAudienceService _creatorAudienceService;
  late final EntitlementService _entitlementService;

  // Created once instead of inline in build() -- see ADR-018 for why a
  // fresh watchX() call inside a StreamBuilder's `stream:` argument tears
  // down and re-registers a live Firestore listener on every rebuild.
  late final Stream<UserProfile> _profile;
  late final Stream<List<Server>> _servers;
  late final Stream<List<VoiceMoment>> _moments;
  final FocusNode _expiryRecoveryFocus = FocusNode(
    debugLabel: 'Creator Studio heading after expiry',
  );
  final MomentExpiryAnnouncer _expiryAnnouncer = MomentExpiryAnnouncer();

  @override
  void initState() {
    super.initState();
    _profileService = widget.profileService ?? ProfileService();
    _momentService = widget.momentService ?? MomentService();
    _creatorAudienceService =
        widget.creatorAudienceService ?? CreatorAudienceService();
    _entitlementService = widget.entitlementService ?? EntitlementService();
    _profile = _profileService.watchCurrentProfile();
    try {
      _servers = (widget.serverRepository ?? ServerService()).watchMyServers();
    } catch (error) {
      _servers = Stream<List<Server>>.error(error);
    }
    _moments = _momentService.watchMyMoments();
  }

  @override
  void dispose() {
    _expiryRecoveryFocus.dispose();
    super.dispose();
  }

  void _handleExpiryDeadline(DateTime deadline) {
    final copy = AppLocalizations.of(context);
    final previousFocus = FocusManager.instance.primaryFocus;
    final recoverFocus = momentExpiryFocusIsWithin(context, previousFocus);
    _expiryAnnouncer.announce(
      context,
      transition: 'creator-studio-${deadline.microsecondsSinceEpoch}',
      message: copy.text(
        'Voice Moment expired and was removed from Creator Studio.',
        'Voice Moment wygasł i został usunięty ze Studia twórcy.',
      ),
    );
    recoverMomentExpiryFocusAfterFrame(
      context: context,
      fallback: _expiryRecoveryFocus,
      previousFocus: recoverFocus ? previousFocus : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final content = Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: ResponsiveContentFrame(
          width: ResponsiveContentWidth.dashboard,
          child: StreamBuilder<UserProfile>(
            stream: _profile,
            builder: (context, profileSnapshot) {
              final profile = profileSnapshot.data;
              if (profileSnapshot.hasError) {
                return _ErrorBody(
                  message: copy.text(
                    'Your profile could not be loaded.',
                    'Nie udało się wczytać Twojego profilu.',
                  ),
                );
              }
              if (profile == null) {
                return _CreatorLoading(
                  label: copy.text(
                    'Loading Creator Studio',
                    'Wczytywanie Studia twórcy',
                  ),
                );
              }
              return StreamBuilder<List<Server>>(
                stream: _servers,
                builder: (context, serversSnapshot) {
                  if (serversSnapshot.hasError) {
                    return _ErrorBody(
                      message: copy.text(
                        'Your server data could not be loaded.',
                        'Nie udało się wczytać danych Twoich serwerów.',
                      ),
                    );
                  }
                  if (!serversSnapshot.hasData) {
                    return _CreatorLoading(
                      label: copy.text(
                        'Loading your servers',
                        'Wczytywanie Twoich serwerów',
                      ),
                    );
                  }
                  final servers = serversSnapshot.data!;
                  return StreamBuilder<List<VoiceMoment>>(
                    stream: _moments,
                    builder: (context, momentsSnapshot) {
                      if (momentsSnapshot.hasError) {
                        return _ErrorBody(
                          message: copy.text(
                            'Your Voice Moments could not be loaded.',
                            'Nie udało się wczytać Twoich materiałów Voice Moment.',
                          ),
                        );
                      }
                      if (!momentsSnapshot.hasData) {
                        return _CreatorLoading(
                          label: copy.text(
                            'Loading your Voice Moments',
                            'Wczytywanie Twoich materiałów Voice Moment',
                          ),
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
                            servers: servers,
                            moments: visibleMoments,
                            isRootTab: widget.isRootTab,
                            expiryRecoveryFocus: _expiryRecoveryFocus,
                            creatorAudienceService: _creatorAudienceService,
                            entitlementService: _entitlementService,
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
    return YoImmersiveDarkSurface(child: content);
  }
}

class _CreatorStudioContent extends StatefulWidget {
  const _CreatorStudioContent({
    required this.profile,
    required this.servers,
    required this.moments,
    required this.expiryRecoveryFocus,
    required this.creatorAudienceService,
    required this.entitlementService,
    this.isRootTab = false,
  });

  final UserProfile profile;
  final List<Server> servers;
  final List<VoiceMoment> moments;
  final FocusNode expiryRecoveryFocus;
  final CreatorAudienceService creatorAudienceService;
  final EntitlementService entitlementService;
  final bool isRootTab;

  @override
  State<_CreatorStudioContent> createState() => _CreatorStudioContentState();
}

class _CreatorStudioContentState extends State<_CreatorStudioContent> {
  Stream<CreatorAudienceProjection>? _audienceProjection;
  late final Stream<SubscriptionEntitlements> _entitlements;
  CreatorAudienceProjection? _savedProjection;

  bool get _canReadAudienceProjection =>
      widget.profile.accountType == AccountType.creator ||
      widget.profile.creatorAudienceEnabled;

  @override
  void initState() {
    super.initState();
    try {
      _entitlements = widget.entitlementService.watchCurrentEntitlements();
    } catch (_) {
      _entitlements = Stream.value(SubscriptionEntitlements.free);
    }
    _configureAudienceProjection();
  }

  @override
  void didUpdateWidget(_CreatorStudioContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    final identityChanged = oldWidget.profile.uid != widget.profile.uid;
    final projectionScopeChanged =
        (oldWidget.profile.accountType == AccountType.creator ||
            oldWidget.profile.creatorAudienceEnabled) !=
        _canReadAudienceProjection;
    if (identityChanged || projectionScopeChanged) {
      _savedProjection = null;
      _configureAudienceProjection();
    } else if (oldWidget.profile.creatorAudienceEnabled !=
        widget.profile.creatorAudienceEnabled) {
      _savedProjection = null;
    }
  }

  void _configureAudienceProjection() {
    _audienceProjection = _canReadAudienceProjection
        ? widget.creatorAudienceService.watchPublicProjection(
            widget.profile.uid,
          )
        : null;
  }

  void _handleAudienceSaved(CreatorAudienceUpdate update) {
    setState(() {
      _savedProjection = CreatorAudienceProjection(
        visible: update.visible,
        followerCount: update.visible ? widget.profile.followerCount : 0,
        followingCount: update.visible ? widget.profile.followingCount : 0,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SubscriptionEntitlements>(
      stream: _entitlements,
      builder: (context, snapshot) {
        final resolved = snapshot.hasData && !snapshot.hasError;
        final entitlements = resolved
            ? snapshot.data!
            : SubscriptionEntitlements.free;
        return _buildWithEntitlements(
          context,
          entitlements,
          resolved: resolved,
        );
      },
    );
  }

  Widget _buildWithEntitlements(
    BuildContext context,
    SubscriptionEntitlements entitlements, {
    required bool resolved,
  }) {
    final audience = _audienceProjection;
    if (audience == null) {
      return _buildContent(
        context,
        const CreatorAudienceProjection.hidden(),
        entitlements,
        entitlementsResolved: resolved,
      );
    }
    return StreamBuilder<CreatorAudienceProjection>(
      stream: audience,
      initialData: widget.profile.creatorAudienceVisible
          ? CreatorAudienceProjection(
              visible: true,
              followerCount: widget.profile.followerCount,
              followingCount: widget.profile.followingCount,
            )
          : const CreatorAudienceProjection.hidden(),
      builder: (context, snapshot) {
        final streamed = snapshot.hasError
            ? const CreatorAudienceProjection.hidden()
            : snapshot.data ?? const CreatorAudienceProjection.hidden();
        final saved = _savedProjection;
        final projection = saved != null && streamed.visible != saved.visible
            ? saved
            : streamed;
        return _buildContent(
          context,
          projection,
          entitlements,
          entitlementsResolved: resolved,
        );
      },
    );
  }

  Widget _buildContent(
    BuildContext context,
    CreatorAudienceProjection audience,
    SubscriptionEntitlements entitlements, {
    required bool entitlementsResolved,
  }) {
    final copy = AppLocalizations.of(context);
    final publishedMoments = widget.moments
        .where((item) => item.isPublished)
        .toList(growable: false);
    final draftMoments = widget.moments
        .where((item) => !item.isPublished)
        .toList(growable: false);
    final showCreatorAudience =
        widget.profile.accountType == AccountType.creator && audience.visible;
    final profile = widget.profile;
    final servers = widget.servers;
    final moments = widget.moments;

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 48),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 4, 0, 16),
          child: Row(
            children: [
              if (!widget.isRootTab) ...[
                YoIconButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  iconSize: 18,
                  size: 40,
                  backgroundColor: _surface,
                  borderColor: _border,
                  tooltip: copy.text('Back', 'Wróć'),
                  semanticLabel: copy.text('Back', 'Wróć'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: MomentExpiryFocusTarget(
                  focusNode: widget.expiryRecoveryFocus,
                  semanticLabel: copy.text('Creator Studio', 'Studio twórcy'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        copy.text('Creator Studio', 'Studio twórcy'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                      Text(
                        copy.text(
                          'Your tools, your growth, your community.',
                          'Twoje narzędzia, rozwój i społeczność.',
                        ),
                        style: const TextStyle(color: _muted, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        _ProfileOverviewCard(profile: profile, serverCount: servers.length),
        const SizedBox(height: 14),
        if (profile.accountType == AccountType.personal) ...[
          _PersonalAccountBanner(profile: profile),
          const SizedBox(height: 14),
        ],
        // Expiration policy (ADR-024): a Creator whose Premium lapsed
        // keeps every byte of Creator data — the paused banner explains
        // why premium tools are unavailable instead of hiding them.
        if (profile.accountType != AccountType.personal &&
            entitlementsResolved &&
            !entitlements.canUseCreator)
          const Padding(
            padding: EdgeInsets.only(bottom: 14),
            child: _CreatorPausedBanner(),
          ),
        if (creatorAudienceSettingIsAvailable(profile, entitlements)) ...[
          CreatorAudienceSetting(
            ownerEnabled: profile.creatorAudienceEnabled,
            publicVisible: audience.visible,
            canEnable: creatorAudienceCanEnable(profile, entitlements),
            ageVerified: profile.creatorAgeVerified,
            canConfirmAge: creatorAudienceCanConfirmAge(profile, entitlements),
            service: widget.creatorAudienceService,
            onSaved: _handleAudienceSaved,
          ),
          const SizedBox(height: 14),
        ],
        const _QuickActionsRow(),
        const SizedBox(height: 24),

        // A slim, glanceable strip rather than a grid of tiles -- these
        // numbers matter, but they're context, not the main event.
        CreatorStudioStatStrip(
          items: [
            if (showCreatorAudience)
              CreatorStudioStatItem(
                value: '${audience.followerCount}',
                label: copy.text('Followers', 'Obserwujący'),
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => FollowListScreen(
                      userId: profile.uid,
                      type: FollowListType.followers,
                    ),
                  ),
                ),
              ),
            if (showCreatorAudience)
              CreatorStudioStatItem(
                value: '${audience.followingCount}',
                label: copy.text('Following', 'Obserwowani'),
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
              value: '${servers.length}',
              label: copy.text('Servers', 'Serwery'),
            ),
            CreatorStudioStatItem(
              value: _formatMinutes(profile.hostMinutes, copy),
              label: copy.text('Hosting time', 'Czas prowadzenia'),
            ),
            CreatorStudioStatItem(
              value: _formatMinutes(profile.voiceMinutes, copy),
              label: copy.text('Speaking time', 'Czas mówienia'),
            ),
          ],
        ),
        const SizedBox(height: 26),

        Row(
          children: [
            Expanded(
              child: _SectionLabel(copy.text('Your servers', 'Twoje serwery')),
            ),
            Text(
              _serverCountLabel(servers.length, copy),
              style: const TextStyle(color: _muted, fontSize: 12.5),
            ),
          ],
        ),
        const SizedBox(height: 10),
        servers.isEmpty
            ? _EmptySection(
                icon: Icons.hub_outlined,
                message: copy.text(
                  'Create your first server to bring your people together.',
                  'Stwórz pierwszy serwer i zbierz swoich ludzi w jednym miejscu.',
                ),
              )
            : _CreatorStudioServersList(servers: servers),
        const SizedBox(height: 26),

        Row(
          children: [
            const Expanded(child: _SectionLabel('Voice Moments')),
            Text(
              _momentSummaryLabel(
                publishedMoments.length,
                draftMoments.length,
                copy,
              ),
              style: const TextStyle(color: _muted, fontSize: 12.5),
            ),
          ],
        ),
        if (moments.isEmpty) ...[
          const SizedBox(height: 10),
          _EmptySection(
            icon: Icons.mic_none_rounded,
            message: copy.text(
              'Post a Voice Moment to give your audience something to react to.',
              'Opublikuj Voice Moment i daj odbiorcom coś, na co mogą zareagować.',
            ),
          ),
        ],
        const SizedBox(height: 26),

        _SectionLabel(copy.text('Recent activity', 'Ostatnia aktywność')),
        const SizedBox(height: 10),
        _RecentActivityCard(rooms: const <VoiceRoom>[], moments: moments),
        const SizedBox(height: 26),

        _SectionLabel(copy.text('Creator tools', 'Narzędzia twórcy')),
        const SizedBox(height: 10),
        CreatorStudioToolsRow(
          onAnalytics: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(builder: (_) => const ServersScreen()),
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

  String _formatMinutes(int minutes, AppLocalizations copy) {
    if (minutes < 60) return copy.isPolish ? '$minutes min' : '${minutes}m';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    if (copy.isPolish) {
      return rest == 0 ? '$hours godz.' : '$hours godz. $rest min';
    }
    return rest == 0 ? '${hours}h' : '${hours}h ${rest}m';
  }
}

class _ProfileOverviewCard extends StatelessWidget {
  const _ProfileOverviewCard({
    required this.profile,
    required this.serverCount,
  });
  final UserProfile profile;
  final int serverCount;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final verification = switch (profile.accountType) {
      AccountType.official => (
        copy.text('Officially verified', 'Oficjalnie zweryfikowane konto'),
        Icons.verified_rounded,
        const Color(0xFF4DA3FF),
      ),
      AccountType.creator => (
        copy.text('Creator account', 'Konto twórcy'),
        Icons.auto_awesome_rounded,
        const Color(0xFFFFA52B),
      ),
      AccountType.personal => (
        copy.text('Personal account', 'Konto osobiste'),
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
            // `photoUrl` is null on every profile the server projects, so
            // this header could only ever draw the initial. The uid resolves
            // through the viewer-authorized grant like every other avatar.
            child: UserAvatar(
              key: const ValueKey('creator-studio-hero-avatar'),
              radius: 30,
              userId: profile.uid,
              mediaRevision: profile.profileUpdatedAt,
              displayName: profile.displayName,
              backgroundColor: const Color(0xFF281133),
              premium: profile.premiumIdentity,
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
          if (serverCount > 0) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _accent,
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
                    copy.isPolish
                        ? '$serverCount ${serverCount == 1 ? 'SERWER' : 'SERWERY'}'
                        : '$serverCount ${serverCount == 1 ? 'SERVER' : 'SERVERS'}',
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
    final copy = AppLocalizations.of(context);
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
              Expanded(
                child: Text(
                  copy.text(
                    'Switch to a Creator account to unlock the full creator toolkit.',
                    'Przełącz konto na konto twórcy, aby odblokować pełny zestaw narzędzi.',
                  ),
                  style: const TextStyle(
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
  const _QuickActionsRow();

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final actions = <Widget>[
      _QuickAction(
        icon: Icons.hub_rounded,
        label: copy.text('Create Server', 'Stwórz serwer'),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const CreateServerScreen()),
        ),
      ),
      _QuickAction(
        icon: Icons.mic_rounded,
        label: copy.text('Post Moment', 'Opublikuj Voice Moment'),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const RecordVoiceMomentScreen(),
          ),
        ),
      ),
      _QuickAction(
        icon: Icons.person_add_rounded,
        label: copy.text('Invite', 'Zaproś'),
        onTap: () => SharePlus.instance.share(
          ShareParams(
            text: copy.text(
              'Join me on YO Voice — one place for voice, Moments and servers: https://yovoice.app/download',
              'Dołącz do mnie w YO Voice — jednym miejscu na głos, Momenty i serwery: https://yovoice.app/download',
            ),
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
    return Semantics(
      button: true,
      label: label,
      child: Material(
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
    final copy = AppLocalizations.of(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    final tools = [
      _CreatorTool(
        Icons.hub_rounded,
        copy.text('Server tools', 'Narzędzia serwera'),
        copy.text(
          'Open your servers, channels and member tools.',
          'Otwórz swoje serwery, kanały i narzędzia dla członków.',
        ),
        onAnalytics,
      ),
      _CreatorTool(
        Icons.push_pin_rounded,
        copy.text('Pinned post', 'Przypięty post'),
        copy.text(
          'Put one published Voice Moment at the top of your profile.',
          'Umieść opublikowany Voice Moment na górze swojego profilu.',
        ),
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
    final copy = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label: copy.template(
        'Open {title}',
        'Otwórz: {title}',
        values: {'title': tool.title},
      ),
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

class _CreatorStudioServersList extends StatelessWidget {
  const _CreatorStudioServersList({required this.servers});

  final List<Server> servers;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final shown = servers.take(5).toList(growable: false);
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    return SizedBox(
      height: 96 + ((textScale - 1) * 100),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: shown.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final server = shown[index];
          return Semantics(
            button: true,
            label: copy.template(
              'Open server {name}',
              'Otwórz serwer {name}',
              values: {'name': server.name},
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => ServerWorkspaceScreen(serverId: server.id),
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
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: const Color(0xFF6D1CAB),
                      child: Text(
                        server.initial,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      server.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      server.isHeld
                          ? copy.text('Preparing', 'W przygotowaniu')
                          : copy.text('Open channels', 'Otwórz kanały'),
                      style: const TextStyle(color: _muted, fontSize: 10.5),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Compatibility renderer for legacy server-bound voice documents.
class CreatorStudioRoomsList extends StatelessWidget {
  const CreatorStudioRoomsList({required this.rooms, super.key});

  final List<VoiceRoom> rooms;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
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
          return Semantics(
            button: true,
            label: copy.template(
              'Open server conversation {name}',
              'Otwórz rozmowę na serwerze {name}',
              values: {'name': room.name},
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () {
                final serverId = room.clubId?.trim();
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => serverId == null || serverId.isEmpty
                        ? const ServersScreen()
                        : ServerWorkspaceScreen(serverId: serverId),
                  ),
                );
              },
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
                            child: Text(
                              copy.text('LIVE', 'NA ŻYWO'),
                              style: const TextStyle(
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
                      _roomAudienceLabel(room, copy),
                      style: const TextStyle(color: _muted, fontSize: 10.5),
                    ),
                  ],
                ),
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
    final copy = AppLocalizations.of(context);
    final events = <(IconData, String, String, DateTime)>[
      for (final room in rooms)
        if (room.createdAt != null)
          (
            Icons.meeting_room_rounded,
            copy.template(
              'Started "{name}"',
              'Rozpoczęto „{name}”',
              values: {'name': room.name},
            ),
            _relativeTime(room.createdAt!, copy),
            room.createdAt!,
          ),
      for (final moment in moments)
        if (moment.createdAt != null && moment.isPublished)
          (
            Icons.mic_rounded,
            copy.text('Published a Voice Moment', 'Opublikowano Voice Moment'),
            _relativeTime(moment.createdAt!, copy),
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
        child: Text(
          copy.text(
            'Create a server or publish a Voice Moment to see your creator activity here.',
            'Stwórz serwer lub opublikuj Voice Moment, aby zobaczyć tutaj swoją aktywność.',
          ),
          style: const TextStyle(color: _muted, fontSize: 12.5, height: 1.4),
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

  String _relativeTime(DateTime date, AppLocalizations copy) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return copy.text('Now', 'Teraz');
    if (diff.inHours < 1) {
      return copy.isPolish ? '${diff.inMinutes} min' : '${diff.inMinutes}m';
    }
    if (diff.inDays < 1) {
      return copy.isPolish ? '${diff.inHours} godz.' : '${diff.inHours}h';
    }
    if (diff.inDays < 30) {
      return copy.isPolish
          ? '${diff.inDays} ${_polishPlural(diff.inDays, 'dzień', 'dni', 'dni')}'
          : '${diff.inDays}d';
    }
    return copy.isPolish
        ? '${diff.inDays ~/ 30} mies.'
        : '${diff.inDays ~/ 30}mo';
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return Semantics(
      liveRegion: true,
      label: '${copy.text('Error', 'Błąd')}. $message',
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class _CreatorLoading extends StatelessWidget {
  const _CreatorLoading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        liveRegion: true,
        label: label,
        child: const CircularProgressIndicator(color: _accent),
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
    final copy = AppLocalizations.of(context);
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
          Expanded(
            child: Text(
              copy.text(
                'Creator tools are paused — your Premium has ended. Your '
                    'Studio data stays safe. Renew Premium, then reactivate '
                    'Creator in Edit profile.',
                'Narzędzia twórcy są wstrzymane, ponieważ dostęp Premium wygasł. '
                    'Dane w Studiu twórcy są bezpieczne. Odnów Premium, a następnie '
                    'ponownie aktywuj konto twórcy w edycji profilu.',
              ),
              style: const TextStyle(
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
            child: Text(
              copy.text('Explore Premium', 'Poznaj Premium'),
              style: const TextStyle(color: Color(0xFFFFB547), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

String _serverCountLabel(int count, AppLocalizations copy) {
  if (!copy.isPolish) return count == 1 ? '1 server' : '$count servers';
  return '$count ${_polishPlural(count, 'serwer', 'serwery', 'serwerów')}';
}

String _momentSummaryLabel(int published, int drafts, AppLocalizations copy) {
  if (!copy.isPolish) return '$published published · $drafts draft';
  final publishedLabel = _polishPlural(
    published,
    'opublikowany',
    'opublikowane',
    'opublikowanych',
  );
  final draftLabel = _polishPlural(
    drafts,
    'wersja robocza',
    'wersje robocze',
    'wersji roboczych',
  );
  return '$published $publishedLabel · $drafts $draftLabel';
}

String _roomAudienceLabel(VoiceRoom room, AppLocalizations copy) {
  if (!copy.isPolish) {
    return room.isLive
        ? '${room.participantCount} listening'
        : '${room.memberCount} members';
  }
  if (room.isLive) {
    final label = room.participantCount == 1 ? 'słuchacz' : 'słuchaczy';
    return '${room.participantCount} $label';
  }
  final label = room.memberCount == 1 ? 'członek' : 'członków';
  return '${room.memberCount} $label';
}

String _polishPlural(int count, String one, String few, String many) {
  if (count == 1) return one;
  final tens = count % 100;
  final units = count % 10;
  if (tens < 12 || tens > 14) {
    if (units >= 2 && units <= 4) return few;
  }
  return many;
}
