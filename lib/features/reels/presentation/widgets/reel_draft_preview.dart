import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/data/services/reel_upload.dart';
import 'reel_composition_canvas.dart';
import 'reel_local_video_controller.dart';
import 'reel_playback_coordinator.dart';

/// Builds the decoder for a picked local file. The default is the platform
/// controller; tests supply a deterministic one without a native player.
typedef ReelVideoControllerFactory =
    VideoPlayerController Function(String sourcePath);

/// Maps pointer movement to the existing stored crop recipe. No new wire
/// interpretation: at 1× there are no spare zoom pixels to pan into.
ReelCropTransform reelCropFromGesture({
  required ReelCropTransform initial,
  required Size viewport,
  required Offset initialFocalPoint,
  required Offset focalPoint,
  required double gestureScale,
}) {
  final scale = (initial.scale * gestureScale).clamp(1.0, 8.0);
  final ratio = scale / initial.scale;
  final center = viewport.center(Offset.zero);
  final originalPan = reelCropTranslation(viewport, initial);
  final pan =
      (originalPan - (initialFocalPoint - center)) * ratio +
      (focalPoint - center);
  final maxX = viewport.width * (scale - 1) / 2;
  final maxY = viewport.height * (scale - 1) / 2;
  return ReelCropTransform(
    scale: scale,
    offsetX: maxX <= 0 ? 0 : (pan.dx / maxX).clamp(-1.0, 1.0),
    offsetY: maxY <= 0 ? 0 : (pan.dy / maxY).clamp(-1.0, 1.0),
  );
}

/// Actual local media and the same authoritative timeline as the published
/// feed. Local bytes never become pretend published records or remote grants.
class ReelDraftPreview extends StatefulWidget {
  const ReelDraftPreview({
    required this.media,
    required this.composition,
    this.backingAudio,
    this.audioPlayerFactory,
    this.cropEnabled = false,
    this.onTextOverlayChanged,
    this.onLinkOverlayChanged,
    this.active = true,
    this.onCropChanged,
    this.onPlayingChanged,
    this.onPositionChanged,
    this.videoControllerFactory,
    super.key,
  });

  final ReelUploadPayload media;
  final ReelUploadPayload? backingAudio;
  final ReelComposition composition;
  final AudioPlayer Function()? audioPlayerFactory;
  final bool cropEnabled;

  /// When set, text/link pills on the preview are draggable (text also
  /// pinchable). The composer passes these only while the Text tool is
  /// active, so crop and overlay gestures never compete for a pointer.
  final ValueChanged<ReelTextOverlay>? onTextOverlayChanged;
  final ValueChanged<ReelLinkOverlay>? onLinkOverlayChanged;
  final bool active;
  final ValueChanged<ReelCropTransform>? onCropChanged;
  final ValueChanged<bool>? onPlayingChanged;

  /// Current decoder position, reported on every tick and after every seek so
  /// a trimmer can draw its playhead without rebuilding the composer.
  final ValueChanged<Duration>? onPositionChanged;

  /// Optional test/platform override for the local video decoder.
  final ReelVideoControllerFactory? videoControllerFactory;

  @override
  State<ReelDraftPreview> createState() => ReelDraftPreviewState();
}

