import 'package:flutter/material.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/features/friends/data/models/friend_request.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/friends/presentation/screens/add_friend_screen.dart';
import 'package:yovoice/features/friends/presentation/screens/blocked_users_screen.dart';
import 'package:yovoice/features/friends/presentation/screens/friend_profile_screen.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/presentation/screens/chat_screen.dart';
import 'package:yovoice/shared/widgets/buttons/yo_icon_button.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';

enum _FriendsFilter { all, online, requests }

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({
    this.isRootTab = false,
    this.showRequestsInitially = false,
    this.friendService,
    this.messageService,
    super.key,
  });

  /// True when hosted as the shell's Friends tab — there is nothing to
  /// pop back to, so the header hides its back button.
  final bool isRootTab;
  final bool showRequestsInitially;
  final FriendService? friendService;
  final MessageService? messageService;

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  static const Color _background = Color(0xFF080711);
  static const Color _surface = Color(0xFF12101D);
  static const Color _border = Color(0xFF30263F);
  static const Color _muted = Color(0xFF9D95AD);
  static const Color _primary = Color(0xFF9D20FF);

  late final FriendService _friendService =
      widget.friendService ?? FriendService();
  late final MessageService _messageService =
      widget.messageService ?? MessageService();
  final TextEditingController _searchController = TextEditingController();

  late final Stream<List<FriendUser>> _friendsStream;
  late final Stream<List<FriendRequest>> _requestsStream;

  final Set<String> _processingRequestIds = <String>{};
  String _query = '';
  _FriendsFilter _filter = _FriendsFilter.all;

  @override
  void initState() {
    super.initState();
    if (widget.showRequestsInitially) {
      _filter = _FriendsFilter.requests;
    }
    _friendsStream = _friendService.watchFriends();
    _requestsStream = _friendService.watchFriendRequests();
    _searchController.addListener(_handleSearchChanged);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_handleSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    final value = _searchController.text.trim().toLowerCase();
    if (value == _query) return;
    setState(() => _query = value);
  }

  Future<void> _openAddFriend() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const AddFriendScreen()),
    );
  }

  Future<void> _openBlockedUsers() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const BlockedUsersScreen()),
    );
  }

  Future<void> _openProfile(FriendUser friend) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => FriendProfileScreen(friend: friend),
      ),
    );
  }

  Future<void> _startChat(FriendUser friend) async {
    try {
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
      if (!mounted) return;
      // `openOrCreateConversation` no longer swallows a refusal from
      // `openDirectConversation` (ADR-062), so a blocked pair, a
      // communication mute or a rate limit arrives here as a real
      // FirebaseFunctionsException. Raw exception text must never be what
      // the user reads.
      _showMessage(
        intentionalOrFriendly(
          error,
          fallback: 'Could not open this conversation.',
        ),
        isError: true,
      );
    }
  }

  Future<void> _acceptRequest(FriendRequest request) async {
    await _runRequestAction(
      request.senderId,
      () => _friendService.acceptFriendRequest(request),
      '${request.senderName} is now your friend.',
    );
  }

  Future<void> _declineRequest(FriendRequest request) async {
    await _runRequestAction(
      request.senderId,
      () => _friendService.declineFriendRequest(request.senderId),
      'Friend request declined.',
    );
  }

  Future<void> _runRequestAction(
    String requestId,
    Future<void> Function() action,
    String successMessage,
  ) async {
    if (_processingRequestIds.contains(requestId)) return;

    setState(() => _processingRequestIds.add(requestId));
    try {
      await action();
      if (mounted) _showMessage(successMessage);
    } catch (error) {
      if (mounted) {
        _showMessage(
          intentionalOrFriendly(
            error,
            fallback: 'Could not update this friend request. Try again.',
          ),
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _processingRequestIds.remove(requestId));
      }
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError
              ? const Color(0xFF481C30)
              : const Color(0xFF203D2C),
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-.86, -.96),
            radius: 1.25,
            colors: [Color(0xFF28103F), Color(0xFF100B1B), _background],
            stops: [0, .38, 1],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: ResponsiveContentFrame(
            width: ResponsiveContentWidth.list,
            alignment: ResponsiveContentAlignment.topLeft,
            child: Column(
              children: [
                _buildHeader(),
                _buildSearch(),
                _buildFilters(),
                const SizedBox(height: 8),
                Expanded(
                  child: _filter == _FriendsFilter.requests
                      ? _buildRequests()
                      : _buildFriends(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxWidth < 440 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.4;
          final leading = <Widget>[
            if (!widget.isRootTab) ...[
              YoIconButton(
                icon: Icons.arrow_back_ios_new_rounded,
                iconSize: 18,
                size: 40,
                backgroundColor: _surface,
                borderColor: _border,
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 10),
            ],
          ];
          const title = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Friends',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.8,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Your people, one tap away.',
                style: TextStyle(color: _muted, fontSize: 13),
              ),
            ],
          );
          final actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              StreamBuilder<int>(
                stream: _friendService.watchPendingFriendRequestCount(),
                builder: (context, snapshot) {
                  final count = snapshot.data ?? 0;
                  return _HeaderButton(
                    tooltip: 'Friend requests',
                    icon: Icons.notifications_none_rounded,
                    badgeCount: count,
                    onTap: () =>
                        setState(() => _filter = _FriendsFilter.requests),
                  );
                },
              ),
              const SizedBox(width: 9),
              _HeaderButton(
                tooltip: 'Blocked users',
                icon: Icons.block_rounded,
                onTap: _openBlockedUsers,
              ),
              const SizedBox(width: 9),
              _HeaderButton(
                tooltip: 'Add friend',
                icon: Icons.person_add_alt_1_rounded,
                highlighted: true,
                onTap: _openAddFriend,
              ),
            ],
          );

          if (compact) {
            return Column(
              children: [
                Row(
                  children: [
                    ...leading,
                    const Expanded(child: title),
                  ],
                ),
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerRight, child: actions),
              ],
            );
          }

          return Row(
            children: [
              ...leading,
              const Expanded(child: title),
              actions,
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearch() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: _filter == _FriendsFilter.requests
              ? 'Search requests...'
              : 'Search friends...',
          hintStyle: const TextStyle(color: _muted),
          prefixIcon: const Icon(Icons.search_rounded, color: _muted),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _searchController,
            builder: (context, value, _) {
              if (value.text.isEmpty) return const SizedBox.shrink();
              return IconButton(
                onPressed: _searchController.clear,
                icon: const Icon(Icons.close_rounded, color: _muted),
              );
            },
          ),
          filled: true,
          fillColor: _surface,
          contentPadding: const EdgeInsets.symmetric(vertical: 13),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(17),
            borderSide: const BorderSide(color: _border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(17),
            borderSide: const BorderSide(color: _primary),
          ),
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 13, 18, 0),
      child: StreamBuilder<int>(
        stream: _friendService.watchPendingFriendRequestCount(),
        builder: (context, snapshot) {
          final requestCount = snapshot.data ?? 0;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(
                  label: 'All',
                  selected: _filter == _FriendsFilter.all,
                  onTap: () => setState(() => _filter = _FriendsFilter.all),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Online',
                  selected: _filter == _FriendsFilter.online,
                  onTap: () => setState(() => _filter = _FriendsFilter.online),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: requestCount > 0
                      ? 'Requests $requestCount'
                      : 'Requests',
                  selected: _filter == _FriendsFilter.requests,
                  onTap: () =>
                      setState(() => _filter = _FriendsFilter.requests),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFriends() {
    return StreamBuilder<List<FriendUser>>(
      stream: _friendsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: _primary),
          );
        }

        if (snapshot.hasError) {
          return _EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'Could not load friends',
            subtitle: friendlyErrorMessage(snapshot.error!),
          );
        }

        final allFriends = snapshot.data ?? const <FriendUser>[];
        final filtered = allFriends
            .where((friend) {
              if (_filter == _FriendsFilter.online && !friend.isOnline) {
                return false;
              }
              if (_query.isEmpty) return true;
              return friend.displayName.toLowerCase().contains(_query) ||
                  friend.searchableUsername.contains(_query);
            })
            .toList(growable: false);

        if (filtered.isEmpty) {
          final isSearching = _query.isNotEmpty;
          return _EmptyState(
            icon: isSearching
                ? Icons.search_off_rounded
                : _filter == _FriendsFilter.online
                ? Icons.wifi_off_rounded
                : Icons.people_outline_rounded,
            title: isSearching
                ? 'No matching friends'
                : _filter == _FriendsFilter.online
                ? 'Nobody is online'
                : 'No friends yet',
            subtitle: isSearching
                ? 'Try another name or username.'
                : _filter == _FriendsFilter.online
                ? 'Online friends will appear here.'
                : 'Find someone and start building your circle.',
            actionLabel: _filter == _FriendsFilter.all && !isSearching
                ? 'Add friend'
                : null,
            onAction: _filter == _FriendsFilter.all && !isSearching
                ? _openAddFriend
                : null,
          );
        }

        final onlineCount = allFriends
            .where((friend) => friend.isOnline)
            .length;

        return ListView(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 120),
          children: [
            _FriendsSummary(
              totalCount: allFriends.length,
              onlineCount: onlineCount,
            ),
            const SizedBox(height: 10),
            ...filtered.map(
              (friend) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _FriendCard(
                  friend: friend,
                  onProfile: () => _openProfile(friend),
                  onMessage: () => _startChat(friend),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRequests() {
    return StreamBuilder<List<FriendRequest>>(
      stream: _requestsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: _primary),
          );
        }

        if (snapshot.hasError) {
          return _EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'Could not load requests',
            subtitle: friendlyErrorMessage(snapshot.error!),
          );
        }

        final requests = (snapshot.data ?? const <FriendRequest>[])
            .where((request) {
              if (_query.isEmpty) return true;
              return request.senderName.toLowerCase().contains(_query);
            })
            .toList(growable: false);

        if (requests.isEmpty) {
          return _EmptyState(
            icon: _query.isEmpty
                ? Icons.mark_email_read_outlined
                : Icons.search_off_rounded,
            title: _query.isEmpty
                ? 'No pending requests'
                : 'No matching requests',
            subtitle: _query.isEmpty
                ? 'New friend requests will appear here.'
                : 'Try another name.',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 120),
          itemCount: requests.length,
          separatorBuilder: (_, __) => const SizedBox(height: 9),
          itemBuilder: (context, index) {
            final request = requests[index];
            return FriendRequestCard(
              request: request,
              processing: _processingRequestIds.contains(request.senderId),
              onAccept: () => _acceptRequest(request),
              onDecline: () => _declineRequest(request),
            );
          },
        );
      },
    );
  }
}

