import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/features/creator/data/models/creator_pinned_post.dart';
import 'package:yovoice/features/creator/data/services/creator_pinned_post_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';

const _pinAccent = Color(0xFFB932FF);
const _pinSurface = Color(0xFF17101F);
const _pinMuted = Color(0xFFA99DB3);

/// Reusable public-profile surface for a Creator's one pinned Voice Moment.
/// It renders nothing when the exact-id read is missing, malformed, expired,
/// unpublished, deleted, or forbidden by the canonical entitlement rules.
class CreatorPinnedMomentCard extends StatefulWidget {
  const CreatorPinnedMomentCard({
    required this.creatorId,
    this.service,
    this.onOpen,
    this.compact = false,
    this.outerPadding = EdgeInsets.zero,
    super.key,
  });

  final String creatorId;
  final CreatorPinnedPostService? service;
  final ValueChanged<VoiceMoment>? onOpen;
  final bool compact;
  final EdgeInsetsGeometry outerPadding;

  @override
  State<CreatorPinnedMomentCard> createState() =>
      _CreatorPinnedMomentCardState();
}

class _CreatorPinnedMomentCardState extends State<CreatorPinnedMomentCard> {
  late CreatorPinnedPostService _service;
  late Stream<PinnedVoiceMoment?> _stream;
  final GlobalKey<_PinnedMomentPlayButtonState> _playButtonKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(CreatorPinnedMomentCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.creatorId != widget.creatorId ||
        oldWidget.service != widget.service) {
      _bind();
    }
  }

  void _bind() {
    _service = widget.service ?? CreatorPinnedPostService();
    _stream = _service.watchPinnedPostForCreator(widget.creatorId);
  }

  Future<void> _openDetails(VoiceMoment moment) async {
    await _playButtonKey.currentState?.stopPlayback();
    if (mounted) widget.onOpen?.call(moment);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PinnedVoiceMoment?>(
      stream: _stream,
      builder: (context, snapshot) {
        final value = snapshot.data;
        if (snapshot.hasError || value == null) {
          return const SizedBox.shrink();
        }
        final moment = value.moment;
        final content = Container(
          width: double.infinity,
          padding: EdgeInsets.all(widget.compact ? 14 : 18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF25102F), _pinSurface],
            ),
            borderRadius: BorderRadius.circular(widget.compact ? 16 : 20),
            border: Border.all(color: const Color(0xFF62317B)),
          ),
          child: Row(
            children: [
              _PinnedMomentPlayButton(key: _playButtonKey, moment: moment),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'PINNED VOICE MOMENT',
                      style: TextStyle(
                        color: _pinAccent,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      moment.caption.trim().isEmpty
                          ? 'Voice Moment'
                          : moment.caption,
                      maxLines: widget.compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        _MomentMeta(
                          icon: Icons.graphic_eq_rounded,
                          label: moment.durationLabel,
                        ),
                        _MomentMeta(
                          icon: Icons.favorite_border_rounded,
                          label: '${moment.likeCount}',
                        ),
                        _MomentMeta(
                          icon: Icons.chat_bubble_outline_rounded,
                          label: '${moment.commentCount}',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (widget.onOpen != null) ...[
                const SizedBox(width: 8),
                Semantics(
                  button: true,
                  label: 'Open pinned Voice Moment details',
                  onTap: () => _openDetails(moment),
                  excludeSemantics: true,
                  child: IconButton(
                    onPressed: () => _openDetails(moment),
                    style: IconButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      foregroundColor: _pinMuted,
                    ),
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ),
              ],
            ],
          ),
        );
        return Padding(padding: widget.outerPadding, child: content);
      },
    );
  }
}

class _PinnedMomentPlayButton extends StatefulWidget {
  const _PinnedMomentPlayButton({required this.moment, super.key});

  final VoiceMoment moment;

  @override
  State<_PinnedMomentPlayButton> createState() =>
      _PinnedMomentPlayButtonState();
}

class _PinnedMomentPlayButtonState extends State<_PinnedMomentPlayButton> {
  final AudioPlayer _player = AudioPlayer();
  late final StreamSubscription<void> _completeSubscription;
  bool _playing = false;
  bool _changingPlayback = false;

  @override
  void initState() {
    super.initState();
    _completeSubscription = _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  @override
  void didUpdateWidget(_PinnedMomentPlayButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.moment.id != widget.moment.id ||
        oldWidget.moment.audioUrl != widget.moment.audioUrl) {
      unawaited(stopPlayback());
    }
  }

  @override
  void dispose() {
    unawaited(_completeSubscription.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> stopPlayback() async {
    try {
      await _player.stop();
    } finally {
      if (mounted) {
        setState(() {
          _playing = false;
          _changingPlayback = false;
        });
      }
    }
  }

  Future<void> _togglePlayback() async {
    final audioUrl = widget.moment.audioUrl;
    if (_changingPlayback || audioUrl == null || audioUrl.isEmpty) return;
    setState(() => _changingPlayback = true);
    try {
      if (_playing) {
        await _player.pause();
      } else {
        await _player.play(UrlSource(audioUrl));
      }
      if (mounted) setState(() => _playing = !_playing);
    } catch (_) {
      if (mounted) setState(() => _playing = false);
    } finally {
      if (mounted) setState(() => _changingPlayback = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: !_changingPlayback,
      label: _playing
          ? 'Pause pinned Voice Moment'
          : 'Play pinned Voice Moment',
      onTap: _changingPlayback ? null : _togglePlayback,
      excludeSemantics: true,
      child: IconButton.filledTonal(
        onPressed: _changingPlayback ? null : _togglePlayback,
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          backgroundColor: _pinAccent.withValues(alpha: .14),
          foregroundColor: _pinAccent,
          side: BorderSide(color: _pinAccent.withValues(alpha: .5)),
        ),
        icon: _changingPlayback
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
      ),
    );
  }
}

class _MomentMeta extends StatelessWidget {
  const _MomentMeta({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: _pinMuted),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            color: _pinMuted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
