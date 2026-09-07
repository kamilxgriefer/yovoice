import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/reels/data/models/reel.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_composition_canvas.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_engagement_bar.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_playback_coordinator.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';
import 'package:yovoice/shared/widgets/states/yo_error_state.dart';
import 'package:yovoice/shared/widgets/states/yo_loading_indicator.dart';

typedef ReelVideoBuilder =
    Widget Function(BuildContext context, Uri mediaUri, Reel reel);

/// One real Reel page. Photos render in-app with the non-destructive crop,
/// filter and overlays. Video uses an injected native player when available;
/// otherwise the signed media URL opens in the platform player instead of
/// pretending a static thumbnail is playback.
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
    this.likePending = false,
    this.commentsOpen = false,
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
  final bool likePending;

  /// True while the wide layout already shows this Reel's thread beside it.
  final bool commentsOpen;

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

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    return Semantics(
      container: true,
      label: copy.template(
        'Reel by {author}',
        'Reel użytkownika {author}',
        values: <String, Object>{'author': widget.reel.authorName},
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.surfaceSunken,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: palette.border),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(27),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Center(
                child: AspectRatio(
                  aspectRatio: 9 / 16,
                  child: FutureBuilder<Uri>(
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
                      final media =
                          widget.reel.media.kind == ReelMediaKind.image
                          ? _ReelPhoto(uri: uri)
                          : widget.videoBuilder!(context, uri, widget.reel);
                      return ReelCompositionFrame(
                        composition: widget.reel.composition,
                        media: media,
                        mediaForeground: const _LegibilityScrim(),
                        onOpenLink: (overlay) => launchUrl(
                          overlay.uri,
                          mode: LaunchMode.externalApplication,
                        ),
                      );
                    },
                  ),
                ),
              ),
              // The footer is aligned to the artwork, not to the card. A card
              // wider than its inscribed 9:16 frame leaves margins painted in
              // the ordinary surface colour — light in Pearl — and white
              // overlay text laid across those margins is unreadable. The
              // empty area of this stack takes no hits, so the playback
              // surface underneath still receives them.
              Center(
                child: AspectRatio(
                  aspectRatio: 9 / 16,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      PositionedDirectional(
                        start: 18,
                        end: 18,
                        bottom: 18,
                        child: _Footer(
                          reel: widget.reel,
                          audioPlaying: _playback.isPlaying,
                          audioLoading: _playback.isLoading,
                          audioEnabled: _playback.canToggle,
                          showAudio: widget.reel.backingAudio != null,
                          onAudio: _togglePlayback,
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
              ),
            ],
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
          if (!controller.value.isPlaying)
            const Center(
              child: Icon(
                Icons.play_circle_fill_rounded,
                size: 72,
                color: Colors.white,
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
              Color(0x24000000),
              Color(0x08000000),
              Color(0xB8000000),
            ],
            stops: <double>[0, .55, 1],
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.reel,
    required this.audioPlaying,
    required this.audioLoading,
    required this.audioEnabled,
    required this.showAudio,
    required this.likePending,
    required this.commentsOpen,
    this.onAudio,
    this.onDelete,
    this.onReport,
    this.onLike,
    this.onComments,
  });

  final Reel reel;
  final bool audioPlaying;
  final bool audioLoading;
  final bool audioEnabled;
  final bool showAudio;
  final bool likePending;
  final bool commentsOpen;
  final VoidCallback? onAudio;
  final Future<void> Function()? onDelete;
  final Future<void> Function()? onReport;
  final VoidCallback? onLike;
  final VoidCallback? onComments;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    // Identity and caption first, then the actions that respond to them: the
    // reading order a screen reader follows is the order that makes sense.
    // The bar is a Wrap, so a 320 px card folds it to two lines instead of
    // overflowing, and text scaling has somewhere to go.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _identityRow(copy),
        const SizedBox(height: 4),
        ReelEngagementBar(
          likeCount: reel.likeCount,
          commentCount: reel.commentCount,
          liked: reel.callerLiked,
          likePending: likePending,
          commentsOpen: commentsOpen,
          onLike: onLike,
          onComments: onComments,
        ),
      ],
    );
  }

  Widget _identityRow(AppLocalizations copy) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                reel.authorName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (reel.composition.caption.isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  reel.composition.caption,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
              ],
              if (reel.composition.audioAttribution.isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  reel.composition.audioAttribution,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
        if (showAudio)
          IconButton.filledTonal(
            key: const ValueKey('reel-playback-toggle'),
            tooltip: reel.media.kind == ReelMediaKind.video
                ? audioPlaying
                      ? copy.text('Pause video', 'Wstrzymaj film')
                      : copy.text('Play video', 'Odtwórz film')
                : audioPlaying
                ? copy.text('Pause backing audio', 'Wstrzymaj podkład')
                : copy.text('Play backing audio', 'Odtwórz podkład'),
            onPressed: audioLoading || !audioEnabled ? null : onAudio,
            icon: audioLoading
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    audioPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
          ),
        if (onDelete != null)
          IconButton(
            tooltip: copy.text('Delete Reel', 'Usuń Reel'),
            color: AppColors.error,
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        if (onReport != null)
          IconButton(
            tooltip: copy.text('Report Reel', 'Zgłoś Reel'),
            color: Colors.white,
            onPressed: onReport,
            icon: const Icon(Icons.flag_outlined),
          ),
      ],
    );
  }
}
