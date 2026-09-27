import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_motion.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/creator/data/models/creator_pinned_post.dart';
import 'package:yovoice/features/creator/data/services/creator_pinned_post_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_expiry_scheduler.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_expiry_accessibility.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_expiry_boundary.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_disc.dart';
import 'package:yovoice/shared/widgets/cards/yo_card.dart';
import 'package:yovoice/shared/widgets/interactions/yo_press_feedback.dart';

// Slim redesign (phase 5): the card's three inline hexes (accent 0xFFB932FF,
// surface 0xFF17101F, muted 0xFFA99DB3) and its dark gradient became palette
// roles. Accent: `interactiveForeground`; muted: `textSecondary`.
//
// Refine-look §8.5: the card is an R2 block (`YoCard`: top-lit fill,
// hairline, radius 20, Pearl's lift) and its play control is the R14 voice
// bead (`YoGradientDisc`, 52 px, 48 compact) — the logo's glass, lit only
// while this Moment actually plays. The card itself takes no tint: the
// profile's colour block is the vibe sticker (the light budget).

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

  /// Test / preview seam for the player (the profile capture harness plays
  /// the pin through it). Production leaves it null.
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
        final palette = context.appPalette;
        final content = SizedBox(
          width: double.infinity,
          child: YoCard(
            padding: EdgeInsets.all(widget.compact ? 12 : 16),
            child: Row(
              children: [
                _PinnedMomentPlayButton(
                  key: _playButtonKey,
                  moment: moment,
                  momentService: widget.momentService,
                  playerFactory: widget.playerFactory,
                  compact: widget.compact,
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
                        style: AppTypography.overline.copyWith(
                          color: palette.interactiveForeground,
                          fontWeight: FontWeight.w700,
                          letterSpacing: .88,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        moment.caption.trim().isEmpty
                            ? copy.text('Voice Moment', 'Voice Moment')
                            : moment.caption,
                        // At ≈150 % text and up the caption gets room to
                        // wrap instead of losing its end to an ellipsis.
                        maxLines: widget.compact
                            ? 1
                            : MediaQuery.textScalerOf(context).scale(14) >= 21
                            ? 4
                            : 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
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
                        foregroundColor: palette.textSecondary,
                      ),
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ),
                ],
              ],
            ),
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
    this.compact = false,
    super.key,
  });

  final VoiceMoment moment;
  final MomentService? momentService;
  final AudioPlayer Function()? playerFactory;
  final bool compact;

  @override
  State<_PinnedMomentPlayButton> createState() =>
      _PinnedMomentPlayButtonState();
}

class _PinnedMomentPlayButtonState extends State<_PinnedMomentPlayButton>
    with SingleTickerProviderStateMixin {
  late final AudioPlayer _player = (widget.playerFactory ?? AudioPlayer.new)();
  MomentService? _moments;
  late final StreamSubscription<void> _completeSubscription;
  // The play ↔ pause morph (R14: AnimatedIcon, 200 ms easeInOut). It only
  // moves on a real play / pause, and snaps under Reduce Motion.
  late final AnimationController _glyph = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );
  late final CurvedAnimation _glyphCurve = CurvedAnimation(
    parent: _glyph,
    curve: Curves.easeInOut,
  );
  bool _playing = false;
  bool _changingPlayback = false;
  bool _failed = false;
  bool _hovered = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    // Keep the Firebase-backed resolver lazy: rendering a public pin must not
    // require Firebase/Storage until the listener actually presses Play.
    _moments = widget.momentService;
    _completeSubscription = _player.onPlayerComplete.listen((_) {
      if (mounted) _setPlaying(false);
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
      // A new pin starts clean: the previous Moment's failure (the refresh
      // glyph) never carries over to it.
      _failed = false;
      unawaited(stopPlayback());
    }
  }

  @override
  void dispose() {
    unawaited(_completeSubscription.cancel());
    unawaited(_player.dispose());
    _glyphCurve.dispose();
    _glyph.dispose();
    super.dispose();
  }

  /// Moves the playing state and the glyph with it: animated from a real
  /// play / pause, snapped when decorative motion is off.
  void _setPlaying(bool playing) {
    setState(() => _playing = playing);
    final target = playing ? 1.0 : 0.0;
    if (AppMotion.decorative(context)) {
      if (playing) {
        _glyph.forward();
      } else {
        _glyph.reverse();
      }
    } else {
      _glyph.value = target;
    }
  }

  Future<void> stopPlayback() async {
    try {
      await _player.stop();
    } finally {
      if (mounted) {
        setState(() => _changingPlayback = false);
        _setPlaying(false);
      }
    }
  }

  Future<void> _togglePlayback() async {
    if (_changingPlayback || !widget.moment.hasMediaReference) return;
    final starting = !_playing;
    setState(() {
      _changingPlayback = true;
      _failed = false;
    });
    if (starting && _hapticsPlatform) {
      unawaited(HapticFeedback.lightImpact());
    }
    try {
      if (_playing) {
        await _player.pause();
      } else {
        final moments = _moments ??= MomentService();
        final uri = await moments.resolveMediaUri(momentId: widget.moment.id);
        await _player.play(UrlSource(uri.toString()));
      }
      if (mounted) _setPlaying(!_playing);
    } catch (_) {
      if (mounted) {
        _setPlaying(false);
        setState(() => _failed = true);
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

  /// Haptics accompany a real play on the phones only.
  static bool get _hapticsPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final size = widget.compact ? 48.0 : 52.0;
    final available = widget.moment.hasMediaReference;
    final status = !available
        ? YoDiscStatus.disabled
        : _changingPlayback
        ? YoDiscStatus.busy
        : _failed
        ? YoDiscStatus.failed
        : YoDiscStatus.idle;
    final canToggle = available && !_changingPlayback;
    return Semantics(
      button: true,
      enabled: canToggle,
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
      onTap: canToggle ? _togglePlayback : null,
      excludeSemantics: true,
      child: YoPressFeedback(
        scale: YoPressFeedback.disc,
        enabled: canToggle,
        child: Material(
          type: MaterialType.transparency,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: canToggle ? _togglePlayback : null,
            customBorder: const CircleBorder(),
            // The bead carries hover (a stronger contact) and focus (its own
            // ring); no ink wash lands on the glass.
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            splashFactory: NoSplash.splashFactory,
            onHover: (value) {
              if (_hovered != value) setState(() => _hovered = value);
            },
            onFocusChange: (value) {
              if (_focused != value) setState(() => _focused = value);
            },
            child: YoGradientDisc(
              size: size,
              // The profile's one emitted light: only while this Moment
              // actually plays.
              emphasis: _playing ? YoDiscEmphasis.lit : YoDiscEmphasis.rest,
              gloss: true,
              status: status,
              hovered: _hovered,
              focused: _focused,
              nudgePlay: !_playing,
              glyph: AnimatedIcon(
                icon: AnimatedIcons.play_pause,
                progress: _glyphCurve,
              ),
            ),
          ),
        ),
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
    final muted = context.appPalette.textSecondary;
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: muted),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: muted,
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
