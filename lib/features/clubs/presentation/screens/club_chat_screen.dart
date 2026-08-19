import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/helpers/error_messages.dart';

import 'package:yovoice/features/clubs/data/models/club_channel.dart';
import 'package:yovoice/features/clubs/data/models/club_chat_authority.dart';
import 'package:yovoice/features/clubs/data/models/club_message.dart';
import 'package:yovoice/features/clubs/data/services/club_chat_service.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_context_action.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';

class ClubChatScreen extends StatefulWidget {
  const ClubChatScreen({
    required this.clubId,
    required this.clubName,
    required this.channel,
    this.firestore,
    this.auth,
    this.chatService,
    super.key,
  });

  final String clubId;
  final String clubName;
  final ClubChannel channel;

  /// Test seams, following the pattern already used by
  /// `ClubInviteResponseScreen` and `CreateClubScreen`. Production always
  /// passes nothing and gets the real instances.
  final FirebaseFirestore? firestore;
  final FirebaseAuth? auth;
  final ClubChatService? chatService;

  @override
  State<ClubChatScreen> createState() => _ClubChatScreenState();
}

class _ClubChatScreenState extends State<ClubChatScreen> {
  static const _background = Color(0xFF080711);
  static const _surface = Color(0xFF171120);
  static const _border = Color(0xFF33263F);
  static const _muted = Color(0xFF9F95A6);
  static const _purple = Color(0xFF9D20FF);

  late final FirebaseFirestore _firestore =
      widget.firestore ?? FirebaseFirestore.instance;
  late final FirebaseAuth _auth = widget.auth ?? FirebaseAuth.instance;
  late final ClubChatService _service =
      widget.chatService ??
      ClubChatService(firestore: _firestore, auth: _auth);
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _sending = false;

  /// Both streams are resolved ONCE, not per build. `build()` runs again
  /// on every keystroke-driven `_sending` flip, and a freshly constructed
  /// stream makes `StreamBuilder` resubscribe — which drops the message
  /// list back to `ConnectionState.waiting` and flashes the spinner over
  /// a conversation that is still on screen.
  late final Stream<List<ClubMessage>> _messageStream = _service.watchMessages(
    clubId: widget.clubId,
    channelId: widget.channel.id,
  );
  late final Stream<ClubChatAuthority> _authorityStream = _service
      .watchAuthority(widget.clubId);

  /// What the viewer may do before either authority document has
  /// arrived: retract their own messages, and nothing else.
  late final ClubChatAuthority _initialAuthority = ClubChatAuthority(
    viewerId: _currentUserId,
  );

