import 'dart:async';

import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/friends/data/models/friend_request.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/friends/data/services/social_graph_service.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

class AddFriendScreen extends StatefulWidget {
  const AddFriendScreen({
    this.friendService,
    this.socialGraphService,
    super.key,
  });

  /// Optional injection seams, matching the established pattern on
  /// ChatScreen and NotificationsScreen: production passes nothing and
  /// gets the live services, tests pass fakes so the accept/decline
  /// wiring below can be exercised without a Firebase app.
  final FriendService? friendService;
  final SocialGraphService? socialGraphService;

  @override
  State<AddFriendScreen> createState() => _AddFriendScreenState();
}

class _AddFriendScreenState extends State<AddFriendScreen> {
  late final FriendService _friendService =
      widget.friendService ?? FriendService();
  late final SocialGraphService _socialGraphService =
      widget.socialGraphService ?? SocialGraphService();
  final TextEditingController _searchController = TextEditingController();

  Timer? _searchDebounce;
  List<FriendUser> _results = const [];
  final Map<String, FriendRelationshipStatus> _relationshipStatuses = {};
  final Set<String> _processingIds = <String>{};
  final Map<String, FriendRelationshipStatus> _suggestionStatuses = {};

  bool _isSearching = false;
  String? _errorMessage;
  late Future<List<SuggestedFriend>> _suggestionsFuture;

  @override
  void initState() {
    super.initState();
    _suggestionsFuture = _socialGraphService.getFriendSuggestions();
  }

