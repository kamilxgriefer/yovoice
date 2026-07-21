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
  static const _background = Color(0xFF080711);
  static const _surface = Color(0xFF12101D);
  static const _border = Color(0xFF2C253B);
  static const _muted = Color(0xFF9D95AD);

  final _service = MessageService();
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  late final Stream<List<Message>> _messages;
  late final Stream<bool> _typing;

  Timer? _typingTimer;
  Message? _replyTo;
  bool _sending = false;

  String get _me => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _messages = _service.watchMessages(widget.conversationId);
    _typing = _service.watchTyping(
      conversationId: widget.conversationId,
      otherUserId: widget.otherUserId,
    );
    _controller.addListener(_onTextChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _markRead());
  }

  void _onTextChanged() {
    _typingTimer?.cancel();
    _service.setTyping(
      conversationId: widget.conversationId,
      isTyping: _controller.text.trim().isNotEmpty,
    );
    _typingTimer = Timer(const Duration(seconds: 2), () {
      _service.setTyping(
        conversationId: widget.conversationId,
        isTyping: false,
      );
    });
  }

  Future<void> _markRead() async {
    try {
      await _service.markConversationRead(widget.conversationId);
    } catch (_) {}
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    final reply = _replyTo;
    _controller.clear();
    setState(() => _replyTo = null);

    try {
      await _service.sendTextMessage(
        conversationId: widget.conversationId,
        recipientId: widget.otherUserId,
        text: text,
        replyTo: reply,
      );
      if (mounted) _focusNode.requestFocus();
    } catch (error) {
      _controller.text = text;
      if (mounted) _error('Could not send the message.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _messageActions(Message message) async {
    final isMine = message.isMine(_me);
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _surface,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: ['❤️', '😂', '😮', '😢', '🔥', '👍']
                    .map((emoji) => InkWell(
                          onTap: () => Navigator.pop(context, 'react:$emoji'),
                          borderRadius: BorderRadius.circular(24),
                          child: Padding(
                            padding: const EdgeInsets.all(9),
                            child: Text(emoji,
                                style: const TextStyle(fontSize: 24)),
                          ),
                        ))
                    .toList(),
              ),
            ),
            if (!message.isDeleted)
              ListTile(
                leading: const Icon(Icons.reply_rounded, color: Colors.white),
                title: const Text('Reply',
                    style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(context, 'reply'),
              ),
            if (isMine && !message.isDeleted && message.type == MessageType.text)
              ListTile(
                leading: const Icon(Icons.edit_rounded, color: Colors.white),
                title: const Text('Edit',
                    style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(context, 'edit'),
              ),
            if (isMine && !message.isDeleted)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded,
                    color: Color(0xFFFF6B81)),
                title: const Text('Delete',
                    style: TextStyle(color: Color(0xFFFF6B81))),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
          ],
        ),
      ),
    );

    if (action == null) return;
    if (action == 'reply') {
      setState(() => _replyTo = message);
      _focusNode.requestFocus();
    } else if (action == 'edit') {
      await _edit(message);
    } else if (action == 'delete') {
      await _service.deleteMessage(
        conversationId: widget.conversationId,
        messageId: message.id,
      );
    } else if (action.startsWith('react:')) {
      await _service.toggleReaction(
        conversationId: widget.conversationId,
        messageId: message.id,
        emoji: action.substring(6),
      );
    }
  }

  Future<void> _edit(Message message) async {
    final editController = TextEditingController(text: message.content);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _surface,
        title: const Text('Edit message',
            style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: editController,
          autofocus: true,
          maxLines: 5,
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, editController.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    editController.dispose();
    if (result != null && result.trim().isNotEmpty) {
      await _service.editMessage(
        conversationId: widget.conversationId,
        messageId: message.id,
        text: result,
      );
    }
  }

  void _error(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _service.setTyping(
      conversationId: widget.conversationId,
      isTyping: false,
    );
    _controller
      ..removeListener(_onTextChanged)
      ..dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: const Color(0xFF100C18),
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        title: Row(
          children: [
            _Avatar(name: widget.otherDisplayName, url: widget.otherPhotoUrl),
            const SizedBox(width: 11),
            Expanded(
              child: StreamBuilder<bool>(
                stream: _typing,
                builder: (context, snapshot) => Column(
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
                    Text(
                      snapshot.data == true
                          ? 'Typing...'
                          : (widget.otherEmail.isEmpty
                              ? 'YoVoice friend'
                              : widget.otherEmail),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: snapshot.data == true
                            ? const Color(0xFFC05AFF)
                            : _muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Message>>(
              stream: _messages,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFFB348FF),
                    ),
                  );
                }
                final messages = snapshot.data!;
                if (messages.isEmpty) {
                  return const Center(
                    child: Text('Say hello 👋',
                        style: TextStyle(color: _muted, fontSize: 16)),
                  );
                }
                unawaited(_markRead());
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    return GestureDetector(
                      onLongPress: () => _messageActions(message),
                      child: _Bubble(
                        message: message,
                        currentUserId: _me,
                      ),
                    );
                  },
                );
              },
            ),
          ),
          if (_replyTo != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
              color: const Color(0xFF171121),
              child: Row(
                children: [
                  const Icon(Icons.reply_rounded,
                      color: Color(0xFFC05AFF), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _replyTo!.isDeleted
                          ? 'Message deleted'
                          : _replyTo!.content,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() => _replyTo = null),
                    icon: const Icon(Icons.close_rounded, color: _muted),
                  ),
                ],
              ),
            ),
          _Composer(
            controller: _controller,
            focusNode: _focusNode,
            sending: _sending,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.currentUserId});

  final Message message;
  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    final mine = message.isMine(currentUserId);
    final read = message.readBy.any((id) => id != currentUserId);
    final reactions = message.reactions.values.toList();

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(
          left: mine ? 54 : 0,
          right: mine ? 0 : 54,
          bottom: 10,
        ),
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: mine ? const Color(0xFF8F24EE) : _ChatScreenState._surface,
                borderRadius: BorderRadius.circular(18),
                border: mine
                    ? null
                    : Border.all(color: _ChatScreenState._border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (message.replyToContent?.isNotEmpty == true)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        message.replyToContent!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  Text(
                    message.isDeleted ? 'Message deleted' : message.content,
                    style: TextStyle(
                      color: message.isDeleted ? Colors.white54 : Colors.white,
                      fontSize: 14,
                      fontStyle:
                          message.isDeleted ? FontStyle.italic : FontStyle.normal,
                    ),
                  ),
                ],
              ),
            ),
            if (reactions.isNotEmpty)
              Transform.translate(
                offset: const Offset(0, -3),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF21192D),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _ChatScreenState._border),
                  ),
                  child: Text(reactions.join(' '),
                      style: const TextStyle(fontSize: 13)),
                ),
              ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _time(context, message.sentAt),
                  style: const TextStyle(color: _ChatScreenState._muted, fontSize: 10),
                ),
                if (message.editedAt != null) ...[
                  const SizedBox(width: 4),
                  const Text('edited',
                      style: TextStyle(color: _ChatScreenState._muted, fontSize: 10)),
                ],
                if (mine) ...[
                  const SizedBox(width: 4),
                  Icon(
                    read ? Icons.done_all_rounded : Icons.done_rounded,
                    size: 15,
                    color: read
                        ? const Color(0xFFC05AFF)
                        : _ChatScreenState._muted,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _time(BuildContext context, DateTime dateTime) {
    return MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(dateTime.toLocal()),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
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
        color: Color(0xFF100C18),
        border: Border(top: BorderSide(color: _ChatScreenState._border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              minLines: 1,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Message',
                hintStyle: const TextStyle(color: _ChatScreenState._muted),
                filled: true,
                fillColor: _ChatScreenState._surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide:
                      const BorderSide(color: _ChatScreenState._border),
                ),
              ),
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: sending ? null : onSend,
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF9325EF),
              foregroundColor: Colors.white,
            ),
            icon: sending
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.arrow_upward_rounded),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.url});

  final String name;
  final String url;

  @override
  Widget build(BuildContext context) {
    final initial =
        name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
    return CircleAvatar(
      radius: 20,
      backgroundColor: const Color(0xFF7B25E8),
      backgroundImage: url.trim().isNotEmpty ? NetworkImage(url) : null,
      child: url.trim().isEmpty
          ? Text(initial,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w800))
          : null,
    );
  }
}
