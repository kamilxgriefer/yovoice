import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/preferences/app_preferences.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/presentation/widgets/direct_media_fullscreen_viewer.dart';
import 'package:yovoice/features/messages/presentation/widgets/direct_video_audio_playback.dart';
import 'package:yovoice/features/messages/presentation/widgets/direct_video_playback_source.dart';
import 'package:yovoice/features/messages/presentation/widgets/direct_voice_playback_source.dart';
import 'package:yovoice/features/messages/presentation/widgets/room_link_message_card.dart';
import 'package:yovoice/features/rooms/data/room_links.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_context_action.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';
import 'package:yovoice/shared/widgets/media/yo_gif_view.dart';
import 'package:yovoice/shared/widgets/voice/voice_player_row.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    required this.message,
    required this.currentUserId,
    required this.onLongPress,
    this.privateMediaLoader,
    this.audioPlayerFactory,
    this.voiceSourcePreparer,
    this.videoSourcePreparer,
    this.videoAudioPreparer,
    this.roomLinkResolver,
    this.roomLinkOpener,
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
  final DirectVideoAudioPreparer? videoAudioPreparer;

  /// Test seams for the room card a text message can carry (see
  /// [RoomLinkMessageCard]). Production passes nothing and gets one
  /// fail-closed Firestore read plus a push to RoomEntryScreen.
  final RoomLinkResolver? roomLinkResolver;
  final RoomLinkOpener? roomLinkOpener;

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
        borderRadius: 18,
        // Slim bubble: compact padding, one 18 px radius with a 4 px tail
        // corner, a 1 px hairline on incoming bubbles and no shadow. The
        // outgoing brand gradient is the bubble's identity (and pinned by
        // `message_bubble_overflow_test.dart`), so it stays. On a wide
        // column the bubble stops at a readable measure instead of running
        // the full width of the thread.
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxBubbleWidth + 48),
          child: Padding(
            padding: EdgeInsets.only(
              left: isMine ? 48 : 0,
              right: isMine ? 0 : 48,
              bottom: 6,
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
                    horizontal: 12,
                    vertical: 8,
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
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(isMine ? 18 : 4),
                      bottomRight: Radius.circular(isMine ? 4 : 18),
                    ),
                    border: isMine ? null : Border.all(color: palette.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (message.replyToContent?.isNotEmpty == true)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                          decoration: BoxDecoration(
                            color: isMine
                                ? Colors.black.withValues(alpha: .18)
                                : palette.surfaceMuted,
                            borderRadius: BorderRadius.circular(8),
                            border: Border(
                              left: BorderSide(
                                color: isMine ? Colors.white : palette.focus,
                                width: 3,
                              ),
                            ),
                          ),
                          child: Text(
                            _localizedReplyPreview(
                              message.replyToContent!,
                              copy,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: bubbleMuted, fontSize: 12),
                          ),
                        ),
                      _MessageContent(
                        message: message,
                        currentUserId: currentUserId,
                        foregroundColor: bubbleForeground,
                        mutedForegroundColor: bubbleMuted,
                        errorForegroundColor: isMine
                            ? const Color(0xFFFFE0E7)
                            : colors.onErrorContainer,
                        privateMediaLoader: privateMediaLoader,
                        audioPlayerFactory: audioPlayerFactory,
                        voiceSourcePreparer: voiceSourcePreparer,
                        videoSourcePreparer: videoSourcePreparer,
                        videoAudioPreparer: videoAudioPreparer,
                        onBrandSurface: isMine,
                        roomLinkResolver: roomLinkResolver,
                        roomLinkOpener: roomLinkOpener,
                      ),
                    ],
                  ),
                ),
                if (reactionSummary.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  // A flat pill: it sits in the thread, it does not float
                  // above it, so it carries a hairline and no shadow.
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: palette.surfaceRaised,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: palette.border),
                    ),
                    child: Text(
                      reactionSummary,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
                const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatTime(context, message.sentAt),
                      style: TextStyle(
                        color: palette.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                    if (message.editedAt != null) ...[
                      const SizedBox(width: 4),
                      Text(
                        copy.text('edited', 'edytowano'),
                        style: TextStyle(
                          color: palette.textTertiary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                    if (isMine) ...[
                      const SizedBox(width: 4),
                      Icon(
                        wasRead ? Icons.done_all_rounded : Icons.done_rounded,
                        size: 14,
                        color: wasRead ? palette.focus : palette.textTertiary,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The widest a bubble grows on a desktop column: a readable measure.
  static const double _maxBubbleWidth = 560;

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
    required this.currentUserId,
    required this.foregroundColor,
    required this.mutedForegroundColor,
    required this.errorForegroundColor,
    required this.privateMediaLoader,
    required this.audioPlayerFactory,
    required this.voiceSourcePreparer,
    required this.videoSourcePreparer,
    required this.videoAudioPreparer,
    required this.onBrandSurface,
    required this.roomLinkResolver,
    required this.roomLinkOpener,
  });

  final Message message;
  final String currentUserId;
  final Color foregroundColor;
  final Color mutedForegroundColor;
  final Color errorForegroundColor;
  final Future<Uint8List?> Function(String? reference, int maxBytes)?
  privateMediaLoader;
  final AudioPlayer Function()? audioPlayerFactory;
  final DirectVoiceSourcePreparer? voiceSourcePreparer;
  final DirectVideoSourcePreparer? videoSourcePreparer;
  final DirectVideoAudioPreparer? videoAudioPreparer;
  final bool onBrandSurface;
  final RoomLinkResolver? roomLinkResolver;
  final RoomLinkOpener? roomLinkOpener;

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
      case MessageType.gif:
        final gif = message.gif;
        if (gif == null) {
          return Text(
            message.content,
            style: TextStyle(color: foregroundColor),
          );
        }
        return YoGifView(
          asset: gif,
          autoLoad:
              AppPreferencesScope.maybeOf(context)?.value.gifAutoLoadEnabled ??
              true,
        );
      case MessageType.voice:
        return _VoiceMessageContent(
          message: message,
          ownerId: currentUserId,
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
          ownerId: currentUserId,
          foregroundColor: foregroundColor,
          mutedForegroundColor: mutedForegroundColor,
          privateMediaLoader: privateMediaLoader,
        );
      case MessageType.video:
        return _VideoMessageContent(
          message: message,
          ownerId: currentUserId,
          foregroundColor: foregroundColor,
          mutedForegroundColor: mutedForegroundColor,
          errorForegroundColor: errorForegroundColor,
          privateMediaLoader: privateMediaLoader,
          videoSourcePreparer: videoSourcePreparer,
          videoAudioPreparer: videoAudioPreparer,
        );
      case MessageType.text:
        final text = Text(
          message.content,
          style: TextStyle(
            color: foregroundColor,
            fontSize: 14.5,
            height: 1.35,
          ),
        );
        // A room invitation is a plain text message carrying the canonical
        // `?room=` link (ADR-151): the text stays exactly as sent and a room
        // card is added beneath it. Anything else renders as before.
        final roomId = findRoomLinkId(message.content);
        if (roomId == null) return text;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            text,
            RoomLinkMessageCard(
              roomId: roomId,
              onBrandSurface: onBrandSurface,
              resolver: roomLinkResolver,
              opener: roomLinkOpener,
            ),
          ],
        );
    }
  }
}

