import 'dart:async';

import 'package:flutter/material.dart';

import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';

class AddFriendScreen extends StatefulWidget {
  const AddFriendScreen({super.key});

  @override
  State<AddFriendScreen> createState() => _AddFriendScreenState();
}

class _AddFriendScreenState extends State<AddFriendScreen> {
  static const Color _background = Color(0xFF080711);
  static const Color _surface = Color(0xFF12101D);
  static const Color _border = Color(0xFF2C253B);
  static const Color _secondaryText = Color(0xFF9D95AD);
  static const Color _primary = Color(0xFFB348FF);

  final FriendService _friendService = FriendService();
  final TextEditingController _searchController = TextEditingController();

  Timer? _searchDebounce;
  List<FriendUser> _results = const [];
  final Map<String, FriendRelationshipStatus> _relationshipStatuses = {};
  final Set<String> _processingIds = <String>{};

  bool _isSearching = false;
  String? _errorMessage;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
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
        users.map(
          (user) => _friendService.getRelationshipStatus(user.id),
        ),
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

    final status = _relationshipStatuses[user.id] ??
        FriendRelationshipStatus.none;

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

      await _friendService.sendFriendRequest(user);

      if (!mounted) return;

      final newStatus = status == FriendRelationshipStatus.requestReceived
          ? FriendRelationshipStatus.friends
          : FriendRelationshipStatus.requestSent;

      setState(() {
        _relationshipStatuses[user.id] = newStatus;
      });

      _showMessage(
        newStatus == FriendRelationshipStatus.friends
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
          _relationshipStatuses[user.id] =
              FriendRelationshipStatus.requestSent;
        });
      }

      _showError(message);
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
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF203D2C),
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  void _showError(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF481C30),
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
            center: Alignment(-0.85, -0.95),
            radius: 1.25,
            colors: [Color(0xFF24103B), Color(0xFF100B1B), _background],
            stops: [0, 0.38, 1],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              _buildSearchField(),
              Expanded(child: _buildContent()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 18, 10),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Back',
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white,
              size: 21,
            ),
          ),
          const SizedBox(width: 4),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Add friends',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Search by username or email',
                  style: TextStyle(
                    color: _secondaryText,
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        textInputAction: TextInputAction.search,
        keyboardType: TextInputType.emailAddress,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          hintText: 'Search people...',
          hintStyle: const TextStyle(color: Color(0xFF756D82), fontSize: 15),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: Color(0xFF9189A6),
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
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
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Color(0xFF9189A6),
                  ),
                )
              : null,
          filled: true,
          fillColor: _surface,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 17,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: _border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: _primary, width: 1.4),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    final query = _searchController.text.trim();

    if (_isSearching) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2.5, color: _primary),
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
      return const _SearchState(
        icon: Icons.person_search_rounded,
        title: 'Find someone you know',
        subtitle:
            'Enter at least 2 characters from their username or email address.',
      );
    }

    if (_results.isEmpty) {
      return const _SearchState(
        icon: Icons.search_off_rounded,
        title: 'No users found',
        subtitle: 'Try another username or email address.',
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
          relationshipStatus: _relationshipStatuses[user.id] ??
              FriendRelationshipStatus.none,
          isProcessing: _processingIds.contains(user.id),
          onPressed: () => _handlePrimaryAction(user),
        );
      },
    );
  }
}

class _UserResultCard extends StatelessWidget {
  const _UserResultCard({
    required this.user,
    required this.relationshipStatus,
    required this.isProcessing,
    required this.onPressed,
  });

  final FriendUser user;
  final FriendRelationshipStatus relationshipStatus;
  final bool isProcessing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final button = _buttonPresentation(relationshipStatus);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _AddFriendScreenState._surface,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: _AddFriendScreenState._border),
      ),
      child: Row(
        children: [
          _UserAvatar(user: user),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (user.email.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    user.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _AddFriendScreenState._secondaryText,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 40,
            child: FilledButton(
              onPressed: isProcessing ||
                      relationshipStatus == FriendRelationshipStatus.friends
                  ? null
                  : onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: button.backgroundColor,
                disabledBackgroundColor: button.disabledBackgroundColor,
                foregroundColor: button.foregroundColor,
                disabledForegroundColor: button.disabledForegroundColor,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              child: isProcessing
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(button.icon, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          button.label,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  static _FriendButtonPresentation _buttonPresentation(
    FriendRelationshipStatus status,
  ) {
    switch (status) {
      case FriendRelationshipStatus.friends:
        return const _FriendButtonPresentation(
          label: 'Friends',
          icon: Icons.people_alt_rounded,
          backgroundColor: Color(0xFF26392E),
          disabledBackgroundColor: Color(0xFF26392E),
          foregroundColor: Color(0xFF73D99A),
          disabledForegroundColor: Color(0xFF73D99A),
        );
      case FriendRelationshipStatus.requestSent:
        return const _FriendButtonPresentation(
          label: 'Cancel',
          icon: Icons.close_rounded,
          backgroundColor: Color(0xFF3A2F1D),
          disabledBackgroundColor: Color(0xFF2A2533),
          foregroundColor: Color(0xFFFFC66D),
          disabledForegroundColor: Color(0xFF8F8799),
        );
      case FriendRelationshipStatus.requestReceived:
        return const _FriendButtonPresentation(
          label: 'Accept',
          icon: Icons.check_rounded,
          backgroundColor: Color(0xFF27613D),
          disabledBackgroundColor: Color(0xFF2A2533),
          foregroundColor: Colors.white,
          disabledForegroundColor: Color(0xFF8F8799),
        );
      case FriendRelationshipStatus.none:
        return const _FriendButtonPresentation(
          label: 'Add',
          icon: Icons.person_add_alt_1_rounded,
          backgroundColor: Color(0xFF8A2BE2),
          disabledBackgroundColor: Color(0xFF2A2533),
          foregroundColor: Colors.white,
          disabledForegroundColor: Color(0xFF8F8799),
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
    final photoUrl = user.photoUrl;

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
      child: ClipOval(
        child: Container(
          color: const Color(0xFF2A173C),
          child: photoUrl != null && photoUrl.isNotEmpty
              ? Image.network(
                  photoUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) {
                    return _AvatarInitial(initial: user.initial);
                  },
                )
              : _AvatarInitial(initial: user.initial),
        ),
      ),
    );
  }
}

class _AvatarInitial extends StatelessWidget {
  const _AvatarInitial({required this.initial});

  final String initial;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 19,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SearchState extends StatelessWidget {
  const _SearchState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
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
                color: const Color(0xFF9C42FF).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(icon, color: const Color(0xFFB348FF), size: 34),
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
                color: Color(0xFF9D95AD),
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
