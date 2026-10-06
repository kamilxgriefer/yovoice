import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:yovoice/shared/widgets/backgrounds/yo_page_background.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_finish.dart';
import 'package:yovoice/core/theme/app_gradients.dart';
import 'package:yovoice/core/theme/app_motion.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/features/achievements/data/achievement_catalog.dart';
import 'package:yovoice/features/achievements/data/models/achievement_definition.dart';
import 'package:yovoice/features/achievements/data/services/achievement_service.dart';
import 'package:yovoice/features/achievements/presentation/screens/achievements_screen.dart';
import 'package:yovoice/features/achievements/presentation/widgets/title_badge.dart';
import 'package:yovoice/features/auth/data/auth_service.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/profile/presentation/my_link_copy.dart';
import 'package:yovoice/features/profile/presentation/screens/edit_profile_screen.dart';
import 'package:yovoice/features/profile/presentation/screens/follow_list_screen.dart';
import 'package:yovoice/features/profile/presentation/widgets/profile_header.dart';
import 'package:yovoice/features/profile/presentation/widgets/profile_journey_card.dart';
import 'package:yovoice/features/profile/presentation/widgets/my_link_sheet.dart';
import 'package:yovoice/features/profile/presentation/widgets/profile_layout.dart';
import 'package:yovoice/features/profile/presentation/widgets/profile_vibe_headline.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/data/services/server_service.dart';
import 'package:yovoice/features/servers/presentation/screens/server_workspace_screen.dart';
import 'package:yovoice/features/creator/data/services/creator_pinned_post_service.dart';
import 'package:yovoice/features/creator/presentation/widgets/creator_pinned_moment_card.dart';
import 'package:yovoice/features/creator/presentation/screens/creator_pinned_moment_screen.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_filled_button.dart';
import 'package:yovoice/shared/widgets/cards/yo_card.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/navigation/yo_server_rail_item.dart';
import 'package:yovoice/shared/widgets/profile/profile_hero_backdrop.dart';
import 'package:yovoice/shared/widgets/states/yo_error_state.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    this.profileService,
    this.achievementService,
    this.serverRepository,
    this.auth,
    this.identityRepository,
    this.mediaService,
  });

  /// Test / preview seams. Production leaves every one null and each
  /// resolves its Firebase-backed default (lazily, so a seam-built screen
  /// never touches an unconfigured Firebase app).
  final ProfileService? profileService;
  final AchievementService? achievementService;
  final ServerRepository? serverRepository;
  final FirebaseAuth? auth;
  final PublicIdentityRepository? identityRepository;
  final ProfileMediaService? mediaService;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final ProfileService _profileService =
      widget.profileService ?? ProfileService();
  late final AchievementService _achievementService =
      widget.achievementService ?? AchievementService();
  late final AuthService _authService = AuthService();
  late final ServerRepository _serverRepository =
      widget.serverRepository ?? ServerService();
  late Stream<UserProfile> _profile = _profileService.watchCurrentProfile();
  late Stream<List<Server>> _servers = _serverRepository.watchMyServers();
  late final FirebaseAuth _firebaseAuth = widget.auth ?? FirebaseAuth.instance;
  late final FirebaseFunctions _firebaseFunctions =
      FirebaseFunctions.instanceFor(region: 'europe-west1');

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

  /// Try again after the profile itself failed to load.
  ///
  /// `watchCurrentProfile()` hands every caller one shared, cached stream,
  /// and a Firestore snapshot listener ends for good after an error. Asking
  /// for it again would return that same dead stream object, and a
  /// [StreamBuilder] only re-subscribes when its stream object changes. So
  /// the cached entry is dropped first: the next call builds a fresh shared
  /// stream with a new listener, and this page subscribes to it. (Pages
  /// already holding the old stream keep it; the next one to subscribe
  /// shares the new one.)
  void _retryProfile() {
    ProfileService.resetCurrentProfileCache();
    setState(() {
      _profile = _profileService.watchCurrentProfile();
      _servers = _serverRepository.watchMyServers();
    });
  }

  /// Try again after the servers list failed: `watchMyServers()` builds a
  /// new stream on every call, and the healthy profile stream is kept.
  void _retryServers() {
    setState(() => _servers = _serverRepository.watchMyServers());
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
      stream: _profile,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ProfileErrorView(
            message: copy.text(
              friendlyErrorMessage(snapshot.error!),
              'Nie udało się wczytać profilu. Spróbuj ponownie.',
            ),
            onRetry: _retryProfile,
          );
        }
        final profile = snapshot.data;
        if (profile == null) {
          return Scaffold(
            key: const ValueKey('profile-loading'),
            backgroundColor: context.appPalette.background,
            body: YoPageBackground(
              // The populated page's canvas, so arriving data changes
              // nothing but the content.
              decoration: ProfileLayout.canvas(context),
              // Back as on the error state: a pushed profile whose load
              // hangs is never a dead end on desktop web, which has no
              // system back gesture.
              child: _WithBack(
                child: Semantics(
                  liveRegion: true,
                  label: copy.text('Loading profile', 'Wczytywanie profilu'),
                  child: const ExcludeSemantics(
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
              ),
            ),
          );
        }

        return StreamBuilder<List<Server>>(
          stream: _servers,
          builder: (context, serversSnapshot) {
            if (serversSnapshot.hasError) {
              return ProfileErrorView(
                message: copy.text(
                  'Your servers could not be loaded.',
                  'Nie udało się wczytać Twoich serwerów.',
                ),
                onRetry: _retryServers,
              );
            }
            final servers = serversSnapshot.data ?? const <Server>[];
            return ProfileScreenView(
              profile: profile,
              servers: servers,
              serversLoading:
                  serversSnapshot.connectionState == ConnectionState.waiting,
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
              onOpenServer: (server) {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ServerWorkspaceScreen(serverId: server.id),
                  ),
                );
              },
              showSuperAdminActivation: _isOwnerAccount,
              isActivatingSuperAdmin: _isActivatingSuperAdmin,
              currentRole: _currentRole,
              onActivateSuperAdmin: _activateSuperAdmin,
              onLogout: () => _authService.signOut(),
              onMyLink: () => unawaited(
                showMyLink(
                  context,
                  auth: _firebaseAuth,
                  profileService: _profileService,
                  mediaService: widget.mediaService,
                  seedProfile: profile,
                ),
              ),
              identityRepository: widget.identityRepository,
              mediaService: widget.mediaService,
            );
          },
        );
      },
    );
  }
}

