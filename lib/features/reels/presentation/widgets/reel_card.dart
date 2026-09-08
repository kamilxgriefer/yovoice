import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_motion.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/reels/data/models/reel.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_composition_canvas.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_engagement_bar.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_playback_coordinator.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';
import 'package:yovoice/shared/widgets/states/yo_error_state.dart';
import 'package:yovoice/shared/widgets/states/yo_loading_indicator.dart';

typedef ReelVideoBuilder =
    Widget Function(BuildContext context, Uri mediaUri, Reel reel);

/// Shadow under the Reel stage in each appearance: heavier in Dark where the
/// card floats over the moments-studio atmosphere, restrained plum in Pearl.
List<BoxShadow> reelCardShadow(BuildContext context) {
  final palette = context.appPalette;
  final dark = Theme.of(context).brightness == Brightness.dark;
  return <BoxShadow>[
    BoxShadow(
      color: palette.shadow.withValues(alpha: dark ? .45 : .16),
      blurRadius: 28,
      offset: const Offset(0, 12),
    ),
  ];
}

/// One real Reel page. Photos render in-app with the non-destructive crop,
/// filter and overlays. Video uses an injected native player when available;
/// otherwise the signed media URL opens in the platform player instead of
/// pretending a static thumbnail is playback.
///
/// The card IS the 9:16 media: its border, radius and shadow are drawn on the
/// inscribed frame, never on a wider box around it, so no gutter of ordinary
/// surface colour ever appears inside the card.
class ReelCard extends StatefulWidget {
  const ReelCard({
    required this.reel,
    required this.service,
    this.videoBuilder,
    this.audioPlaybackFactory,
    this.isActive = true,
    this.onDelete,
    this.onReport,
    this.onLike,
    this.onComments,
    this.onOpenAuthor,
    this.likePending = false,
    this.commentsOpen = false,
    this.showIdentity = true,
    this.borderRadius = 24,
    super.key,
  });

  final Reel reel;
  final ReelService service;
  final ReelVideoBuilder? videoBuilder;
  final ReelAudioPlaybackFactory? audioPlaybackFactory;
  final bool isActive;
  final Future<void> Function()? onDelete;
  final Future<void> Function()? onReport;

  /// Engagement is owned by the feed, not by the card: the card renders the
  /// counts it is given and reports intent upwards. That is what keeps a
  /// card, the wide context panel and an open thread showing one truth.
  ///
  /// Null means there is no viewer to act as. An unverified account keeps a
  /// live control that explains its gate rather than a dead button.
  final VoidCallback? onLike;
  final VoidCallback? onComments;

  /// What a tap on the author does. Production leaves it null and opens the
  /// shared profile preview; tests inject a seam so they never touch
  /// Firestore.
  final void Function(Reel reel)? onOpenAuthor;
  final bool likePending;

  /// True while the wide layout already shows this Reel's thread beside it.
  final bool commentsOpen;

  /// False when a docked context panel already carries the author and the
  /// caption, so the frame shows only the action rail and the sound chip.
  final bool showIdentity;
  final double borderRadius;

  @override
  State<ReelCard> createState() => _ReelCardState();
}

class _ReelCardState extends State<ReelCard> with WidgetsBindingObserver {
  late Future<Uri> _media = _loadMedia();
  late ReelPlaybackCoordinator _playback = _createPlayback();

  Future<Uri> _loadMedia() => widget.service.resolveMediaUri(widget.reel.id);

  ReelPlaybackCoordinator _createPlayback() => ReelPlaybackCoordinator(
    reel: widget.reel,
    resolveBackingAudioUri: () => widget.service.resolveMediaUri(
      widget.reel.id,
      asset: ReelAssetKind.backingAudio,
    ),
    audioPlaybackFactory: widget.audioPlaybackFactory,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _playback.addListener(_onPlaybackChanged);
    if (!widget.isActive) {
      unawaited(_playback.setActive(false).catchError((Object _) {}));
    }
  }

