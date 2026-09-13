import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';

Future<void> showDirectImageFullscreenViewer(
  BuildContext context, {
  required ImageProvider imageProvider,
  Listenable? ownershipChanges,
  bool Function()? ownershipIsCurrent,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => DirectImageFullscreenViewer(
        imageProvider: imageProvider,
        ownershipChanges: ownershipChanges,
        ownershipIsCurrent: ownershipIsCurrent,
      ),
    ),
  );
}

/// Full-screen viewer for an already-authorized direct-message image.
///
/// The caller passes the same [ImageProvider] used by the message preview. A
/// private `gs://` attachment therefore stays as authenticated in-memory bytes,
/// while a legacy HTTPS image reuses Flutter's decoded image cache.
class DirectImageFullscreenViewer extends StatefulWidget {
  const DirectImageFullscreenViewer({
    required this.imageProvider,
    this.ownershipChanges,
    this.ownershipIsCurrent,
    super.key,
  });

  final ImageProvider imageProvider;
  final Listenable? ownershipChanges;
  final bool Function()? ownershipIsCurrent;

  @override
  State<DirectImageFullscreenViewer> createState() =>
      _DirectImageFullscreenViewerState();
}

class _DirectImageFullscreenViewerState
    extends State<DirectImageFullscreenViewer> {
  int _attempt = 0;

  bool get _ownsImage => widget.ownershipIsCurrent?.call() ?? true;

  @override
  void initState() {
    super.initState();
    widget.ownershipChanges?.addListener(_ownershipChanged);
  }

  @override
  void didUpdateWidget(covariant DirectImageFullscreenViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ownershipChanges != widget.ownershipChanges) {
      oldWidget.ownershipChanges?.removeListener(_ownershipChanged);
      widget.ownershipChanges?.addListener(_ownershipChanged);
    }
  }

  @override
  void dispose() {
    widget.ownershipChanges?.removeListener(_ownershipChanged);
    super.dispose();
  }

  void _ownershipChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _retry() async {
    await widget.imageProvider.evict();
    if (mounted) setState(() => _attempt += 1);
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final title = copy.text('Full-screen photo', 'Zdjęcie na pełnym ekranie');
    final close = copy.text('Close photo', 'Zamknij zdjęcie');
    final ownsImage = _ownsImage;

    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: title,
      child: Scaffold(
        key: const ValueKey('direct-image-fullscreen-viewer'),
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (ownsImage)
              Semantics(
                image: true,
                label: title,
                child: InteractiveViewer(
                  key: const ValueKey('direct-image-fullscreen-pan-zoom'),
                  minScale: 1,
                  maxScale: 5,
                  clipBehavior: Clip.hardEdge,
                  child: Center(
                    child: Image(
                      key: ValueKey('direct-image-fullscreen-image-$_attempt'),
                      image: widget.imageProvider,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.high,
                      frameBuilder: (context, child, frame, synchronous) {
                        if (synchronous || frame != null) return child;
                        return Center(
                          child: Semantics(
                            label: copy.text(
                              'Loading full-screen photo',
                              'Wczytywanie zdjęcia na pełnym ekranie',
                            ),
                            child: CircularProgressIndicator(
                              color: palette.focus,
                            ),
                          ),
                        );
                      },
                      errorBuilder: (_, _, _) => _FullscreenMediaError(
                        icon: Icons.broken_image_outlined,
                        message: copy.text(
                          'Could not display this photo.',
                          'Nie udało się wyświetlić tego zdjęcia.',
                        ),
                        onRetry: _retry,
                      ),
                    ),
                  ),
                ),
              )
            else
              _FullscreenMediaError(
                icon: Icons.no_photography_outlined,
                message: copy.text(
                  'This photo is no longer available.',
                  'To zdjęcie nie jest już dostępne.',
                ),
              ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                minimum: const EdgeInsets.all(8),
                child: Align(
                  alignment: AlignmentDirectional.topStart,
                  child: _FullscreenCloseButton(
                    tooltip: close,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

typedef DirectVideoControllerLoader = Future<VideoPlayerController> Function();
typedef DirectVideoControllerPlayer =
    Future<void> Function(VideoPlayerController controller);
typedef DirectVideoControllerValidator =
    bool Function(VideoPlayerController controller);

Future<void> showDirectVideoFullscreenViewer(
  BuildContext context, {
  required DirectVideoControllerLoader controllerLoader,
  DirectVideoControllerPlayer? controllerPlayer,
  DirectVideoControllerValidator? controllerIsCurrent,
  Listenable? ownershipChanges,
  bool Function()? ownershipIsCurrent,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => DirectVideoFullscreenViewer(
        controllerLoader: controllerLoader,
        controllerPlayer: controllerPlayer,
        controllerIsCurrent: controllerIsCurrent,
        ownershipChanges: ownershipChanges,
        ownershipIsCurrent: ownershipIsCurrent,
      ),
    ),
  );
}

/// Full-screen controls around a controller owned by the message preview.
///
/// No storage reference or signed URL crosses this route boundary. Private
/// videos are first resolved through the authenticated byte loader and its
/// platform source preparer; this viewer only receives the resulting
/// controller and never disposes the caller-owned source.
class DirectVideoFullscreenViewer extends StatefulWidget {
  const DirectVideoFullscreenViewer({
    required this.controllerLoader,
    this.controllerPlayer,
    this.controllerIsCurrent,
    this.ownershipChanges,
    this.ownershipIsCurrent,
    super.key,
  });

  final DirectVideoControllerLoader controllerLoader;
  final DirectVideoControllerPlayer? controllerPlayer;
  final DirectVideoControllerValidator? controllerIsCurrent;
  final Listenable? ownershipChanges;
  final bool Function()? ownershipIsCurrent;

  @override
  State<DirectVideoFullscreenViewer> createState() =>
      _DirectVideoFullscreenViewerState();
}

class _DirectVideoFullscreenViewerState
    extends State<DirectVideoFullscreenViewer> {
  VideoPlayerController? _controller;
  Object? _error;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    widget.ownershipChanges?.addListener(_ownershipChanged);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant DirectVideoFullscreenViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ownershipChanges != widget.ownershipChanges) {
      oldWidget.ownershipChanges?.removeListener(_ownershipChanged);
      widget.ownershipChanges?.addListener(_ownershipChanged);
    }
  }

  void _ownershipChanged() {
    if (!mounted) return;
    if (widget.ownershipIsCurrent?.call() ?? true) return;
    _loadGeneration += 1;
    final controller = _controller;
    if (controller != null) {
      unawaited(_pauseControllerBestEffort(controller));
    }
    setState(() {
      _controller = null;
      _error = StateError('Video is no longer available');
    });
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    if (mounted) {
      setState(() {
        _controller = null;
        _error = null;
      });
    }
    try {
      final controller = await widget.controllerLoader();
      if (!_ownsLoad(generation, controller)) {
        unawaited(_pauseControllerBestEffort(controller));
        return;
      }
      setState(() => _controller = controller);
      if (controller.value.position >= controller.value.duration) {
        await controller.seekTo(Duration.zero);
      }
      if (!_ownsLoad(generation, controller)) {
        await _revokeController(generation, controller);
        return;
      }
      await _playController(generation, controller);
    } catch (error) {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _controller = null;
          _error = error;
        });
      }
    }
  }

  bool _ownsLoad(int generation, VideoPlayerController controller) =>
      mounted &&
      generation == _loadGeneration &&
      (widget.ownershipIsCurrent?.call() ?? true) &&
      (widget.controllerIsCurrent?.call(controller) ?? true);

  Future<void> _playController(
    int generation,
    VideoPlayerController controller,
  ) async {
    if (!_ownsLoad(generation, controller)) {
      unawaited(_pauseControllerBestEffort(controller));
      throw StateError('Video is no longer available');
    }
    try {
      await (widget.controllerPlayer?.call(controller) ?? controller.play());
    } finally {
      if (!_ownsLoad(generation, controller)) {
        unawaited(_pauseControllerBestEffort(controller));
      }
    }
    if (!_ownsLoad(generation, controller)) {
      throw StateError('Video is no longer available');
    }
  }

  Future<void> _toggleController(VideoPlayerValue value) async {
    final generation = _loadGeneration;
    final controller = _controller;
    if (controller == null) return;
    try {
      if (!_ownsLoad(generation, controller)) {
        await _revokeController(generation, controller);
        return;
      }
      if (value.isPlaying) {
        await _pauseControllerBestEffort(controller);
        return;
      }
      if (value.position >= value.duration) {
        await controller.seekTo(Duration.zero);
      }
      await _playController(generation, controller);
    } catch (error) {
      unawaited(_pauseControllerBestEffort(controller));
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _controller = null;
          _error = error;
        });
      }
    }
  }

  Future<void> _revokeController(
    int generation,
    VideoPlayerController controller,
  ) async {
    unawaited(_pauseControllerBestEffort(controller));
    if (!mounted || generation != _loadGeneration) return;
    setState(() {
      _controller = null;
      _error = StateError('Video is no longer available');
    });
  }

  Future<void> _pauseControllerBestEffort(
    VideoPlayerController controller,
  ) async {
    try {
      await controller.pause();
    } catch (_) {
      // The preview owns the controller and may already be disposing it.
    }
  }

  Future<void> _pause() async {
    final controller = _controller;
    if (controller != null) await _pauseControllerBestEffort(controller);
  }

  Future<void> _close() async {
    unawaited(_pause());
    if (mounted) await Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    widget.ownershipChanges?.removeListener(_ownershipChanged);
    _loadGeneration += 1;
    unawaited(_pause());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final controller = _controller;
    final title = copy.text('Full-screen video', 'Film na pełnym ekranie');
    final close = copy.text('Close video', 'Zamknij film');

    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: title,
      child: Scaffold(
        key: const ValueKey('direct-video-fullscreen-viewer'),
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (controller != null)
              _FullscreenVideoSurface(
                controller: controller,
                onToggle: _toggleController,
                isCurrent: () => _ownsLoad(_loadGeneration, controller),
              )
            else if (_error != null)
              _FullscreenMediaError(
                icon: Icons.videocam_off_outlined,
                message: copy.text(
                  'Could not play this video.',
                  'Nie udało się odtworzyć tego filmu.',
                ),
                onRetry: _load,
              )
            else
              Center(
                child: Semantics(
                  label: copy.text(
                    'Loading full-screen video',
                    'Wczytywanie filmu na pełnym ekranie',
                  ),
                  child: CircularProgressIndicator(color: palette.focus),
                ),
              ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                minimum: const EdgeInsets.all(8),
                child: Align(
                  alignment: AlignmentDirectional.topStart,
                  child: _FullscreenCloseButton(
                    tooltip: close,
                    onPressed: _close,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FullscreenVideoSurface extends StatelessWidget {
  const _FullscreenVideoSurface({
    required this.controller,
    required this.onToggle,
    required this.isCurrent,
  });

  final VideoPlayerController controller;
  final Future<void> Function(VideoPlayerValue value) onToggle;
  final bool Function() isCurrent;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final aspectRatio = value.aspectRatio.isFinite && value.aspectRatio > 0
            ? value.aspectRatio
            : 16 / 9;
        final toggleLabel = value.isPlaying
            ? copy.text('Pause video', 'Wstrzymaj film')
            : copy.text('Play video', 'Odtwórz film');
        return Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: aspectRatio,
                child: VideoPlayer(controller),
              ),
            ),
            if (value.isBuffering)
              Center(child: CircularProgressIndicator(color: palette.focus)),
            Center(
              child: Material(
                color: Colors.black.withValues(alpha: .48),
                shape: const CircleBorder(),
                child: IconButton(
                  key: const ValueKey('direct-video-fullscreen-toggle'),
                  tooltip: toggleLabel,
                  onPressed: isCurrent() ? () => onToggle(value) : null,
                  constraints: const BoxConstraints.tightFor(
                    width: 64,
                    height: 64,
                  ),
                  iconSize: 38,
                  color: Colors.white,
                  icon: Icon(
                    value.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 0,
              child: SafeArea(
                top: false,
                minimum: const EdgeInsets.only(bottom: 10),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .68),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        VideoProgressIndicator(
                          controller,
                          allowScrubbing: true,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          colors: VideoProgressColors(
                            playedColor: palette.focus,
                            bufferedColor: Colors.white38,
                            backgroundColor: Colors.white24,
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _formatVideoTime(value.position),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              _formatVideoTime(value.duration),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FullscreenCloseButton extends StatelessWidget {
  const _FullscreenCloseButton({
    required this.tooltip,
    required this.onPressed,
  });

  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: .62),
      shape: const CircleBorder(),
      child: IconButton(
        key: const ValueKey('direct-media-fullscreen-close'),
        tooltip: tooltip,
        onPressed: onPressed,
        constraints: const BoxConstraints.tightFor(width: 48, height: 48),
        color: Colors.white,
        icon: const Icon(Icons.close_rounded),
      ),
    );
  }
}

class _FullscreenMediaError extends StatelessWidget {
  const _FullscreenMediaError({
    required this.icon,
    required this.message,
    this.onRetry,
  });

  final IconData icon;
  final String message;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return Center(
      child: Semantics(
        liveRegion: true,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white70, size: 48),
              const SizedBox(height: 14),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: onRetry,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(copy.text('Try again', 'Spróbuj ponownie')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _formatVideoTime(Duration duration) {
  final totalSeconds = duration.inSeconds.clamp(0, 359999);
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  final clock =
      '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
  return hours == 0 ? clock : '$hours:$clock';
}