  void _retrySuggestions() {
    setState(() {
      _suggestionsFuture = _socialGraphService.getFriendSuggestions();
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _addSuggestion(SuggestedFriend suggestion) async {
    if (_processingIds.contains(suggestion.uid)) return;
    setState(() => _processingIds.add(suggestion.uid));
    try {
      final relationship = await _friendService.sendFriendRequest(
        FriendUser(
          id: suggestion.uid,
          displayName: suggestion.displayName,
          email: '',
          photoUrl: suggestion.photoUrl,
          isOnline: false,
          lastSeen: null,
        ),
      );
      if (!mounted) return;
      setState(() => _suggestionStatuses[suggestion.uid] = relationship);
      _showMessage(
        relationship == FriendRelationshipStatus.friends
            ? 'You and ${suggestion.displayName} are now friends.'
            : 'Friend request sent to ${suggestion.displayName}.',
      );
    } catch (error) {
      if (mounted) _showError(_readableError(error));
    } finally {
      if (mounted) setState(() => _processingIds.remove(suggestion.uid));
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final query = value.trim();

    if (query.length < 2) {
      setState(() {
        _results = const [];
        _relationshipStatuses.clear();
        _isSearching = false;
        _errorMessage = null;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _errorMessage = null;
    });

    _searchDebounce = Timer(const Duration(milliseconds: 450), () {
      _searchUsers(query);
    });
  }

  Future<void> _searchUsers(String query) async {
    try {
      final users = await _friendService.searchUsers(query);
      final statuses = await Future.wait(
        users.map((user) => _friendService.getRelationshipStatus(user.id)),
      );

      if (!mounted || _searchController.text.trim() != query) {
        return;
      }

      setState(() {
        _results = users;
        _relationshipStatuses
          ..clear()
          ..addEntries(
            List.generate(
              users.length,
              (index) => MapEntry(users[index].id, statuses[index]),
            ),
          );
        _isSearching = false;
        _errorMessage = null;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _results = const [];
        _relationshipStatuses.clear();
        _isSearching = false;
        _errorMessage = _readableError(error);
      });
    }
  }

  Future<void> _handlePrimaryAction(FriendUser user) async {
    if (_processingIds.contains(user.id)) return;

    final status =
        _relationshipStatuses[user.id] ?? FriendRelationshipStatus.none;

    if (status == FriendRelationshipStatus.friends) {
      return;
    }

    setState(() => _processingIds.add(user.id));

    try {
      if (status == FriendRelationshipStatus.requestSent) {
        await _friendService.cancelFriendRequest(user.id);

        if (!mounted) return;
        setState(() {
          _relationshipStatuses[user.id] = FriendRelationshipStatus.none;
        });
        _showMessage('Friend request cancelled.');
        return;
      }

      if (status == FriendRelationshipStatus.requestReceived) {
        // Accepting must go through the explicit accept mutation, never a
        // reciprocal sendFriendRequest — "Accept" relying on the server's
        // reciprocal-accept branch is exactly how sending auto-created a
        // friendship. Mirrors ProfilePreviewSheet's accept wiring.
        await _friendService.acceptFriendRequest(
          FriendRequest(
            senderId: user.id,
            senderName: user.displayName,
            senderEmail: user.email,
            senderPhotoUrl: user.photoUrl,
            createdAt: null,
          ),
        );

        if (!mounted) return;
        setState(() {
          _relationshipStatuses[user.id] = FriendRelationshipStatus.friends;
        });
        _showMessage('You and ${user.displayName} are now friends.');
        return;
      }

      final relationship = await _friendService.sendFriendRequest(user);

      if (!mounted) return;

      setState(() {
        _relationshipStatuses[user.id] = relationship;
      });

      _showMessage(
        relationship == FriendRelationshipStatus.friends
            ? 'You and ${user.displayName} are now friends.'
            : 'Friend request sent to ${user.displayName}.',
      );
    } catch (error) {
      if (!mounted) return;

      final message = _readableError(error);

      if (message == 'You are already friends.') {
        setState(() {
          _relationshipStatuses[user.id] = FriendRelationshipStatus.friends;
        });
      } else if (message == 'Friend request already sent.') {
        setState(() {
          _relationshipStatuses[user.id] = FriendRelationshipStatus.requestSent;
        });
      }

      _showError(message);
    } finally {
      if (mounted) {
        setState(() => _processingIds.remove(user.id));
      }
    }
  }

  Future<void> _declineRequest(FriendUser user) async {
    if (_processingIds.contains(user.id)) return;
    if (_relationshipStatuses[user.id] !=
        FriendRelationshipStatus.requestReceived) {
      return;
    }

    setState(() => _processingIds.add(user.id));

    try {
      await _friendService.declineFriendRequest(user.id);

      if (!mounted) return;
      setState(() {
        _relationshipStatuses[user.id] = FriendRelationshipStatus.none;
      });
      _showMessage('Friend request declined.');
    } catch (error) {
      if (mounted) _showError(_readableError(error));
    } finally {
      if (mounted) {
        setState(() => _processingIds.remove(user.id));
      }
    }
  }

  String _readableError(Object error) {
    final message = error.toString();

    if (message.contains('cannot add yourself')) {
      return 'You cannot add yourself.';
    }
    if (message.contains('already friends')) {
      return 'You are already friends.';
    }
    if (message.contains('already sent')) {
      return 'Friend request already sent.';
    }
    if (message.contains('no longer exists')) {
      return 'This user no longer exists.';
    }
    if (message.contains('not signed in')) {
      return 'You must be signed in.';
    }
    if (message.contains('permission-denied')) {
      return 'Firestore permission denied. Check your security rules.';
    }
    if (message.contains('unavailable')) {
      return 'Service is temporarily unavailable. Check your connection.';
    }

    return 'Something went wrong. Please try again.';
  }

  void _showMessage(String message) {
    final palette = context.appPalette;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(color: palette.successForeground),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: palette.successSurface,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  void _showError(String message) {
    final palette = context.appPalette;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(color: palette.dangerForeground),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: palette.dangerSurface,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      key: const ValueKey('add-friend-screen'),
      backgroundColor: palette.background,
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.85, -0.95),
            radius: 1.25,
            colors: [
              Color.lerp(
                palette.backgroundTop,
                colors.primary,
                isDark ? .18 : .055,
              )!,
              palette.backgroundTop,
              palette.background,
            ],
            stops: const [0, 0.38, 1],
          ),
        ),
        child: SafeArea(
          child: ResponsiveContentFrame(
            width: ResponsiveContentWidth.list,
            alignment: ResponsiveContentAlignment.topLeft,
            child: Column(
              children: [
                _buildHeader(),
                _buildSearchField(),
                Expanded(child: _buildContent()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final palette = context.appPalette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 18, 10),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Back',
            icon: Icon(
              Icons.arrow_back_ios_new_rounded,
              color: palette.textPrimary,
              size: 21,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Add friends',
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Search by name or username',
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    final palette = context.appPalette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        textInputAction: TextInputAction.search,
        keyboardType: TextInputType.text,
        style: TextStyle(
          color: palette.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          hintText: 'Search people...',
          hintStyle: TextStyle(color: palette.textTertiary, fontSize: 15),
          prefixIcon: Icon(Icons.search_rounded, color: palette.textSecondary),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  tooltip: 'Clear search',
                  onPressed: () {
                    _searchDebounce?.cancel();
                    _searchController.clear();
                    setState(() {
                      _results = const [];
                      _relationshipStatuses.clear();
                      _isSearching = false;
                      _errorMessage = null;
                    });
                  },
                  icon: Icon(Icons.close_rounded, color: palette.textSecondary),
                )
              : null,
          filled: true,
          fillColor: palette.surface,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 17,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: palette.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: palette.focus, width: 2),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    final query = _searchController.text.trim();

    if (_isSearching) {
      return Center(
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: context.appPalette.interactiveForeground,
        ),
      );
    }

    if (_errorMessage != null) {
      return _SearchState(
        icon: Icons.error_outline_rounded,
        title: 'Could not search users',
        subtitle: _errorMessage!,
      );
    }

    if (query.length < 2) {
      return _buildSuggestions();
    }

    if (_results.isEmpty) {
      return const _SearchState(
        icon: Icons.search_off_rounded,
        title: 'No users found',
        subtitle: 'Try another display name or username.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final user = _results[index];
        return _UserResultCard(
          user: user,
          relationshipStatus:
              _relationshipStatuses[user.id] ?? FriendRelationshipStatus.none,
          isProcessing: _processingIds.contains(user.id),
          onPressed: () => _handlePrimaryAction(user),
          onDecline: () => _declineRequest(user),
        );
      },
    );
  }

  Widget _buildSuggestions() {
    return FutureBuilder<List<SuggestedFriend>>(
      future: _suggestionsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Center(
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: context.appPalette.interactiveForeground,
            ),
          );
        }
        if (snapshot.hasError) {
          return _SearchState(
            icon: Icons.cloud_off_rounded,
            title: 'Could not load suggestions',
            subtitle: 'Check your connection and try again.',
            actionLabel: 'Retry',
            onAction: _retrySuggestions,
          );
        }
        final suggestions = snapshot.data ?? const <SuggestedFriend>[];
        if (suggestions.isEmpty) {
          return const _SearchState(
            icon: Icons.person_search_rounded,
            title: 'Find someone you know',
            subtitle:
                'Enter at least 2 characters from their display name or username.',
          );
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 10, left: 2),
              child: Text(
                'Suggested for you',
                style: TextStyle(
                  color: context.appPalette.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            ...suggestions.map(
              (suggestion) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _SuggestionCard(
                  suggestion: suggestion,
                  isProcessing: _processingIds.contains(suggestion.uid),
                  relationshipStatus: _suggestionStatuses[suggestion.uid],
                  onPressed: () => _addSuggestion(suggestion),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    required this.suggestion,
    required this.isProcessing,
    required this.relationshipStatus,
    required this.onPressed,
  });

  final SuggestedFriend suggestion;
  final bool isProcessing;
  final FriendRelationshipStatus? relationshipStatus;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final isFriend = relationshipStatus == FriendRelationshipStatus.friends;
    final isSent = relationshipStatus == FriendRelationshipStatus.requestSent;
    final isComplete = isFriend || isSent;

    return Container(
      key: ValueKey('friend-suggestion-${suggestion.uid}'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            padding: const EdgeInsets.all(2),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFFC32BFF), Color(0xFF6D25FF)],
              ),
            ),
            child: ClipOval(
              child: UserAvatar(
                radius: 24,
                userId: suggestion.uid,
                displayName: suggestion.displayName,
                backgroundColor: palette.surfaceSunken,
              ),
            ),
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
                      suggestion.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    UserIdentityBadges(uid: suggestion.uid),
                  ],
                ),
                if (suggestion.mutualCount > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    suggestion.mutualCount == 1
                        ? '1 mutual friend'
                        : '${suggestion.mutualCount} mutual friends',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 44,
            child: FilledButton.icon(
              onPressed: isProcessing || isComplete ? null : onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: isFriend
                    ? palette.successSurface
                    : isSent
                    ? palette.warningSurface
                    : colors.primary,
                disabledBackgroundColor: isFriend
                    ? palette.successSurface
                    : isSent
                    ? palette.warningSurface
                    : palette.surfaceMuted,
                foregroundColor: isFriend
                    ? palette.successForeground
                    : isSent
                    ? palette.warningForeground
                    : colors.onPrimary,
                disabledForegroundColor: isFriend
                    ? palette.successForeground
                    : isSent
                    ? palette.warningForeground
                    : palette.textTertiary,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              icon: isProcessing
                  ? SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.onPrimary,
                      ),
                    )
                  : Icon(
                      isComplete
                          ? Icons.check_rounded
                          : Icons.person_add_alt_1_rounded,
                      size: 18,
                    ),
              label: Text(
                isFriend ? 'Friends' : (isSent ? 'Sent' : 'Add'),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UserResultCard extends StatelessWidget {
  const _UserResultCard({
    required this.user,
    required this.relationshipStatus,
    required this.isProcessing,
    required this.onPressed,
    required this.onDecline,
  });

  final FriendUser user;
  final FriendRelationshipStatus relationshipStatus;
  final bool isProcessing;
  final VoidCallback onPressed;

  /// Shown only while a request from this user is pending: Accept must
  /// always travel with a visible way to say no.
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final button = _buttonPresentation(relationshipStatus, palette, colors);
    final identity = Row(
      children: [
        _UserAvatar(user: user),
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
                    user.displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  UserIdentityBadges(uid: user.id),
                ],
              ),
              if (user.username.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  '@${user.username}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.textSecondary, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ],
    );
    final primary = FilledButton(
      onPressed:
          isProcessing ||
              relationshipStatus == FriendRelationshipStatus.friends ||
              relationshipStatus == FriendRelationshipStatus.blocked
          ? null
          : onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 44),
        backgroundColor: button.backgroundColor,
        disabledBackgroundColor: button.disabledBackgroundColor,
        foregroundColor: button.foregroundColor,
        disabledForegroundColor: button.disabledForegroundColor,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      ),
      child: isProcessing
          ? SizedBox(
              width: 17,
              height: 17,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: button.foregroundColor,
              ),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(button.icon, size: 18),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    button.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
    );
    final decline =
        relationshipStatus == FriendRelationshipStatus.requestReceived
        ? SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              onPressed: isProcessing ? null : onDecline,
              tooltip: 'Decline friend request',
              style: IconButton.styleFrom(
                backgroundColor: palette.dangerSurface,
                disabledBackgroundColor: palette.surfaceMuted,
                foregroundColor: palette.dangerForeground,
                disabledForegroundColor: palette.textTertiary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              icon: const Icon(Icons.close_rounded, size: 20),
            ),
          )
        : null;

    return Container(
      key: ValueKey('friend-search-result-${user.id}'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: palette.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stack =
              constraints.maxWidth < 360 ||
              MediaQuery.textScalerOf(context).scale(1) >= 1.5;
          final actions = Row(
            children: [
              Expanded(child: primary),
              if (decline != null) ...[const SizedBox(width: 8), decline],
            ],
          );
          if (stack) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [identity, const SizedBox(height: 12), actions],
            );
          }
          return Row(
            children: [
              Expanded(child: identity),
              const SizedBox(width: 10),
              Flexible(child: primary),
              if (decline != null) ...[const SizedBox(width: 6), decline],
            ],
          );
        },
      ),
    );
  }

  static _FriendButtonPresentation _buttonPresentation(
    FriendRelationshipStatus status,
    AppPalette palette,
    ColorScheme colors,
  ) {
    switch (status) {
      case FriendRelationshipStatus.friends:
        return _FriendButtonPresentation(
          label: 'Friends',
          icon: Icons.people_alt_rounded,
          backgroundColor: palette.successSurface,
          disabledBackgroundColor: palette.successSurface,
          foregroundColor: palette.successForeground,
          disabledForegroundColor: palette.successForeground,
        );
      case FriendRelationshipStatus.requestSent:
        return _FriendButtonPresentation(
          label: 'Cancel',
          icon: Icons.close_rounded,
          backgroundColor: palette.warningSurface,
          disabledBackgroundColor: palette.surfaceMuted,
          foregroundColor: palette.warningForeground,
          disabledForegroundColor: palette.textTertiary,
        );
      case FriendRelationshipStatus.requestReceived:
        return _FriendButtonPresentation(
          label: 'Accept',
          icon: Icons.check_rounded,
          backgroundColor: colors.primary,
          disabledBackgroundColor: palette.surfaceMuted,
          foregroundColor: colors.onPrimary,
          disabledForegroundColor: palette.textTertiary,
        );
      case FriendRelationshipStatus.none:
        return _FriendButtonPresentation(
          label: 'Add',
          icon: Icons.person_add_alt_1_rounded,
          backgroundColor: colors.primary,
          disabledBackgroundColor: palette.surfaceMuted,
          foregroundColor: colors.onPrimary,
          disabledForegroundColor: palette.textTertiary,
        );
      case FriendRelationshipStatus.blocked:
        return _FriendButtonPresentation(
          label: 'Blocked',
          icon: Icons.block_rounded,
          backgroundColor: palette.dangerSurface,
          disabledBackgroundColor: palette.dangerSurface,
          foregroundColor: palette.dangerForeground,
          disabledForegroundColor: palette.dangerForeground,
        );
    }
  }
}

class _FriendButtonPresentation {
  const _FriendButtonPresentation({
    required this.label,
    required this.icon,
    required this.backgroundColor,
    required this.disabledBackgroundColor,
    required this.foregroundColor,
    required this.disabledForegroundColor,
  });

  final String label;
  final IconData icon;
  final Color backgroundColor;
  final Color disabledBackgroundColor;
  final Color foregroundColor;
  final Color disabledForegroundColor;
}

class _UserAvatar extends StatelessWidget {
  const _UserAvatar({required this.user});

  final FriendUser user;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;

    return Container(
      width: 52,
      height: 52,
      padding: const EdgeInsets.all(2),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [Color(0xFFC32BFF), Color(0xFF6D25FF)],
        ),
      ),
      child: UserAvatar(
        radius: 24,
        userId: user.id,
        displayName: user.displayName,
        backgroundColor: palette.surfaceSunken,
      ),
    );
  }
}

class _SearchState extends StatelessWidget {
  const _SearchState({
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
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 50),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(icon, color: colors.onPrimaryContainer, size: 34),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 13,
                height: 1.45,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(120, 44),
                  backgroundColor: colors.primary,
                  foregroundColor: colors.onPrimary,
                ),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