  @override
  void didUpdateWidget(covariant ReelCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sourceChanged =
        oldWidget.reel.id != widget.reel.id ||
        !identical(oldWidget.service, widget.service) ||
        !identical(oldWidget.audioPlaybackFactory, widget.audioPlaybackFactory);
    if (sourceChanged) {
      _playback.removeListener(_onPlaybackChanged);
      _playback.dispose();
      _playback = _createPlayback()..addListener(_onPlaybackChanged);
      _media = _loadMedia();
      if (!widget.isActive) {
        unawaited(_playback.setActive(false).catchError((Object _) {}));
      }
    } else if (oldWidget.isActive != widget.isActive) {
      unawaited(_playback.setActive(widget.isActive).catchError((Object _) {}));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _playback.removeListener(_onPlaybackChanged);
    _playback.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return;
    unawaited(_playback.pause().catchError((Object _) {}));
  }

  void _onPlaybackChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _togglePlayback() async {
    try {
      await _playback.toggle();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              AppLocalizations.of(context).text(
                'This audio is unavailable right now.',
                'Ten dźwięk jest teraz niedostępny.',
              ),
            ),
          ),
        );
    }
  }

  void _openAuthor() {
    final seam = widget.onOpenAuthor;
    if (seam != null) {
      seam(widget.reel);
      return;
    }
    unawaited(
      showProfilePreview(
        context,
        userId: widget.reel.authorId,
        displayName: widget.reel.authorName,
      ),
    );
  }

  Widget _buildMedia(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return FutureBuilder<Uri>(
      future: _media,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return YoErrorState(
            message: copy.text(
              'This Reel is unavailable right now.',
              'Ten Reel jest teraz niedostępny.',
            ),
            onRetry: () => setState(() => _media = _loadMedia()),
            compact: true,
          );
        }
        final uri = snapshot.data;
        if (uri == null) {
          return YoLoadingIndicator(
            message: copy.text('Loading Reel', 'Ładowanie Reela'),
          );
        }
        if (widget.reel.media.kind == ReelMediaKind.video &&
            widget.videoBuilder == null) {
          return _DefaultReelVideoPlayer(
            uri: uri,
            reel: widget.reel,
            playback: _playback,
            onToggle: _togglePlayback,
          );
        }
        final media = widget.reel.media.kind == ReelMediaKind.image
            ? _ReelPhoto(uri: uri)
            : widget.videoBuilder!(context, uri, widget.reel);
        return ReelCompositionFrame(
          composition: widget.reel.composition,
          media: media,
          mediaForeground: const _LegibilityScrim(),
          onOpenLink: (overlay) =>
              launchUrl(overlay.uri, mode: LaunchMode.externalApplication),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final radius = widget.borderRadius;
    return Semantics(
      container: true,
      label: copy.template(
        'Reel by {author}',
        'Reel użytkownika {author}',
        values: <String, Object>{'author': widget.reel.authorName},
      ),
      child: Center(
        child: AspectRatio(
          aspectRatio: 9 / 16,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final mediaHeight = constraints.maxHeight;
              return DecoratedBox(
                decoration: BoxDecoration(
                  // Only visible while the media loads or fails.
                  color: palette.surfaceSunken,
                  borderRadius: BorderRadius.circular(radius),
                  border: Border.all(color: palette.border),
                  boxShadow: reelCardShadow(context),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(radius - 1),
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      _buildMedia(context),
                      // The empty area of this layer takes no hits, so the
                      // playback surface underneath still receives them.
                      PositionedDirectional(
                        start: 0,
                        end: 0,
                        bottom: 0,
                        child: _OverlayFooter(
                          reel: widget.reel,
                          mediaHeight: mediaHeight,
                          showIdentity: widget.showIdentity,
                          audioPlaying: _playback.isPlaying,
                          audioLoading: _playback.isLoading,
                          audioEnabled: _playback.canToggle,
                          showAudioToggle: widget.reel.backingAudio != null,
                          onAudio: _togglePlayback,
                          onOpenAuthor: _openAuthor,
                          onDelete: widget.onDelete,
                          onReport: widget.onReport,
                          onLike: widget.onLike,
                          onComments: widget.onComments,
                          likePending: widget.likePending,
                          commentsOpen: widget.commentsOpen,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ReelPhoto extends StatelessWidget {
  const _ReelPhoto({required this.uri});

  final Uri uri;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      uri.toString(),
      fit: BoxFit.cover,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, _, _) => ColoredBox(
        color: context.appPalette.surfaceSunken,
        child: Icon(
          Icons.broken_image_outlined,
          size: 52,
          color: context.appPalette.textTertiary,
        ),
      ),
    );
  }
}

class _DefaultReelVideoPlayer extends StatefulWidget {
  const _DefaultReelVideoPlayer({
    required this.uri,
    required this.reel,
    required this.playback,
    required this.onToggle,
  });

  final Uri uri;
  final Reel reel;
  final ReelPlaybackCoordinator playback;
  final Future<void> Function() onToggle;

  @override
  State<_DefaultReelVideoPlayer> createState() =>
      _DefaultReelVideoPlayerState();
}

class _DefaultReelVideoPlayerState extends State<_DefaultReelVideoPlayer> {
  VideoPlayerController? _controller;
  _VideoPlayerPlayback? _playbackDriver;
  ReelPlaybackCoordinator? _attachedPlayback;
  Object? _error;
  bool _lastPlaying = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void didUpdateWidget(covariant _DefaultReelVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uri != widget.uri ||
        oldWidget.reel.id != widget.reel.id ||
        !identical(oldWidget.playback, widget.playback)) {
      _disposeController();
      _initialize();
    }
  }

  Future<void> _initialize() async {
    final controller = VideoPlayerController.networkUrl(widget.uri);
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setLooping(false);
      await controller.setVolume(
        widget.reel.composition.originalAudioVolume / 100,
      );
      await controller.seekTo(
        Duration(milliseconds: widget.reel.composition.trimStartMs),
      );
      final driver = _VideoPlayerPlayback(controller);
      _playbackDriver = driver;
      _attachedPlayback = widget.playback;
      _lastPlaying = controller.value.isPlaying;
      controller.addListener(_handlePlayback);
      await widget.playback.attachVideo(driver);
      if (!mounted || !identical(_controller, controller)) return;
      if (mounted) setState(() => _error = null);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  void _handlePlayback() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.hasError) {
      unawaited(widget.playback.pause().catchError((Object _) {}));
      if (_error == null && mounted) {
        setState(
          () => _error = StateError(
            controller.value.errorDescription ?? 'Video playback failed.',
          ),
        );
      }
      return;
    }
    unawaited(widget.playback.synchronizeVideoTick().catchError((Object _) {}));
    final playing = controller.value.isPlaying;
    if (playing != _lastPlaying && mounted) {
      _lastPlaying = playing;
      setState(() {});
    }
  }

  void _disposeController() {
    final controller = _controller;
    final driver = _playbackDriver;
    final attachedPlayback = _attachedPlayback;
    _controller = null;
    _playbackDriver = null;
    _attachedPlayback = null;
    if (driver != null) attachedPlayback?.detachVideo(driver);
    if (controller != null) {
      controller.removeListener(_handlePlayback);
      unawaited(controller.dispose());
    }
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final controller = _controller;
    if (_error != null) {
      return ColoredBox(
        color: palette.surfaceSunken,
        child: Center(
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: () {
                  _disposeController();
                  setState(() => _error = null);
                  _initialize();
                },
                icon: const Icon(Icons.refresh_rounded),
                label: Text(copy.text('Retry', 'Spróbuj ponownie')),
              ),
              TextButton.icon(
                onPressed: () =>
                    launchUrl(widget.uri, mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new_rounded),
                label: Text(copy.text('Open video', 'Otwórz film')),
              ),
            ],
          ),
        ),
      );
    }
    if (controller == null || !controller.value.isInitialized) {
      return YoLoadingIndicator(
        message: copy.text('Loading video', 'Ładowanie filmu'),
      );
    }
    return ReelPlaybackSurface(
      isPlaying: controller.value.isPlaying,
      onToggle: widget.onToggle,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ReelCompositionFrame(
            composition: widget.reel.composition,
            media: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: controller.value.size.width,
                height: controller.value.size.height,
                child: VideoPlayer(controller),
              ),
            ),
            mediaForeground: const _LegibilityScrim(),
            onOpenLink: (overlay) =>
                launchUrl(overlay.uri, mode: LaunchMode.externalApplication),
          ),
          Center(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: controller.value.isPlaying ? 0 : 1,
                duration: AppMotion.resolve(context, AppMotion.quick),
                child: const Icon(
                  Icons.play_circle_fill_rounded,
                  size: 72,
                  color: Colors.white,
                  shadows: <Shadow>[
                    Shadow(color: Color(0x73000000), blurRadius: 12),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Accessible full-canvas playback action shared by the real decoder and its
/// deterministic widget coverage. [AccessibleTapRegion] supplies pointer,
/// assistive-technology, Enter and Space activation plus a visible focus ring.
class ReelPlaybackSurface extends StatelessWidget {
  const ReelPlaybackSurface({
    required this.isPlaying,
    required this.onToggle,
    required this.child,
    super.key,
  });

  final bool isPlaying;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final label = isPlaying
        ? copy.text('Pause video', 'Wstrzymaj film')
        : copy.text('Play video', 'Odtwórz film');
    return AccessibleTapRegion(
      key: const ValueKey('reel-video-playback-surface'),
      onTap: onToggle,
      semanticLabel: label,
      tooltip: label,
      borderRadius: 0,
      focusContrastColor: Colors.black,
      child: child,
    );
  }
}

class _VideoPlayerPlayback implements ReelVideoPlayback {
  const _VideoPlayerPlayback(this.controller);

  final VideoPlayerController controller;

  @override
  bool get isPlaying => controller.value.isPlaying;

  @override
  Duration get position => controller.value.position;

  @override
  Future<void> pause() => controller.pause();

  @override
  Future<void> play() => controller.play();

  @override
  Future<void> seek(Duration position) => controller.seekTo(position);

  @override
  Future<void> setVolume(double volume) => controller.setVolume(volume);
}

/// A light base wash inside the composition space: it settles the top edge
/// and the centre play glyph. The text no longer relies on it — the footer
/// scrim in card space carries every line.
class _LegibilityScrim extends StatelessWidget {
  const _LegibilityScrim();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Color(0x1F000000),
              Color(0x00000000),
              Color(0x00000000),
              Color(0x59000000),
            ],
            stops: <double>[0, .35, .60, 1],
          ),
        ),
      ),
    );
  }
}

