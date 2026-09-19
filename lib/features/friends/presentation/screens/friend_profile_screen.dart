import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:yovoice/shared/widgets/backgrounds/yo_page_background.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/friends/data/services/social_graph_service.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/presentation/screens/chat_screen.dart';
import 'package:yovoice/features/creator/data/services/creator_pinned_post_service.dart';
import 'package:yovoice/features/creator/presentation/widgets/creator_pinned_moment_card.dart';
import 'package:yovoice/features/creator/presentation/screens/creator_pinned_moment_screen.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/profile/presentation/screens/follow_list_screen.dart';
import 'package:yovoice/features/profile/presentation/widgets/profile_header.dart';
import 'package:yovoice/features/profile/presentation/widgets/profile_vibe_headline.dart';
import 'package:yovoice/shared/widgets/identity/official_role_badge.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/profile/profile_banner.dart';
import 'package:yovoice/shared/widgets/profile/profile_photo_viewer.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';
import 'package:yovoice/shared/widgets/profile/people_status_ring.dart';

class FriendProfileScreen extends StatefulWidget {
  const FriendProfileScreen({
    required this.friend,
    this.firestore,
    this.auth,
    this.friendService,
    this.messageService,
    this.profileService,
    this.followService,
    this.socialGraphService,
    this.profileMediaService,
    this.creatorPinnedPostService,
    super.key,
  });

  final FriendUser friend;
  final FirebaseFirestore? firestore;
  final FirebaseAuth? auth;

  /// Injectable seams keep responsive widget tests on the exact production
  /// screen without requiring a configured Firebase app.
  final FriendService? friendService;
  final MessageService? messageService;
  final ProfileService? profileService;
  final FollowService? followService;
  final SocialGraphService? socialGraphService;
  final ProfileMediaService? profileMediaService;
  final CreatorPinnedPostService? creatorPinnedPostService;

  @override
  State<FriendProfileScreen> createState() => _FriendProfileScreenState();
}

class _FriendProfileScreenState extends State<FriendProfileScreen> {
  late final FirebaseFirestore _firestore =
      widget.firestore ?? FirebaseFirestore.instance;
  late final FirebaseAuth _auth = widget.auth ?? FirebaseAuth.instance;
  late final FriendService _friendService =
      widget.friendService ?? FriendService(firestore: _firestore, auth: _auth);
  late final MessageService? _ownedMessageService =
      widget.messageService == null &&
          (widget.firestore != null || widget.auth != null)
      ? MessageService(firestore: _firestore, auth: _auth)
      : null;
  late final MessageService _messageService =
      widget.messageService ?? _ownedMessageService ?? MessageService.live;
  late final ProfileMediaService? _profileMediaService =
      widget.profileMediaService ??
      (widget.auth != null ? ProfileMediaService(auth: _auth) : null);
  late final ProfileService _profileService =
      widget.profileService ??
      ProfileService(firestore: _firestore, auth: _auth);
  late final FollowService _followService =
      widget.followService ?? FollowService(firestore: _firestore, auth: _auth);
  late final SocialGraphService _socialGraphService =
      widget.socialGraphService ?? SocialGraphService();

  late final Future<MutualFriendsSummary> _mutualFriendsFuture;

  bool _openingChat = false;
  bool _removingFriend = false;
  bool _changingFollow = false;
  bool _blocking = false;
  bool _openingSocialList = false;

  @override
  void initState() {
    super.initState();
    _mutualFriendsFuture = _socialGraphService
        .getMutualFriends(widget.friend.id)
        .catchError((_) => MutualFriendsSummary.empty);
  }

  @override
  void dispose() {
    unawaited(_ownedMessageService?.dispose());
    super.dispose();
  }