typedef _DirectMediaSnapshot = ({
  String ownerId,
  String conversationId,
  String messageId,
  String reference,
});

class _StaleDirectMediaLoad implements Exception {
  const _StaleDirectMediaLoad();
}

const _directVideoTeardownWait = Duration(seconds: 2);

Future<bool> _settlesWithin(Future<void> operation, Duration timeout) {
  final result = Completer<bool>();
  final timer = Timer(timeout, () => result.complete(false));
  operation.then<void>(
    (_) {
      if (!result.isCompleted) result.complete(true);
    },
    onError: (Object _, StackTrace __) {
      if (!result.isCompleted) result.complete(true);
    },
  );
  return result.future.whenComplete(timer.cancel);
}

Future<void> _pauseVideoControllerBestEffort(
  VideoPlayerController controller,
) async {
  try {
    await controller.pause();
  } catch (_) {
    // A revoked controller may already be closing on the platform side.
  }
}

Future<void> _disposeVideoResources({
  VideoPlayerController? controller,
  PreparedDirectVideoSource? prepared,
}) async {
  await Future.wait<void>([
    if (controller != null)
      () async {
        try {
          await controller.dispose();
        } catch (_) {
          // The decoder may already have torn itself down.
        }
      }(),
    if (prepared != null)
      () async {
        try {
          await prepared.dispose();
        } catch (_) {
          // A best-effort temp-file cleanup must not escape disposal.
        }
      }(),
  ]);
}

