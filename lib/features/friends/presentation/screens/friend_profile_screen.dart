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
import 'package:yovoice/features/creator/presentation/widgets/creator_pinned_moment_card.dart';
import 'package:yovoice/features/creator/presentation/screens/creator_pinned_moment_screen.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/profile/presentation/screens/follow_list_screen.dart';
import 'package:yovoice/features/profile/presentation/widgets/profile_vibe_headline.dart';
import 'package:yovoice/shared/widgets/identity/official_role_badge.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/profile/profile_photo_viewer.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

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
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
                          sliver: SliverList.list(
                            children: [
                              _avatar(profile),
                              const SizedBox(height: 16),
                              Text(
                                profile?.displayName ??
                                    widget.friend.displayName,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: palette.textPrimary,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              if ((profile?.username ?? '').isNotEmpty)
                                Text(
                                  '@${profile!.username.replaceAll(' ', '').toLowerCase()}',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: palette.textSecondary,
                                    fontSize: 15,
                                  ),
                                ),
                              const SizedBox(height: 8),
                              Center(
                                child: UserIdentityBadges(
                                  uid: widget.friend.id,
                                  variant: IdentityBadgeVariant.full,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Center(child: _status()),
                              if ((profile?.bio ?? '').trim().isNotEmpty) ...[
                                const SizedBox(height: 18),
                                Center(
                                  child: ConstrainedBox(
                                    key: const ValueKey(
                                      'friend-profile-bio-frame',
                                    ),
                                    constraints: const BoxConstraints(
                                      maxWidth: 680,
                                    ),
                                    child: Text(
                                      profile!.bio,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: palette.textSecondary,
                                        height: 1.45,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 22),
                              _socialStats(profile),
                              const SizedBox(height: 14),
                              _mutualFriends(),
                              const SizedBox(height: 18),
                              _profileActions(isFollowing),
                              if (profile != null &&
                                  profile.accountType != AccountType.personal)
                                CreatorPinnedMomentCard(
                                  creatorId: widget.friend.id,
                                  outerPadding: const EdgeInsets.only(top: 14),
                                  onOpen: (moment) =>
                                      Navigator.of(context).push<void>(
                                        MaterialPageRoute<void>(
                                          builder: (_) =>
                                              CreatorPinnedMomentScreen(
                                                moment: moment,
                                              ),
                                        ),
                                      ),
                                ),
                              const SizedBox(height: 14),
                              _voiceIdentity(profile),
                              const SizedBox(height: 26),
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
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatar(UserProfile? profile) {
    final name = profile?.displayName ?? widget.friend.displayName;
    final revision =
        profile?.profileUpdatedAt ?? widget.friend.profileUpdatedAt;
    return Center(
      child: ProfilePhotoButton(
        userId: widget.friend.id,
        displayName: name,
        mediaRevision: revision,
        mediaService: _profileMediaService,
        minimumSize: const Size(124, 124),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [Color(0xFF6A00FF), Color(0xFFD12CFF)],
            ),
          ),
          child: UserAvatar(
            radius: 58,
            userId: widget.friend.id,
            mediaRevision: revision,
            mediaService: _profileMediaService,
            displayName: name,
            backgroundColor: context.appPalette.surfaceSunken,
            premium: profile?.premiumIdentity ?? widget.friend.premiumIdentity,
          ),
        ),
      ),
    );
  }

  Widget _profileActions(bool isFollowing) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaledBodySize = MediaQuery.textScalerOf(context).scale(14);
        final shouldStack = constraints.maxWidth < 360 || scaledBodySize >= 21;
        if (shouldStack) {
          return Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: _followButton(isFollowing),
              ),
              const SizedBox(height: 10),
              SizedBox(width: double.infinity, child: _messageButton()),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: _followButton(isFollowing)),
            const SizedBox(width: 10),
            Expanded(child: _messageButton()),
          ],
        );
      },
    );
  }

  Widget _status() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: widget.friend.isOnline
          ? context.appPalette.successSurface
          : context.appPalette.surfaceMuted,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      widget.friend.isOnline
          ? AppLocalizations.of(context).text('Online now', 'Teraz online')
          : AppLocalizations.of(context).text('Offline', 'Offline'),
      style: TextStyle(
        color: widget.friend.isOnline
            ? context.appPalette.successForeground
            : context.appPalette.textSecondary,
        fontWeight: FontWeight.w700,
        fontSize: 12,
      ),
    ),
  );

  Widget _socialStats(UserProfile? profile) => LayoutBuilder(
    builder: (context, constraints) {
      final palette = context.appPalette;
      final copy = AppLocalizations.of(context);
      final scaledBodySize = MediaQuery.textScalerOf(context).scale(14);
      final shouldStack = constraints.maxWidth < 360 || scaledBodySize >= 21;
      final stats = [
        _stat(
          profile?.friendCount ?? 0,
          copy.text('Friends', 'Znajomi'),
          null,
          keyName: 'friends',
        ),
        _stat(
          profile?.followerCount ?? 0,
          copy.text('Followers', 'Obserwujący'),
          () => _openList(FollowListType.followers),
          keyName: 'followers',
        ),
        _stat(
          profile?.followingCount ?? 0,
          copy.text('Following', 'Obserwowani'),
          () => _openList(FollowListType.following),
          keyName: 'following',
        ),
      ];

      return Container(
        key: const ValueKey('friend-profile-stats'),
        padding: EdgeInsets.symmetric(vertical: shouldStack ? 8 : 17),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: palette.border),
        ),
        child: shouldStack
            ? Column(
                children: [
                  stats[0],
                  Divider(height: 1, color: palette.border),
                  stats[1],
                  Divider(height: 1, color: palette.border),
                  stats[2],
                ],
              )
            : Row(children: [for (final stat in stats) Expanded(child: stat)]),
      );
    },
  );

  Widget _stat(
    int value,
    String label,
    VoidCallback? onTap, {
    required String keyName,
  }) {
    final content = ExcludeSemantics(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$value',
                style: TextStyle(
                  color: context.appPalette.textPrimary,
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  color: context.appPalette.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final key = ValueKey('friend-profile-stat-$keyName');
    if (onTap == null) {
      return Semantics(key: key, label: '$label: $value', child: content);
    }
    return AccessibleTapRegion(
      key: key,
      onTap: onTap,
      semanticLabel: '$label: $value',
      borderRadius: 12,
      child: content,
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(16),
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
      constraints: const BoxConstraints(minHeight: 52),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
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
              ),
        label: Text(
          isFollowing
              ? copy.text('Following', 'Obserwujesz')
              : copy.text('Follow', 'Obserwuj'),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _messageButton() {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: OutlinedButton.icon(
        key: const ValueKey('friend-profile-message-button'),
        onPressed: _openingChat ? null : _openChat,
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.textPrimary,
          disabledForegroundColor: palette.textTertiary,
          side: BorderSide(color: palette.borderStrong),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        icon: _openingChat
            ? const SizedBox(
                width: 17,
                height: 17,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.chat_bubble_outline_rounded),
        label: Text(
          copy.text('Message', 'Wiadomość'),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(20),
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
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  copy.text('Voice identity', 'Tożsamość głosowa'),
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
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
