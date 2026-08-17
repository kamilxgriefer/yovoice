import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_context_action.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    required this.message,
    required this.currentUserId,
    required this.onLongPress,
    this.privateMediaLoader,
    this.audioPlayerFactory,
    super.key,
  });

  final Message message;
  final String currentUserId;
  final VoidCallback onLongPress;
  final Future<Uint8List?> Function(String? reference, int maxBytes)?
  privateMediaLoader;
  final AudioPlayer Function()? audioPlayerFactory;

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
      child: AccessibleContextAction(
        onOpen: onLongPress,
        semanticLabel: isMine
            ? 'Open actions for your message'
            : 'Open actions for this message',
        borderRadius: 22,
        child: Padding(
          padding: EdgeInsets.only(
            left: isMine ? 54 : 0,
            right: isMine ? 0 : 54,
            bottom: 10,
          ),
          child: Column(
            crossAxisAlignment: isMine
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
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
                    _MessageContent(
                      message: message,
                      privateMediaLoader: privateMediaLoader,
                      audioPlayerFactory: audioPlayerFactory,
                    ),
                  ],
                ),
              ),
              if (reactionSummary.isNotEmpty) ...[
                const SizedBox(height: 4),
                Container(
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
              ],
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
  const _MessageContent({
    required this.message,
    required this.privateMediaLoader,
    required this.audioPlayerFactory,
  });

  final Message message;
  final Future<Uint8List?> Function(String? reference, int maxBytes)?
  privateMediaLoader;
  final AudioPlayer Function()? audioPlayerFactory;

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
        return _VoiceMessageContent(
          message: message,
          privateMediaLoader: privateMediaLoader,
          audioPlayerFactory: audioPlayerFactory,
        );
      case MessageType.image:
        return _ImageMessageContent(
          message: message,
          privateMediaLoader: privateMediaLoader,
        );
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

class _VoiceMessageContent extends StatefulWidget {
  const _VoiceMessageContent({
    required this.message,
    required this.privateMediaLoader,
    required this.audioPlayerFactory,
  });

  final Message message;
  final Future<Uint8List?> Function(String? reference, int maxBytes)?
  privateMediaLoader;
  final AudioPlayer Function()? audioPlayerFactory;

  @override
  State<_VoiceMessageContent> createState() => _VoiceMessageContentState();
}

class _VoiceMessageContentState extends State<_VoiceMessageContent> {
  late final AudioPlayer _player;
  StreamSubscription<PlayerState>? _stateSubscription;
  Uint8List? _bytes;
  bool _loading = false;
  bool _playing = false;
  bool _paused = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _player = widget.audioPlayerFactory?.call() ?? AudioPlayer();
    _stateSubscription = _player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() {
        _playing = state == PlayerState.playing;
        _paused = state == PlayerState.paused;
      });
    });
  }

  @override
  void didUpdateWidget(covariant _VoiceMessageContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != widget.message.id ||
        oldWidget.message.mediaUrl != widget.message.mediaUrl) {
      _bytes = null;
      _loading = false;
      _playing = false;
      _paused = false;
      _failed = false;
      unawaited(_player.stop());
    }
  }

  @override
  void dispose() {
    unawaited(_stateSubscription?.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_loading) return;
    if (_playing) {
      await _player.pause();
      return;
    }
    if (_paused) {
      await _player.resume();
      return;
    }
    try {
      setState(() {
        _loading = true;
        _failed = false;
      });
      final reference = widget.message.mediaUrl?.trim() ?? '';
      if (reference.startsWith('gs://')) {
        _bytes ??=
            await (widget.privateMediaLoader?.call(
                  reference,
                  12 * 1024 * 1024,
                ) ??
                _privateMediaBytes(reference, maxBytes: 12 * 1024 * 1024));
        final bytes = _bytes;
        if (bytes == null || bytes.isEmpty) {
          throw StateError('Voice message unavailable');
        }
        await _player.play(BytesSource(bytes));
      } else if (reference.startsWith('https://')) {
        await _player.play(UrlSource(reference));
      } else {
        throw StateError('Voice message unavailable');
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final duration = widget.message.durationSeconds ?? 0;

    return Semantics(
      button: true,
      label: _failed
          ? 'Voice message unavailable. Tap to retry.'
          : _playing
          ? 'Pause voice message'
          : 'Play voice message, $duration seconds',
      child: InkWell(
        onTap: _toggle,
        borderRadius: BorderRadius.circular(12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_loading)
              const SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            else
              Icon(
                _failed
                    ? Icons.refresh_rounded
                    : _playing
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                color: _failed ? const Color(0xFFFF9BB1) : Colors.white,
                size: 27,
              ),
            const SizedBox(width: 6),
            Flexible(
              fit: FlexFit.loose,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 48, maxWidth: 126),
                child: SizedBox(
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
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${duration ~/ 60}:${(duration % 60).toString().padLeft(2, '0')}',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageMessageContent extends StatefulWidget {
  const _ImageMessageContent({
    required this.message,
    required this.privateMediaLoader,
  });

  final Message message;
  final Future<Uint8List?> Function(String? reference, int maxBytes)?
  privateMediaLoader;

  @override
  State<_ImageMessageContent> createState() => _ImageMessageContentState();
}

class _ImageMessageContentState extends State<_ImageMessageContent> {
  late Future<Uint8List?> _image = _load();

  Future<Uint8List?> _load() =>
      widget.privateMediaLoader?.call(
        widget.message.mediaUrl,
        8 * 1024 * 1024,
      ) ??
      _privateMediaBytes(widget.message.mediaUrl, maxBytes: 8 * 1024 * 1024);

  @override
  void didUpdateWidget(covariant _ImageMessageContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != widget.message.id ||
        oldWidget.message.mediaUrl != widget.message.mediaUrl) {
      _image = _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaUrl = widget.message.mediaUrl?.trim() ?? '';

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

    if (mediaUrl.startsWith('https://')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.network(
          mediaUrl,
          width: 210,
          height: 230,
          fit: BoxFit.cover,
          semanticLabel: 'Photo message',
          errorBuilder: (_, _, _) => const SizedBox(
            width: 210,
            height: 130,
            child: Center(
              child: Icon(Icons.broken_image_outlined, color: Colors.white54),
            ),
          ),
        ),
      );
    }

    return FutureBuilder<Uint8List?>(
      key: ValueKey('${widget.message.id}:${widget.message.mediaUrl}'),
      future: _image,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(
            width: 210,
            height: 160,
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
          );
        }
        final bytes = snapshot.data;
        if (snapshot.hasError || bytes == null || bytes.isEmpty) {
          return TextButton.icon(
            onPressed: () => setState(() => _image = _load()),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Photo unavailable — retry'),
          );
        }
        return Semantics(
          image: true,
          label: 'Photo message',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.memory(
              bytes,
              width: 210,
              height: 230,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),
          ),
        );
      },
    );
  }
}

Future<Uint8List?> _privateMediaBytes(
  String? reference, {
  required int maxBytes,
}) async {
  final value = reference?.trim() ?? '';
  if (!value.startsWith('gs://')) return null;
  return FirebaseStorage.instance.refFromURL(value).getData(maxBytes);
}
