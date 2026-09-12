import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_sizing.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/moments/presentation/widgets/reply_playback_arbiter.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_story_viewer.dart'
    show StoryWaveform;

/// One voice reply inside a thread: play/pause, a position-fed silhouette
/// and the real duration of the recording.
///
/// The player is created on the FIRST deliberate tap, never in `initState` —
/// opening a thread with ten voice replies must not allocate ten decoders,
/// and opening a screen never starts audio. The media URI is resolved
/// through the caller's [resolveMediaUri], so the same row serves a Voice
/// Moment reply today (`MomentService.resolveMediaUri(momentId, commentId)`)
/// and any other comment-scoped grant later, without this widget knowing a
/// service.
///
/// Playback is arbitrated: starting this reply pauses the host's main
/// recording and stops any other reply ([ReplyPlaybackArbiter]); the main
/// recording starting stops this one.
class VoiceReplyMiniPlayer extends StatefulWidget {
  const VoiceReplyMiniPlayer({
    required this.commentId,
    required this.authorName,
    required this.durationSeconds,
    required this.resolveMediaUri,
    this.arbiter,
    this.playerFactory,
    super.key,
  });

  final String commentId;
  final String authorName;
  final int durationSeconds;

  /// Mints the short-lived, comment-scoped media grant for this reply.
  final Future<Uri> Function() resolveMediaUri;

  /// The thread host's arbiter. Absent (a preview outside a thread) the row
  /// still plays, it simply arbitrates nothing.
  final ReplyPlaybackArbiter? arbiter;

  @visibleForTesting
  final AudioPlayer Function()? playerFactory;

  /// The row's height at every width: a 40-px disc inside a 48-px target
  /// plus the card's own padding.
  static const double height = 56;
  static const double discSize = 40;
  static const double waveformHeight = 20;

  @override
  State<VoiceReplyMiniPlayer> createState() => _VoiceReplyMiniPlayerState();
}

class _VoiceReplyMiniPlayerState extends State<VoiceReplyMiniPlayer> {
  AudioPlayer? _player;
  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];
  final ValueNotifier<double> _progress = ValueNotifier<double>(0);
  bool _playing = false;
  bool _busy = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    widget.arbiter?.addListener(_handleArbiter);
  }

  @override
  void didUpdateWidget(covariant VoiceReplyMiniPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.arbiter, widget.arbiter)) {
      oldWidget.arbiter?.removeListener(_handleArbiter);
      widget.arbiter?.addListener(_handleArbiter);
    }
  }

  @override
  void dispose() {
    widget.arbiter?.removeListener(_handleArbiter);
    widget.arbiter?.replyStopped(widget.commentId);
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _player?.dispose();
    _progress.dispose();
    super.dispose();
  }

  /// Another reply — or the main recording — took the floor.
  void _handleArbiter() {
    final active = widget.arbiter?.activeReplyId;
    if (active == widget.commentId || !_playing) return;
    final player = _player;
    if (player != null) unawaited(player.pause().catchError((Object _) {}));
    if (mounted) setState(() => _playing = false);
  }

  AudioPlayer _ensurePlayer() {
    final existing = _player;
    if (existing != null) return existing;
    final player = (widget.playerFactory ?? AudioPlayer.new)();
    _player = player;
    _subscriptions
      ..add(
        player.onPositionChanged.listen((position) {
          final total = widget.durationSeconds * 1000;
          if (total <= 0) return;
          _progress.value = (position.inMilliseconds / total).clamp(0.0, 1.0);
        }),
      )
      ..add(
        player.onPlayerComplete.listen((_) {
          _progress.value = 1;
          widget.arbiter?.replyStopped(widget.commentId);
          if (mounted) setState(() => _playing = false);
        }),
      );
    return player;
  }

  Future<void> _toggle() async {
    if (_busy) return;
    final copy = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final player = _ensurePlayer();

    if (_playing) {
      widget.arbiter?.replyStopped(widget.commentId);
      try {
        await player.pause();
      } catch (_) {
        // Nothing to pause.
      }
      if (mounted) setState(() => _playing = false);
      return;
    }

    // The arbiter first: the main recording pauses and any other reply
    // stops BEFORE this one is granted, so two sources never overlap even
    // for the length of a round trip.
    widget.arbiter?.replyStarted(widget.commentId);
    setState(() {
      _playing = true;
      _busy = true;
    });
    try {
      if (_loaded) {
        await player.resume();
      } else {
        final uri = await widget.resolveMediaUri();
        if (!mounted) return;
        await player.play(UrlSource(uri.toString()));
        _loaded = true;
      }
      if (mounted) setState(() => _busy = false);
    } catch (_) {
      widget.arbiter?.replyStopped(widget.commentId);
      if (!mounted) return;
      setState(() {
        _playing = false;
        _busy = false;
      });
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              copy.text(
                'This voice reply is unavailable right now.',
                'Ta odpowiedź głosowa jest teraz niedostępna.',
              ),
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final duration = _clock(widget.durationSeconds);
    final values = <String, Object>{
      'name': widget.authorName,
      'duration': duration,
    };
    final label = _playing
        ? copy.template(
            'Pause voice reply from {name}, {duration}',
            'Wstrzymaj odpowiedź głosową: {name}, {duration}',
            values: values,
          )
        : copy.template(
            'Play voice reply from {name}, {duration}',
            'Odtwórz odpowiedź głosową: {name}, {duration}',
            values: values,
          );

    return Semantics(
      button: true,
      toggled: _playing,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: palette.surfaceMuted,
        borderRadius: AppRadius.md,
        child: InkWell(
          key: ValueKey('voice-reply-mini-player-${widget.commentId}'),
          borderRadius: AppRadius.md,
          onTap: () => unawaited(_toggle()),
          child: Container(
            constraints: const BoxConstraints(
              minHeight: VoiceReplyMiniPlayer.height,
            ),
            decoration: BoxDecoration(
              borderRadius: AppRadius.md,
              border: Border.all(color: palette.border),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppRhythm.item,
              vertical: AppRhythm.tight,
            ),
            child: Row(
              children: [
                _disc(context),
                const SizedBox(width: AppRhythm.item),
                Expanded(
                  child: ValueListenableBuilder<double>(
                    valueListenable: _progress,
                    builder: (context, progress, _) => StoryWaveform(
                      progress: progress,
                      height: VoiceReplyMiniPlayer.waveformHeight,
                      barWidth: 2,
                      barGap: 3,
                      barRadius: 1,
                      playedGradient: palette.audioProgressGradient,
                    ),
                  ),
                ),
                const SizedBox(width: AppRhythm.item),
                Text(
                  duration,
                  maxLines: 1,
                  style: AppTypography.bodySmall.copyWith(
                    color: palette.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _disc(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: VoiceReplyMiniPlayer.discSize,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          shape: BoxShape.circle,
          border: Border.all(color: palette.border),
        ),
        child: Center(
          child: _busy
              ? SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: palette.audioAccent,
                  ),
                )
              : Icon(
                  _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 20,
                  color: colors.onSurface,
                ),
        ),
      ),
    );
  }
}

/// The row is a single 48-px-tall target; [AppSizing.standardControlHeight]
/// is the floor the Moments surfaces hold themselves to.
const double kVoiceReplyMiniPlayerTarget = AppSizing.standardControlHeight;

String _clock(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  return '${safe ~/ 60}:${(safe % 60).toString().padLeft(2, '0')}';
}