/// Identity column bottom-start, action rail bottom-end, one footer scrim
/// under both: a ~100 px ramp and then flat 84 % black beneath every line, so
/// white text clears 4.5:1 even on a pure-white frame.
class _OverlayFooter extends StatelessWidget {
  const _OverlayFooter({
    required this.reel,
    required this.mediaHeight,
    required this.showIdentity,
    required this.audioPlaying,
    required this.audioLoading,
    required this.audioEnabled,
    required this.showAudioToggle,
    required this.likePending,
    required this.commentsOpen,
    required this.onOpenAuthor,
    this.onAudio,
    this.onDelete,
    this.onReport,
    this.onLike,
    this.onComments,
  });

  final Reel reel;
  final double mediaHeight;
  final bool showIdentity;
  final bool audioPlaying;
  final bool audioLoading;
  final bool audioEnabled;
  final bool showAudioToggle;
  final bool likePending;
  final bool commentsOpen;
  final VoidCallback onOpenAuthor;
  final VoidCallback? onAudio;
  final Future<void> Function()? onDelete;
  final Future<void> Function()? onReport;
  final VoidCallback? onLike;
  final VoidCallback? onComments;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    // Short media (a phone with the header and the dock on screen) folds the
    // rail into a row and trims the caption instead of covering the frame.
    final compact = mediaHeight < 400;
    // Smaller still — a 320x568 window with the shell's dock leaves a frame
    // roughly 110 x 196, and three 48 px controls already fill it. The
    // identity column is dropped here rather than laid out and then clipped
    // off the top of the card: a half-cut name is worse than none, and the
    // author is still announced by the card's own semantics. This is a
    // graceful floor, not a target — a viewport this short really wants a
    // collapsed header or a dedicated immersive route.
    final micro = mediaHeight < 320;
    final captionLines = compact
        ? 1
        : mediaHeight < 560
        ? 2
        : 3;
    final showSound =
        showAudioToggle || reel.composition.audioAttribution.isNotEmpty;

    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (showIdentity && !micro) ...<Widget>[
          ReelAuthorRow(reel: reel, showAvatar: !compact, onTap: onOpenAuthor),
          if (reel.composition.caption.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            IgnorePointer(
              child: Text(
                reel.composition.caption,
                maxLines: captionLines,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  height: 1.35,
                  shadows: reelOverlayTextShadows,
                ),
              ),
            ),
          ],
        ],
        if (showSound && !micro) ...<Widget>[
          if (showIdentity) const SizedBox(height: 8),
          _SoundChip(
            reel: reel,
            showToggle: showAudioToggle,
            audioPlaying: audioPlaying,
            audioLoading: audioLoading,
            audioEnabled: audioEnabled,
            onAudio: onAudio,
          ),
        ],
      ],
    );

    final moderation = onDelete != null
        ? ReelOverlayPlateButton(
            icon: Icons.delete_outline_rounded,
            semanticLabel: copy.text('Delete Reel', 'Usuń Reel'),
            glyphColor: AppColors.error,
            onTap: onDelete,
          )
        : onReport != null
        ? ReelOverlayPlateButton(
            icon: Icons.flag_outlined,
            semanticLabel: copy.text('Report Reel', 'Zgłoś Reel'),
            onTap: onReport,
          )
        : null;
    final rail = ReelEngagementBar(
      likeCount: reel.likeCount,
      commentCount: reel.commentCount,
      liked: reel.callerLiked,
      likePending: likePending,
      commentsOpen: commentsOpen,
      railAxis: compact ? Axis.horizontal : Axis.vertical,
      railTrailing: moderation,
      onLike: onLike,
      onComments: onComments,
    );

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0x00000000), Color(0xD6000000)],
          stops: <double>[0, .40],
        ),
      ),
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(
          16,
          micro
              ? 8
              : compact
              ? 56
              : 96,
          12,
          16,
        ),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  identity,
                  const SizedBox(height: 8),
                  Align(alignment: AlignmentDirectional.centerEnd, child: rail),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(child: identity),
                  const SizedBox(width: 16),
                  rail,
                ],
              ),
      ),
    );
  }
}

