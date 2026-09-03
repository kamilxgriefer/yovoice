import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/presentation/widgets/direct_video_playback_source.dart';
import 'package:yovoice/features/messages/presentation/widgets/direct_voice_playback_source.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_context_action.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    required this.message,
    required this.currentUserId,
    required this.onLongPress,
    this.privateMediaLoader,
    this.audioPlayerFactory,
    this.voiceSourcePreparer,
    this.videoSourcePreparer,
    super.key,
  });

  final Message message;
  final String currentUserId;
  final VoidCallback onLongPress;
  final Future<Uint8List?> Function(String? reference, int maxBytes)?
  privateMediaLoader;
  final AudioPlayer Function()? audioPlayerFactory;
  final DirectVoiceSourcePreparer? voiceSourcePreparer;
  final DirectVideoSourcePreparer? videoSourcePreparer;

  @override
  Widget build(BuildContext context) {
    final isMine = message.isMine(currentUserId);
    final wasRead = message.readBy.any((id) => id != currentUserId);
    final reactionSummary = _reactionSummary(message.reactions.values);
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final copy = AppLocalizations.of(context);
    final bubbleForeground = isMine ? Colors.white : palette.textPrimary;
    // Outgoing metadata is small text on the brightest gradient stop. Keep it
    // opaque so the worst-case pair remains AA-readable in both themes.
    final bubbleMuted = isMine ? Colors.white : palette.textSecondary;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: AccessibleContextAction(
        onOpen: onLongPress,
        semanticLabel: isMine
            ? copy.text(
                'Open actions for your message',
                'Otwórz opcje swojej wiadomości',
              )
            : copy.text(
                'Open actions for this message',
                'Otwórz opcje tej wiadomości',
              ),
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
                key: ValueKey(
                  isMine
                      ? 'outgoing-message-bubble'
                      : 'incoming-message-bubble',
                ),
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
                  color: isMine ? null : palette.surfaceRaised,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(20),
                    topRight: const Radius.circular(20),
                    bottomLeft: Radius.circular(isMine ? 20 : 5),
                    bottomRight: Radius.circular(isMine ? 5 : 20),
                  ),
                  border: isMine ? null : Border.all(color: palette.border),
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
                          color: isMine
                              ? Colors.black.withValues(alpha: .18)
                              : palette.surfaceMuted,
                          borderRadius: BorderRadius.circular(11),
                          border: Border(
                            left: BorderSide(
                              color: isMine ? Colors.white : palette.focus,
                              width: 3,
                            ),
                          ),
                        ),
                        child: Text(
                          _localizedReplyPreview(message.replyToContent!, copy),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: bubbleMuted, fontSize: 12),
                        ),
                      ),
                    _MessageContent(
                      message: message,
                      foregroundColor: bubbleForeground,
                      mutedForegroundColor: bubbleMuted,
                      errorForegroundColor: isMine
                          ? const Color(0xFFFFE0E7)
                          : colors.onErrorContainer,
                      privateMediaLoader: privateMediaLoader,
                      audioPlayerFactory: audioPlayerFactory,
                      voiceSourcePreparer: voiceSourcePreparer,
                      videoSourcePreparer: videoSourcePreparer,
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
                    color: palette.surfaceRaised,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: palette.border),
                    boxShadow: [
                      BoxShadow(
                        color: palette.shadow.withValues(alpha: .18),
                        blurRadius: 8,
                      ),
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
                    style: TextStyle(color: palette.textTertiary, fontSize: 10),
                  ),
                  if (message.editedAt != null) ...[
                    const SizedBox(width: 4),
                    Text(
                      copy.text('edited', 'edytowano'),
                      style: TextStyle(
                        color: palette.textTertiary,
                        fontSize: 10,
                      ),
                    ),
                  ],
                  if (isMine) ...[
                    const SizedBox(width: 5),
                    Icon(
                      wasRead ? Icons.done_all_rounded : Icons.done_rounded,
                      size: 15,
                      color: wasRead ? palette.focus : palette.textTertiary,
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
    required this.foregroundColor,
    required this.mutedForegroundColor,
    required this.errorForegroundColor,
    required this.privateMediaLoader,
    required this.audioPlayerFactory,
    required this.voiceSourcePreparer,
    required this.videoSourcePreparer,
  });

  final Message message;
  final Color foregroundColor;
  final Color mutedForegroundColor;
  final Color errorForegroundColor;
  final Future<Uint8List?> Function(String? reference, int maxBytes)?
  privateMediaLoader;
  final AudioPlayer Function()? audioPlayerFactory;
  final DirectVoiceSourcePreparer? voiceSourcePreparer;
  final DirectVideoSourcePreparer? videoSourcePreparer;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    if (message.isDeleted) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.block_rounded, color: mutedForegroundColor, size: 16),
          const SizedBox(width: 7),
          Text(
            copy.text('Message deleted', 'Wiadomość usunięta'),
            style: TextStyle(
              color: mutedForegroundColor,
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
          foregroundColor: foregroundColor,
          mutedForegroundColor: mutedForegroundColor,
          errorForegroundColor: errorForegroundColor,
          privateMediaLoader: privateMediaLoader,
          audioPlayerFactory: audioPlayerFactory,
          voiceSourcePreparer: voiceSourcePreparer,
        );
      case MessageType.image:
        return _ImageMessageContent(
          message: message,
          foregroundColor: foregroundColor,
          mutedForegroundColor: mutedForegroundColor,
          privateMediaLoader: privateMediaLoader,
        );
      case MessageType.video:
        return _VideoMessageContent(
          message: message,
          foregroundColor: foregroundColor,
          mutedForegroundColor: mutedForegroundColor,
          errorForegroundColor: errorForegroundColor,
          privateMediaLoader: privateMediaLoader,
          videoSourcePreparer: videoSourcePreparer,
        );
      case MessageType.text:
        return Text(
          message.content,
          style: TextStyle(
            color: foregroundColor,
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
    required this.foregroundColor,
    required this.mutedForegroundColor,
    required this.errorForegroundColor,
    required this.privateMediaLoader,
    required this.audioPlayerFactory,
    required this.voiceSourcePreparer,
  });

  final Message message;
  final Color foregroundColor;
  final Color mutedForegroundColor;
  final Color errorForegroundColor;
  final Future<Uint8List?> Function(String? reference, int maxBytes)?
  privateMediaLoader;
  final AudioPlayer Function()? audioPlayerFactory;
  final DirectVoiceSourcePreparer? voiceSourcePreparer;

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
  PreparedDirectVoiceSource? _preparedSource;

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
      unawaited(_releasePreparedSource());
    }
  }

  @override
  void dispose() {
    unawaited(_stateSubscription?.cancel());
    unawaited(_player.dispose());
    unawaited(_releasePreparedSource());
    super.dispose();
  }

  Future<void> _releasePreparedSource() async {
    final prepared = _preparedSource;
    _preparedSource = null;
    await prepared?.dispose();
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
        _preparedSource ??=
            await (widget.voiceSourcePreparer ?? prepareDirectVoiceSource)(
              bytes,
              widget.message.id,
            );
        await _player.play(_preparedSource!.source);
      } else if (reference.startsWith('https://')) {
        await _player.play(UrlSource(reference));
      } else {
        throw StateError('Voice message unavailable');
      }
    } catch (_) {
      // A native temporary file may have been removed under memory pressure,
      // or a platform player may have rejected the first preparation. Retry
      // must rebuild the source instead of replaying a poisoned handle.
      await _releasePreparedSource();
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final duration = widget.message.durationSeconds ?? 0;
    final copy = AppLocalizations.of(context);

    return Semantics(
      button: true,
      label: _failed
          ? copy.text(
              'Voice message unavailable. Tap to retry.',
              'Wiadomość głosowa jest niedostępna. Dotknij, aby spróbować ponownie.',
            )
          : _playing
          ? copy.text('Pause voice message', 'Wstrzymaj wiadomość głosową')
          : copy.template(
              'Play voice message, {duration} seconds',
              'Odtwórz wiadomość głosową, {duration} s',
              values: <String, Object>{'duration': duration},
            ),
      child: InkWell(
        key: ValueKey<String>('direct-voice-${widget.message.id}'),
        onTap: _toggle,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: 44,
                child: Center(
                  child: _loading
                      ? SizedBox.square(
                          dimension: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: widget.foregroundColor,
                          ),
                        )
                      : Icon(
                          _failed
                              ? Icons.refresh_rounded
                              : _playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: _failed
                              ? widget.errorForegroundColor
                              : widget.foregroundColor,
                          size: 27,
                        ),
                ),
              ),
              const SizedBox(width: 2),
              Flexible(
                fit: FlexFit.loose,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    maxWidth: 126,
                  ),
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
                              color: widget.foregroundColor.withValues(
                                alpha: .82,
                              ),
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
                style: TextStyle(
                  color: widget.mutedForegroundColor,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImageMessageContent extends StatefulWidget {
  const _ImageMessageContent({
    required this.message,
    required this.foregroundColor,
    required this.mutedForegroundColor,
    required this.privateMediaLoader,
    this.width = 210,
    this.height = 230,
  });

  final Message message;
  final Color foregroundColor;
  final Color mutedForegroundColor;
  final Future<Uint8List?> Function(String? reference, int maxBytes)?
  privateMediaLoader;
  final double width;
  final double height;

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
    final copy = AppLocalizations.of(context);

    if (mediaUrl.isEmpty) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_outlined, color: widget.mutedForegroundColor),
          const SizedBox(width: 8),
          Text(
            copy.text('Photo', 'Zdjęcie'),
            style: TextStyle(color: widget.foregroundColor),
          ),
        ],
      );
    }

    if (mediaUrl.startsWith('https://')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.network(
          mediaUrl,
          width: widget.width,
          height: widget.height,
          fit: BoxFit.cover,
          semanticLabel: copy.text('Photo message', 'Wiadomość ze zdjęciem'),
          errorBuilder: (_, _, _) => SizedBox(
            width: widget.width,
            height: widget.height,
            child: Center(
              child: Icon(
                Icons.broken_image_outlined,
                color: widget.mutedForegroundColor,
              ),
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
          return SizedBox(
            width: widget.width,
            height: widget.height,
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: widget.foregroundColor,
              ),
            ),
          );
        }
        final bytes = snapshot.data;
        if (snapshot.hasError || bytes == null || bytes.isEmpty) {
          return TextButton.icon(
            onPressed: () => setState(() => _image = _load()),
            style: TextButton.styleFrom(
              foregroundColor: widget.foregroundColor,
            ),
            icon: const Icon(Icons.refresh_rounded),
            label: Text(
              copy.text(
                'Photo unavailable — retry',
                'Zdjęcie jest niedostępne — spróbuj ponownie',
              ),
            ),
          );
        }
        return Semantics(
          image: true,
          label: copy.text('Photo message', 'Wiadomość ze zdjęciem'),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.memory(
              bytes,
              width: widget.width,
              height: widget.height,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),
          ),
        );
      },
    );
  }
}

