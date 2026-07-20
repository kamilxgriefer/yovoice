import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';

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
  static const Color _surface = Color(0xFF12101D);
  static const Color _border = Color(0xFF2C253B);
  static const Color _secondaryText = Color(0xFF9D95AD);

  final MessageService _messageService = MessageService();
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocusNode = FocusNode();

  late final Stream<List<Message>> _messagesStream;

  bool _isSending = false;
  bool _hasMarkedRead = false;

  String get _currentUserId {
    return FirebaseAuth.instance.currentUser?.uid ?? '';
  }

  @override
  void initState() {
    super.initState();
    _messagesStream = _messageService.watchMessages(widget.conversationId);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_markRead());
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _messageFocusNode.dispose();
    super.dispose();
  }

  Future<void> _markRead() async {
    if (_hasMarkedRead) {
      return;
    }

    _hasMarkedRead = true;

    try {
      await _messageService.markConversationRead(widget.conversationId);
    } catch (_) {
      _hasMarkedRead = false;
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();

    if (text.isEmpty || _isSending) {
      return;
    }

    setState(() {
      _isSending = true;
    });

    _messageController.clear();

    try {
      await _messageService.sendTextMessage(
        conversationId: widget.conversationId,
        recipientId: widget.otherUserId,
        text: text,
      );

      if (mounted) {
        _messageFocusNode.requestFocus();
      }
    } catch (error) {
      _messageController.text = text;

      if (mounted) {
        _showError(_readableError(error));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }

  String _readableError(Object error) {
    final message = error.toString();

    if (message.contains('permission-denied')) {
      return 'Firestore permission denied. Check your security rules.';
    }

    if (message.contains('signed in')) {
      return 'You must be signed in to send messages.';
    }

    return 'Could not send the message. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: const Color(0xFF100C18),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          color: Colors.white,
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            _ChatAvatar(
              displayName: widget.otherDisplayName,
              photoUrl: widget.otherPhotoUrl,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.otherDisplayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.otherEmail.isEmpty
                        ? 'YoVoice friend'
                        : widget.otherEmail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _secondaryText,
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () {
              _showError('Voice calls are coming next.');
            },
            icon: const Icon(Icons.call_outlined),
            color: Colors.white,
            tooltip: 'Voice call',
          ),
          const SizedBox(width: 6),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: _border),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Message>>(
              stream: _messagesStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFFB348FF),
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return const _ChatStateMessage(
                    icon: Icons.error_outline_rounded,
                    title: 'Could not load messages',
                    subtitle: 'Check your connection and Firestore rules.',
                  );
                }

                final messages = snapshot.data ?? const <Message>[];

                if (messages.isEmpty) {
                  return _ChatStateMessage(
                    icon: Icons.waving_hand_outlined,
                    title: 'Say hello',
                    subtitle:
                        'Start your conversation with ${widget.otherDisplayName}.',
                  );
                }

                unawaited(_markRead());

                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final nextMessage = index + 1 < messages.length
                        ? messages[index + 1]
                        : null;
                    final showTime = nextMessage == null ||
                        message.sentAt
                                .difference(nextMessage.sentAt)
                                .inMinutes
                                .abs() >
                            5 ||
                        message.senderId != nextMessage.senderId;

                    return _MessageBubble(
                      message: message,
                      currentUserId: _currentUserId,
                      showTime: showTime,
                    );
                  },
                );
              },
            ),
          ),
          _MessageComposer(
            controller: _messageController,
            focusNode: _messageFocusNode,
            isSending: _isSending,
            onSend: _sendMessage,
            onVoicePressed: () {
              _showError('Voice messages are coming next.');
            },
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.currentUserId,
    required this.showTime,
  });

  final Message message;
  final String currentUserId;
  final bool showTime;

  @override
  Widget build(BuildContext context) {
    final isMine = message.isMine(currentUserId);
    final isRead = message.readBy.any((userId) => userId != currentUserId);

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(
          left: isMine ? 54 : 0,
          right: isMine ? 0 : 54,
          bottom: showTime ? 12 : 4,
        ),
        child: Column(
          crossAxisAlignment:
              isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                gradient: isMine
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: <Color>[
                          Color(0xFFAA2BFF),
                          Color(0xFF781BEE),
                        ],
                      )
                    : null,
                color: isMine ? null : _ChatScreenState._surface,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isMine ? 18 : 5),
                  bottomRight: Radius.circular(isMine ? 5 : 18),
                ),
                border: isMine
                    ? null
                    : Border.all(color: _ChatScreenState._border),
              ),
              child: message.isDeleted
                  ? const Text(
                      'Message deleted',
                      style: TextStyle(
                        color: Color(0xFFB9B0C4),
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                      ),
                    )
                  : Text(
                      message.content,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        height: 1.35,
                      ),
                    ),
            ),
            if (showTime) ...[
              const SizedBox(height: 5),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatMessageTime(context, message.sentAt),
                    style: const TextStyle(
                      color: _ChatScreenState._secondaryText,
                      fontSize: 10,
                    ),
                  ),
                  if (isMine) ...[
                    const SizedBox(width: 4),
                    Icon(
                      isRead ? Icons.done_all_rounded : Icons.done_rounded,
                      color: isRead
                          ? const Color(0xFFC05AFF)
                          : _ChatScreenState._secondaryText,
                      size: 15,
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _formatMessageTime(
    BuildContext context,
    DateTime dateTime,
  ) {
    final local = dateTime.toLocal();

    return MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(local),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
  }
}

class _MessageComposer extends StatelessWidget {
  const _MessageComposer({
    required this.controller,
    required this.focusNode,
    required this.isSending,
    required this.onSend,
    required this.onVoicePressed,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSending;
  final VoidCallback onSend;
  final VoidCallback onVoicePressed;

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(12, 10, 12, 10 + safeBottom),
      decoration: const BoxDecoration(
        color: Color(0xFF100C18),
        border: Border(
          top: BorderSide(color: _ChatScreenState._border),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            onPressed: onVoicePressed,
            icon: const Icon(Icons.mic_none_rounded),
            color: const Color(0xFFC05AFF),
            tooltip: 'Voice message',
          ),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              minLines: 1,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
              ),
              decoration: InputDecoration(
                hintText: 'Message',
                hintStyle: const TextStyle(
                  color: _ChatScreenState._secondaryText,
                ),
                filled: true,
                fillColor: _ChatScreenState._surface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: const BorderSide(
                    color: _ChatScreenState._border,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: const BorderSide(
                    color: _ChatScreenState._border,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: const BorderSide(
                    color: Color(0xFF8E2BEF),
                  ),
                ),
              ),
              onSubmitted: (_) {
                onSend();
              },
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              onTap: isSending ? null : onSend,
              customBorder: const CircleBorder(),
              child: Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: <Color>[Color(0xFFB52DFF), Color(0xFF7418E8)],
                  ),
                ),
                child: isSending
                    ? const Padding(
                        padding: EdgeInsets.all(13),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(
                        Icons.arrow_upward_rounded,
                        color: Colors.white,
                        size: 23,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatAvatar extends StatelessWidget {
  const _ChatAvatar({
    required this.displayName,
    required this.photoUrl,
  });

  final String displayName;
  final String photoUrl;

  @override
  Widget build(BuildContext context) {
    final initial = displayName.trim().isEmpty
        ? '?'
        : displayName.trim().characters.first.toUpperCase();

    return Container(
      width: 39,
      height: 39,
      padding: const EdgeInsets.all(2),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: <Color>[Color(0xFFC32BFF), Color(0xFF6D25FF)],
        ),
      ),
      child: ClipOval(
        child: photoUrl.trim().isNotEmpty
            ? Image.network(
                photoUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) {
                  return _ChatAvatarFallback(initial: initial);
                },
              )
            : _ChatAvatarFallback(initial: initial),
      ),
    );
  }
}

class _ChatAvatarFallback extends StatelessWidget {
  const _ChatAvatarFallback({required this.initial});

  final String initial;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF271834),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ChatStateMessage extends StatelessWidget {
  const _ChatStateMessage({
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
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: const Color(0xFFB348FF),
              size: 44,
            ),
            const SizedBox(height: 15),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _ChatScreenState._secondaryText,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
