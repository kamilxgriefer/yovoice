import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/presentation/widgets/message_bubble.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    required this.conversationId,
    required this.otherUserId,
    required this.otherDisplayName,
    required this.otherEmail,
    required this.otherPhotoUrl,
    super.key,
  });

  final String conversationId;
  final String otherUserId;
  final String otherDisplayName;
  final String otherEmail;
  final String otherPhotoUrl;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const Color _background = Color(0xFF080711);
  static const Color _surface = Color(0xFF15101E);
  static const Color _surface2 = Color(0xFF1D1628);
  static const Color _border = Color(0xFF30263F);
  static const Color _muted = Color(0xFF9D95AD);
  static const Color _primary = Color(0xFF9D20FF);

  final MessageService _service = MessageService();
  final TextEditingController _controller =
      TextEditingController();
  final FocusNode _focusNode = FocusNode();

  late final Stream<List<Message>> _messages;
  late final Stream<bool> _typing;
  late final Stream<ChatPresence> _presence;

  Timer? _typingTimer;
  Message? _replyTo;
  bool _sending = false;
  bool _muted = false;

  String get _currentUserId =>
      FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _messages = _service.watchMessages(widget.conversationId);
    _typing = _service.watchTyping(
      conversationId: widget.conversationId,
      otherUserId: widget.otherUserId,
    );
    _presence = _service.watchUserPresence(widget.otherUserId);
    _controller.addListener(_handleTyping);
    unawaited(_markRead());
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _controller
      ..removeListener(_handleTyping)
      ..dispose();
    _focusNode.dispose();
    unawaited(
      _service.setTyping(
        conversationId: widget.conversationId,
        isTyping: false,
      ),
    );
    super.dispose();
  }

  void _handleTyping() {
    final hasText = _controller.text.trim().isNotEmpty;

    unawaited(
      _service.setTyping(
        conversationId: widget.conversationId,
        isTyping: hasText,
      ),
    );

    _typingTimer?.cancel();

    if (hasText) {
      _typingTimer = Timer(const Duration(seconds: 4), () {
        unawaited(
          _service.setTyping(
            conversationId: widget.conversationId,
            isTyping: false,
          ),
        );
      });
    }
  }

  Future<void> _markRead() async {
    try {
      await _service.markConversationRead(widget.conversationId);
    } catch (_) {
      // The stream stays usable even when read receipts cannot update.
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();

    if (text.isEmpty || _sending) {
      return;
    }

    setState(() => _sending = true);

    try {
      await _service.sendTextMessage(
        conversationId: widget.conversationId,
        recipientId: widget.otherUserId,
        text: text,
        replyTo: _replyTo,
      );

      _controller.clear();

      if (mounted) {
        setState(() => _replyTo = null);
      }
    } catch (error) {
      if (mounted) {
        _showMessage(
          error.toString().replaceFirst('Bad state: ', ''),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _messageActions(Message message) async {
    if (message.isDeleted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _MessageActionsSheet(
          isMine: message.isMine(_currentUserId),
          onReaction: (emoji) {
            Navigator.pop(sheetContext);
            unawaited(
              _service.toggleReaction(
                conversationId: widget.conversationId,
                messageId: message.id,
                emoji: emoji,
              ),
            );
          },
          onReply: () {
            Navigator.pop(sheetContext);
            setState(() => _replyTo = message);
            _focusNode.requestFocus();
          },
          onEdit: () {
            Navigator.pop(sheetContext);
            unawaited(_editMessage(message));
          },
          onDelete: () {
            Navigator.pop(sheetContext);
            unawaited(_deleteMessage(message));
          },
        );
      },
    );
  }

  Future<void> _editMessage(Message message) async {
    final editController = TextEditingController(
      text: message.content,
    );

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: _surface,
          title: const Text(
            'Edit message',
            style: TextStyle(color: Colors.white),
          ),
          content: TextField(
            controller: editController,
            autofocus: true,
            maxLines: 5,
            minLines: 1,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Message',
              hintStyle: const TextStyle(color: _muted),
              filled: true,
              fillColor: _surface2,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: const BorderSide(color: _border),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                editController.text,
              ),
              style: FilledButton.styleFrom(
                backgroundColor: _primary,
              ),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    editController.dispose();

    if (result == null || result.trim().isEmpty) {
      return;
    }

    try {
      await _service.editMessage(
        conversationId: widget.conversationId,
        messageId: message.id,
        text: result,
      );
    } catch (error) {
      if (mounted) {
        _showMessage(error.toString());
      }
    }
  }

  Future<void> _deleteMessage(Message message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: _surface,
          title: const Text(
            'Delete message?',
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            'The message will be replaced with “Message deleted”.',
            style: TextStyle(color: _muted),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text(
                'Delete',
                style: TextStyle(color: Color(0xFFFF668B)),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await _service.deleteMessage(
        conversationId: widget.conversationId,
        messageId: message.id,
      );
    } catch (error) {
      if (mounted) {
        _showMessage(error.toString());
      }
    }
  }

  Future<void> _toggleMute() async {
    try {
      await _service.setConversationMuted(
        conversationId: widget.conversationId,
        muted: !_muted,
      );

      if (mounted) {
        setState(() => _muted = !_muted);
        _showMessage(
          _muted
              ? 'Conversation muted.'
              : 'Notifications turned on.',
        );
      }
    } catch (_) {
      if (mounted) {
        _showMessage('Could not update notifications.');
      }
    }
  }

  Future<void> _archiveConversation() async {
    try {
      await _service.archiveConversation(widget.conversationId);

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        _showMessage('Could not archive this conversation.');
      }
    }
  }

  void _showAttachmentNotice(String feature) {
    _showMessage(
      '$feature is prepared in the interface. Firebase Storage upload is the next integration step.',
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message
                .replaceFirst('Bad state: ', '')
                .replaceFirst('Invalid argument(s): ', ''),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF2A1939),
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
            center: Alignment(-.75, -1),
            radius: 1.2,
            colors: [
              Color(0xFF26103E),
              Color(0xFF100B1B),
              _background,
            ],
            stops: [0, .35, 1],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _ChatHeader(
                displayName: widget.otherDisplayName,
                photoUrl: widget.otherPhotoUrl,
                presenceStream: _presence,
                muted: _muted,
                onBack: () => Navigator.pop(context),
                onMute: _toggleMute,
                onArchive: _archiveConversation,
              ),
              Expanded(
                child: StreamBuilder<List<Message>>(
                  stream: _messages,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState ==
                            ConnectionState.waiting &&
                        !snapshot.hasData) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: _primary,
                          strokeWidth: 2.5,
                        ),
                      );
                    }

                    if (snapshot.hasError) {
                      return const Center(
                        child: Text(
                          'Could not load this conversation.',
                          style: TextStyle(color: _muted),
                        ),
                      );
                    }

                    final messages =
                        snapshot.data ?? const <Message>[];

                    if (messages.isEmpty) {
                      return _EmptyConversation(
                        name: widget.otherDisplayName,
                        photoUrl: widget.otherPhotoUrl,
                      );
                    }

                    unawaited(_markRead());

                    return ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(
                        14,
                        18,
                        14,
                        18,
                      ),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final message = messages[index];
                        final nextMessage =
                            index + 1 < messages.length
                                ? messages[index + 1]
                                : null;
                        final showDate = nextMessage == null ||
                            !_sameDay(
                              message.sentAt,
                              nextMessage.sentAt,
                            );

                        return Column(
                          children: [
                            if (showDate)
                              _DateDivider(date: message.sentAt),
                            MessageBubble(
                              message: message,
                              currentUserId: _currentUserId,
                              onLongPress: () =>
                                  _messageActions(message),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
              StreamBuilder<bool>(
                stream: _typing,
                builder: (context, snapshot) {
                  if (snapshot.data != true) {
                    return const SizedBox.shrink();
                  }

                  return const _TypingIndicator();
                },
              ),
              if (_replyTo != null)
                _ReplyPreview(
                  message: _replyTo!,
                  onClose: () {
                    setState(() => _replyTo = null);
                  },
                ),
              _Composer(
                controller: _controller,
                focusNode: _focusNode,
                sending: _sending,
                onSend: _send,
                onPhoto: () =>
                    _showAttachmentNotice('Photo sharing'),
                onVoice: () =>
                    _showAttachmentNotice('Voice messages'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static bool _sameDay(DateTime first, DateTime second) {
    return first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({
    required this.displayName,
    required this.photoUrl,
    required this.presenceStream,
    required this.muted,
    required this.onBack,
    required this.onMute,
    required this.onArchive,
  });

  final String displayName;
  final String photoUrl;
  final Stream<ChatPresence> presenceStream;
  final bool muted;
  final VoidCallback onBack;
  final VoidCallback onMute;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 8, 8, 8),
      decoration: const BoxDecoration(
        color: Color(0xCC0E0A15),
        border: Border(
          bottom: BorderSide(color: _ChatScreenState._border),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          _Avatar(
            name: displayName,
            url: photoUrl,
            radius: 20,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: StreamBuilder<ChatPresence>(
              stream: presenceStream,
              builder: (context, snapshot) {
                final presence = snapshot.data;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _presenceText(presence),
                      style: TextStyle(
                        color: presence?.isOnline == true
                            ? const Color(0xFF50DF86)
                            : _ChatScreenState._muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          IconButton(
            onPressed: () {},
            tooltip: 'Voice call',
            icon: const Icon(
              Icons.call_outlined,
              color: Colors.white,
            ),
          ),
          PopupMenuButton<String>(
            color: _ChatScreenState._surface,
            icon: const Icon(
              Icons.more_horiz_rounded,
              color: Colors.white,
            ),
            onSelected: (value) {
              if (value == 'mute') {
                onMute();
              } else if (value == 'archive') {
                onArchive();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem<String>(
                value: 'mute',
                child: Row(
                  children: [
                    Icon(
                      muted
                          ? Icons.notifications_active_outlined
                          : Icons.notifications_off_outlined,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      muted ? 'Unmute' : 'Mute',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'archive',
                child: Row(
                  children: [
                    Icon(
                      Icons.archive_outlined,
                      color: Colors.white,
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Archive',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _presenceText(ChatPresence? presence) {
    if (presence?.isOnline == true) {
      return 'Active now';
    }

    final lastSeen = presence?.lastSeen;

    if (lastSeen == null) {
      return 'Offline';
    }

    final difference = DateTime.now().difference(lastSeen);

    if (difference.inMinutes < 1) {
      return 'Active just now';
    }

    if (difference.inMinutes < 60) {
      return 'Active ${difference.inMinutes}m ago';
    }

    if (difference.inHours < 24) {
      return 'Active ${difference.inHours}h ago';
    }

    return 'Active ${difference.inDays}d ago';
  }
}

class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation({
    required this.name,
    required this.photoUrl,
  });

  final String name;
  final String photoUrl;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Avatar(
              name: name,
              url: photoUrl,
              radius: 43,
            ),
            const SizedBox(height: 17),
            Text(
              name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 21,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'You are friends on YoVoice',
              style: TextStyle(
                color: _ChatScreenState._muted,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Say hello 👋',
              style: TextStyle(
                color: Color(0xFFD27AFF),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateDivider extends StatelessWidget {
  const _DateDivider({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));
    final label = _sameDate(date, now)
        ? 'Today'
        : _sameDate(date, yesterday)
            ? 'Yesterday'
            : '${date.day}/${date.month}/${date.year}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        label,
        style: const TextStyle(
          color: _ChatScreenState._muted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  static bool _sameDate(DateTime first, DateTime second) {
    return first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 13,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: _ChatScreenState._surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: _ChatScreenState._border,
              ),
            ),
            child: const Row(
              children: [
                _TypingDot(delay: 0),
                SizedBox(width: 4),
                _TypingDot(delay: 180),
                SizedBox(width: 4),
                _TypingDot(delay: 360),
              ],
            ),
          ),
          const SizedBox(width: 9),
          const Text(
            'typing…',
            style: TextStyle(
              color: _ChatScreenState._muted,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _TypingDot extends StatefulWidget {
  const _TypingDot({required this.delay});

  final int delay;

  @override
  State<_TypingDot> createState() => _TypingDotState();
}

class _TypingDotState extends State<_TypingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;
  Timer? _delayTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );
    _animation = Tween<double>(
      begin: .55,
      end: 1,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );

    _delayTimer = Timer(
      Duration(milliseconds: widget.delay),
      () {
        if (mounted) {
          _controller.repeat(reverse: true);
        }
      },
    );
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _animation,
      child: Container(
        width: 6,
        height: 6,
        decoration: const BoxDecoration(
          color: Color(0xFFC35CFF),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _ReplyPreview extends StatelessWidget {
  const _ReplyPreview({
    required this.message,
    required this.onClose,
  });

  final Message message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      decoration: const BoxDecoration(
        color: Color(0xFF171121),
        border: Border(
          top: BorderSide(color: _ChatScreenState._border),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 37,
            decoration: BoxDecoration(
              color: const Color(0xFFC05AFF),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          const SizedBox(width: 11),
          const Icon(
            Icons.reply_rounded,
            color: Color(0xFFC05AFF),
            size: 20,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Replying to message',
                  style: TextStyle(
                    color: Color(0xFFD690FF),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message.previewText(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onClose,
            icon: const Icon(
              Icons.close_rounded,
              color: _ChatScreenState._muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.onSend,
    required this.onPhoto,
    required this.onVoice,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onPhoto;
  final VoidCallback onVoice;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        10,
        9,
        10,
        10 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF0F0B16),
        border: Border(
          top: BorderSide(color: _ChatScreenState._border),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            onPressed: onPhoto,
            style: IconButton.styleFrom(
              backgroundColor: _ChatScreenState._surface2,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.camera_alt_outlined),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: _ChatScreenState._surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: _ChatScreenState._border,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization:
                          TextCapitalization.sentences,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Message…',
                        hintStyle: TextStyle(
                          color: _ChatScreenState._muted,
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.fromLTRB(
                          15,
                          12,
                          8,
                          12,
                        ),
                      ),
                      onSubmitted: (_) => onSend(),
                    ),
                  ),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (context, value, _) {
                      final hasText = value.text.trim().isNotEmpty;

                      return AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: hasText
                            ? IconButton(
                                key: const ValueKey('send'),
                                onPressed:
                                    sending ? null : onSend,
                                icon: sending
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child:
                                            CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.send_rounded,
                                        color:
                                            _ChatScreenState._primary,
                                      ),
                              )
                            : IconButton(
                                key: const ValueKey('voice'),
                                onPressed: onVoice,
                                icon: const Icon(
                                  Icons.mic_none_rounded,
                                  color: Colors.white,
                                ),
                              ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageActionsSheet extends StatelessWidget {
  const _MessageActionsSheet({
    required this.isMine,
    required this.onReaction,
    required this.onReply,
    required this.onEdit,
    required this.onDelete,
  });

  final bool isMine;
  final ValueChanged<String> onReaction;
  final VoidCallback onReply;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    const reactions = ['❤️', '😂', '🔥', '😮', '😢', '👍'];

    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        18 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF15101E),
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(26),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          const SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: reactions
                .map(
                  (emoji) => InkWell(
                    onTap: () => onReaction(emoji),
                    customBorder: const CircleBorder(),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        emoji,
                        style: const TextStyle(fontSize: 27),
                      ),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
          const Divider(color: _ChatScreenState._border),
          ListTile(
            onTap: onReply,
            leading: const Icon(
              Icons.reply_rounded,
              color: Colors.white,
            ),
            title: const Text(
              'Reply',
              style: TextStyle(color: Colors.white),
            ),
          ),
          if (isMine)
            ListTile(
              onTap: onEdit,
              leading: const Icon(
                Icons.edit_outlined,
                color: Colors.white,
              ),
              title: const Text(
                'Edit',
                style: TextStyle(color: Colors.white),
              ),
            ),
          if (isMine)
            ListTile(
              onTap: onDelete,
              leading: const Icon(
                Icons.delete_outline_rounded,
                color: Color(0xFFFF668B),
              ),
              title: const Text(
                'Delete',
                style: TextStyle(color: Color(0xFFFF668B)),
              ),
            ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.name,
    required this.url,
    required this.radius,
  });

  final String name;
  final String url;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty
        ? '?'
        : name.trim().characters.first.toUpperCase();

    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFF7B25E8),
      backgroundImage:
          url.trim().isNotEmpty ? NetworkImage(url) : null,
      child: url.trim().isEmpty
          ? Text(
              initial,
              style: TextStyle(
                color: Colors.white,
                fontSize: radius * .65,
                fontWeight: FontWeight.w900,
              ),
            )
          : null,
    );
  }
}
