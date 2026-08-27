import 'package:flutter/material.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/friends/data/services/social_graph_service.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/presentation/screens/chat_screen.dart';
import 'package:yovoice/features/creator/presentation/widgets/creator_pinned_moment_card.dart';
import 'package:yovoice/features/creator/presentation/screens/creator_pinned_moment_screen.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/profile/presentation/screens/follow_list_screen.dart';
import 'package:yovoice/shared/widgets/identity/official_role_badge.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';

class FriendProfileScreen extends StatefulWidget {
  const FriendProfileScreen({
    required this.friend,
    this.friendService,
    this.messageService,
    this.profileService,
    this.followService,
    this.socialGraphService,
    super.key,
  });

  final FriendUser friend;

  /// Injectable seams keep responsive widget tests on the exact production
  /// screen without requiring a configured Firebase app.
  final FriendService? friendService;
  final MessageService? messageService;
  final ProfileService? profileService;
  final FollowService? followService;
  final SocialGraphService? socialGraphService;

  @override
  State<FriendProfileScreen> createState() => _FriendProfileScreenState();
}

class _FriendProfileScreenState extends State<FriendProfileScreen> {
  static const _background = Color(0xFF080711);
  static const _surface = Color(0xFF15101E);
  static const _border = Color(0xFF352840);
  static const _muted = Color(0xFFA99DB3);

  late final FriendService _friendService =
      widget.friendService ?? FriendService();
  late final MessageService _messageService =
      widget.messageService ?? MessageService.live;
  late final ProfileService _profileService =
      widget.profileService ?? ProfileService();
  late final FollowService _followService =
      widget.followService ?? FollowService();
  late final SocialGraphService _socialGraphService =
      widget.socialGraphService ?? SocialGraphService();

  late final Future<MutualFriendsSummary> _mutualFriendsFuture;

  bool _openingChat = false;
  bool _removingFriend = false;
  bool _changingFollow = false;
  bool _blocking = false;