class _VoiceMessageContent extends StatefulWidget {
  const _VoiceMessageContent({
    required this.message,
    required this.ownerId,
    required this.foregroundColor,
    required this.mutedForegroundColor,
    required this.errorForegroundColor,
    required this.privateMediaLoader,
    required this.audioPlayerFactory,
    required this.voiceSourcePreparer,
  });

  final Message message;
  final String ownerId;
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
  Future<void> _playerCommandTail = Future<void>.value();
  StreamSubscription<PlayerState>? _stateSubscription;
  Uint8List? _bytes;
  int _mediaGeneration = 0;
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
    if (oldWidget.ownerId != widget.ownerId ||
        oldWidget.message.conversationId != widget.message.conversationId ||
        oldWidget.message.id != widget.message.id ||
        oldWidget.message.mediaUrl != widget.message.mediaUrl) {
      _mediaGeneration += 1;
      final prepared = _takePreparedSource();
      _bytes = null;
      _loading = false;
      _playing = false;
      _paused = false;
      _failed = false;
      unawaited(_interruptPlayerAndDisposeSource(prepared));
    }
  }

  @override
  void dispose() {
    _mediaGeneration += 1;
    final prepared = _takePreparedSource();
    unawaited(_stateSubscription?.cancel());
    unawaited(_disposePlayerAndSource(prepared));
    super.dispose();
  }

  PreparedDirectVoiceSource? _takePreparedSource() {
    final prepared = _preparedSource;
    _preparedSource = null;
    return prepared;
  }

  Future<void> _disposePreparedSource(
    PreparedDirectVoiceSource? prepared,
  ) async {
    try {
      await prepared?.dispose();
    } catch (_) {
      // Temporary playback files are best-effort cleanup resources.
    }
  }

  Future<void> _runPlayerCommand(Future<void> Function() command) {
    final operation = _playerCommandTail.then((_) => command());
    _playerCommandTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return operation;
  }

  Future<void> _interruptPlayer() {
    final immediateStop = _player.stop().catchError((Object _) {});
    final previousCommands = _playerCommandTail;
    final barrier = Future.wait<void>([
      previousCommands,
      immediateStop,
    ]).then<void>((_) {});
    _playerCommandTail = barrier;
    return barrier;
  }

  Future<void> _interruptPlayerAndDisposeSource(
    PreparedDirectVoiceSource? prepared,
  ) async {
    await _interruptPlayer();
    await _disposePreparedSource(prepared);
  }

  Future<void> _disposePlayerAndSource(
    PreparedDirectVoiceSource? prepared,
  ) async {
    await _interruptPlayer();
    await _disposePreparedSource(prepared);
    try {
      await _runPlayerCommand(_player.dispose);
    } catch (_) {
      // The native player may already have been released by the platform.
    }
  }

  _DirectMediaSnapshot get _mediaSnapshot => (
    ownerId: widget.ownerId.trim(),
    conversationId: widget.message.conversationId,
    messageId: widget.message.id,
    reference: widget.message.mediaUrl?.trim() ?? '',
  );

  bool _ownsMediaLoad(int generation, _DirectMediaSnapshot snapshot) =>
      mounted &&
      snapshot.ownerId.isNotEmpty &&
      generation == _mediaGeneration &&
      _mediaSnapshot == snapshot;

  Future<void> _playOwnedSource(
    Source source,
    int generation,
    _DirectMediaSnapshot snapshot,
  ) {
    return _runPlayerCommand(() async {
      if (!_ownsMediaLoad(generation, snapshot)) return;
      try {
        await _player.play(source);
      } finally {
        if (!_ownsMediaLoad(generation, snapshot)) {
          try {
            await _player.stop();
          } catch (_) {
            // A superseded source must never survive a late platform play.
          }
        }
      }
    });
  }

  Future<void> _toggle() async {
    if (_loading) return;
    if (_playing) {
      await _runPlayerCommand(_player.pause);
      return;
    }
    if (_paused) {
      await _runPlayerCommand(_player.resume);
      return;
    }
    final generation = ++_mediaGeneration;
    final snapshot = _mediaSnapshot;
    if (!_ownsMediaLoad(generation, snapshot)) return;
    try {
      setState(() {
        _loading = true;
        _failed = false;
      });
      final reference = snapshot.reference;
      if (reference.startsWith('gs://')) {
        final bytes =
            _bytes ??
            await (widget.privateMediaLoader?.call(
                  reference,
                  12 * 1024 * 1024,
                ) ??
                _privateMediaBytes(reference, maxBytes: 12 * 1024 * 1024));
        if (!_ownsMediaLoad(generation, snapshot)) return;
        if (bytes == null || bytes.isEmpty) {
          throw StateError('Voice message unavailable');
        }
        _bytes = bytes;
        var prepared = _preparedSource;
        if (prepared == null) {
          final created =
              await (widget.voiceSourcePreparer ?? prepareDirectVoiceSource)(
                bytes,
                snapshot.messageId,
              );
          if (!_ownsMediaLoad(generation, snapshot)) {
            await created.dispose();
            return;
          }
          _preparedSource = created;
          prepared = created;
        }
        if (!_ownsMediaLoad(generation, snapshot)) return;
        await _playOwnedSource(prepared.source, generation, snapshot);
      } else if (reference.startsWith('https://')) {
        if (!_ownsMediaLoad(generation, snapshot)) return;
        await _playOwnedSource(UrlSource(reference), generation, snapshot);
      } else {
        throw StateError('Voice message unavailable');
      }
    } catch (_) {
      // A native temporary file may have been removed under memory pressure,
      // or a platform player may have rejected the first preparation. Retry
      // must rebuild the source instead of replaying a poisoned handle.
      if (_ownsMediaLoad(generation, snapshot)) {
        final prepared = _takePreparedSource();
        await _interruptPlayerAndDisposeSource(prepared);
        if (_ownsMediaLoad(generation, snapshot)) {
          setState(() => _failed = true);
        }
      }
    } finally {
      if (_ownsMediaLoad(generation, snapshot)) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final duration = widget.message.durationSeconds ?? 0;
    final copy = AppLocalizations.of(context);

    return VoicePlayerRow(
      status: _loading
          ? VoicePlayerRowStatus.loading
          : _failed
          ? VoicePlayerRowStatus.failed
          : _playing
          ? VoicePlayerRowStatus.playing
          : _paused
          ? VoicePlayerRowStatus.paused
          : VoicePlayerRowStatus.idle,
      durationSeconds: duration,
      // No progress: this player reports play / pause / loading / failed and
      // no position, so the bars stay a still silhouette rather than a fill
      // invented from the duration.
      semanticsLabel: _failed
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
      onTap: _toggle,
      tapKey: ValueKey<String>('direct-voice-${widget.message.id}'),
      style: VoicePlayerRowStyle.inline(
        foreground: widget.foregroundColor,
        mutedForeground: widget.mutedForegroundColor,
        errorForeground: widget.errorForegroundColor,
      ),
    );
  }
}