class _VideoMessageContent extends StatefulWidget {
  const _VideoMessageContent({
    required this.message,
    required this.foregroundColor,
    required this.mutedForegroundColor,
    required this.errorForegroundColor,
    required this.privateMediaLoader,
    required this.videoSourcePreparer,
    this.width = 238,
    this.height = 158,
  });

  final Message message;
  final Color foregroundColor;
  final Color mutedForegroundColor;
  final Color errorForegroundColor;
  final Future<Uint8List?> Function(String? reference, int maxBytes)?
  privateMediaLoader;
  final DirectVideoSourcePreparer? videoSourcePreparer;
  final double width;
  final double height;

  @override
  State<_VideoMessageContent> createState() => _VideoMessageContentState();
}

class _VideoMessageContentState extends State<_VideoMessageContent> {
  VideoPlayerController? _controller;
  PreparedDirectVideoSource? _preparedSource;
  Uint8List? _bytes;
  bool _loading = false;
  bool _failed = false;

  @override
  void didUpdateWidget(covariant _VideoMessageContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != widget.message.id ||
        oldWidget.message.mediaUrl != widget.message.mediaUrl) {
      unawaited(_release());
      _bytes = null;
      _loading = false;
      _failed = false;
    }
  }

  @override
  void dispose() {
    unawaited(_release());
    super.dispose();
  }

  Future<void> _release() async {
    final controller = _controller;
    final prepared = _preparedSource;
    _controller = null;
    _preparedSource = null;
    await Future.wait<void>([
      if (controller != null) controller.dispose(),
      if (prepared != null) prepared.dispose(),
    ]);
  }

  Future<void> _toggle() async {
    if (_loading) return;
    final existing = _controller;
    if (existing != null && existing.value.isInitialized) {
      if (existing.value.isPlaying) {
        await existing.pause();
      } else {
        if (existing.value.position >= existing.value.duration) {
          await existing.seekTo(Duration.zero);
        }
        await existing.play();
      }
      return;
    }

    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final reference = widget.message.mediaUrl?.trim() ?? '';
      late final VideoPlayerController controller;
      if (reference.startsWith('https://')) {
        controller = VideoPlayerController.networkUrl(Uri.parse(reference));
      } else if (reference.startsWith('gs://')) {
        _bytes ??=
            await (widget.privateMediaLoader?.call(
                  reference,
                  64 * 1024 * 1024,
                ) ??
                _privateMediaBytes(reference, maxBytes: 64 * 1024 * 1024));
        final bytes = _bytes;
        if (bytes == null || bytes.isEmpty) {
          throw StateError('Video unavailable');
        }
        _preparedSource ??=
            await (widget.videoSourcePreparer ?? prepareDirectVideoSource)(
              bytes,
              widget.message.id,
              reference,
            );
        controller = _preparedSource!.createController();
      } else {
        throw StateError('Video unavailable');
      }
      _controller = controller;
      await controller.initialize();
      await controller.setLooping(false);
      if (!mounted) {
        await _release();
        return;
      }
      setState(() {});
      await controller.play();
    } catch (_) {
      await _release();
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final controller = _controller;
    final initialized = controller?.value.isInitialized ?? false;
    final duration = widget.message.durationSeconds ?? 0;
    final label = _failed
        ? copy.text(
            'Video unavailable. Tap to retry.',
            'Film jest niedostępny. Dotknij, aby spróbować ponownie.',
          )
        : copy.template(
            'Play video message, {duration} seconds',
            'Odtwórz wiadomość wideo, {duration} s',
            values: <String, Object>{'duration': duration},
          );

    return Semantics(
      button: true,
      label: label,
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: ColoredBox(
            color: Colors.black,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (initialized) VideoPlayer(controller!),
                if (!initialized)
                  Center(
                    child: Icon(
                      Icons.video_file_outlined,
                      color: widget.mutedForegroundColor,
                      size: 40,
                    ),
                  ),
                Center(
                  child: Material(
                    color: Colors.black.withValues(alpha: .52),
                    shape: const CircleBorder(),
                    child: InkWell(
                      key: ValueKey('direct-video-${widget.message.id}'),
                      onTap: _toggle,
                      customBorder: const CircleBorder(),
                      child: SizedBox.square(
                        dimension: 52,
                        child: Center(
                          child: _loading
                              ? const SizedBox.square(
                                  dimension: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : initialized
                              ? ValueListenableBuilder<VideoPlayerValue>(
                                  valueListenable: controller!,
                                  builder: (context, value, _) => Icon(
                                    value.isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 30,
                                  ),
                                )
                              : Icon(
                                  _failed
                                      ? Icons.refresh_rounded
                                      : Icons.play_arrow_rounded,
                                  color: _failed
                                      ? widget.errorForegroundColor
                                      : Colors.white,
                                  size: 30,
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 10,
                  bottom: 8,
                  child: Text(
                    '${duration ~/ 60}:${(duration % 60).toString().padLeft(2, '0')}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      shadows: [Shadow(blurRadius: 5, color: Colors.black)],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Media-only renderer used by the Shared media destination.
///
/// Keeping this path on the same authenticated byte loader and native voice
/// preparation as chat bubbles prevents a second, subtly less secure media
/// implementation from appearing in the gallery.
class DirectMessageMediaPreview extends StatelessWidget {
  const DirectMessageMediaPreview({
    required this.message,
    this.photoWidth = 210,
    this.photoHeight = 230,
    this.privateMediaLoader,
    this.audioPlayerFactory,
    this.voiceSourcePreparer,
    this.videoSourcePreparer,
    super.key,
  });

  final Message message;
  final double photoWidth;
  final double photoHeight;
  final Future<Uint8List?> Function(String? reference, int maxBytes)?
  privateMediaLoader;
  final AudioPlayer Function()? audioPlayerFactory;
  final DirectVoiceSourcePreparer? voiceSourcePreparer;
  final DirectVideoSourcePreparer? videoSourcePreparer;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return switch (message.type) {
      MessageType.image => _ImageMessageContent(
        message: message,
        foregroundColor: palette.textPrimary,
        mutedForegroundColor: palette.textSecondary,
        privateMediaLoader: privateMediaLoader,
        width: photoWidth,
        height: photoHeight,
      ),
      MessageType.voice => _VoiceMessageContent(
        message: message,
        foregroundColor: palette.textPrimary,
        mutedForegroundColor: palette.textSecondary,
        errorForegroundColor: colors.error,
        privateMediaLoader: privateMediaLoader,
        audioPlayerFactory: audioPlayerFactory,
        voiceSourcePreparer: voiceSourcePreparer,
      ),
      MessageType.video => _VideoMessageContent(
        message: message,
        foregroundColor: palette.textPrimary,
        mutedForegroundColor: palette.textSecondary,
        errorForegroundColor: colors.error,
        privateMediaLoader: privateMediaLoader,
        videoSourcePreparer: videoSourcePreparer,
        width: photoWidth,
        height: photoHeight,
      ),
      MessageType.text => const SizedBox.shrink(),
    };
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

String _localizedReplyPreview(String value, AppLocalizations copy) {
  return switch (value.trim()) {
    'Message deleted' => copy.text('Message deleted', 'Wiadomość usunięta'),
    'Voice message' => copy.text('Voice message', 'Wiadomość głosowa'),
    'Photo' => copy.text('Photo', 'Zdjęcie'),
    'Video' => copy.text('Video', 'Film'),
    _ => value,
  };
}
