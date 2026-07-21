import 'package:flutter/material.dart';

import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/presentation/screens/chat_screen.dart';

class FriendProfileScreen extends StatefulWidget {
  const FriendProfileScreen({required this.friend, super.key});

  final FriendUser friend;

  @override
  State<FriendProfileScreen> createState() => _FriendProfileScreenState();
}

class _FriendProfileScreenState extends State<FriendProfileScreen> {
  static const Color _background = Color(0xFF080711);
  static const Color _surface = Color(0xFF12101D);
  static const Color _border = Color(0xFF2C253B);
  static const Color _secondaryText = Color(0xFF9D95AD);
  static const Color _primary = Color(0xFFB348FF);

  final FriendService _friendService = FriendService();
  final MessageService _messageService = MessageService();

  bool _isOpeningChat = false;
  bool _isRemovingFriend = false;

  Future<void> _openChat() async {
    if (_isOpeningChat || _isRemovingFriend) return;

    setState(() => _isOpeningChat = true);

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
      if (mounted) {
        _showError(_readableError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _isOpeningChat = false);
      }
    }
  }

  Future<void> _confirmRemoveFriend() async {
    if (_isOpeningChat || _isRemovingFriend) return;

    final shouldRemove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF171320),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: const BorderSide(color: _border),
          ),
          title: const Text(
            'Remove friend?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
          ),
          content: Text(
            '${widget.friend.displayName} will be removed from your friends list. The existing conversation will not be deleted.',
            style: const TextStyle(color: _secondaryText, height: 1.45),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFB3264E),
                foregroundColor: Colors.white,
              ),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );

    if (shouldRemove != true || !mounted) return;

    setState(() => _isRemovingFriend = true);

    try {
      await _friendService.removeFriend(widget.friend.id);

      if (!mounted) return;

      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${widget.friend.displayName} was removed.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF2A1939),
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        _showError(_readableError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _isRemovingFriend = false);
      }
    }
  }

  String _readableError(Object error) {
    final message = error.toString();

    if (message.contains('permission-denied')) {
      return 'Firestore permission denied. Check your security rules.';
    }
    if (message.contains('signed in')) {
      return 'You must be signed in.';
    }
    if (message.contains('unavailable')) {
      return 'Service is temporarily unavailable. Check your connection.';
    }

    return 'Something went wrong. Please try again.';
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
    final friend = widget.friend;

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
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 24, 22, 40),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Column(
                        children: [
                          _ProfileAvatar(friend: friend),
                          const SizedBox(height: 18),
                          Text(
                            friend.displayName,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.6,
                            ),
                          ),
                          if (friend.email.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              friend.email,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: _secondaryText,
                                fontSize: 14,
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          _OnlineStatus(friend: friend),
                          const SizedBox(height: 28),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: FilledButton.icon(
                              onPressed: _isOpeningChat || _isRemovingFriend
                                  ? null
                                  : _openChat,
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF8A2BE2),
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: const Color(0xFF352B42),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              icon: _isOpeningChat
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.chat_bubble_outline_rounded),
                              label: Text(
                                _isOpeningChat ? 'Opening chat...' : 'Message',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: _surface,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: _border),
                            ),
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.graphic_eq_rounded,
                                  color: _primary,
                                  size: 24,
                                ),
                                SizedBox(width: 13),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Voice Moments',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      SizedBox(height: 3),
                                      Text(
                                        'Shared voice activity will appear here later.',
                                        style: TextStyle(
                                          color: _secondaryText,
                                          fontSize: 12,
                                          height: 1.35,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 28),
                          TextButton.icon(
                            onPressed: _isOpeningChat || _isRemovingFriend
                                ? null
                                : _confirmRemoveFriend,
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFFFF6F8E),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 13,
                              ),
                            ),
                            icon: _isRemovingFriend
                                ? const SizedBox(
                                    width: 17,
                                    height: 17,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFFFF6F8E),
                                    ),
                                  )
                                : const Icon(Icons.person_remove_outlined),
                            label: Text(
                              _isRemovingFriend
                                  ? 'Removing...'
                                  : 'Remove friend',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
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

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 18, 8),
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
            child: Text(
              'Friend profile',
              style: TextStyle(
                color: Colors.white,
                fontSize: 21,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.friend});

  final FriendUser friend;

  @override
  Widget build(BuildContext context) {
    final photoUrl = friend.photoUrl;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 118,
          height: 118,
          padding: const EdgeInsets.all(3),
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
                      errorBuilder: (_, __, ___) => _LargeInitial(
                        initial: friend.initial,
                      ),
                    )
                  : _LargeInitial(initial: friend.initial),
            ),
          ),
        ),
        Positioned(
          right: 7,
          bottom: 7,
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: friend.isOnline
                  ? const Color(0xFF42D47D)
                  : const Color(0xFF746D7D),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF080711), width: 4),
            ),
          ),
        ),
      ],
    );
  }
}

class _LargeInitial extends StatelessWidget {
  const _LargeInitial({required this.initial});

  final String initial;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF9F75D9), Color(0xFF3C2868)],
        ),
      ),
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 42,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _OnlineStatus extends StatelessWidget {
  const _OnlineStatus({required this.friend});

  final FriendUser friend;

  @override
  Widget build(BuildContext context) {
    final text = friend.isOnline ? 'Online now' : _lastSeenText(friend.lastSeen);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        color: friend.isOnline
            ? const Color(0xFF173726)
            : const Color(0xFF211D29),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: friend.isOnline
              ? const Color(0xFF2D6B46)
              : const Color(0xFF383140),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: friend.isOnline
              ? const Color(0xFF73D99A)
              : const Color(0xFFA69DAD),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  static String _lastSeenText(DateTime? lastSeen) {
    if (lastSeen == null) return 'Offline';

    final difference = DateTime.now().difference(lastSeen);

    if (difference.inMinutes < 1) return 'Last seen just now';
    if (difference.inMinutes < 60) {
      return 'Last seen ${difference.inMinutes} min ago';
    }
    if (difference.inHours < 24) {
      return 'Last seen ${difference.inHours} h ago';
    }
    if (difference.inDays < 7) {
      return 'Last seen ${difference.inDays} d ago';
    }

    final day = lastSeen.day.toString().padLeft(2, '0');
    final month = lastSeen.month.toString().padLeft(2, '0');
    return 'Last seen $day.$month.${lastSeen.year}';
  }
}