class _ImageMessageContent extends StatefulWidget {
  const _ImageMessageContent({
    required this.message,
    required this.ownerId,
    required this.foregroundColor,
    required this.mutedForegroundColor,
    required this.privateMediaLoader,
    this.width = 210,
    this.height = 230,
  });

  final Message message;
  final String ownerId;
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
  int _mediaGeneration = 0;
  final ValueNotifier<int> _ownershipChanges = ValueNotifier<int>(0);
  late Future<Uint8List?> _image = _beginLoad();

  _DirectMediaSnapshot get _mediaSnapshot => (
    ownerId: widget.ownerId.trim(),
    conversationId: widget.message.conversationId,
    messageId: widget.message.id,
    reference: widget.message.mediaUrl?.trim() ?? '',
  );

  bool _ownsMediaLoad(int generation, _DirectMediaSnapshot snapshot) =>
      mounted &&
      snapshot.ownerId.isNotEmpty &&
      generation == _mediaGeneration &&
      _mediaSnapshot == snapshot;

  Future<Uint8List?> _beginLoad() {
    final generation = _mediaGeneration;
    final snapshot = _mediaSnapshot;
    if (!_ownsMediaLoad(generation, snapshot)) {
      return Future<Uint8List?>.value();
    }
    if (snapshot.reference.startsWith('https://')) {
      return Future<Uint8List?>.value();
    }
    return _load(generation, snapshot);
  }

