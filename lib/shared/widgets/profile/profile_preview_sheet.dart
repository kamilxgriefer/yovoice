import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/features/friends/data/models/friend_request.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/friends/data/services/social_graph_service.dart';
import 'package:yovoice/features/friends/presentation/screens/friend_profile_screen.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/presentation/screens/chat_screen.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:yovoice/features/staff/data/staff_capabilities.dart';
import 'package:yovoice/features/staff/presentation/widgets/user_actions_menu.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/overlays/yo_modal_sheet_chrome.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// The one way to open "who is this person?" from anywhere in the app —
/// a tap on any avatar or name (participant lists, chats, friends,
/// moments, search) opens this compact preview instead of yanking the
/// user to a full-screen route. Full profile, message, friend and
/// follow actions are one tap away; backing out returns exactly where
/// the user was (crucial inside a live room — the preview never
/// disconnects or covers the room).
Future<void> showProfilePreview(
  BuildContext context, {
  required String userId,
  String? displayName,
  String? photoUrl,
  FirebaseFirestore? firestore,
  FirebaseAuth? auth,
  FriendService? friendService,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    showDragHandle: false,
    barrierColor: Colors.black.withValues(alpha: .72),
    constraints: ResponsiveContentFrame.adaptiveModalConstraints(context),
    builder: (_) => ProfilePreviewSheet(
      userId: userId,
      seedDisplayName: displayName,
      seedPhotoUrl: photoUrl,
      firestore: firestore,
      auth: auth,
      friendService: friendService,
    ),
  );
}

class ProfilePreviewSheet extends StatefulWidget {
  const ProfilePreviewSheet({
    required this.userId,
    this.seedDisplayName,
    this.seedPhotoUrl,
    this.firestore,
    this.auth,
    this.friendService,
    super.key,
  });

  final String userId;

  /// Whatever the tapping surface already knew — painted instantly while
  /// the real profile loads, so the sheet never opens empty.
  final String? seedDisplayName;
  final String? seedPhotoUrl;

  /// Injection seams keep the production route testable without a live app.
  /// Ordinary call sites leave both null and use the Firebase singletons.
  final FirebaseFirestore? firestore;
  final FirebaseAuth? auth;
  final FriendService? friendService;

  @override
  State<ProfilePreviewSheet> createState() => _ProfilePreviewSheetState();
}

class _ProfilePreviewSheetState extends State<ProfilePreviewSheet> {
  static const _surface = Color(0xFF171021);
  static const _surface2 = Color(0xFF221630);
  static const _border = Color(0xFF3A2C49);
  static const _primary = Color(0xFF9D20FF);
  static const _muted = Color(0xFFA69CAF);
  static const _online = Color(0xFF35D07F);

  late final FirebaseFirestore _firestore =
      widget.firestore ?? FirebaseFirestore.instance;
  late final FirebaseAuth _auth = widget.auth ?? FirebaseAuth.instance;
  late final _profiles = ProfileService(firestore: _firestore, auth: _auth);
  late final _friends =
      widget.friendService ?? FriendService(firestore: _firestore, auth: _auth);
  late final _follows = FollowService(firestore: _firestore, auth: _auth);
  late final _messages = MessageService(firestore: _firestore, auth: _auth);
  final _socialGraph = SocialGraphService();

  FriendRelationshipStatus? _relationship;
  MutualFriendsSummary? _mutuals;
  StaffCapabilities _capabilities = StaffCapabilities.none;
  bool _personallyMuted = false;
  bool _busyFriend = false;
  bool _busyFollow = false;
  bool _busyMessage = false;

  String get _currentUid => _auth.currentUser?.uid ?? '';
  bool get _isSelf => widget.userId == _currentUid;

  @override
  void initState() {
    super.initState();
    // The ••• menu's staff section renders only what the server granted;
    // failure means the personal-only menu, never a guess.
    StaffCapabilityService(auth: _auth)
        .load()
        .then((capabilities) {
          if (mounted) setState(() => _capabilities = capabilities);
        })
        .catchError((_) {});
    if (!_isSelf && _currentUid.isNotEmpty) {
      _firestore
          .collection('users')
          .doc(_currentUid)
          .collection('muted')
          .doc(widget.userId)
          .get()
          .then((snapshot) {
            if (mounted) setState(() => _personallyMuted = snapshot.exists);
          })
          .catchError((_) {});
    }
    if (!_isSelf) {
      unawaited(_loadRelationship());
      unawaited(
        _socialGraph
            .getMutualFriends(widget.userId)
            .then((summary) {
              if (mounted) setState(() => _mutuals = summary);
            })
            // Mutual friends are a bonus, never a blocker: the Cloud
            // Function being cold/unreachable must not break the sheet.
            .catchError((_) {}),
      );
    }
  }