/// Where a [ReelAuthorRow] is drawn, which decides its foreground.
///
/// [overlay] sits on artwork of unknown luminance: fixed white with the
/// shared text shadows. [panel] sits on an ordinary app surface in the wide
/// layout and uses semantic palette roles.
enum ReelAuthorRowVariant { overlay, panel }

/// The author of a Reel, as one tappable identity control.
///
/// One widget serves the card overlay and the wide context panel so the two
/// can never disagree about who published a Reel or what tapping the name
/// does. The avatar resolves through the existing viewer-authorised profile
/// media service — the Reel wire carries no photo URL and none is invented,
/// so the initial is the honest fallback.
class ReelAuthorRow extends StatelessWidget {
  const ReelAuthorRow({
    required this.reel,
    required this.onTap,
    this.showAvatar = true,
    this.variant = ReelAuthorRowVariant.overlay,
    this.secondaryLine,
    super.key,
  });

  final Reel reel;
  final VoidCallback onTap;
  final bool showAvatar;
  final ReelAuthorRowVariant variant;

  /// Panel only: a second line under the name, such as the publish time.
  final String? secondaryLine;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final overlay = variant == ReelAuthorRowVariant.overlay;
    final radius = overlay ? 16.0 : 20.0;
    final name = Text(
      reel.authorName,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: overlay ? Colors.white : palette.textPrimary,
        fontSize: overlay ? 16 : 18,
        fontWeight: FontWeight.w800,
        height: 1.2,
        shadows: overlay ? reelOverlayTextShadows : null,
      ),
    );
    final secondary = secondaryLine;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: AccessibleTapRegion(
        onTap: onTap,
        semanticLabel: copy.template(
          'Open profile for {author}',
          'Otwórz profil: {author}',
          values: <String, Object>{'author': reel.authorName},
        ),
        borderRadius: overlay ? 999 : 16,
        minimumSize: const Size(44, 44),
        focusContrastColor: overlay ? Colors.black : null,
        child: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(0, 4, overlay ? 10 : 8, 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (showAvatar) ...<Widget>[
                ExcludeSemantics(
                  child: UserAvatar(
                    radius: radius,
                    userId: reel.authorId,
                    displayName: reel.authorName,
                  ),
                ),
                SizedBox(width: overlay ? 8 : 12),
              ],
              Flexible(
                child: secondary == null || secondary.isEmpty
                    ? name
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          name,
                          const SizedBox(height: 2),
                          Text(
                            secondary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.textTertiary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The audio line of the frame: attribution (or the generic name) on a 72 %
/// plate, with the playback toggle leading it when the Reel has backing audio.
///
/// The toggle stays an [IconButton] — its key, tooltips and 44 px target are
/// the contract the playback coordinator coverage holds it to.
class _SoundChip extends StatelessWidget {
  const _SoundChip({
    required this.reel,
    required this.showToggle,
    required this.audioPlaying,
    required this.audioLoading,
    required this.audioEnabled,
    this.onAudio,
  });

  final Reel reel;
  final bool showToggle;
  final bool audioPlaying;
  final bool audioLoading;
  final bool audioEnabled;
  final VoidCallback? onAudio;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final attribution = reel.composition.audioAttribution;
    final text = attribution.isNotEmpty
        ? attribution
        : copy.text('Backing audio', 'Podkład');
    final toggleLabel = reel.media.kind == ReelMediaKind.video
        ? audioPlaying
              ? copy.text('Pause video', 'Wstrzymaj film')
              : copy.text('Play video', 'Odtwórz film')
        : audioPlaying
        ? copy.text('Pause backing audio', 'Wstrzymaj podkład')
        : copy.text('Play backing audio', 'Odtwórz podkład');
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: SizedBox(
        height: 44,
        child: Stack(
          children: <Widget>[
            // The visible pill is 32 tall; the toggle keeps a 44 px target
            // that overhangs it by 6 px above and below.
            const PositionedDirectional(
              start: 0,
              end: 0,
              top: 6,
              bottom: 6,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: reelOverlayPlateColor,
                    borderRadius: BorderRadius.all(Radius.circular(999)),
                  ),
                ),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (showToggle)
                  IconButton(
                    key: const ValueKey('reel-playback-toggle'),
                    tooltip: toggleLabel,
                    onPressed: audioLoading || !audioEnabled ? null : onAudio,
                    iconSize: 20,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 44,
                      height: 44,
                    ),
                    style: IconButton.styleFrom(
                      foregroundColor: Colors.white,
                      disabledForegroundColor: Colors.white.withValues(
                        alpha: .5,
                      ),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: audioLoading
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            audioPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                          ),
                  )
                else
                  const Padding(
                    padding: EdgeInsetsDirectional.only(start: 10, end: 6),
                    child: Icon(
                      Icons.music_note_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                Flexible(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(end: 10),
                    child: IgnorePointer(
                      child: Text(
                        text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