class ReelDraftPreviewState extends State<ReelDraftPreview>
    with WidgetsBindingObserver {
  VideoPlayerController? _video;
  String? _videoSourcePath;
  Future<void> _preparations = Future<void>.value();
  ReelPlaybackCoordinator? _playback;
  ReelCropTransform? _gestureCrop;
  Offset _gestureFocal = Offset.zero;
  Offset? _pointerDown;
  int _epoch = 0;
  bool _preparing = true;
  bool _quiet = false;
  bool _failed = false;
  bool _lastPlaying = false;
  bool _trimEditing = false;
  bool _trimDirty = false;
  bool _resumeAfterTrim = false;
  int _trimEditToken = 0;
  Duration? _scrubTarget;
  bool _scrubbing = false;
  Duration? _lastPosition;
  int _preparationCount = 0;

  bool get isPlaying => _playback?.isPlaying ?? false;

  /// Whether a trim handle is currently held.
  bool get isTrimEditing => _trimEditing;

  /// The live coordinator; tests use it to prove a scrub keeps the timeline.
  @visibleForTesting
  ReelPlaybackCoordinator? get debugPlayback => _playback;

  /// How many times the timeline was (re)built since the preview mounted.
  @visibleForTesting
  int get debugPreparations => _preparationCount;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_prepare());
  }

  @override
  void didUpdateWidget(covariant ReelDraftPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sourceChanged = !identical(oldWidget.media.bytes, widget.media.bytes);
    final old = oldWidget.composition;
    final next = widget.composition;
    final trimChanged =
        old.trimStartMs != next.trimStartMs || old.trimEndMs != next.trimEndMs;
    if (sourceChanged ||
        !identical(oldWidget.backingAudio?.bytes, widget.backingAudio?.bytes) ||
        old.audioTrimStartMs != next.audioTrimStartMs ||
        old.originalAudioVolume != next.originalAudioVolume ||
        old.backingAudioVolume != next.backingAudioVolume) {
      unawaited(_prepare());
    } else if (trimChanged) {
      // A trim-only change keeps the decoder and, while a handle is held,
      // the timeline too: the drag scrubs frames and the release rebuilds
      // the loop once. Slider and keyboard edits rebuild quietly right away.
      if (_trimEditing) {
        _trimDirty = true;
      } else {
        unawaited(_prepare(trimOnly: true));
      }
    } else if (oldWidget.active != widget.active) {
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      unawaited(
        _playback
            ?.setActive(
              widget.active &&
                  (lifecycle == null || lifecycle == AppLifecycleState.resumed),
            )
            .catchError((Object _) {}),
      );
    }
  }

  bool _current(int epoch) => mounted && epoch == _epoch;

  Future<void> _prepare({bool trimOnly = false}) {
    final epoch = ++_epoch;
    _preparationCount += 1;
    _preparing = true;
    _failed = false;
    _trimDirty = false;
    // A trim-only rebuild on an already decoded clip is a coordinator swap,
    // not a decode, so it neither blanks the frame nor shows the spinner.
    _quiet =
        trimOnly &&
        widget.media.mediaKind == ReelMediaKind.video &&
        _videoSourcePath == widget.media.sourcePath &&
        (_video?.value.isInitialized ?? false);
    if (_lastPlaying) {
      _lastPlaying = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_current(epoch)) widget.onPlayingChanged?.call(false);
      });
    }
    // Source decoding and disposal are serialized. A rapid slider/source
    // change invalidates older work without opening competing native players.
    _preparations = _preparations
        .catchError((Object _) {})
        .then((_) => _prepareNow(epoch, keepFrame: trimOnly));
    return _preparations;
  }

  Future<void> _prepareNow(int epoch, {required bool keepFrame}) async {
    if (!_current(epoch)) return;
    final oldPlayback = _playback;
    _playback = null;
    oldPlayback?.removeListener(_onPlayback);
    if (oldPlayback != null) {
      try {
        // Deactivation rewinds to the old start; after a trim the frame the
        // user just placed must stay put, so only pause before replacing.
        if (keepFrame) {
          await oldPlayback.pause();
        } else {
          await oldPlayback.setActive(false);
        }
      } catch (_) {}
      oldPlayback.dispose();
    }
    if (!_current(epoch)) return;
    if (widget.media.mediaKind != ReelMediaKind.video ||
        _videoSourcePath != widget.media.sourcePath ||
        !(_video?.value.isInitialized ?? false)) {
      final previous = _video;
      _video = null;
      _videoSourcePath = null;
      previous?.removeListener(_onVideoTick);
      if (previous != null) await previous.dispose();
      if (!_current(epoch)) return;
    }
    try {
      if (widget.media.mediaKind == ReelMediaKind.video && _video == null) {
        final path = widget.media.sourcePath;
        if (path == null || path.isEmpty) throw StateError('No local media');
        final video =
            widget.videoControllerFactory?.call(path) ??
            createReelLocalVideoController(path);
        _video = video;
        _videoSourcePath = path;
        await video.initialize().timeout(const Duration(seconds: 15));
        if (!_current(epoch)) return;
        await video.setLooping(false);
        video.addListener(_onVideoTick);
      }
      if (!_current(epoch)) return;
      final audio = widget.backingAudio;
      final playback = ReelPlaybackCoordinator.draft(
        mediaKind: widget.media.mediaKind,
        composition: widget.composition,
        backingAudioDurationMs: audio?.durationMs,
        // This URI is a local adapter identifier, never a network destination.
        resolveBackingAudioUri: () async =>
            Uri(scheme: 'memory', path: 'selected-audio'),
        audioPlaybackFactory: () => _LocalDraftAudio(
          payload: audio!,
          player: widget.audioPlayerFactory?.call() ?? AudioPlayer(),
        ),
      );
      _playback = playback..addListener(_onPlayback);
      final video = _video;
      if (video != null) await playback.attachVideo(_LocalDraftVideo(video));
      final foreground = WidgetsBinding.instance.lifecycleState;
      await playback.setActive(
        widget.active &&
            (foreground == null || foreground == AppLifecycleState.resumed),
      );
      if (_current(epoch)) {
        setState(() {
          _preparing = false;
          _quiet = false;
        });
      }
    } catch (_) {
      if (_current(epoch)) {
        setState(() {
          _failed = true;
          _preparing = false;
          _quiet = false;
        });
      }
    }
  }

  void _onVideoTick() {
    final video = _video;
    if (video != null) {
      final position = video.value.position;
      if (position != _lastPosition) {
        _lastPosition = position;
        widget.onPositionChanged?.call(position);
      }
    }
    final playback = _playback;
    if (playback == null) return;
    unawaited(
      playback.synchronizeVideoTick().catchError((Object _) {
        if (mounted && identical(playback, _playback)) {
          setState(() => _failed = true);
        }
      }),
    );
  }

  void _onPlayback() {
    if (!mounted) return;
    setState(() {});
    final playing = isPlaying;
    if (_lastPlaying == playing) return;
    _lastPlaying = playing;
    final epoch = _epoch;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_current(epoch)) widget.onPlayingChanged?.call(playing);
    });
  }

  Future<void> pause() async {
    // The coordinator invalidates an in-flight play synchronously. Navigation
    // must not wait for a native decoder which is still opening local bytes.
    unawaited(_playback?.pause(reset: true).catchError((Object _) {}));
  }

  /// Holds the timeline while a trim handle moves: playback pauses in place
  /// (no rewind) and trim-only recipe updates stop rebuilding the loop until
  /// [endTrimEdit]. Safe to call repeatedly.
  void beginTrimEdit() {
    _trimEditToken += 1;
    if (_trimEditing) return;
    _trimEditing = true;
    _resumeAfterTrim = isPlaying;
    unawaited(_playback?.pause().catchError((Object _) {}));
  }

  /// Shows the frame at [position] on the existing decoder. Seeks coalesce:
  /// while one is in flight the newest target wins, so a fast drag never
  /// queues a backlog of native seeks.
  Future<void> scrub(Duration position) async {
    _scrubTarget = position;
    if (_scrubbing) return;
    _scrubbing = true;
    try {
      while (mounted) {
        final target = _scrubTarget;
        if (target == null) break;
        _scrubTarget = null;
        final video = _video;
        if (video == null || !video.value.isInitialized) break;
        final playback = _playback;
        if (playback != null && playback.isPlaying) {
          await playback.pause().catchError((Object _) {});
        }
        await video.seekTo(target);
      }
    } catch (_) {
      // A failed seek keeps the last good frame; the recipe still updates.
    } finally {
      _scrubbing = false;
    }
  }

  /// Releases the hold from [beginTrimEdit]. The composer's pending rebuild
  /// is allowed to land first so the final range is rebuilt exactly once;
  /// playback then resumes inside the new range if it was playing before.
  Future<void> endTrimEdit() async {
    if (!_trimEditing) return;
    final token = _trimEditToken;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || token != _trimEditToken) return;
    _trimEditing = false;
    final resume = _resumeAfterTrim;
    _resumeAfterTrim = false;
    if (_trimDirty) {
      _trimDirty = false;
      await _prepare(trimOnly: true);
    } else {
      await _preparations.catchError((Object _) {});
    }
    if (resume && mounted && token == _trimEditToken && !_trimEditing) {
      await toggle();
    }
  }

  Future<void> toggle() async {
    if (_preparing || !widget.active) return;
    final playback = _playback;
    final epoch = _epoch;
    try {
      await playback?.toggle();
      if (_current(epoch) && identical(playback, _playback)) {
        setState(() => _failed = false);
      }
    } catch (_) {
      if (_current(epoch) && identical(playback, _playback)) {
        setState(() => _failed = true);
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(
      _playback
          ?.setActive(state == AppLifecycleState.resumed && widget.active)
          .catchError((Object _) {}),
    );
  }

  @override
  void dispose() {
    _epoch++;
    WidgetsBinding.instance.removeObserver(this);
    _playback?.removeListener(_onPlayback);
    _playback?.dispose();
    _video?.removeListener(_onVideoTick);
    unawaited(_video?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final video = _video;
    final Widget media = widget.media.mediaKind == ReelMediaKind.image
        ? Image.memory(
            widget.media.bytes,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Center(
              child: Icon(
                Icons.broken_image_outlined,
                color: palette.dangerForeground,
              ),
            ),
          )
        : video?.value.isInitialized == true
        ? FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: video!.value.size.width,
              height: video.value.size.height,
              child: VideoPlayer(video),
            ),
          )
        : ColoredBox(color: palette.surfaceSunken);
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewport = constraints.biggest;
          return Stack(
            fit: StackFit.expand,
            children: [
              Listener(
                onPointerDown: (event) => _pointerDown = event.localPosition,
                child: GestureDetector(
                  key: const ValueKey('reel-crop-gesture'),
                  behavior: HitTestBehavior.opaque,
                  onScaleStart: !widget.cropEnabled
                      ? null
                      : (details) {
                          _gestureCrop = widget.composition.crop;
                          _gestureFocal = details.pointerCount == 1
                              ? _pointerDown ?? details.localFocalPoint
                              : details.localFocalPoint;
                        },
                  onScaleUpdate: !widget.cropEnabled
                      ? null
                      : (details) {
                          final initial = _gestureCrop;
                          if (initial == null) return;
                          widget.onCropChanged?.call(
                            reelCropFromGesture(
                              initial: initial,
                              viewport: viewport,
                              initialFocalPoint: _gestureFocal,
                              focalPoint: details.localFocalPoint,
                              gestureScale: details.scale,
                            ),
                          );
                        },
                  child: ReelCompositionFrame(
                    composition: widget.composition,
                    media: media,
                    onTextOverlayChanged: widget.onTextOverlayChanged,
                    onLinkOverlayChanged: widget.onLinkOverlayChanged,
                  ),
                ),
              ),
              if (_preparing && !_quiet)
                const Center(child: CircularProgressIndicator()),
              if (_failed)
                Center(
                  child: Material(
                    color: palette.surfaceRaised,
                    borderRadius: BorderRadius.circular(16),
                    child: TextButton.icon(
                      onPressed: _prepare,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(copy.text('Retry preview', 'Ponów podgląd')),
                    ),
                  ),
                ),
              if (!_preparing && !_failed && (_playback?.canToggle ?? false))
                PositionedDirectional(
                  bottom: 12,
                  start: 12,
                  end: 12,
                  child: Center(
                    child: IconButton.filledTonal(
                      key: const ValueKey('reel-local-video-playback'),
                      constraints: const BoxConstraints.tightFor(
                        width: 48,
                        height: 48,
                      ),
                      tooltip: isPlaying
                          ? copy.text('Pause preview', 'Wstrzymaj podgląd')
                          : copy.text('Play preview', 'Odtwórz podgląd'),
                      onPressed: toggle,
                      icon: Icon(
                        isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _LocalDraftVideo implements ReelVideoPlayback {
  _LocalDraftVideo(this.controller);
  final VideoPlayerController controller;
  @override
  bool get isPlaying => controller.value.isPlaying;
  @override
  Duration get position => controller.value.position;
  @override
  Future<void> play() => controller.play();
  @override
  Future<void> pause() => controller.pause();
  @override
  Future<void> seek(Duration position) => controller.seekTo(position);
  @override
  Future<void> setVolume(double volume) => controller.setVolume(volume);
}

class _LocalDraftAudio implements ReelAudioPlayback {
  _LocalDraftAudio({required this.payload, required this.player});
  final ReelUploadPayload payload;
  final AudioPlayer player;
  @override
  Stream<Duration> get positionChanges => player.onPositionChanged;
  @override
  Stream<void> get completions => player.onPlayerComplete;
  @override
  Future<void> load(Uri _) async {
    await player.setReleaseMode(ReleaseMode.stop);
    await player
        .setSource(BytesSource(payload.bytes, mimeType: payload.contentType))
        .timeout(const Duration(seconds: 12));
  }

  @override
  Future<void> play() => player.resume();
  @override
  Future<void> pause() => player.pause();
  @override
  Future<void> stop() => player.stop();
  @override
  Future<void> seek(Duration position) => player.seek(position);
  @override
  Future<void> setVolume(double volume) => player.setVolume(volume);
  @override
  Future<void> dispose() => player.dispose();
}