/// The own profile's page once its data has arrived: canvas, content frame
/// and every block, in reading order.
///
/// Public for the same reason as [ProfileHeader]: the Slim capture harness
/// (`test/slim_profile_capture.dart`) renders THIS widget with fixture data
/// instead of a hand-mirrored copy. The optional services are test / preview
/// seams; production leaves them null and every widget resolves its own.
class ProfileScreenView extends StatelessWidget {
  const ProfileScreenView({
    required this.profile,
    required this.servers,
    required this.serversLoading,
    required this.onEdit,
    required this.onAchievements,
    required this.onOpenServer,
    required this.showSuperAdminActivation,
    required this.isActivatingSuperAdmin,
    required this.currentRole,
    required this.onActivateSuperAdmin,
    required this.onLogout,
    this.onMyLink,
    this.identityRepository,
    this.mediaService,
    this.creatorPinnedPostService,
    this.pinnedMomentService,
    this.pinnedPlayerFactory,
    super.key,
  });

  final UserProfile profile;
  final List<Server> servers;
  final bool serversLoading;
  final VoidCallback onEdit;
  final VoidCallback onAchievements;
  final ValueChanged<Server> onOpenServer;
  final bool showSuperAdminActivation;
  final bool isActivatingSuperAdmin;
  final String currentRole;
  final Future<void> Function() onActivateSuperAdmin;
  final Future<void> Function() onLogout;

