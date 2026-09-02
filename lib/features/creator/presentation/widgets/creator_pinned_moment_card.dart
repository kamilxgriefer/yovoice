import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/creator/data/models/creator_pinned_post.dart';
import 'package:yovoice/features/creator/data/services/creator_pinned_post_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_expiry_scheduler.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_expiry_accessibility.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_expiry_boundary.dart';

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
    this.momentService,
    this.onOpen,
    this.compact = false,
    this.outerPadding = EdgeInsets.zero,
    this.playerFactory,
    this.expiryClock,
    this.expiryTimerFactory,
    super.key,
  });

  final String creatorId;
  final CreatorPinnedPostService? service;
  final MomentService? momentService;
  final ValueChanged<VoiceMoment>? onOpen;
  final bool compact;
  final EdgeInsetsGeometry outerPadding;

  @visibleForTesting
  final AudioPlayer Function()? playerFactory;

  @visibleForTesting
  final MomentExpiryClock? expiryClock;

  @visibleForTesting
  final MomentExpiryTimerFactory? expiryTimerFactory;

  @override
  State<CreatorPinnedMomentCard> createState() =>
      _CreatorPinnedMomentCardState();
}

class _CreatorPinnedMomentCardState extends State<CreatorPinnedMomentCard> {
  late CreatorPinnedPostService _service;
  late Stream<PinnedVoiceMoment?> _stream;
  final GlobalKey<_PinnedMomentPlayButtonState> _playButtonKey = GlobalKey();
  final MomentExpiryAnnouncer _expiryAnnouncer = MomentExpiryAnnouncer();

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

  void _handleExpired(VoiceMoment moment) {
    final copy = AppLocalizations.of(context);
    final previousFocus = FocusManager.instance.primaryFocus;
    final recoverFocus = momentExpiryFocusIsWithin(context, previousFocus);
    final player = _playButtonKey.currentState;
    if (player != null) unawaited(player.stopPlayback());
    _expiryAnnouncer.announce(
      context,
      transition: 'public-pin-${moment.id}',
      message: copy.text(
        'Pinned Voice Moment expired.',
        'Przypięty Voice Moment wygasł.',
      ),
    );
    if (!recoverFocus || previousFocus == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          previousFocus.hasFocus ||
          !momentExpirySurfaceIsVisible(context)) {
        return;
      }
      FocusScope.of(context).nextFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
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
              _PinnedMomentPlayButton(
                key: _playButtonKey,
                moment: moment,
                momentService: widget.momentService,
                playerFactory: widget.playerFactory,
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      copy.text(
                        'PINNED VOICE MOMENT',
                        'PRZYPIĘTY VOICE MOMENT',
                      ),
                      style: const TextStyle(
                        color: _pinAccent,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      moment.caption.trim().isEmpty
                          ? copy.text('Voice Moment', 'Voice Moment')
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
                          semanticLabel: copy.text(
                            'Duration ${moment.durationLabel}',
                            'Czas trwania: ${moment.durationLabel}',
                          ),
                        ),
                        _MomentMeta(
                          icon: Icons.favorite_border_rounded,
                          label: '${moment.likeCount}',
                          semanticLabel: _localizedLikeCount(
                            moment.likeCount,
                            copy,
                          ),
                        ),
                        _MomentMeta(
                          icon: Icons.chat_bubble_outline_rounded,
                          label: '${moment.commentCount}',
                          semanticLabel: _localizedCommentCount(
                            moment.commentCount,
                            copy,
                          ),
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
                  label: copy.text(
                    'Open pinned Voice Moment details',
                    'Otwórz szczegóły przypiętego materiału Voice Moment',
                  ),
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
        return MomentExpiryBoundary(
          moment: moment,
          clock: widget.expiryClock,
          timerFactory: widget.expiryTimerFactory,
          onExpired: () => _handleExpired(moment),
          child: Padding(padding: widget.outerPadding, child: content),
        );
      },
    );
  }
}

class _PinnedMomentPlayButton extends StatefulWidget {
  const _PinnedMomentPlayButton({
    required this.moment,
    this.momentService,
    this.playerFactory,
    super.key,
  });

  final VoiceMoment moment;
  final MomentService? momentService;
  final AudioPlayer Function()? playerFactory;

  @override
  State<_PinnedMomentPlayButton> createState() =>
      _PinnedMomentPlayButtonState();
}

class _PinnedMomentPlayButtonState extends State<_PinnedMomentPlayButton> {
  late final AudioPlayer _player = (widget.playerFactory ?? AudioPlayer.new)();
  MomentService? _moments;
  late final StreamSubscription<void> _completeSubscription;
  bool _playing = false;
  bool _changingPlayback = false;

  @override
  void initState() {
    super.initState();
    // Keep the Firebase-backed resolver lazy: rendering a public pin must not
    // require Firebase/Storage until the listener actually presses Play.
    _moments = widget.momentService;
    _completeSubscription = _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  @override
  void didUpdateWidget(_PinnedMomentPlayButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.momentService != widget.momentService) {
      _moments = widget.momentService;
    }
    if (oldWidget.moment.id != widget.moment.id ||
        oldWidget.moment.mediaGeneration != widget.moment.mediaGeneration) {
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
    if (_changingPlayback || !widget.moment.hasMediaReference) return;
    setState(() => _changingPlayback = true);
    try {
      if (_playing) {
        await _player.pause();
      } else {
        final moments = _moments ??= MomentService();
        final uri = await moments.resolveMediaUri(momentId: widget.moment.id);
        await _player.play(UrlSource(uri.toString()));
      }
      if (mounted) setState(() => _playing = !_playing);
    } catch (_) {
      if (mounted) {
        setState(() => _playing = false);
        ScaffoldMessenger.maybeOf(context)
          ?..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context).text(
                  'This Voice Moment could not be played. Try again.',
                  'Nie udało się odtworzyć tego materiału Voice Moment. Spróbuj ponownie.',
                ),
              ),
            ),
          );
      }
    } finally {
      if (mounted) setState(() => _changingPlayback = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return Semantics(
      button: true,
      enabled: !_changingPlayback,
      label: _changingPlayback
          ? copy.text(
              'Preparing pinned Voice Moment',
              'Przygotowywanie przypiętego Voice Moment',
            )
          : _playing
          ? copy.text(
              'Pause pinned Voice Moment',
              'Wstrzymaj przypięty Voice Moment',
            )
          : copy.text(
              'Play pinned Voice Moment',
              'Odtwórz przypięty Voice Moment',
            ),
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
  const _MomentMeta({
    required this.icon,
    required this.label,
    required this.semanticLabel,
  });

  final IconData icon;
  final String label;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: Row(
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
      ),
    );
  }
}

String _localizedLikeCount(int count, AppLocalizations copy) {
  if (!copy.isPolish) return '$count likes';
  return '$count ${_polishPlural(count, 'polubienie', 'polubienia', 'polubień')}';
}

String _localizedCommentCount(int count, AppLocalizations copy) {
  if (!copy.isPolish) return '$count comments';
  return '$count ${_polishPlural(count, 'komentarz', 'komentarze', 'komentarzy')}';
}

String _polishPlural(int count, String one, String few, String many) {
  if (count == 1) return one;
  final tens = count % 100;
  final units = count % 10;
  if (tens < 12 || tens > 14) {
    if (units >= 2 && units <= 4) return few;
  }
  return many;
}