class _FriendsSummary extends StatelessWidget {
  const _FriendsSummary({required this.totalCount, required this.onlineCount});

  final int totalCount;
  final int onlineCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0xB312101D),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _FriendsScreenState._border),
      ),
      child: Row(
        children: [
          const Icon(Icons.groups_2_rounded, color: Color(0xFFB348FF)),
          const SizedBox(width: 10),
          Text(
            '$totalCount friends',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFF20D66B),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            '$onlineCount online',
            style: const TextStyle(color: _FriendsScreenState._muted),
          ),
        ],
      ),
    );
  }
}

class _FriendCard extends StatelessWidget {
  const _FriendCard({
    required this.friend,
    required this.onProfile,
    required this.onMessage,
  });

  final FriendUser friend;
  final VoidCallback onProfile;
  final VoidCallback onMessage;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = friend.photoUrl?.trim().isNotEmpty == true;

    return Material(
      color: _FriendsScreenState._surface,
      borderRadius: BorderRadius.circular(19),
      child: InkWell(
        onTap: onProfile,
        borderRadius: BorderRadius.circular(19),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(19),
            border: Border.all(color: _FriendsScreenState._border),
          ),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Color(0xFFC32BFF), Color(0xFF6D25FF)],
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 27,
                      backgroundColor: const Color(0xFF2A173C),
                      backgroundImage: hasPhoto
                          ? NetworkImage(friend.photoUrl!)
                          : null,
                      child: hasPhoto
                          ? null
                          : Text(
                              friend.initial,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                    ),
                  ),
                  Positioned(
                    right: 1,
                    bottom: 1,
                    child: Container(
                      width: 15,
                      height: 15,
                      decoration: BoxDecoration(
                        color: friend.isOnline
                            ? const Color(0xFF20D66B)
                            : const Color(0xFF6D6275),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _FriendsScreenState._surface,
                          width: 3,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          friend.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        UserIdentityBadges(uid: friend.id),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      friend.isOnline
                          ? 'Online now'
                          : friend.username.isNotEmpty
                          ? '@${friend.username}'
                          : 'Offline',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: friend.isOnline
                            ? const Color(0xFF6EE7A0)
                            : _FriendsScreenState._muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Message',
                onPressed: onMessage,
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF2B183A),
                  foregroundColor: const Color(0xFFD8A0FF),
                ),
                icon: const Icon(Icons.chat_bubble_rounded, size: 20),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right_rounded,
                color: _FriendsScreenState._muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FriendRequestCard extends StatelessWidget {
  const FriendRequestCard({
    required this.request,
    required this.processing,
    required this.onAccept,
    required this.onDecline,
    super.key,
  });

  final FriendRequest request;
  final bool processing;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final photo = request.senderPhotoUrl;
    final hasPhoto = photo != null && photo.trim().isNotEmpty;
    final name = request.senderName.trim().isNotEmpty
        ? request.senderName.trim()
        : 'YO Voice user';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _FriendsScreenState._surface,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: _FriendsScreenState._border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 27,
            backgroundColor: const Color(0xFF5D2181),
            backgroundImage: hasPhoto ? NetworkImage(photo) : null,
            child: hasPhoto
                ? null
                : Text(
                    name.isEmpty ? '?' : name[0].toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
          ),
          const SizedBox(width: 13),
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
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Wants to be your friend',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _FriendsScreenState._muted,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 11),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final textScale = MediaQuery.textScalerOf(context).scale(1);
                    final stackActions =
                        textScale > 1.4 || constraints.maxWidth < 250;
                    final accept = FilledButton.icon(
                      key: const ValueKey('friend-request-accept'),
                      onPressed: processing ? null : onAccept,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        backgroundColor: _FriendsScreenState._primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: processing
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Accept'),
                    );
                    final decline = OutlinedButton.icon(
                      key: const ValueKey('friend-request-decline'),
                      onPressed: processing ? null : onDecline,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        foregroundColor: const Color(0xFFC5BACD),
                        side: const BorderSide(
                          color: _FriendsScreenState._border,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('Decline'),
                    );

                    if (stackActions) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [accept, const SizedBox(height: 8), decline],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(child: accept),
                        const SizedBox(width: 8),
                        Expanded(child: decline),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: selected
            ? _FriendsScreenState._primary
            : _FriendsScreenState._surface,
        borderRadius: BorderRadius.circular(99),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(99),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              border: selected
                  ? null
                  : Border.all(color: _FriendsScreenState._border),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.highlighted = false,
    this.badgeCount = 0,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final bool highlighted;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final semanticLabel = badgeCount > 0
        ? '$tooltip, $badgeCount pending'
        : tooltip;
    return Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: semanticLabel,
        onTap: onTap,
        excludeSemantics: true,
        child: Material(
          color: highlighted
              ? _FriendsScreenState._primary
              : _FriendsScreenState._surface,
          borderRadius: BorderRadius.circular(15),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(15),
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
                border: highlighted
                    ? null
                    : Border.all(color: _FriendsScreenState._border),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Icon(icon, color: Colors.white, size: 21),
                  if (badgeCount > 0)
                    Positioned(
                      top: -5,
                      right: -5,
                      child: Container(
                        constraints: const BoxConstraints(
                          minWidth: 20,
                          minHeight: 20,
                        ),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE51852),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _FriendsScreenState._background,
                            width: 2,
                          ),
                        ),
                        child: Text(
                          badgeCount > 99 ? '99+' : '$badgeCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 130),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFF9C42FF).withValues(alpha: .15),
                borderRadius: BorderRadius.circular(23),
              ),
              child: Icon(icon, color: const Color(0xFFB348FF), size: 35),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _FriendsScreenState._muted,
                fontSize: 13,
                height: 1.45,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  backgroundColor: _FriendsScreenState._primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 13,
                  ),
                ),
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