  /// Opens "Mój link" (ADR-238). Null (a preview without a session) draws
  /// none of its three entry points.
  final VoidCallback? onMyLink;
  final PublicIdentityRepository? identityRepository;
  final ProfileMediaService? mediaService;
  final CreatorPinnedPostService? creatorPinnedPostService;

  /// Test / preview seams for the pinned Moment's playback (its media
  /// resolver and its player). Production leaves both null.
  final MomentService? pinnedMomentService;
  final AudioPlayer Function()? pinnedPlayerFactory;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Scaffold(
      backgroundColor: palette.background,
      // The scroll view runs the full width of the route so the banner can be
      // the header's full-bleed background; every readable block keeps the
      // 1040pt feed measure through ProfileHeader and the measured padding
      // below.
      body: YoPageBackground(
        // Refine-look R1: the Chats / Friends canvas radial, the same one a
        // friend's profile and every profile state paint; omitted under
        // high contrast.
        decoration: ProfileLayout.canvas(context),
        child: _ProfileContent(
          profile: profile,
          servers: servers,
          serversLoading: serversLoading,
          onEdit: onEdit,
          onAchievements: onAchievements,
          onOpenServer: onOpenServer,
          showSuperAdminActivation: showSuperAdminActivation,
          isActivatingSuperAdmin: isActivatingSuperAdmin,
          currentRole: currentRole,
          onActivateSuperAdmin: onActivateSuperAdmin,
          onLogout: onLogout,
          onMyLink: onMyLink,
          identityRepository: identityRepository,
          mediaService: mediaService,
          creatorPinnedPostService: creatorPinnedPostService,
          pinnedMomentService: pinnedMomentService,
          pinnedPlayerFactory: pinnedPlayerFactory,
        ),
      ),
    );
  }
}

class _ProfileContent extends StatelessWidget {
  const _ProfileContent({
    required this.profile,
    required this.servers,
    required this.serversLoading,
    required this.onEdit,
    required this.onAchievements,
    required this.onOpenServer,
    required this.showSuperAdminActivation,
    required this.isActivatingSuperAdmin,
    required this.currentRole,
    required this.onActivateSuperAdmin,
    required this.onLogout,
    this.onMyLink,
    this.identityRepository,
    this.mediaService,
    this.creatorPinnedPostService,
    this.pinnedMomentService,
    this.pinnedPlayerFactory,
  });

  final UserProfile profile;
  final List<Server> servers;
  final bool serversLoading;
  final VoidCallback onEdit;
  final VoidCallback onAchievements;
  final ValueChanged<Server> onOpenServer;
  final bool showSuperAdminActivation;
  final bool isActivatingSuperAdmin;
  final String currentRole;
  final Future<void> Function() onActivateSuperAdmin;
  final Future<void> Function() onLogout;
  final VoidCallback? onMyLink;
  final PublicIdentityRepository? identityRepository;
  final ProfileMediaService? mediaService;
  final CreatorPinnedPostService? creatorPinnedPostService;
  final MomentService? pinnedMomentService;
  final AudioPlayer Function()? pinnedPlayerFactory;