  Future<void> _loadRelationship() async {
    try {
      final status = await _friends.getRelationshipStatus(widget.userId);
      if (mounted) setState(() => _relationship = status);
    } catch (_) {
      // Leave the friend button in its loading state rather than lying.
    }
  }

  FriendUser _asFriendUser(UserProfile profile) => FriendUser(
    id: profile.uid,
    displayName: profile.displayName,
    email: profile.email,
    photoUrl: profile.photoUrl,
    isOnline: false,
    lastSeen: null,
  );

  void _snack(Object error, String fallback) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(intentionalOrFriendly(error, fallback: fallback))),
    );
  }

  Future<void> _openFullProfile(UserProfile profile) async {
    Navigator.of(context).pop();
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => FriendProfileScreen(friend: _asFriendUser(profile)),
      ),
    );
  }

  Future<void> _message(UserProfile profile) async {
    if (_busyMessage) return;
    setState(() => _busyMessage = true);
    try {
      final conversationId = await _messages.openOrCreateConversation(
        otherUserId: profile.uid,
        otherDisplayName: profile.displayName,
        otherEmail: profile.email,
        otherPhotoUrl: profile.photoUrl ?? '',
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ChatScreen(
            conversationId: conversationId,
            otherUserId: profile.uid,
            otherDisplayName: profile.displayName,
            otherEmail: profile.email,
            otherPhotoUrl: profile.photoUrl ?? '',
          ),
        ),
      );
    } catch (error) {
      _snack(error, "Couldn't open this chat. Please try again.");
    } finally {
      if (mounted) setState(() => _busyMessage = false);
    }
  }

  Future<void> _friendAction(UserProfile profile) async {
    final status = _relationship;
    if (status == null || _busyFriend) return;
    setState(() => _busyFriend = true);
    try {
      switch (status) {
        case FriendRelationshipStatus.none:
          final relationship = await _friends.sendFriendRequest(
            _asFriendUser(profile),
          );
          if (mounted) {
            setState(() => _relationship = relationship);
          }
        case FriendRelationshipStatus.requestSent:
          await _friends.cancelFriendRequest(profile.uid);
          if (mounted) {
            setState(() => _relationship = FriendRelationshipStatus.none);
          }
        case FriendRelationshipStatus.requestReceived:
          await _friends.acceptFriendRequest(
            FriendRequestLike.from(profile).toRequest(),
          );
          if (mounted) {
            setState(() => _relationship = FriendRelationshipStatus.friends);
          }
        case FriendRelationshipStatus.friends:
        case FriendRelationshipStatus.blocked:
          break;
      }
    } catch (error) {
      _snack(error, "Couldn't update your friend request. Please try again.");
    } finally {
      if (mounted) setState(() => _busyFriend = false);
    }
  }

  Future<void> _toggleFollow(bool isFollowing, UserProfile profile) async {
    if (_busyFollow) return;
    setState(() => _busyFollow = true);
    try {
      if (isFollowing) {
        await _follows.unfollow(profile.uid);
      } else {
        await _follows.follow(profile.uid);
      }
    } catch (error) {
      _snack(error, "Couldn't update follow. Please try again.");
    } finally {
      if (mounted) setState(() => _busyFollow = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .9,
      ),
      decoration: const BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: _border)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: StreamBuilder<UserProfile>(
        stream: _profiles.watchProfile(widget.userId),
        builder: (context, snapshot) {
          final profile = snapshot.data;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle centred, the ••• user-actions menu upper-right —
              // present on every account's sheet with the personal
              // actions, growing the staff section only when the server
              // granted one.
              SizedBox(
                height: 48,
                child: Stack(
                  alignment: Alignment.topCenter,
                  children: [
                    const YoModalSheetChrome(
                      sheetLabel: 'profile preview',
                      surfaceColor: _surface,
                    ),
                    if (!_isSelf)
                      Positioned(
                        right: 56,
                        top: 2,
                        child: UserActionsMenu(
                          targetUid: widget.userId,
                          targetName:
                              profile?.displayName ??
                              widget.seedDisplayName ??
                              'this user',
                          capabilities: _capabilities,
                          currentUid: _currentUid,
                          isBlocked:
                              _relationship == FriendRelationshipStatus.blocked,
                          isPersonallyMuted: _personallyMuted,
                          onChanged: () {
                            if (mounted) {
                              setState(
                                () => _personallyMuted = !_personallyMuted,
                              );
                            }
                          },
                        ),
                      ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
                  child: snapshot.hasError
                      ? _ErrorBody(error: snapshot.error!)
                      : _Body(
                          userId: widget.userId,
                          profile: profile,
                          seedDisplayName: widget.seedDisplayName,
                          seedPhotoUrl: widget.seedPhotoUrl,
                          isSelf: _isSelf,
                          relationship: _relationship,
                          mutuals: _mutuals,
                          busyFriend: _busyFriend,
                          busyMessage: _busyMessage,
                          busyFollow: _busyFollow,
                          followStream: _isSelf
                              ? null
                              : _follows.watchIsFollowing(widget.userId),
                          onOpenFull: _openFullProfile,
                          onMessage: _message,
                          onFriend: _friendAction,
                          onFollow: _toggleFollow,
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Bridges a [UserProfile] into the FriendRequest shape
/// acceptFriendRequest expects (it only ever reads senderId + names).
class FriendRequestLike {
  FriendRequestLike._(this._profile);

  factory FriendRequestLike.from(UserProfile profile) =>
      FriendRequestLike._(profile);

  final UserProfile _profile;

  FriendRequest toRequest() => FriendRequest(
    senderId: _profile.uid,
    senderName: _profile.displayName,
    senderEmail: _profile.email,
    senderPhotoUrl: _profile.photoUrl,
    createdAt: null,
  );
}

class _Body extends StatelessWidget {
  const _Body({
    required this.userId,
    required this.profile,
    required this.seedDisplayName,
    required this.seedPhotoUrl,
    required this.isSelf,
    required this.relationship,
    required this.mutuals,
    required this.busyFriend,
    required this.busyMessage,
    required this.busyFollow,
    required this.followStream,
    required this.onOpenFull,
    required this.onMessage,
    required this.onFriend,
    required this.onFollow,
  });

  final String userId;
  final UserProfile? profile;
  final String? seedDisplayName;
  final String? seedPhotoUrl;
  final bool isSelf;
  final FriendRelationshipStatus? relationship;
  final MutualFriendsSummary? mutuals;
  final bool busyFriend;
  final bool busyMessage;
  final bool busyFollow;
  final Stream<bool>? followStream;
  final ValueChanged<UserProfile> onOpenFull;
  final ValueChanged<UserProfile> onMessage;
  final ValueChanged<UserProfile> onFriend;
  final void Function(bool isFollowing, UserProfile profile) onFollow;

  static const _muted = _ProfilePreviewSheetState._muted;

  @override
  Widget build(BuildContext context) {
    final name = profile?.displayName ?? seedDisplayName ?? '…';
    final photo = profile?.photoUrl ?? seedPhotoUrl;
    final vibe = profile?.statusMessage.trim() ?? '';
    final bio = profile?.bio.trim() ?? '';
    final headline = vibe.isNotEmpty ? vibe : bio;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Color(0xFF6A00FF), Color(0xFFD12CFF)],
                ),
              ),
              child: UserAvatar(
                radius: 34,
                photoUrl: photo,
                displayName: name,
                premium: profile?.premiumIdentity ?? false,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 3),
                  if (profile != null)
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '@${profile!.username}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _muted,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _PresenceDot(online: profile!.isOnline),
                      ],
                    ),
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      // The authoritative identity leads: official role
                      // always, VIP beside it when held. The chips after
                      // are account/social facts, not roles.
                      UserIdentityBadges(uid: userId),
                      if (profile?.accountType == AccountType.creator)
                        const _Chip(
                          icon: Icons.auto_awesome_rounded,
                          label: 'Creator',
                          color: Color(0xFFC98BFF),
                        ),
                      if (profile?.accountType == AccountType.official)
                        const _Chip(
                          icon: Icons.verified_rounded,
                          label: 'Official',
                          color: Color(0xFF6FC3FF),
                        ),
                      if (relationship == FriendRelationshipStatus.friends)
                        const _Chip(
                          icon: Icons.people_alt_rounded,
                          label: 'Friends',
                          color: Color(0xFF35D07F),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        if (headline.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            headline,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFD9CFE3),
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ],
        if (!isSelf && (mutuals?.count ?? 0) > 0) ...[
          const SizedBox(height: 10),
          Text(
            mutuals!.count == 1
                ? '1 mutual friend'
                : '${mutuals!.count} mutual friends',
            style: const TextStyle(
              color: _muted,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 18),
        if (isSelf)
          _SecondaryButton(
            icon: Icons.person_rounded,
            label: 'This is you',
            onPressed: null,
          )
        else if (relationship == FriendRelationshipStatus.blocked)
          const Text(
            'You have blocked this user.',
            style: TextStyle(color: _muted, fontSize: 13),
          )
        else ...[
          LayoutBuilder(
            builder: (context, constraints) {
              final stackActions =
                  constraints.maxWidth < 330 ||
                  MediaQuery.textScalerOf(context).scale(1) >= 1.5;
              final message = _PrimaryButton(
                icon: Icons.chat_bubble_rounded,
                label: 'Message',
                busy: busyMessage,
                onPressed: profile == null ? null : () => onMessage(profile!),
              );

              if (stackActions) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    message,
                    const SizedBox(height: 8),
                    _friendButton(),
                    if (followStream != null) ...[
                      const SizedBox(height: 8),
                      _followButton(),
                    ],
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: message),
                  const SizedBox(width: 10),
                  Expanded(child: _friendButton()),
                  if (followStream != null) ...[
                    const SizedBox(width: 10),
                    Expanded(child: _followButton()),
                  ],
                ],
              );
            },
          ),
        ],
        const SizedBox(height: 10),
        Center(
          child: TextButton(
            onPressed: profile == null ? null : () => onOpenFull(profile!),
            child: const Text(
              'View full profile',
              style: TextStyle(
                color: Color(0xFFC98BFF),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _friendButton() {
    final (label, icon, enabled) = switch (relationship) {
      null => ('…', Icons.person_add_alt_1_rounded, false),
      FriendRelationshipStatus.none => (
        'Add friend',
        Icons.person_add_alt_1_rounded,
        true,
      ),
      FriendRelationshipStatus.requestSent => (
        'Requested',
        Icons.hourglass_top_rounded,
        true,
      ),
      FriendRelationshipStatus.requestReceived => (
        'Accept',
        Icons.check_circle_rounded,
        true,
      ),
      FriendRelationshipStatus.friends => (
        'Friends',
        Icons.people_alt_rounded,
        false,
      ),
      FriendRelationshipStatus.blocked => (
        'Blocked',
        Icons.block_rounded,
        false,
      ),
    };
    return _SecondaryButton(
      icon: icon,
      label: label,
      busy: busyFriend,
      onPressed: enabled && profile != null ? () => onFriend(profile!) : null,
    );
  }

  Widget _followButton() {
    return StreamBuilder<bool>(
      stream: followStream,
      builder: (context, snapshot) {
        final following = snapshot.data ?? false;
        return _SecondaryButton(
          icon: following
              ? Icons.notifications_active_rounded
              : Icons.rss_feed_rounded,
          label: following ? 'Following' : 'Follow',
          busy: busyFollow,
          onPressed: profile == null || !snapshot.hasData
              ? null
              : () => onFollow(following, profile!),
        );
      },
    );
  }
}

class _PresenceDot extends StatelessWidget {
  const _PresenceDot({required this.online});

  final bool online;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: online
                ? _ProfilePreviewSheetState._online
                : const Color(0xFF5C5368),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          online ? 'Online' : 'Offline',
          style: const TextStyle(
            color: _ProfilePreviewSheetState._muted,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final showIcon = MediaQuery.textScalerOf(context).scale(1) < 1.5;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: .4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showIcon) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: busy ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: _ProfilePreviewSheetState._primary,
        padding: const EdgeInsets.symmetric(vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
      icon: busy
          ? const SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Icon(icon, size: 17),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: busy ? null : onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        disabledForegroundColor: const Color(0xFF9C90A8),
        side: const BorderSide(color: _ProfilePreviewSheetState._border),
        backgroundColor: _ProfilePreviewSheetState._surface2,
        padding: const EdgeInsets.symmetric(vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
      icon: busy
          ? const SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 17),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(
          intentionalOrFriendly(
            error,
            fallback: "Couldn't load this profile. Please try again.",
          ),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFFA69CAF), fontSize: 14),
        ),
      ),
    );
  }
}