  Future<Uint8List?> _load(
    int generation,
    _DirectMediaSnapshot snapshot,
  ) async {
    final bytes =
        await (widget.privateMediaLoader?.call(
              snapshot.reference,
              8 * 1024 * 1024,
            ) ??
            _privateMediaBytes(snapshot.reference, maxBytes: 8 * 1024 * 1024));
    if (!_ownsMediaLoad(generation, snapshot)) {
      throw const _StaleDirectMediaLoad();
    }
    return bytes;
  }

  void _revokeMediaIdentity() {
    _mediaGeneration += 1;
    final generation = _mediaGeneration;
    scheduleMicrotask(() {
      if (_ownershipChanges.value < generation) {
        _ownershipChanges.value = generation;
      }
    });
  }

  void _open(BuildContext context, ImageProvider imageProvider) {
    final generation = _mediaGeneration;
    final snapshot = _mediaSnapshot;
    unawaited(
      showDirectImageFullscreenViewer(
        context,
        imageProvider: imageProvider,
        ownershipChanges: _ownershipChanges,
        ownershipIsCurrent: () => _ownsMediaLoad(generation, snapshot),
      ),
    );
  }

  @override
  void didUpdateWidget(covariant _ImageMessageContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ownerId != widget.ownerId ||
        oldWidget.message.conversationId != widget.message.conversationId ||
        oldWidget.message.id != widget.message.id ||
        oldWidget.message.mediaUrl != widget.message.mediaUrl) {
      _revokeMediaIdentity();
      _image = _beginLoad();
    }
  }

  @override
  void dispose() {
    _revokeMediaIdentity();
    // A full-screen route can briefly outlive its source bubble. It owns the
    // final listener lifetime, so this notifier must remain valid until that
    // route observes revocation and closes.
    super.dispose();
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
      final imageProvider = NetworkImage(mediaUrl);
      return AccessibleTapRegion(
        key: ValueKey('direct-image-${widget.message.id}'),
        onTap: () => _open(context, imageProvider),
        semanticLabel: copy.text(
          'Open photo full screen',
          'Otwórz zdjęcie na pełnym ekranie',
        ),
        tooltip: copy.text('View photo', 'Wyświetl zdjęcie'),
        borderRadius: 14,
        focusContrastColor: Colors.black,
        child: ExcludeSemantics(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image(
              image: imageProvider,
              width: widget.width,
              height: widget.height,
              fit: BoxFit.cover,
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
            onPressed: () => setState(() => _image = _beginLoad()),
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
        final imageProvider = MemoryImage(bytes);
        return AccessibleTapRegion(
          key: ValueKey('direct-image-${widget.message.id}'),
          onTap: () => _open(context, imageProvider),
          semanticLabel: copy.text(
            'Open photo full screen',
            'Otwórz zdjęcie na pełnym ekranie',
          ),
          tooltip: copy.text('View photo', 'Wyświetl zdjęcie'),
          borderRadius: 14,
          focusContrastColor: Colors.black,
          child: ExcludeSemantics(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image(
                image: imageProvider,
                width: widget.width,
                height: widget.height,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
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
    required this.ownerId,
    required this.foregroundColor,
    required this.mutedForegroundColor,
    required this.errorForegroundColor,
    required this.privateMediaLoader,
    required this.videoSourcePreparer,
    required this.videoAudioPreparer,
    this.width = 238,
    this.height = 158,
  });

  final Message message;
  final String ownerId;
  final Color foregroundColor;
  final Color mutedForegroundColor;
  final Color errorForegroundColor;
  final Future<Uint8List?> Function(String? reference, int maxBytes)?
  privateMediaLoader;
  final DirectVideoSourcePreparer? videoSourcePreparer;
  final DirectVideoAudioPreparer? videoAudioPreparer;
  final double width;
  final double height;

  @override
  State<_VideoMessageContent> createState() => _VideoMessageContentState();
}

class _VideoMessageContentState extends State<_VideoMessageContent> {
  VideoPlayerController? _controller;
  Future<VideoPlayerController>? _controllerLoad;
  PreparedDirectVideoSource? _preparedSource;
  final Map<VideoPlayerController, Set<Future<void>>> _activePlays = {};
  final ValueNotifier<int> _ownershipChanges = ValueNotifier<int>(0);
  Uint8List? _bytes;
  int _mediaGeneration = 0;
  bool _loading = false;
  bool _failed = false;

  @override
  void didUpdateWidget(covariant _VideoMessageContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ownerId != widget.ownerId ||
        oldWidget.message.conversationId != widget.message.conversationId ||
        oldWidget.message.id != widget.message.id ||
        oldWidget.message.mediaUrl != widget.message.mediaUrl) {
      _revokeMediaIdentity();
      unawaited(_release());
      _controllerLoad = null;
      _bytes = null;
      _loading = false;
      _failed = false;
    }
  }

  @override
  void dispose() {
    _revokeMediaIdentity();
    _controllerLoad = null;
    _bytes = null;
    unawaited(_release());
    super.dispose();
  }

  Future<void> _release() async {
    final controller = _controller;
    final prepared = _preparedSource;
    _controller = null;
    _preparedSource = null;
    // didUpdateWidget runs during build. Yield before controller commands,
    // because video_player synchronously notifies its listeners on pause.
    await Future<void>.value();
    if (controller == null) {
      await _disposeVideoResources(prepared: prepared);
      return;
    }
    unawaited(_pauseVideoControllerBestEffort(controller));
    final active = List<Future<void>>.of(
      _activePlays[controller] ?? const <Future<void>>{},
    );
    if (active.isNotEmpty) {
      final settled = Future.wait<void>(
        active.map(
          (play) =>
              play.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
        ),
      );
      final completedInTime = await _settlesWithin(
        settled,
        _directVideoTeardownWait,
      );
      if (!completedInTime) {
        _activePlays.remove(controller);
        // Disposing video_player while its native play Future is unresolved
        // can let the late continuation create an uncancellable position
        // timer. Detach immediately, then finish cleanup once that command
        // settles; the generation guard issues another pause at that point.
        unawaited(
          settled.then((_) async {
            unawaited(_pauseVideoControllerBestEffort(controller));
            await _disposeVideoResources(
              controller: controller,
              prepared: prepared,
            );
          }),
        );
        return;
      }
    }
    _activePlays.remove(controller);
    unawaited(_pauseVideoControllerBestEffort(controller));
    await _disposeVideoResources(controller: controller, prepared: prepared);
  }

  _DirectMediaSnapshot get _mediaSnapshot => (
    ownerId: widget.ownerId.trim(),
    conversationId: widget.message.conversationId,
    messageId: widget.message.id,
    reference: widget.message.mediaUrl?.trim() ?? '',
  );

  bool _ownsMediaLoad(int generation, _DirectMediaSnapshot snapshot) =>
      mounted &&
      snapshot.ownerId.isNotEmpty &&
      generation == _mediaGeneration &&
      _mediaSnapshot == snapshot;

  void _revokeMediaIdentity() {
    _mediaGeneration += 1;
    final generation = _mediaGeneration;
    scheduleMicrotask(() {
      if (_ownershipChanges.value < generation) {
        _ownershipChanges.value = generation;
      }
    });
  }

  bool _ownsController(
    VideoPlayerController controller,
    int generation,
    _DirectMediaSnapshot snapshot,
  ) =>
      _ownsMediaLoad(generation, snapshot) &&
      identical(_controller, controller);

  Future<void> _playOwnedController(
    VideoPlayerController controller,
    int generation,
    _DirectMediaSnapshot snapshot,
  ) {
    late final Future<void> operation;
    operation = () async {
      if (!_ownsController(controller, generation, snapshot)) {
        throw const _StaleDirectMediaLoad();
      }
      await _prepareAudiblePlayback(controller, generation, snapshot);
      if (!_ownsController(controller, generation, snapshot)) {
        throw const _StaleDirectMediaLoad();
      }
      try {
        await controller.play();
      } finally {
        if (!_ownsController(controller, generation, snapshot)) {
          unawaited(_pauseVideoControllerBestEffort(controller));
        }
      }
      if (!_ownsController(controller, generation, snapshot)) {
        throw const _StaleDirectMediaLoad();
      }
    }();
    final active = _activePlays.putIfAbsent(controller, () => {});
    active.add(operation);
    operation.then<void>(
      (_) => _removeActivePlay(controller, operation),
      onError: (Object _, StackTrace __) =>
          _removeActivePlay(controller, operation),
    );
    return operation;
  }

  Future<void> _prepareAudiblePlayback(
    VideoPlayerController controller,
    int generation,
    _DirectMediaSnapshot snapshot,
  ) async {
    try {
      await (widget.videoAudioPreparer ?? prepareDirectVideoAudioPlayback)();
    } catch (_) {
      // Keep video available if a platform audio-session repair is rejected.
    }
    if (!_ownsController(controller, generation, snapshot)) return;
    try {
      // Reassert on every start. The same controller can be paused while a
      // call, recorder or another media surface changes process audio state.
      await controller.setVolume(1);
    } catch (_) {
      // VideoPlayer defaults to full volume, so playback remains worthwhile
      // even if a platform-specific volume command fails.
    }
  }

  void _removeActivePlay(
    VideoPlayerController controller,
    Future<void> operation,
  ) {
    final active = _activePlays[controller];
    active?.remove(operation);
    if (active?.isEmpty ?? false) _activePlays.remove(controller);
  }

  Future<VideoPlayerController> _ensureController() {
    final existing = _controller;
    if (existing != null && existing.value.isInitialized) {
      return Future.value(existing);
    }
    final pending = _controllerLoad;
    if (pending != null) return pending;

    final generation = _mediaGeneration;
    final snapshot = _mediaSnapshot;
    final operation = _initializeController(generation, snapshot);
    _controllerLoad = operation;
    operation.then<void>(
      (_) {
        if (identical(_controllerLoad, operation)) _controllerLoad = null;
      },
      onError: (Object _, StackTrace __) {
        if (identical(_controllerLoad, operation)) _controllerLoad = null;
      },
    );
    return operation;
  }

  Future<VideoPlayerController> _initializeController(
    int generation,
    _DirectMediaSnapshot snapshot,
  ) async {
    VideoPlayerController? controller;
    PreparedDirectVideoSource? prepared;
    try {
      final reference = snapshot.reference;
      if (reference.startsWith('https://')) {
        controller = VideoPlayerController.networkUrl(Uri.parse(reference));
      } else if (reference.startsWith('gs://')) {
        final bytes =
            _bytes ??
            await (widget.privateMediaLoader?.call(
                  reference,
                  64 * 1024 * 1024,
                ) ??
                _privateMediaBytes(reference, maxBytes: 64 * 1024 * 1024));
        if (!_ownsMediaLoad(generation, snapshot)) {
          throw const _StaleDirectMediaLoad();
        }
        if (bytes == null || bytes.isEmpty) {
          throw StateError('Video unavailable');
        }
        _bytes = bytes;
        prepared =
            await (widget.videoSourcePreparer ?? prepareDirectVideoSource)(
              bytes,
              snapshot.messageId,
              reference,
            );
        if (!_ownsMediaLoad(generation, snapshot)) {
          throw const _StaleDirectMediaLoad();
        }
        controller = prepared.createController();
      } else {
        throw StateError('Video unavailable');
      }
      await controller.initialize();
      await controller.setLooping(false);
      if (!_ownsMediaLoad(generation, snapshot)) {
        throw const _StaleDirectMediaLoad();
      }
      _controller = controller;
      _preparedSource = prepared;
      setState(() {});
      return controller;
    } catch (_) {
      await _disposeVideoResources(controller: controller, prepared: prepared);
      rethrow;
    }
  }

  Future<void> _toggle() async {
    if (_loading) return;
    final generation = _mediaGeneration;
    final snapshot = _mediaSnapshot;
    if (!_ownsMediaLoad(generation, snapshot)) return;
    final existing = _controller;
    if (existing != null && existing.value.isInitialized) {
      try {
        if (existing.value.isPlaying) {
          await existing.pause();
        } else {
          if (existing.value.position >= existing.value.duration) {
            await existing.seekTo(Duration.zero);
          }
          await _playOwnedController(existing, generation, snapshot);
        }
      } catch (_) {
        if (_ownsMediaLoad(generation, snapshot)) {
          setState(() => _failed = true);
        }
      }
      return;
    }

    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final controller = await _ensureController();
      if (!_ownsMediaLoad(generation, snapshot)) return;
      await _playOwnedController(controller, generation, snapshot);
    } catch (_) {
      if (_ownsMediaLoad(generation, snapshot)) {
        setState(() => _failed = true);
      }
    } finally {
      if (_ownsMediaLoad(generation, snapshot)) {
        setState(() => _loading = false);
      }
    }
  }

  Future<VideoPlayerController> _controllerForFullscreen(
    int generation,
    _DirectMediaSnapshot snapshot,
  ) async {
    try {
      if (!_ownsMediaLoad(generation, snapshot)) {
        throw const _StaleDirectMediaLoad();
      }
      final controller = await _ensureController();
      if (!_ownsMediaLoad(generation, snapshot)) {
        throw const _StaleDirectMediaLoad();
      }
      setState(() => _failed = false);
      return controller;
    } catch (_) {
      if (_ownsMediaLoad(generation, snapshot)) {
        setState(() => _failed = true);
      }
      rethrow;
    }
  }

  Future<void> _playControllerForFullscreen(
    VideoPlayerController controller,
    int generation,
    _DirectMediaSnapshot snapshot,
  ) async {
    await _playOwnedController(controller, generation, snapshot);
  }

  void _openFullscreen() {
    final generation = _mediaGeneration;
    final snapshot = _mediaSnapshot;
    unawaited(
      showDirectVideoFullscreenViewer(
        context,
        controllerLoader: () => _controllerForFullscreen(generation, snapshot),
        controllerPlayer: (controller) =>
            _playControllerForFullscreen(controller, generation, snapshot),
        controllerIsCurrent: (controller) =>
            _ownsController(controller, generation, snapshot),
        ownershipChanges: _ownershipChanges,
        ownershipIsCurrent: () => _ownsMediaLoad(generation, snapshot),
      ),
    );
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
                PositionedDirectional(
                  top: 6,
                  end: 6,
                  child: Material(
                    color: Colors.black.withValues(alpha: .56),
                    shape: const CircleBorder(),
                    child: IconButton(
                      key: ValueKey(
                        'direct-video-fullscreen-${widget.message.id}',
                      ),
                      tooltip: copy.text(
                        'Open video full screen',
                        'Otwórz film na pełnym ekranie',
                      ),
                      onPressed: _openFullscreen,
                      constraints: const BoxConstraints.tightFor(
                        width: 48,
                        height: 48,
                      ),
                      color: Colors.white,
                      icon: const Icon(Icons.fullscreen_rounded),
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
    required this.currentUserId,
    this.photoWidth = 210,
    this.photoHeight = 230,
    this.privateMediaLoader,
    this.audioPlayerFactory,
    this.voiceSourcePreparer,
    this.videoSourcePreparer,
    this.videoAudioPreparer,
    super.key,
  });

  final Message message;
  final String currentUserId;
  final double photoWidth;
  final double photoHeight;
  final Future<Uint8List?> Function(String? reference, int maxBytes)?
  privateMediaLoader;
  final AudioPlayer Function()? audioPlayerFactory;
  final DirectVoiceSourcePreparer? voiceSourcePreparer;
  final DirectVideoSourcePreparer? videoSourcePreparer;
  final DirectVideoAudioPreparer? videoAudioPreparer;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return switch (message.type) {
      MessageType.image => _ImageMessageContent(
        message: message,
        ownerId: currentUserId,
        foregroundColor: palette.textPrimary,
        mutedForegroundColor: palette.textSecondary,
        privateMediaLoader: privateMediaLoader,
        width: photoWidth,
        height: photoHeight,
      ),
      MessageType.voice => _VoiceMessageContent(
        message: message,
        ownerId: currentUserId,
        foregroundColor: palette.textPrimary,
        mutedForegroundColor: palette.textSecondary,
        errorForegroundColor: colors.error,
        privateMediaLoader: privateMediaLoader,
        audioPlayerFactory: audioPlayerFactory,
        voiceSourcePreparer: voiceSourcePreparer,
      ),
      MessageType.video => _VideoMessageContent(
        message: message,
        ownerId: currentUserId,
        foregroundColor: palette.textPrimary,
        mutedForegroundColor: palette.textSecondary,
        errorForegroundColor: colors.error,
        privateMediaLoader: privateMediaLoader,
        videoSourcePreparer: videoSourcePreparer,
        videoAudioPreparer: videoAudioPreparer,
        width: photoWidth,
        height: photoHeight,
      ),
      MessageType.text || MessageType.gif => const SizedBox.shrink(),
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