  String get _currentUserId => _auth.currentUser?.uid ?? '';
  bool get _isAnnouncements =>
      widget.channel.type == ClubChannelType.announcement;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _service.sendTextMessage(
        clubId: widget.clubId,
        channelId: widget.channel.id,
        text: text,
      );
      _controller.clear();
      _focusNode.requestFocus();
    } catch (error) {
      _showNotice(
        intentionalOrFriendly(
          error,
          fallback: 'Could not send your message. Please try again.',
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// [authority] is the same value that decided whether to OFFER this
  /// action, so the dialog can only ever be shown for a removal the rules
  /// permit — and can name what will actually happen.
  Future<void> _delete(ClubMessage message, ClubChatAuthority authority) async {
    final moderating = authority.isModeratingOthers(message);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _surface,
        title: Text(
          moderating ? 'Remove this message?' : 'Delete message?',
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          moderating
              ? 'This removes ${message.senderName}’s message for everyone in '
                    '#${widget.channel.name}, and records your account against '
                    'the removal.'
              : 'This message will be replaced with “Message deleted”.',
          style: const TextStyle(color: _muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              moderating ? 'Remove' : 'Delete',
              style: const TextStyle(color: Color(0xFFFF668B)),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.deleteMessage(
        clubId: widget.clubId,
        channelId: widget.channel.id,
        message: message,
      );
    } catch (error) {
      _showNotice(
        intentionalOrFriendly(
          error,
          fallback: 'Could not remove this message. Please try again.',
        ),
      );
    }
  }

  void _showNotice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: Colors.white,
        titleSpacing: 0,
        shape: const Border(bottom: BorderSide(color: _border)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_isAnnouncements ? '📣' : '#'} ${widget.channel.name}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
            Text(
              widget.clubName,
              style: const TextStyle(color: _muted, fontSize: 11),
            ),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: ResponsiveContentFrame(
          width: ResponsiveContentWidth.list,
          child: Column(
            children: [
              Expanded(
                child: StreamBuilder<ClubChatAuthority>(
                  stream: _authorityStream,
                  initialData: _initialAuthority,
                  builder: (context, authoritySnapshot) {
                    final authority =
                        authoritySnapshot.data ?? _initialAuthority;
                    return _buildMessages(authority);
                  },
                ),
              ),
              _Composer(
                controller: _controller,
                focusNode: _focusNode,
                sending: _sending,
                hint: _isAnnouncements
                    ? 'Write an announcement…'
                    : 'Message #${widget.channel.name}',
                onSend: _send,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessages(ClubChatAuthority authority) {
    return StreamBuilder<List<ClubMessage>>(
      stream: _messageStream,
      builder: (context, snapshot) {
        // `hasData` guards the spinner as well as the connection state:
        // a reconnect re-enters `waiting` while the already-delivered
        // conversation is still on screen, and blanking it would be a
        // regression, not a loading state.
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: _purple));
        }
        if (snapshot.hasError) {
          return _ChatState(
            icon: Icons.cloud_off_rounded,
            title: 'Could not load messages',
            subtitle: friendlyErrorMessage(
              snapshot.error ?? 'unknown',
              fallback: 'Could not load this chat.',
            ),
          );
        }
        final messages = snapshot.data ?? const <ClubMessage>[];
        if (messages.isEmpty) {
          return _ChatState(
            icon: _isAnnouncements
                ? Icons.campaign_rounded
                : Icons.forum_rounded,
            title: _isAnnouncements
                ? 'No announcements yet'
                : 'Start the club conversation',
            subtitle: _isAnnouncements
                ? 'Important club updates will appear here.'
                : 'Be the first member to write in #${widget.channel.name}.',
          );
        }
        return ListView.builder(
          reverse: true,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final message = messages[index];
            // The gate and the write consult one object, so an offered
            // action is always an action the rules accept.
            return _ClubMessageTile(
              message: message,
              isMine: message.senderId == _currentUserId,
              isModeration: authority.isModeratingOthers(message),
              onRemove: authority.canRemove(message)
                  ? () => _delete(message, authority)
                  : null,
            );
          },
        );
      },
    );
  }
}

class _ClubMessageTile extends StatelessWidget {
  const _ClubMessageTile({
    required this.message,
    required this.isMine,
    required this.isModeration,
    required this.onRemove,
  });

  final ClubMessage message;
  final bool isMine;

  /// Whether [onRemove] would be an act of moderation on somebody else's
  /// message rather than the author retracting their own. Only affects
  /// how the action is announced.
  final bool isModeration;

  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = message.senderPhotoUrl?.isNotEmpty ?? false;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AccessibleContextAction(
        onOpen: onRemove,
        semanticLabel: isModeration
            ? 'Remove ${message.senderName}’s message'
            : 'Delete your message',
        borderRadius: 16,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 19,
              backgroundColor: const Color(0xFF6C2D9A),
              backgroundImage: hasPhoto
                  ? NetworkImage(message.senderPhotoUrl!)
                  : null,
              child: hasPhoto
                  ? null
                  : Text(
                      message.senderName.isEmpty
                          ? '?'
                          : message.senderName[0].toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                padding: const EdgeInsets.fromLTRB(13, 10, 13, 11),
                decoration: BoxDecoration(
                  color: isMine
                      ? const Color(0xFF261436)
                      : const Color(0xFF171120),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isMine
                        ? const Color(0xFF5B2A7B)
                        : const Color(0xFF33263F),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            message.senderName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isMine
                                  ? const Color(0xFFD8A9FF)
                                  : Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        UserIdentityBadges(uid: message.senderId),
                        const Spacer(),
                        Text(
                          _formatTime(message.sentAt),
                          style: const TextStyle(
                            color: Color(0xFF817889),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      message.wasRemovedByModerator
                          ? 'Removed by a moderator'
                          : message.isDeleted
                          ? 'Message deleted'
                          : message.content,
                      style: TextStyle(
                        color: message.isDeleted
                            ? const Color(0xFF8E8595)
                            : const Color(0xFFEAE4ED),
                        fontSize: 14,
                        height: 1.35,
                        fontStyle: message.isDeleted
                            ? FontStyle.italic
                            : FontStyle.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatTime(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.hint,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final String hint;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        10,
        12,
        10 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF100C17),
        border: Border(top: BorderSide(color: Color(0xFF33263F))),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              minLines: 1,
              maxLines: 5,
              maxLength: 2000,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                counterText: '',
                hintText: hint,
                hintStyle: const TextStyle(color: Color(0xFF817889)),
                filled: true,
                fillColor: const Color(0xFF171120),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 13,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: const BorderSide(color: Color(0xFF33263F)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: const BorderSide(color: Color(0xFF9D20FF)),
                ),
              ),
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: 9),
          IconButton.filled(
            onPressed: sending ? null : onSend,
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF9D20FF),
              disabledBackgroundColor: const Color(0xFF513060),
              minimumSize: const Size(48, 48),
            ),
            icon: sending
                ? const SizedBox(
                    width: 19,
                    height: 19,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.arrow_upward_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _ChatState extends StatelessWidget {
  const _ChatState({
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
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: const Color(0xFFC17BFF), size: 48),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF9F95A6), height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