  @override
  void initState() {
    super.initState();
    _mutualFriendsFuture = _socialGraphService
        .getMutualFriends(widget.friend.id)
        .catchError((_) => MutualFriendsSummary.empty);
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
          ),
        ),
      );
    } catch (error) {
      // See ADR-062: a refusal from `openDirectConversation` now reaches
      // this handler instead of being swallowed into a client-side write.
      if (mounted) {
        _showError(
          intentionalOrFriendly(
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
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF171320),
        title: const Text(
          'Remove friend?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          '${widget.friend.displayName} will be removed from your friends list.',
          style: const TextStyle(color: _muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB3264E),
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
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
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF171320),
        title: const Text('Block user?', style: TextStyle(color: Colors.white)),
        content: Text(
          '${widget.friend.displayName} will be removed as a friend and '
          "won't be able to message, follow, or send you requests. You can "
          'unblock them anytime from Blocked users.',
          style: const TextStyle(color: _muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB3264E),
            ),
            child: const Text('Block'),
          ),
        ],
      ),
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
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message.contains('permission-denied')
                ? 'Your account is not allowed to do that right now.'
                : 'Something went wrong. Please try again.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  void _openList(FollowListType type) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => FollowListScreen(userId: widget.friend.id, type: type),
      ),
    );
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
            return Scaffold(
              backgroundColor: _background,
              body: Container(
                key: const ValueKey('friend-profile-background'),
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(-.8, -1),
                    radius: 1.3,
                    colors: [Color(0xFF321051), Color(0xFF120B1E), _background],
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
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              if ((profile?.username ?? '').isNotEmpty)
                                Text(
                                  '@${profile!.username.replaceAll(' ', '').toLowerCase()}',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: _muted,
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
                                      style: const TextStyle(
                                        color: Color(0xFFD4CADC),
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
                                      ? 'Removing...'
                                      : 'Remove friend',
                                ),
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFFFF6F8E),
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
                                  _blocking ? 'Blocking...' : 'Block user',
                                ),
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFF8F8799),
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

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(8, 8, 18, 4),
    child: Row(
      children: [
        IconButton(
          onPressed: () => Navigator.pop(context),
          tooltip: 'Back',
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
        ),
        const Expanded(
          child: Text(
            'Profile',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _avatar(UserProfile? profile) {
    final photo = profile?.photoUrl ?? widget.friend.photoUrl;
    final name = profile?.displayName ?? widget.friend.displayName;
    return Semantics(
      image: true,
      label: 'Profile photo of $name',
      child: ExcludeSemantics(
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFF6A00FF), Color(0xFFD12CFF)],
              ),
            ),
            child: CircleAvatar(
              radius: 58,
              backgroundColor: const Color(0xFF281133),
              backgroundImage: photo?.isNotEmpty == true
                  ? NetworkImage(photo!)
                  : null,
              child: photo?.isNotEmpty == true
                  ? null
                  : Text(
                      name.isEmpty ? '?' : name[0].toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 42,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
            ),
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
          ? const Color(0xFF173726)
          : const Color(0xFF211D29),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      widget.friend.isOnline ? 'Online now' : 'Offline',
      style: TextStyle(
        color: widget.friend.isOnline ? const Color(0xFF73D99A) : _muted,
        fontWeight: FontWeight.w700,
        fontSize: 12,
      ),
    ),
  );

  Widget _socialStats(UserProfile? profile) => LayoutBuilder(
    builder: (context, constraints) {
      final scaledBodySize = MediaQuery.textScalerOf(context).scale(14);
      final shouldStack = constraints.maxWidth < 360 || scaledBodySize >= 21;
      final stats = [
        _stat(profile?.friendCount ?? 0, 'Friends', null),
        _stat(
          profile?.followerCount ?? 0,
          'Followers',
          () => _openList(FollowListType.followers),
        ),
        _stat(
          profile?.followingCount ?? 0,
          'Following',
          () => _openList(FollowListType.following),
        ),
      ];

      return Container(
        key: const ValueKey('friend-profile-stats'),
        padding: EdgeInsets.symmetric(vertical: shouldStack ? 8 : 17),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _border),
        ),
        child: shouldStack
            ? Column(
                children: [
                  stats[0],
                  const Divider(height: 1, color: _border),
                  stats[1],
                  const Divider(height: 1, color: _border),
                  stats[2],
                ],
              )
            : Row(children: [for (final stat in stats) Expanded(child: stat)]),
      );
    },
  );

  Widget _stat(int value, String label, VoidCallback? onTap) => Semantics(
    key: ValueKey('friend-profile-stat-${label.toLowerCase()}'),
    label: '$label: $value',
    button: onTap != null,
    onTap: onTap,
    child: ExcludeSemantics(
      child: InkWell(
        onTap: onTap,
        excludeFromSemantics: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$value',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _mutualFriends() {
    return FutureBuilder<MutualFriendsSummary>(
      future: _mutualFriendsFuture,
      builder: (context, snapshot) {
        final summary = snapshot.data;
        if (summary == null || summary.count == 0) {
          return const SizedBox.shrink();
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _border),
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
                        child: _MutualFriendAvatar(friend: summary.sample[i]),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  summary.count == 1
                      ? '1 mutual friend'
                      : '${summary.count} mutual friends',
                  style: const TextStyle(
                    color: Colors.white,
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

  Widget _followButton(bool isFollowing) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 52),
    child: FilledButton.icon(
      key: const ValueKey('friend-profile-follow-button'),
      onPressed: _changingFollow ? null : () => _toggleFollow(isFollowing),
      style: FilledButton.styleFrom(
        backgroundColor: isFollowing
            ? const Color(0xFF2A2033)
            : const Color(0xFF9F20F4),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      icon: _changingFollow
          ? const SizedBox(
              width: 17,
              height: 17,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Icon(
              isFollowing
                  ? Icons.check_rounded
                  : Icons.person_add_alt_1_rounded,
            ),
      label: Text(
        isFollowing ? 'Following' : 'Follow',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
  );

  Widget _messageButton() => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 52),
    child: OutlinedButton.icon(
      key: const ValueKey('friend-profile-message-button'),
      onPressed: _openingChat ? null : _openChat,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Color(0xFF6B4A7B)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      icon: _openingChat
          ? const SizedBox(
              width: 17,
              height: 17,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.chat_bubble_outline_rounded),
      label: const Text(
        'Message',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
  );

  Widget _voiceIdentity(UserProfile? profile) {
    final languages = <String>{
      if ((profile?.nativeLanguage ?? '').isNotEmpty) profile!.nativeLanguage,
      ...?profile?.spokenLanguages,
      ...?profile?.learningLanguages,
    }.toList();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          const Icon(Icons.language_rounded, color: Color(0xFFB348FF)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              languages.isEmpty
                  ? 'Voice identity not added yet.'
                  : languages.join(' • '),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileLoading extends StatelessWidget {
  const _ProfileLoading();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: _FriendProfileScreenState._background,
      body: Center(child: CircularProgressIndicator(color: Color(0xFFB348FF))),
    );
  }
}

class _UnavailableProfile extends StatelessWidget {
  const _UnavailableProfile({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _FriendProfileScreenState._background,
      body: SafeArea(
        child: ResponsiveContentFrame(
          width: ResponsiveContentWidth.list,
          alignment: ResponsiveContentAlignment.topCenter,
          child: Column(
            key: const ValueKey('friend-profile-unavailable'),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  tooltip: 'Back',
                  onPressed: onBack,
                  icon: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: Colors.white,
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
                              color: _FriendProfileScreenState._surface,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _FriendProfileScreenState._border,
                              ),
                            ),
                            child: const Icon(
                              Icons.lock_outline_rounded,
                              color: Color(0xFFB348FF),
                              size: 30,
                            ),
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            'This profile isn\'t available',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'The person may have changed who can view their profile.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _FriendProfileScreenState._muted,
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
    );
  }
}

class _MutualFriendAvatar extends StatelessWidget {
  const _MutualFriendAvatar({required this.friend});

  final SuggestedFriend friend;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = friend.photoUrl?.trim().isNotEmpty == true;
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF2A173C),
        border: Border.all(color: _FriendProfileScreenState._surface, width: 2),
        image: hasPhoto
            ? DecorationImage(
                image: NetworkImage(friend.photoUrl!),
                fit: BoxFit.cover,
              )
            : null,
      ),
      alignment: Alignment.center,
      child: hasPhoto
          ? null
          : Text(
              friend.initial,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
    );
  }
}