  void _openFollowList(BuildContext context, FollowListType type) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => FollowListScreen(userId: profile.uid, type: type),
      ),
    );
  }

  /// Stats from real, current data only. Servers is the live
  /// `watchMyServers()` list this page already renders below (never the
  /// achievement engine's `communityCount`, which only ever grows and misses
  /// joins older than the engine), and it is left out while that list is
  /// still loading rather than shown as a made-up 0. Moments stays out until
  /// there is a live count: `momentCount` is the same kind of never-falling
  /// achievement counter and would keep counting deleted or expired Moments.
  /// Followers and following stay behind the one fail-closed
  /// creator-audience gate, as the former `_SocialStats` panel did.
  List<ProfileStat> _stats(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return [
      if (!serversLoading)
        ProfileStat(
          value: servers.length,
          label: copy.navigationServers,
          keyName: 'servers',
        ),
      ProfileStat(
        value: profile.friendCount,
        label: copy.friends,
        keyName: 'friends',
      ),
      if (profile.canExposeCreatorAudience) ...[
        ProfileStat(
          value: profile.followerCount,
          label: copy.text('Followers', 'Obserwujący'),
          keyName: 'followers',
          onTap: () => _openFollowList(context, FollowListType.followers),
        ),
        ProfileStat(
          value: profile.followingCount,
          label: copy.text('Following', 'Obserwowani'),
          keyName: 'following',
          onTap: () => _openFollowList(context, FollowListType.following),
        ),
      ],
    ];
  }

  Widget _actions(BuildContext context) {
    final copy = AppLocalizations.of(context);
    const minimumSize = Size(0, ProfileActionBar.buttonHeight);
    const padding = EdgeInsets.symmetric(horizontal: 12);
    return ProfileActionBar(
      key: const ValueKey('profile-actions'),
      // Refine-look R5: the page's one CTA — the primary action gradient
      // and its lift (the light budget's one CTA lift on Profile). It is
      // still a FilledButton inside, and it paints its own keyboard-focus
      // indicator over the gradient, so it is never wrapped in a second
      // ring (UI.md, semantic colour ownership).
      primary: YoGradientFilledButton(
        key: const ValueKey('profile-edit-button'),
        onPressed: onEdit,
        shape: ProfileActionBar.shape,
        minimumSize: minimumSize,
        padding: padding,
        child: Text(
          copy.text('Edit profile', 'Edytuj profil'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      // R7 neutral: glass, control hairline, page ink.
      secondary: OutlinedButton(
        key: const ValueKey('profile-awards-button'),
        onPressed: onAchievements,
        style: ProfileActionBar.neutralStyle(context).merge(
          OutlinedButton.styleFrom(minimumSize: minimumSize, padding: padding),
        ),
        child: Text(
          copy.text('Awards', 'Nagrody'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      icon: ProfileActionIconButton(
        key: const ValueKey('profile-more-button'),
        icon: Icons.more_horiz_rounded,
        tooltip: copy.more,
        onPressed: () => _showAccountSheet(context),
      ),
    );
  }

  /// The icon action: the account actions in a bottom sheet (contextual
  /// actions live in sheets, not dialogs). The same options stay listed in
  /// the account section at the foot of the page.
  Future<void> _showAccountSheet(BuildContext context) async {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      backgroundColor: palette.surfaceRaised,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onMyLink != null)
              ListTile(
                key: const ValueKey('profile-more-my-link'),
                leading: Icon(
                  Icons.qr_code_2_rounded,
                  color: palette.textPrimary,
                ),
                title: Text(
                  MyLinkCopy(copy).title,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () => Navigator.pop(sheetContext, 'myLink'),
              ),
            ListTile(
              key: const ValueKey('profile-more-edit'),
              leading: Icon(Icons.edit_outlined, color: palette.textPrimary),
              title: Text(
                copy.text('Edit profile', 'Edytuj profil'),
                style: TextStyle(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () => Navigator.pop(sheetContext, 'edit'),
            ),
            ListTile(
              key: const ValueKey('profile-more-logout'),
              leading: Icon(Icons.logout_rounded, color: colors.error),
              title: Text(
                copy.text('Log out', 'Wyloguj się'),
                style: TextStyle(
                  color: colors.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () => Navigator.pop(sheetContext, 'logout'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    switch (choice) {
      case 'myLink':
        onMyLink?.call();
      case 'edit':
        onEdit();
      case 'logout':
        await _confirmLogout(context, onLogout);
    }
  }

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
          child: ProfileHeader(
            profile: profile,
            title: title,
            onEdit: onEdit,
            onMyLink: onMyLink,
            identityRepository: identityRepository,
            mediaService: mediaService,
            stats: _stats(context),
            actions: _actions(context),
          ),
        ),
        ProfileMeasuredSliverPadding(
          maxWidth: ResponsiveContentWidth.feed.maxWidth,
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 124),
          // From a 900 pt column every section takes the header cluster's
          // 640 pt measure, start-aligned under it (the banner stays full
          // width); phones and tablets use the whole column.
          sliver: SliverList.list(
            children: [
              ProfileMeasure(child: ProfileVoiceIdentityCard(profile: profile)),
              if (profile.accountType != AccountType.personal)
                ProfileMeasure(
                  child: CreatorPinnedMomentCard(
                    creatorId: profile.uid,
                    service: creatorPinnedPostService,
                    momentService: pinnedMomentService,
                    playerFactory: pinnedPlayerFactory,
                    outerPadding: const EdgeInsets.only(top: 12),
                    onOpen: (moment) => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            CreatorPinnedMomentScreen(moment: moment),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              ProfileMeasure(
                child: ProfileJourneyCard(
                  communitiesCount: servers.length,
                  messageCount: profile.messageCount,
                  voiceMinutes: profile.voiceMinutes,
                  roomCount: servers
                      .where((server) => server.ownerId == profile.uid)
                      .length,
                ),
              ),
              const SizedBox(height: 12),
              ProfileMeasure(
                child: _ServersCard(
                  servers: servers,
                  currentUid: profile.uid,
                  isLoading: serversLoading,
                  onOpen: onOpenServer,
                ),
              ),
              const SizedBox(height: 12),
              ProfileMeasure(
                child: _AchievementsCard(
                  profile: profile,
                  unlocked: unlocked,
                  onTap: onAchievements,
                ),
              ),
              const SizedBox(height: 12),
              ProfileMeasure(
                child: _AccountCard(
                  onEdit: onEdit,
                  onMyLink: onMyLink,
                  showSuperAdminActivation: showSuperAdminActivation,
                  isActivatingSuperAdmin: isActivatingSuperAdmin,
                  currentRole: currentRole,
                  onActivateSuperAdmin: onActivateSuperAdmin,
                  onLogout: onLogout,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The one log-out confirmation, shared by the account section and the
/// header's account sheet so both paths ask the same question.
Future<void> _confirmLogout(
  BuildContext context,
  Future<void> Function() onLogout,
) async {
  final copy = AppLocalizations.of(context);
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

class _ServersCard extends StatelessWidget {
  const _ServersCard({
    required this.servers,
    required this.currentUid,
    required this.isLoading,
    required this.onOpen,
  });

  final List<Server> servers;
  final String currentUid;
  final bool isLoading;
  final ValueChanged<Server> onOpen;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final total = servers.length;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(
            icon: Icons.hub_rounded,
            title: copy.text('My servers', 'Moje serwery'),
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
                'Your servers will appear here after you join or create one.',
                'Serwery pojawią się tutaj, gdy do nich dołączysz lub je utworzysz.',
              ),
              style: TextStyle(color: palette.textSecondary, height: 1.4),
            )
          else
            // One layer: the servers ride the section as flat faces (the
            // shared `YoServerTile` squircle + name + real member count), not
            // as bordered cards inside the bordered section.
            SizedBox(
              height: _CommunityTile.extent(context),
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  ...servers.map(
                    (server) => Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: _CommunityTile(
                        name: server.name,
                        initial: server.initial,
                        type: server.type,
                        subtitle:
                            '${_memberCount(copy, server.memberCount)}'
                            '${server.ownerId == currentUid ? copy.text(' · Owner', ' · Właściciel') : ''}',
                        badge: copy.text('SERVER', 'SERWER'),
                        isOwner: server.ownerId == currentUid,
                        onTap: () => onOpen(server),
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
}

class _CommunityTile extends StatelessWidget {
  const _CommunityTile({
    required this.name,
    required this.initial,
    required this.type,
    required this.subtitle,
    required this.badge,
    required this.onTap,
    this.isOwner = false,
  });

  final String name;
  final String initial;
  final ServerType type;
  final String subtitle;

  /// "SERVER" — voiced with the name instead of drawn as a pill: the
  /// section heading already says these are servers.
  final String badge;
  final VoidCallback onTap;

  /// Marks a server the member OWNS (board screen 5's crown) — driven by
  /// the server's real ownerId, never a guess.
  final bool isOwner;

  static const double _face = 52;
  static const double _width = 104;

  /// The tile widens with the reader's text (up to 1.75×), so an enlarged
  /// name and member count keep whole words instead of breaking mid-word;
  /// the rail scrolls sideways for the rest.
  static double width(BuildContext context) =>
      _width *
      (MediaQuery.textScalerOf(context).scale(13) / 13).clamp(1.0, 1.75);

  /// The rail's height: the face, then a name line and a two-line meta at
  /// the ambient text scale, so enlarged text grows the rail, never clips it.
  static double extent(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return 8 +
        _face +
        8 +
        scaler.scale(13) * 1.3 +
        scaler.scale(11) * 1.3 * 2 +
        12;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Semantics(
      button: true,
      label: '$name, $badge, $subtitle',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: AppRadius.tile,
        onTap: onTap,
        child: SizedBox(
          width: width(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
            child: Column(
              children: [
                SizedBox.square(
                  dimension: _face,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      YoServerTile(initial: initial, type: type, size: _face),
                      if (isOwner)
                        PositionedDirectional(
                          end: -4,
                          top: -4,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: palette.surfaceRaised,
                              shape: BoxShape.circle,
                              border: Border.all(color: palette.hairline),
                            ),
                            child: const Icon(
                              Icons.workspace_premium_rounded,
                              size: 13,
                              color: AppColors.vipGold,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 13,
                    height: 1.3,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: palette.textTertiary,
                    fontSize: 11,
                    height: 1.3,
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
    return _Panel(
      onTap: onTap,
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
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            _ProgressPill(value: progress),
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
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.onEdit,
    required this.onMyLink,
    required this.showSuperAdminActivation,
    required this.isActivatingSuperAdmin,
    required this.currentRole,
    required this.onActivateSuperAdmin,
    required this.onLogout,
  });

  final VoidCallback onEdit;
  final VoidCallback? onMyLink;
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
          if (onMyLink case final onMyLink?)
            _Option(
              key: const ValueKey('profile-account-my-link'),
              icon: Icons.qr_code_2_rounded,
              title: MyLinkCopy(copy).title,
              onTap: onMyLink,
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
            onTap: () => _confirmLogout(context, onLogout),
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
    return Column(
      children: [
        _RowFocusRing(
          child: ListTile(
            onTap: isActivated || isLoading ? null : onTap,
            // Focus is the ring (R16), not a wash spilling past it.
            focusColor: Colors.transparent,
            minTileHeight: _Option.rowHeight,
            horizontalTitleGap: _Option.titleGap,
            leading: const _GlyphBox(icon: Icons.admin_panel_settings_rounded),
            title: Text(
              isActivated
                  ? copy.text('SuperAdmin active', 'SuperAdmin aktywny')
                  : copy.text('Activate SuperAdmin', 'Aktywuj SuperAdmin'),
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
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
                        ? palette.interactiveForeground
                        : palette.textTertiary,
                  ),
          ),
        ),
        const _RowDivider(),
      ],
    );
  }
}

/// One profile section: the R2 block (refine-look §3) — the top-lit fill, a
/// `hairline` edge, radius 20, Pearl's soft lift; a flat `surface` with a
/// `borderStrong` edge under high contrast. The same finish as the header's
/// stats band, so 12 and 20 never sit together on the page.
///
/// Its content sits on a transparent [Material], so the ink of the rows and
/// taps inside it — the account list, a server face — paints on the section
/// itself, above its fill. A section with [onTap] (the awards panel) is one
/// button with the block's hover, press and focus states.
class _Panel extends StatelessWidget {
  const _Panel({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
  });
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: YoCard(
        padding: padding,
        onTap: onTap,
        child: Material(type: MaterialType.transparency, child: child),
      ),
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
    final heading = Text(
      title,
      style: TextStyle(
        color: palette.textPrimary,
        fontSize: 16,
        height: 1.25,
        fontWeight: FontWeight.w700,
        letterSpacing: -.25,
      ),
    );
    final action = this.action == null
        ? null
        : Text(
            this.action!,
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          );
    final titleRow = Row(
      children: [
        Icon(icon, color: palette.interactiveForeground, size: 20),
        const SizedBox(width: 10),
        Expanded(child: heading),
        if (action != null && !ProfileLayout.largeText(context)) action,
      ],
    );
    // At large text the count moves under the title, so the title keeps
    // whole words instead of being squeezed beside it.
    if (action == null || !ProfileLayout.largeText(context)) return titleRow;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        titleRow,
        const SizedBox(height: 2),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 30),
          child: action,
        ),
      ],
    );
  }
}

/// The next achievement's progress: an 8 px pill track with a
/// `primaryAction` fill that grows once, over `entrance`, from empty to the
/// real value (and on to a new value when it changes). The growth is
/// decorative motion ([AppMotion.decorative]): none under Reduce Motion,
/// accessible navigation or a paused [TickerMode]. The section keeps itself
/// alive in the page's lazy list, so scrolling it away and back never
/// replays the growth. The copy below it carries the numbers for screen
/// readers; the bar adds the percentage.
class _ProgressPill extends StatefulWidget {
  const _ProgressPill({required this.value});

  final double value;

  @override
  State<_ProgressPill> createState() => _ProgressPillState();
}

class _ProgressPillState extends State<_ProgressPill>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final value = widget.value;
    final palette = context.appPalette;
    final scheme = Theme.of(context).colorScheme;
    final highContrast = MediaQuery.highContrastOf(context);
    final clamped = value.clamp(0.0, 1.0);
    return Semantics(
      value: '${(clamped * 100).round()}%',
      child: ExcludeSemantics(
        child: Container(
          key: const ValueKey('profile-achievement-progress'),
          height: 8,
          decoration: BoxDecoration(
            color: palette.surfaceSunken,
            borderRadius: AppRadius.pill,
            border: highContrast
                ? Border.all(color: palette.borderStrong)
                : null,
          ),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: clamped),
            duration: AppMotion.decorative(context)
                ? AppMotion.entrance
                : Duration.zero,
            curve: AppMotion.entranceCurve,
            builder: (context, progress, _) => FractionallySizedBox(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: progress,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: AppGradients.primaryAction(scheme),
                  borderRadius: AppRadius.pill,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _IdentityChipTone { external, voice, learning }

/// One identity detail as a neutral pill (refine-look §8.5): `glass` in
/// Dark, a white fill in Pearl, a `hairline` edge and 12.5 w600 page ink.
/// The tone lives only on the glyph.
class _Chip extends StatelessWidget {
  const _Chip(this.label, this.icon, {required this.tone});
  final String label;
  final IconData icon;
  final _IdentityChipTone tone;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final highContrast = MediaQuery.highContrastOf(context);
    final accent = switch (tone) {
      _IdentityChipTone.external => colors.tertiary,
      _IdentityChipTone.voice => palette.interactiveForeground,
      _IdentityChipTone.learning =>
        palette.isDark
            ? AppColors.vipGold
            : Color.lerp(AppColors.vipGold, palette.textPrimary, .62)!,
    };
    final Color surface;
    if (highContrast) {
      surface = palette.surface;
    } else {
      surface = palette.isDark ? palette.glass : palette.surfaceRaised;
    }
    final usesLargeText = MediaQuery.textScalerOf(context).scale(12.5) >= 18;
    return Container(
      key: ValueKey('profile-identity-chip-$label'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: AppRadius.pill,
        border: Border.all(
          color: highContrast ? palette.borderStrong : palette.hairline,
        ),
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

/// A 40 px R16 glyph box: radius 12, the scheme's container pair as a soft
/// diagonal, the glyph in `interactiveForeground`. [danger] keeps the
/// logout row in error ink on the danger surface.
class _GlyphBox extends StatelessWidget {
  const _GlyphBox({required this.icon, this.danger = false});

  final IconData icon;
  final bool danger;

  static const double size = 40;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final scheme = Theme.of(context).colorScheme;
    final highContrast = MediaQuery.highContrastOf(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: danger
          ? BoxDecoration(
              color: palette.dangerSurface,
              borderRadius: AppRadius.card,
            )
          : AppFinish.glyphBox(scheme, highContrast: highContrast),
      child: Icon(
        icon,
        size: 22,
        color: danger ? scheme.error : palette.interactiveForeground,
      ),
    );
  }
}

/// An account row's keyboard focus (refine-look R16): a 2 px `focus` ring
/// at radius 16, painted over the row so nothing shifts, 4 px inside the
/// row so it sits concentric with the block's radius-20 clip. The rows
/// drop their focus wash (a full-bleed rectangle that spilled past the
/// ring); hover and press keep theirs.
class _RowFocusRing extends StatelessWidget {
  const _RowFocusRing({required this.child});

  final Widget child;

  static const double inset = 4;

  @override
  Widget build(BuildContext context) {
    return ProfileFocusRing(
      key: const ValueKey('profile-account-row-focus-ring'),
      color: context.appPalette.focus,
      borderRadius: const BorderRadius.all(Radius.circular(16)),
      inset: const EdgeInsets.all(inset),
      child: child,
    );
  }
}

/// The hairline between account rows, starting under the row titles.
class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Divider(
      height: 1,
      indent: _Option.dividerIndent,
      endIndent: 16,
      color: MediaQuery.highContrastOf(context)
          ? palette.borderStrong
          : palette.hairline,
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
    super.key,
  });
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool destructive;
  final bool showDivider;

  /// Account rows (refine-look §8.5): 64 px tall, the title 12 px after a
  /// 40 px glyph box, so rows and their hairlines start at 68.
  static const double rowHeight = 64;
  static const double titleGap = 12;
  static const double dividerIndent = 16 + _GlyphBox.size + titleGap;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final color = destructive ? colors.error : palette.textPrimary;
    return Column(
      children: [
        _RowFocusRing(
          child: ListTile(
            onTap: onTap,
            // Focus is the ring (R16), not a wash spilling past it.
            focusColor: Colors.transparent,
            minTileHeight: rowHeight,
            horizontalTitleGap: titleGap,
            leading: _GlyphBox(icon: icon, danger: destructive),
            title: Text(
              title,
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            trailing: Icon(
              Icons.chevron_right_rounded,
              color: palette.textTertiary,
            ),
          ),
        ),
        if (showDivider) const _RowDivider(),
      ],
    );
  }
}

/// The page's error state: the shared [YoErrorState] (a plain-language
/// explanation and Try again) on the page canvas, with Back when the page
/// was pushed as a route. Loading keeps its spinner; nothing here is a
/// placeholder for data that did not arrive.
///
/// Public for the same reason as [ProfileScreenView]: the capture harness
/// renders this exact widget.
class ProfileErrorView extends StatelessWidget {
  const ProfileErrorView({required this.message, this.onRetry, super.key});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Scaffold(
      key: const ValueKey('profile-error'),
      backgroundColor: palette.background,
      body: YoPageBackground(
        // The populated page's canvas, so Try again → loaded changes only
        // the content, never the atmosphere.
        decoration: ProfileLayout.canvas(context),
        child: _WithBack(
          child: Center(
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: ProfileLayout.wideMeasure,
                ),
                child: YoErrorState(message: message, onRetry: onRetry),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The loading and error states' Back, when the profile was pushed as a
/// route (in the desktop shell's content slot it is not, and the shell
/// owns navigation).
class _WithBack extends StatelessWidget {
  const _WithBack({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final canPop = Navigator.of(context).canPop();
    return SafeArea(
      child: Stack(
        children: [
          Positioned.fill(child: child),
          if (canPop)
            PositionedDirectional(
              top: 4,
              start: 6,
              child: IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                tooltip: copy.text('Back', 'Wstecz'),
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                icon: Icon(
                  Icons.arrow_back_rounded,
                  color: palette.textPrimary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