  Future<void> _openChat() async {
    if (_openingChat || _removingFriend) return;
    setState(() => _openingChat = true);
    try {
      final friend = widget.friend;
      final conversationId = await _messageService.openOrCreateConversation(
        otherUserId: friend.id,
        otherDisplayName: friend.displayName,
        otherEmail: friend.email,
        otherPhotoUrl: friend.photoUrl ?? '',
      );
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ChatScreen(
            conversationId: conversationId,
            otherUserId: friend.id,
            otherDisplayName: friend.displayName,
            otherEmail: friend.email,
            otherPhotoUrl: friend.photoUrl ?? '',
            otherProfileUpdatedAt: friend.profileUpdatedAt,
            messageService: _messageService,
            profileMediaService: _profileMediaService,
            firestore: _firestore,
            auth: _auth,
          ),
        ),
      );
    } catch (error) {
      // See ADR-062: a refusal from `openDirectConversation` now reaches
      // this handler instead of being swallowed into a client-side write.
      if (mounted) {
        _showError(
          AppLocalizations.of(context).isPolish
              ? 'Nie udało się otworzyć rozmowy.'
              : intentionalOrFriendly(
                  error,
                  fallback: 'Could not open this conversation.',
                ),
        );
      }
    } finally {
      if (mounted) setState(() => _openingChat = false);
    }
  }

  Future<void> _toggleFollow(bool isFollowing) async {
    if (_changingFollow) return;
    setState(() => _changingFollow = true);
    try {
      if (isFollowing) {
        await _followService.unfollow(widget.friend.id);
      } else {
        await _followService.follow(widget.friend.id);
      }
    } catch (error) {
      if (mounted) _showError(error.toString());
    } finally {
      if (mounted) setState(() => _changingFollow = false);
    }
  }

  Future<void> _confirmRemoveFriend() async {
    if (_openingChat || _removingFriend) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final palette = dialogContext.appPalette;
        final colors = Theme.of(dialogContext).colorScheme;
        final copy = AppLocalizations.of(dialogContext);
        return AlertDialog(
          backgroundColor: palette.surfaceRaised,
          title: Text(
            copy.text('Remove friend?', 'Usunąć ze znajomych?'),
            style: TextStyle(color: palette.textPrimary),
          ),
          content: Text(
            copy.text(
              '${widget.friend.displayName} will be removed from your friends list.',
              '${widget.friend.displayName} zniknie z Twojej listy znajomych.',
            ),
            style: TextStyle(color: palette.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(copy.text('Cancel', 'Anuluj')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: FilledButton.styleFrom(
                backgroundColor: colors.error,
                foregroundColor: colors.onError,
              ),
              child: Text(copy.text('Remove', 'Usuń')),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    setState(() => _removingFriend = true);
    try {
      await _friendService.removeFriend(widget.friend.id);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) _showError(error.toString());
    } finally {
      if (mounted) setState(() => _removingFriend = false);
    }
  }

  Future<void> _confirmBlock() async {
    if (_blocking || _removingFriend) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final palette = dialogContext.appPalette;
        final colors = Theme.of(dialogContext).colorScheme;
        final copy = AppLocalizations.of(dialogContext);
        return AlertDialog(
          backgroundColor: palette.surfaceRaised,
          title: Text(
            copy.text('Block user?', 'Zablokować użytkownika?'),
            style: TextStyle(color: palette.textPrimary),
          ),
          content: Text(
            copy.text(
              '${widget.friend.displayName} will be removed as a friend and '
                  "won't be able to message, follow, or send you requests. You can "
                  'unblock them anytime from Blocked users.',
              '${widget.friend.displayName} zostanie usunięty ze znajomych i nie będzie '
                  'mógł wysyłać Ci wiadomości, obserwować Cię ani zapraszać do znajomych. '
                  'Możesz go odblokować w dowolnej chwili.',
            ),
            style: TextStyle(color: palette.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(copy.text('Cancel', 'Anuluj')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: FilledButton.styleFrom(
                backgroundColor: colors.error,
                foregroundColor: colors.onError,
              ),
              child: Text(copy.text('Block', 'Zablokuj')),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    setState(() => _blocking = true);
    try {
      await _friendService.blockUser(widget.friend.id);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) _showError(error.toString());
    } finally {
      if (mounted) setState(() => _blocking = false);
    }
  }

  void _showError(String message) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message.contains('permission-denied')
                ? copy.text(
                    'Your account is not allowed to do that right now.',
                    'Twoje konto nie może teraz wykonać tej czynności.',
                  )
                : copy.text(
                    'Something went wrong. Please try again.',
                    'Coś poszło nie tak. Spróbuj ponownie.',
                  ),
            style: TextStyle(color: palette.dangerForeground),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: palette.dangerSurface,
        ),
      );
  }

  Future<void> _openList(FollowListType type) async {
    if (_openingSocialList) return;
    _openingSocialList = true;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => FollowListScreen(
            userId: widget.friend.id,
            type: type,
            service: _followService,
          ),
        ),
      );
    } finally {
      _openingSocialList = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<UserProfile>(
      stream: _profileService.watchProfile(widget.friend.id),
      builder: (context, profileSnapshot) {
        if (profileSnapshot.hasError) {
          return _UnavailableProfile(
            onBack: () => Navigator.of(context).maybePop(),
          );
        }
        if (!profileSnapshot.hasData) {
          return const _ProfileLoading();
        }
        final profile = profileSnapshot.data;
        return StreamBuilder<bool>(
          stream: _followService.watchIsFollowing(widget.friend.id),
          builder: (context, followSnapshot) {
            final isFollowing = followSnapshot.data ?? false;
            final palette = context.appPalette;
            final colors = Theme.of(context).colorScheme;
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final copy = AppLocalizations.of(context);
            return Scaffold(
              backgroundColor: palette.background,
              body: YoPageBackground(
                key: const ValueKey('friend-profile-background'),
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(-.8, -1),
                    radius: 1.3,
                    colors: [
                      Color.lerp(
                        palette.backgroundTop,
                        colors.primary,
                        isDark ? .18 : .055,
                      )!,
                      palette.backgroundTop,
                      palette.background,
                    ],
                  ),
                ),
                child: SafeArea(
                  child: ResponsiveContentFrame(
                    width: ResponsiveContentWidth.list,
                    alignment: ResponsiveContentAlignment.topCenter,
                    child: CustomScrollView(
                      key: const ValueKey('friend-profile-content-frame'),
                      slivers: [
                        SliverToBoxAdapter(child: _header()),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                          sliver: SliverList.list(
                            children: [
                              // Slim header (phase 5): banner, then the
                              // identity row (avatar + name + handle +
                              // presence), the stats row and the action bar
                              // — the same pieces, in the same order, as the
                              // own profile's ProfileHeader. The banner stays
                              // fully above the avatar here.
                              _banner(profile),
                              const SizedBox(height: 12),
                              _identity(profile),
                              const SizedBox(height: 10),
                              Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: UserIdentityBadges(
                                  uid: widget.friend.id,
                                  variant: IdentityBadgeVariant.full,
                                ),
                              ),
                              if ((profile?.bio ?? '').trim().isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Align(
                                  alignment: AlignmentDirectional.centerStart,
                                  child: ConstrainedBox(
                                    key: const ValueKey(
                                      'friend-profile-bio-frame',
                                    ),
                                    constraints: const BoxConstraints(
                                      maxWidth: 680,
                                    ),
                                    child: Text(
                                      profile!.bio,
                                      style: TextStyle(
                                        color: palette.textSecondary,
                                        height: 1.45,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 14),
                              _profileBody(profile, isFollowing),
                              const SizedBox(height: 20),
                              TextButton.icon(
                                onPressed: _removingFriend
                                    ? null
                                    : _confirmRemoveFriend,
                                icon: _removingFriend
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.person_remove_outlined),
                                label: Text(
                                  _removingFriend
                                      ? copy.text('Removing...', 'Usuwanie...')
                                      : copy.text(
                                          'Remove friend',
                                          'Usuń ze znajomych',
                                        ),
                                ),
                                style: TextButton.styleFrom(
                                  foregroundColor: palette.dangerForeground,
                                  disabledForegroundColor: palette.textTertiary,
                                ),
                              ),
                              TextButton.icon(
                                onPressed: _blocking ? null : _confirmBlock,
                                icon: _blocking
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.block_rounded),
                                label: Text(
                                  _blocking
                                      ? copy.text(
                                          'Blocking...',
                                          'Blokowanie...',
                                        )
                                      : copy.text(
                                          'Block user',
                                          'Zablokuj użytkownika',
                                        ),
                                ),
                                style: TextButton.styleFrom(
                                  foregroundColor: palette.dangerForeground,
                                  disabledForegroundColor: palette.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _header() {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 18, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            tooltip: copy.text('Back', 'Wstecz'),
            icon: Icon(
              Icons.arrow_back_ios_new_rounded,
              color: palette.textPrimary,
            ),
          ),
          Expanded(
            child: Text(
              copy.text('Profile', 'Profil'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The friend's banner ("zdjęcie w tle"). Own Profile has always drawn one
  /// and a friend's profile drew none, so the same identity read differently
  /// depending on whose profile you opened. The band is sized by available
  /// width, never by a device label.
  Widget _banner(UserProfile? profile) {
    final name = profile?.displayName ?? widget.friend.displayName;
    final revision =
        profile?.profileUpdatedAt ?? widget.friend.profileUpdatedAt;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Breakpoint on the band's own measure, not the window. This feed is
        // capped at ResponsiveContentWidth.list (880) and pays a 20px gutter
        // on each side, so the widest band the screen can ever hand this
        // builder is 840: a 900 threshold is unreachable here and the banner
        // would stay phone-sized on tablets and desktop alike. 700 is the
        // first step above a 768pt tablet's 728px band.
        final height = constraints.maxWidth >= 700 ? 168.0 : 116.0;
        return ProfileBannerButton(
          userId: widget.friend.id,
          displayName: name,
          mediaRevision: revision,
          mediaService: _profileMediaService,
          child: SizedBox(
            width: double.infinity,
            height: height,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ProfileBanner(
                userId: widget.friend.id,
                mediaRevision: revision,
                mediaService: _profileMediaService,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _avatar(UserProfile? profile, {required double radius}) {
    final name = profile?.displayName ?? widget.friend.displayName;
    final revision =
        profile?.profileUpdatedAt ?? widget.friend.profileUpdatedAt;
    const ring = 3.0;
    final extent = (radius + ring) * 2;
    return ProfilePhotoButton(
      userId: widget.friend.id,
      displayName: name,
      mediaRevision: revision,
      mediaService: _profileMediaService,
      minimumSize: Size(extent, extent),
      // Slim: a flat hairline ring from the palette (the former violet →
      // magenta hex gradient was decoration, not state).
      child: Container(
        padding: const EdgeInsets.all(ring),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: context.appPalette.background,
          border: Border.all(color: context.appPalette.border),
        ),
        child: UserAvatar(
          radius: radius,
          userId: widget.friend.id,
          mediaRevision: revision,
          mediaService: _profileMediaService,
          displayName: name,
          backgroundColor: context.appPalette.surfaceSunken,
          premium: profile?.premiumIdentity ?? widget.friend.premiumIdentity,
        ),
      ),
    );
  }

  /// Stats, actions, mutual friends, the pinned Moment and the Voice identity
  /// as ONE group: the profile's social block reads (and scrolls, and is
  /// announced) as a unit, the way the own profile groups them under its
  /// header.
  Widget _profileBody(UserProfile? profile, bool isFollowing) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The same readable measure as the own profile header's counters
        // and buttons.
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _socialStats(profile),
                const SizedBox(height: 12),
                _profileActions(
                  isFollowing,
                  creatorAudienceVisible:
                      profile?.canExposeCreatorAudience == true,
                ),
              ],
            ),
          ),
        ),
        _mutualFriends(),
        if (profile != null && profile.accountType != AccountType.personal)
          CreatorPinnedMomentCard(
            creatorId: widget.friend.id,
            service: widget.creatorPinnedPostService,
            outerPadding: const EdgeInsets.only(top: 12),
            onOpen: (moment) => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => CreatorPinnedMomentScreen(moment: moment),
              ),
            ),
          ),
        const SizedBox(height: 12),
        _voiceIdentity(profile),
      ],
    );
  }

  /// Avatar beside name, handle and presence — the own profile header's
  /// identity row, read from the public projection instead.
  Widget _identity(UserProfile? profile) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final palette = context.appPalette;
        final isWide = constraints.maxWidth >= 700;
        final radius = switch (constraints.maxWidth) {
          < 360 => 34.0,
          < 700 => 40.0,
          _ => 46.0,
        };
        final username = profile?.username ?? '';
        // At large text the name gets the full measure under the avatar
        // instead of a narrow column beside it.
        final stack = MediaQuery.textScalerOf(context).scale(14) >= 21;
        final details = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              header: true,
              child: Text(
                profile?.displayName ?? widget.friend.displayName,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: isWide ? 26 : 22,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.3,
                ),
              ),
            ),
            if (username.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                '@${profile!.username.replaceAll(' ', '').toLowerCase()}',
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            const SizedBox(height: 8),
            _status(),
          ],
        );
        if (stack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _avatar(profile, radius: radius),
              const SizedBox(height: 12),
              details,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _avatar(profile, radius: radius),
            const SizedBox(width: 14),
            Expanded(child: details),
          ],
        );
      },
    );
  }

  Widget _profileActions(
    bool isFollowing, {
    required bool creatorAudienceVisible,
  }) {
    // A hidden audience cannot gain new followers. Existing followers
    // keep the Unfollow action so opting out never traps a relationship.
    final showFollowAction = creatorAudienceVisible || isFollowing;
    final copy = AppLocalizations.of(context);
    return ProfileActionBar(
      key: const ValueKey('friend-profile-actions'),
      primary: showFollowAction
          ? _followButton(isFollowing)
          : _messageButton(primary: true),
      secondary: showFollowAction ? _messageButton(primary: false) : null,
      icon: ProfileActionIconButton(
        key: const ValueKey('friend-profile-more-button'),
        icon: Icons.more_horiz_rounded,
        tooltip: copy.more,
        onPressed: _showMoreSheet,
      ),
    );
  }

  /// The icon action: Remove friend and Block user in a bottom sheet
  /// (contextual actions live in sheets, not dialogs). The same two actions
  /// stay listed at the foot of the profile, and both paths run the same
  /// confirmation.
  Future<void> _showMoreSheet() async {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
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
            ListTile(
              key: const ValueKey('friend-profile-more-remove'),
              enabled: !_removingFriend,
              leading: Icon(
                Icons.person_remove_outlined,
                color: palette.dangerForeground,
              ),
              title: Text(
                copy.text('Remove friend', 'Usuń ze znajomych'),
                style: TextStyle(
                  color: palette.dangerForeground,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () => Navigator.pop(sheetContext, 'remove'),
            ),
            ListTile(
              key: const ValueKey('friend-profile-more-block'),
              enabled: !_blocking,
              leading: Icon(
                Icons.block_rounded,
                color: palette.dangerForeground,
              ),
              title: Text(
                copy.text('Block user', 'Zablokuj użytkownika'),
                style: TextStyle(
                  color: palette.dangerForeground,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () => Navigator.pop(sheetContext, 'block'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'remove':
        await _confirmRemoveFriend();
      case 'block':
        await _confirmBlock();
    }
  }

  Widget _status() {
    final status = PeopleStatus.fromPresence(
      isOnline: widget.friend.isOnline,
      availability: widget.friend.availability,
    );
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: status == PeopleStatus.online
            ? palette.successSurface
            : palette.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        switch (status) {
          PeopleStatus.online => copy.text('Online now', 'Teraz online'),
          // Every other state, including away, uses the one shared mapping so
          // this card can never disagree with the Home rail or the preview
          // sheet — and can never show untranslated English in a Polish UI.
          _ => status.localizedLabel(copy),
        },
        style: TextStyle(
          color: status == PeopleStatus.away
              ? palette.textSecondary
              : status.foreground(palette),
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  /// The public projection (`publicProfiles/{uid}`) carries only
  /// `friendCount`, `followerCount` and `followingCount`, so this row never
  /// shows Servers or Moments; followers / following stay behind the
  /// server-written `creatorAudienceVisible` gate.
  Widget _socialStats(UserProfile? profile) {
    final copy = AppLocalizations.of(context);
    final showCreatorAudience = profile?.canExposeCreatorAudience == true;
    return ProfileStatsRow(
      containerKey: const ValueKey('friend-profile-stats'),
      stats: [
        ProfileStat(
          value: profile?.friendCount ?? 0,
          label: copy.text('Friends', 'Znajomi'),
          keyPrefix: 'friend-profile-stat',
          keyName: 'friends',
        ),
        if (showCreatorAudience) ...[
          ProfileStat(
            value: profile?.followerCount ?? 0,
            label: copy.text('Followers', 'Obserwujący'),
            keyPrefix: 'friend-profile-stat',
            keyName: 'followers',
            onTap: () => _openList(FollowListType.followers),
          ),
          ProfileStat(
            value: profile?.followingCount ?? 0,
            label: copy.text('Following', 'Obserwowani'),
            keyPrefix: 'friend-profile-stat',
            keyName: 'following',
            onTap: () => _openList(FollowListType.following),
          ),
        ],
      ],
    );
  }

  Widget _mutualFriends() {
    return FutureBuilder<MutualFriendsSummary>(
      future: _mutualFriendsFuture,
      builder: (context, snapshot) {
        final palette = context.appPalette;
        final copy = AppLocalizations.of(context);
        final summary = snapshot.data;
        if (summary == null || summary.count == 0) {
          return const SizedBox.shrink();
        }

        return Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 20 + (summary.sample.length.clamp(0, 4) * 14),
                height: 28,
                child: Stack(
                  children: [
                    for (var i = 0; i < summary.sample.length.clamp(0, 4); i++)
                      Positioned(
                        left: i * 14.0,
                        child: _MutualFriendAvatar(
                          friend: summary.sample[i],
                          mediaService: _profileMediaService,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  summary.count == 1
                      ? copy.text('1 mutual friend', '1 wspólny znajomy')
                      : copy.text(
                          '${summary.count} mutual friends',
                          '${summary.count} wspólnych znajomych',
                        ),
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _followButton(bool isFollowing) {
    final colors = Theme.of(context).colorScheme;
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: ProfileActionBar.buttonHeight,
      ),
      child: FilledButton.icon(
        key: const ValueKey('friend-profile-follow-button'),
        onPressed: _changingFollow ? null : () => _toggleFollow(isFollowing),
        style: FilledButton.styleFrom(
          backgroundColor: isFollowing
              ? colors.secondaryContainer
              : colors.primary,
          foregroundColor: isFollowing
              ? colors.onSecondaryContainer
              : colors.onPrimary,
          disabledBackgroundColor: palette.surfaceMuted,
          disabledForegroundColor: palette.textTertiary,
          minimumSize: const Size(0, ProfileActionBar.buttonHeight),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ProfileActionBar.radius),
          ),
        ),
        icon: _changingFollow
            ? const SizedBox(
                width: 17,
                height: 17,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                isFollowing
                    ? Icons.check_rounded
                    : Icons.person_add_alt_1_rounded,
                size: 18,
              ),
        label: Text(
          isFollowing
              ? copy.text('Following', 'Obserwujesz')
              : copy.text('Follow', 'Obserwuj'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  /// Message is the primary CTA when Follow is not offered (an ordinary
  /// profile), and the outlined secondary one beside Follow otherwise.
  Widget _messageButton({required bool primary}) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(ProfileActionBar.radius),
    );
    const minimumSize = Size(0, ProfileActionBar.buttonHeight);
    const padding = EdgeInsets.symmetric(horizontal: 12);
    final icon = _openingChat
        ? const SizedBox(
            width: 17,
            height: 17,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.chat_bubble_outline_rounded, size: 18);
    final label = Text(
      copy.text('Message', 'Wiadomość'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontWeight: FontWeight.w700),
    );
    const key = ValueKey('friend-profile-message-button');
    final onPressed = _openingChat ? null : _openChat;
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: ProfileActionBar.buttonHeight,
      ),
      child: primary
          ? FilledButton.icon(
              key: key,
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                disabledBackgroundColor: palette.surfaceMuted,
                disabledForegroundColor: palette.textTertiary,
                minimumSize: minimumSize,
                padding: padding,
                shape: shape,
              ),
              icon: icon,
              label: label,
            )
          : OutlinedButton.icon(
              key: key,
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                foregroundColor: palette.textPrimary,
                disabledForegroundColor: palette.textTertiary,
                side: BorderSide(color: palette.borderStrong),
                minimumSize: minimumSize,
                padding: padding,
                shape: shape,
              ),
              icon: icon,
              label: label,
            ),
    );
  }

  Widget _voiceIdentity(UserProfile? profile) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final vibe = profile?.statusMessage.trim() ?? '';
    final languages = <String>{
      if ((profile?.nativeLanguage ?? '').isNotEmpty) profile!.nativeLanguage,
      ...?profile?.spokenLanguages,
      ...?profile?.learningLanguages,
    }.toList();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      // Slim: one flat layer, 1 px hairline, the card radius 12.
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.language_rounded,
                color: palette.interactiveForeground,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  copy.text('Voice identity', 'Tożsamość głosowa'),
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if (vibe.isNotEmpty) ...[
            const SizedBox(height: 14),
            ProfileVibeHeadline(
              key: const ValueKey('friend-profile-vibe'),
              vibe: vibe,
            ),
          ],
          if (languages.isNotEmpty) ...[
            const SizedBox(height: 13),
            Text(
              languages.join(' • '),
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
          ] else if (vibe.isEmpty) ...[
            const SizedBox(height: 13),
            Text(
              copy.text(
                'Voice identity not added yet.',
                'Tożsamość głosowa nie została jeszcze uzupełniona.',
              ),
              style: TextStyle(color: palette.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProfileLoading extends StatelessWidget {
  const _ProfileLoading();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('friend-profile-loading'),
      backgroundColor: context.appPalette.background,
      body: YoPageBackground(
        child: Center(
          child: CircularProgressIndicator(
            color: context.appPalette.interactiveForeground,
          ),
        ),
      ),
    );
  }
}

class _UnavailableProfile extends StatelessWidget {
  const _UnavailableProfile({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: palette.background,
      body: YoPageBackground(
        child: SafeArea(
          child: ResponsiveContentFrame(
            width: ResponsiveContentWidth.list,
            alignment: ResponsiveContentAlignment.topCenter,
            child: Column(
              key: const ValueKey('friend-profile-unavailable'),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    tooltip: copy.text('Back', 'Wstecz'),
                    onPressed: onBack,
                    icon: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: palette.surface,
                                shape: BoxShape.circle,
                                border: Border.all(color: palette.border),
                              ),
                              child: Icon(
                                Icons.lock_outline_rounded,
                                color: palette.interactiveForeground,
                                size: 30,
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              copy.text(
                                'This profile isn\'t available',
                                'Ten profil jest niedostępny',
                              ),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: palette.textPrimary,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              copy.text(
                                'The person may have changed who can view their profile.',
                                'Ta osoba mogła zmienić ustawienia widoczności profilu.',
                              ),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: palette.textSecondary,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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

class _MutualFriendAvatar extends StatelessWidget {
  const _MutualFriendAvatar({required this.friend, this.mediaService});

  final SuggestedFriend friend;
  final ProfileMediaService? mediaService;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: palette.surfaceSunken,
        border: Border.all(color: palette.surface, width: 2),
      ),
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      child: UserAvatar(
        radius: 12,
        userId: friend.uid,
        mediaRevision: friend.profileUpdatedAt,
        mediaService: mediaService,
        displayName: friend.displayName,
        backgroundColor: palette.surfaceSunken,
      ),
    );
  }
}
