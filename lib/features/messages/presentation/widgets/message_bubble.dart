import 'package:flutter/material.dart';

import 'package:yovoice/features/messages/data/models/message.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    required this.message,
    required this.currentUserId,
    required this.onLongPress,
    super.key,
  });

  final Message message;
  final String currentUserId;
  final VoidCallback onLongPress;

  static const Color _surface = Color(0xFF17121F);
  static const Color _border = Color(0xFF30263F);
  static const Color _muted = Color(0xFF9D95AD);

  @override
  Widget build(BuildContext context) {
    final isMine = message.isMine(currentUserId);
    final wasRead = message.readBy.any((id) => id != currentUserId);
    final reactionSummary = _reactionSummary(message.reactions.values);

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Padding(
          padding: EdgeInsets.only(
            left: isMine ? 54 : 0,
            right: isMine ? 0 : 54,
            bottom: reactionSummary.isEmpty ? 10 : 18,
          ),
          child: Column(
            crossAxisAlignment: isMine
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      gradient: isMine
                          ? const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFFA72DFF), Color(0xFF7821E8)],
                            )
                          : null,
                      color: isMine ? null : _surface,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(20),
                        topRight: const Radius.circular(20),
                        bottomLeft: Radius.circular(isMine ? 20 : 5),
                        bottomRight: Radius.circular(isMine ? 5 : 20),
                      ),
                      border: isMine ? null : Border.all(color: _border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (message.replyToContent?.isNotEmpty == true)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: .18),
                              borderRadius: BorderRadius.circular(11),
                              border: Border(
                                left: BorderSide(
                                  color: isMine
                                      ? Colors.white70
                                      : const Color(0xFFC35CFF),
                                  width: 3,
                                ),
                              ),
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
                        _MessageContent(message: message),
                      ],
                    ),
                  ),
                  if (reactionSummary.isNotEmpty)
                    Positioned(
                      bottom: -13,
                      right: isMine ? 7 : null,
                      left: isMine ? null : 7,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF21192D),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: _border),
                          boxShadow: const [
                            BoxShadow(color: Color(0x44000000), blurRadius: 8),
                          ],
                        ),
                        child: Text(
                          reactionSummary,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatTime(context, message.sentAt),
                    style: const TextStyle(color: _muted, fontSize: 10),
                  ),
                  if (message.editedAt != null) ...[
                    const SizedBox(width: 4),
                    const Text(
                      'edited',
                      style: TextStyle(color: _muted, fontSize: 10),
                    ),
                  ],
                  if (isMine) ...[
                    const SizedBox(width: 5),
                    Icon(
                      wasRead ? Icons.done_all_rounded : Icons.done_rounded,
                      size: 15,
                      color: wasRead ? const Color(0xFFD276FF) : _muted,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _reactionSummary(Iterable<String> reactions) {
    final counts = <String, int>{};

    for (final reaction in reactions) {
      if (reaction.trim().isEmpty) {
        continue;
      }

      counts[reaction] = (counts[reaction] ?? 0) + 1;
    }

    return counts.entries
        .map(
          (entry) =>
              entry.value > 1 ? '${entry.key} ${entry.value}' : entry.key,
        )
        .join(' ');
  }

  static String _formatTime(BuildContext context, DateTime dateTime) {
    return MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(dateTime.toLocal()),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
  }
}

class _MessageContent extends StatelessWidget {
  const _MessageContent({required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    if (message.isDeleted) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.block_rounded, color: Colors.white54, size: 16),
          SizedBox(width: 7),
          Text(
            'Message deleted',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 14,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      );
    }

    switch (message.type) {
      case MessageType.voice:
        return _VoiceMessageContent(message: message);
      case MessageType.image:
        return _ImageMessageContent(message: message);
      case MessageType.text:
        return Text(
          message.content,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14.5,
            height: 1.35,
          ),
        );
    }
  }
}

class _VoiceMessageContent extends StatelessWidget {
  const _VoiceMessageContent({required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    final duration = message.durationSeconds ?? 0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 27),
        const SizedBox(width: 6),
        SizedBox(
          width: 126,
          height: 32,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(24, (index) {
              final height = 7 + ((index * 13 + duration) % 22);

              return Expanded(
                child: Container(
                  height: height.toDouble(),
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .82),
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${duration ~/ 60}:${(duration % 60).toString().padLeft(2, '0')}',
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ],
    );
  }
}

class _ImageMessageContent extends StatelessWidget {
  const _ImageMessageContent({required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    final mediaUrl = message.mediaUrl?.trim() ?? '';

    if (mediaUrl.isEmpty) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_outlined, color: Colors.white70),
          SizedBox(width: 8),
          Text('Photo', style: TextStyle(color: Colors.white)),
        ],
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Image.network(
        mediaUrl,
        width: 210,
        height: 230,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) {
          return const SizedBox(
            width: 210,
            height: 130,
            child: Center(
              child: Icon(Icons.broken_image_outlined, color: Colors.white54),
            ),
          );
        },
      ),
    );
  }
}
