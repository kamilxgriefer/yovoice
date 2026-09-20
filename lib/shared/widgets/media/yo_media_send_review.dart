import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/shared/widgets/badges/yo_metric_pill.dart';
import 'package:yovoice/shared/widgets/buttons/yo_button.dart';
import 'package:yovoice/shared/widgets/buttons/yo_icon_button.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/media/picked_media_video_controller.dart';
import 'package:yovoice/shared/widgets/overlays/immersive_overlay_atoms.dart';
import 'package:yovoice/shared/widgets/overlays/yo_modal_sheet_chrome.dart';
import 'package:yovoice/shared/widgets/voice/voice_player_row.dart';

export 'package:yovoice/shared/widgets/media/picked_media_video_controller.dart'
    show YoMediaPreviewControllerFactory, pickedMediaVideoController;

/// What a picked file is, for the purpose of previewing it.
enum YoPickedMediaKind { image, video, document }

/// One file the person picked from their library, before anything uploads.
///
/// The caller measures [sizeBytes] (an `XFile.length()`), and may already
/// know the [duration] of a video (from an inspector) or hold its [bytes]
/// (a file shelf that reads the whole selection). The review never reads a
/// file whose size already breaks the destination's limit.
@immutable
class YoPickedMedia {
  const YoPickedMedia({
    required this.file,
    required this.kind,
    required this.sizeBytes,
    required this.displayName,
    this.contentType,
    this.duration,
    this.bytes,
  });

  final XFile file;
  final YoPickedMediaKind kind;
  final int sizeBytes;
  final String displayName;
  final String? contentType;
  final Duration? duration;
  final Uint8List? bytes;

  YoPickedMedia withDuration(Duration value) => YoPickedMedia(
    file: file,
    kind: kind,
    sizeBytes: sizeBytes,
    displayName: displayName,
    contentType: contentType,
    duration: value,
    bytes: bytes,
  );
}

/// The destination's own limits, passed from the constants its service and
/// backend already enforce, so the review can never disagree with them.
@immutable
class YoMediaSendLimits {
  const YoMediaSendLimits({
    this.maxImageBytes,
    this.maxVideoBytes,
    this.maxDocumentBytes,
    this.minVideoDuration = const Duration(seconds: 1),
    this.maxVideoDuration,
  });

  final int? maxImageBytes;
  final int? maxVideoBytes;
  final int? maxDocumentBytes;
  final Duration minVideoDuration;
  final Duration? maxVideoDuration;

  int? maxBytesFor(YoPickedMediaKind kind) => switch (kind) {
    YoPickedMediaKind.image => maxImageBytes,
    YoPickedMediaKind.video => maxVideoBytes,
    YoPickedMediaKind.document => maxDocumentBytes,
  };
}

enum YoMediaSendChoice {
  /// The person confirmed. When the caller passed an `onSend`, it has already
  /// completed successfully.
  send,

  /// The file cannot go to this destination; reopen the same picker.
  chooseAnother,
}

@immutable
class YoMediaSendDecision {
  const YoMediaSendDecision(this.choice, this.item);

  final YoMediaSendChoice choice;

  /// The reviewed item, carrying the duration the preview measured.
  final YoPickedMedia item;
}

/// Runs the caller's durable hand-off (an outbox enqueue) while the review
/// stays open. A throw keeps the review open with the error and Send armed.
typedef YoMediaSendHandler = Future<void> Function(YoPickedMedia item);

/// Width at and above which the review is a centered dialog instead of a
/// bottom sheet. Matches [YoModalSheetChrome.desktopBreakpoint].
const double yoMediaSendReviewDialogBreakpoint =
    YoModalSheetChrome.desktopBreakpoint;

/// The one confirm-before-send surface for media picked from the device
/// library (ADR-211). Presentation only: it never uploads. The caller keeps
/// its service, owner guards and outbox, and passes them in as [onSend] and
/// [closeWhen].
///
/// Returns null when the person cancels (or [closeWhen] fires).
Future<YoMediaSendDecision?> showYoMediaSendReview(
  BuildContext context, {
  required YoPickedMedia item,
  required YoMediaSendLimits limits,
  required String title,
  required String sendLabel,
  String? destinationLabel,
  YoMediaSendHandler? onSend,
  String Function(Object error)? describeSendError,
  Stream<Object?>? closeWhen,
  YoMediaPreviewControllerFactory? videoControllerFactory,
}) {
  final review = YoMediaSendReview(
    item: item,
    limits: limits,
    title: title,
    sendLabel: sendLabel,
    destinationLabel: destinationLabel,
    onSend: onSend,
    describeSendError: describeSendError,
    closeWhen: closeWhen,
    videoControllerFactory: videoControllerFactory,
  );
  final width = MediaQuery.sizeOf(context).width;
  if (width >= yoMediaSendReviewDialogBreakpoint) {
    return showDialog<YoMediaSendDecision>(
      context: context,
      barrierDismissible: true,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: review,
        ),
      ),
    );
  }
  return showModalBottomSheet<YoMediaSendDecision>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    showDragHandle: false,
    constraints: ResponsiveContentFrame.adaptiveModalConstraints(
      context,
      maxWidth: 560,
    ),
    builder: (_) => review,
  );
}

/// The review body. Public so capture harnesses and tests can mount it
/// directly; product code opens it through [showYoMediaSendReview].
class YoMediaSendReview extends StatefulWidget {
  const YoMediaSendReview({
    required this.item,
    required this.limits,
    required this.title,
    required this.sendLabel,
    this.destinationLabel,
    this.onSend,
    this.describeSendError,
    this.closeWhen,
    this.videoControllerFactory,
    super.key,
  });

  static const Duration previewTimeout = Duration(seconds: 12);

  final YoPickedMedia item;
  final YoMediaSendLimits limits;
  final String title;
  final String sendLabel;
  final String? destinationLabel;
  final YoMediaSendHandler? onSend;
  final String Function(Object error)? describeSendError;
  final Stream<Object?>? closeWhen;
  final YoMediaPreviewControllerFactory? videoControllerFactory;

  @override
  State<YoMediaSendReview> createState() => _YoMediaSendReviewState();
}

class _YoMediaSendReviewState extends State<YoMediaSendReview> {
  late YoPickedMedia _item = widget.item;
  Future<Uint8List>? _imageBytes;
  VideoPlayerController? _controller;
  bool _probing = false;
  bool _previewUnavailable = false;
  bool _muted = true;
  bool _sending = false;
  bool _closed = false;
  String? _sendError;
  StreamSubscription<Object?>? _closeSubscription;
  final FocusNode _reviewFocus = FocusNode(debugLabel: 'yo-media-review');

  bool get _dialog =>
      MediaQuery.sizeOf(context).width >= yoMediaSendReviewDialogBreakpoint;

  int? get _maxBytes => widget.limits.maxBytesFor(_item.kind);

  bool get _tooLarge {
    final max = _maxBytes;
    return max != null && _item.sizeBytes > max;
  }

  bool get _tooLong {
    final max = widget.limits.maxVideoDuration;
    final duration = _item.duration;
    return _item.kind == YoPickedMediaKind.video &&
        max != null &&
        duration != null &&
        // The services measure a clip in whole seconds, rounded up.
        (duration.inMilliseconds + 999) ~/ 1000 > max.inSeconds;
  }

  bool get _tooShort {
    final duration = _item.duration;
    return _item.kind == YoPickedMediaKind.video &&
        duration != null &&
        duration < widget.limits.minVideoDuration;
  }

  bool get _durationUnknown =>
      _item.kind == YoPickedMediaKind.video &&
      !_probing &&
      _item.duration == null;

  bool get _blocked => _tooLarge || _tooLong || _tooShort || _durationUnknown;

  bool get _canSend => !_blocked && !_probing && !_sending;

  @override
  void initState() {
    super.initState();
    _closeSubscription = widget.closeWhen?.listen((_) => _closeForSignal());
    if (_item.kind == YoPickedMediaKind.image && !_tooLarge) {
      final bytes = _item.bytes;
      // `Future.sync`, never a bare call: a picked file whose read fails
      // synchronously (a handle that streams rather than materializes, an
      // evicted temporary) must surface as the broken-preview card, not as an
      // exception out of `initState` that takes the whole review down.
      _imageBytes = bytes != null
          ? Future<Uint8List>.value(bytes)
          : Future<Uint8List>.sync(_item.file.readAsBytes);
    }
    if (_item.kind == YoPickedMediaKind.video && !_tooLarge) {
      _probing = true;
      _prepareVideo();
    }
  }

  Future<void> _prepareVideo() async {
    VideoPlayerController? controller;
    try {
      controller = (widget.videoControllerFactory ?? pickedMediaVideoController)(
        _item.file,
      );
      await controller.initialize().timeout(YoMediaSendReview.previewTimeout);
      await controller.setVolume(0);
      final measured = controller.value.duration;
      if (!mounted) {
        _disposeController(controller);
        return;
      }
      setState(() {
        _controller = controller;
        _probing = false;
        if (measured > Duration.zero) _item = _item.withDuration(measured);
      });
    } catch (_) {
      if (controller != null) _disposeController(controller);
      if (!mounted) return;
      setState(() {
        _probing = false;
        _previewUnavailable = true;
      });
    }
  }

  void _disposeController(VideoPlayerController controller) {
    // A controller whose platform create failed never completes its dispose
    // future; it holds no player, so nothing is waited on.
    unawaited(controller.dispose().catchError((Object _) {}));
  }

  void _closeForSignal() {
    if (_closed || !mounted) return;
    _closed = true;
    final route = ModalRoute.of(context);
    if (route == null) return;
    final navigator = Navigator.of(context);
    if (route.isCurrent) {
      navigator.pop();
    } else if (route.isActive) {
      navigator.removeRoute(route);
    }
  }

  /// Every way out of the review except [closeWhen] waits for a running
  /// hand-off: closing mid-send would leave the person believing they
  /// cancelled a message that still goes, or hide a failure.
  void _cancel() {
    if (_sending) return;
    _finish(null);
  }

  /// Enter sends only while the review itself holds focus. When the person
  /// has tabbed to a button (Cancel, Close, Play), Enter activates that
  /// button instead.
  KeyEventResult _onReviewKey(FocusNode node, KeyEvent event) {
    if (!node.hasPrimaryFocus || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.enter &&
        key != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    unawaited(_send());
    return KeyEventResult.handled;
  }

  void _finish(YoMediaSendDecision? decision) {
    if (_closed || !mounted) return;
    _closed = true;
    _controller?.pause();
    Navigator.of(context).pop(decision);
  }

  Future<void> _send() async {
    if (!_canSend) return;
    final handler = widget.onSend;
    if (handler == null) {
      _finish(YoMediaSendDecision(YoMediaSendChoice.send, _item));
      return;
    }
    await _controller?.pause();
    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      await handler(_item);
      if (!mounted || _closed) return;
      setState(() => _sending = false);
      _finish(YoMediaSendDecision(YoMediaSendChoice.send, _item));
    } catch (error) {
      if (!mounted || _closed) return;
      final copy = AppLocalizations.of(context);
      setState(() {
        _sending = false;
        _sendError =
            widget.describeSendError?.call(error) ??
            copy.text(
              'This could not be sent. Try again.',
              'Nie udało się tego wysłać. Spróbuj ponownie.',
            );
      });
    }
  }

  @override
  void dispose() {
    _closeSubscription?.cancel();
    _reviewFocus.dispose();
    final controller = _controller;
    if (controller != null) {
      controller.pause().catchError((Object _) {});
      _disposeController(controller);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final viewport = MediaQuery.sizeOf(context);
    final dialog = _dialog;
    final narrow = viewport.width < 600;
    final maxHeight = viewport.height * (dialog ? .8 : .94);
    final issue = _issueText(copy);
    final warning = _warningText(copy);
    // A document has no pixels to inspect, and a blocked file needs its
    // reason and actions in view more than a large preview.
    final stageHeight = _item.kind == YoPickedMediaKind.document
        ? 200.0
        : (viewport.height * (issue != null ? .32 : (narrow ? .46 : .55)))
              .clamp(180.0, 460.0)
              .toDouble();

    Widget body = Material(
      key: const ValueKey('yo-media-review'),
      color: palette.surfaceRaised,
      borderRadius: dialog
          ? AppRadius.xl
          : const BorderRadius.vertical(top: Radius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            YoModalSheetChrome(
              sheetLabel: widget.title,
              surfaceColor: palette.surfaceRaised,
              onClose: _cancel,
            ),
            Flexible(
              child: SingleChildScrollView(
                key: const ValueKey('yo-media-review-body'),
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      widget.title,
                      style: AppTypography.titleLarge.copyWith(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (widget.destinationLabel case final destination?)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          destination,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodyMedium.copyWith(
                            color: palette.textSecondary,
                          ),
                        ),
                      ),
                    // The reason comes before the preview, so a blocked file
                    // explains itself without scrolling.
                    if (issue != null)
                      _Banner(
                        key: const ValueKey('yo-media-review-issue'),
                        message: issue,
                        danger: true,
                      )
                    else if (_sendError case final error?)
                      _Banner(
                        key: const ValueKey('yo-media-review-send-error'),
                        message: error,
                        danger: true,
                      )
                    else if (warning != null)
                      _Banner(
                        key: const ValueKey('yo-media-review-warning'),
                        message: warning,
                        danger: false,
                      ),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: stageHeight,
                      child: _stage(context, stageHeight),
                    ),
                    const SizedBox(height: 12),
                    _meta(context),
                  ],
                ),
              ),
            ),
            _actions(context, blockedHint: issue != null),
          ],
        ),
      ),
    );

    // While a hand-off runs, the sheet's drag-to-dismiss (which pops the
    // route directly, past PopScope) is claimed here and goes nowhere.
    body = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragStart: _sending ? (_) {} : null,
      onVerticalDragUpdate: _sending ? (_) {} : null,
      onVerticalDragEnd: _sending ? (_) {} : null,
      child: body,
    );
    if (dialog) {
      body = Focus(
        focusNode: _reviewFocus,
        autofocus: true,
        onKeyEvent: _onReviewKey,
        child: body,
      );
    }
    // The barrier, Esc, and system back all go through maybePop.
    return PopScope(canPop: !_sending, child: body);
  }

  String? _issueText(AppLocalizations copy) {
    if (_tooLarge) {
      final values = <String, Object>{
        'size': formatMediaBytes(_item.sizeBytes, copy),
        'limit': formatMediaBytes(_maxBytes!, copy),
      };
      return switch (_item.kind) {
        YoPickedMediaKind.image => copy.template(
          'This photo is {size}. Photos can be up to {limit}.',
          'To zdjęcie ma {size}. Zdjęcie może mieć maksymalnie {limit}.',
          values: values,
        ),
        YoPickedMediaKind.video => copy.template(
          'This video is {size}. Videos can be up to {limit}.',
          'Ten film ma {size}. Film może mieć maksymalnie {limit}.',
          values: values,
        ),
        YoPickedMediaKind.document => copy.template(
          'This file is {size}. Files can be up to {limit}.',
          'Ten plik ma {size}. Plik może mieć maksymalnie {limit}.',
          values: values,
        ),
      };
    }
    if (_tooLong) {
      return copy.template(
        'This video is {length}. Videos can be up to {max} seconds.',
        'Ten film trwa {length}. Film może trwać maksymalnie {max} s.',
        values: <String, Object>{
          'length': _clock(_item.duration!),
          'max': widget.limits.maxVideoDuration!.inSeconds,
        },
      );
    }
    if (_tooShort) {
      return copy.text(
        'This video is too short to send.',
        'Ten film jest za krótki, aby go wysłać.',
      );
    }
    if (_durationUnknown) {
      return copy.text(
        "This video can't be read. Choose another one.",
        'Nie można odczytać tego filmu. Wybierz inny.',
      );
    }
    return null;
  }

  String? _warningText(AppLocalizations copy) {
    if (_item.kind == YoPickedMediaKind.video && _previewUnavailable) {
      return copy.text('Preview unavailable', 'Podgląd niedostępny');
    }
    return null;
  }

  String _stageLabel(AppLocalizations copy) {
    final size = formatMediaBytes(_item.sizeBytes, copy);
    final duration = _item.duration;
    return switch (_item.kind) {
      YoPickedMediaKind.image => copy.template(
        'Photo, {size}',
        'Zdjęcie, {size}',
        values: <String, Object>{'size': size},
      ),
      YoPickedMediaKind.video when duration != null => copy.template(
        'Video, {length}, {size}',
        'Film, {length}, {size}',
        values: <String, Object>{'length': _clock(duration), 'size': size},
      ),
      YoPickedMediaKind.video => copy.template(
        'Video, {size}',
        'Film, {size}',
        values: <String, Object>{'size': size},
      ),
      YoPickedMediaKind.document => copy.template(
        '{name}, {size}',
        '{name}, {size}',
        values: <String, Object>{'name': _item.displayName, 'size': size},
      ),
    };
  }

  Widget _stage(BuildContext context, double stageHeight) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final Widget content = switch (_item.kind) {
      YoPickedMediaKind.image => _imageStage(context, stageHeight),
      YoPickedMediaKind.video => _videoStage(context),
      YoPickedMediaKind.document => _placeholder(
        context,
        icon: _documentIcon(_item.contentType),
        label: _item.displayName,
        detail: _documentTypeLabel(copy, _item.contentType),
      ),
    };
    return Semantics(
      key: const ValueKey('yo-media-review-stage'),
      container: true,
      explicitChildNodes: true,
      image: _item.kind == YoPickedMediaKind.image,
      label: _stageLabel(copy),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.surfaceSunken,
          borderRadius: AppRadius.card,
          border: Border.all(color: palette.border),
        ),
        child: ClipRRect(borderRadius: AppRadius.card, child: content),
      ),
    );
  }

  Widget _imageStage(BuildContext context, double stageHeight) {
    final copy = AppLocalizations.of(context);
    final future = _imageBytes;
    if (future == null) {
      return _placeholder(
        context,
        icon: Icons.image_outlined,
        label: _item.displayName,
      );
    }
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return FutureBuilder<Uint8List>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) return _brokenImage(context, copy);
        final bytes = snapshot.data;
        if (bytes == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return LayoutBuilder(
          builder: (context, constraints) => Image.memory(
            bytes,
            fit: BoxFit.contain,
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            cacheWidth: (constraints.maxWidth * dpr).round().clamp(1, 4096),
            excludeFromSemantics: true,
            gaplessPlayback: true,
            errorBuilder: (context, _, _) => _brokenImage(context, copy),
          ),
        );
      },
    );
  }

  Widget _brokenImage(BuildContext context, AppLocalizations copy) =>
      _placeholder(
        context,
        icon: Icons.broken_image_outlined,
        label: copy.text(
          "This photo can't be previewed",
          'Nie można wyświetlić podglądu zdjęcia',
        ),
        detail: _item.displayName,
      );

  Widget _videoStage(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final controller = _controller;
    if (_probing) {
      return _placeholder(
        context,
        icon: Icons.videocam_outlined,
        label: copy.text('Preparing preview…', 'Przygotowuję podgląd…'),
        busy: true,
      );
    }
    if (controller == null || !controller.value.isInitialized) {
      return _placeholder(
        context,
        icon: Icons.videocam_outlined,
        label: _item.displayName,
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final palette = context.appPalette;
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final aspect = value.aspectRatio > 0 ? value.aspectRatio : 16 / 9;
        final playing = value.isPlaying;
        final playLabel = playing
            ? copy.text('Pause preview', 'Wstrzymaj podgląd')
            : copy.text('Play preview', 'Odtwórz podgląd');
        final muteLabel = _muted
            ? copy.text('Turn sound on', 'Włącz dźwięk')
            : copy.text('Mute', 'Wycisz');
        return Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: aspect,
                child: ExcludeSemantics(child: VideoPlayer(controller)),
              ),
            ),
            Center(
              child: YoIconButton(
                key: const ValueKey('yo-media-review-play'),
                icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                tooltip: playLabel,
                semanticLabel: playLabel,
                size: 56,
                iconSize: 30,
                foregroundColor: AppColors.white,
                backgroundColor: overlayPlateColor,
                borderColor: Colors.transparent,
                onPressed: () {
                  if (playing) {
                    controller.pause();
                  } else {
                    controller.play();
                  }
                },
              ),
            ),
            Positioned(
              left: 8,
              right: 4,
              bottom: 4,
              child: Row(
                children: [
                  DecoratedBox(
                    decoration: const BoxDecoration(
                      color: overlayPlateColor,
                      borderRadius: AppRadius.pill,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      child: Text(
                        '${_clock(value.position)} / ${_clock(value.duration)}',
                        maxLines: 1,
                        style: AppTypography.labelMedium.copyWith(
                          color: AppColors.white,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: Center(
                        child: VideoProgressIndicator(
                          controller,
                          allowScrubbing: true,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          colors: VideoProgressColors(
                            playedColor: scheme.primary,
                            bufferedColor: palette.borderStrong,
                            backgroundColor: palette.border,
                          ),
                        ),
                      ),
                    ),
                  ),
                  YoIconButton(
                    key: const ValueKey('yo-media-review-mute'),
                    icon: _muted
                        ? Icons.volume_off_rounded
                        : Icons.volume_up_rounded,
                    tooltip: muteLabel,
                    semanticLabel: muteLabel,
                    size: 44,
                    iconSize: 20,
                    foregroundColor: AppColors.white,
                    backgroundColor: overlayPlateColor,
                    borderColor: Colors.transparent,
                    onPressed: () {
                      setState(() => _muted = !_muted);
                      controller.setVolume(_muted ? 0 : 1);
                    },
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _placeholder(
    BuildContext context, {
    required IconData icon,
    required String label,
    String? detail,
    bool busy = false,
  }) {
    final palette = context.appPalette;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(strokeWidth: 3),
              )
            else
              Icon(icon, size: 40, color: palette.textSecondary),
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodyMedium.copyWith(
                color: palette.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (detail != null) ...[
              const SizedBox(height: 2),
              Text(
                detail,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodySmall.copyWith(
                  color: palette.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _meta(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final duration = _item.duration;
    final showName = _item.kind != YoPickedMediaKind.document;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          YoMetricPill(
            key: const ValueKey('yo-media-review-size'),
            value: formatMediaBytes(_item.sizeBytes, copy),
            icon: Icons.sd_storage_outlined,
            tone: _tooLarge
                ? YoMetricPillTone.danger
                : YoMetricPillTone.outlined,
          ),
          if (_item.kind == YoPickedMediaKind.video && duration != null)
            YoMetricPill(
              key: const ValueKey('yo-media-review-duration'),
              value: _clock(duration),
              icon: Icons.schedule_rounded,
              tone: _tooLong || _tooShort
                  ? YoMetricPillTone.danger
                  : YoMetricPillTone.outlined,
            ),
          if (showName && _item.displayName.isNotEmpty)
            Text(
              _item.displayName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySmall.copyWith(
                color: palette.textTertiary,
              ),
            ),
        ],
      ),
    );
  }

  Widget _actions(BuildContext context, {required bool blockedHint}) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final cancel = YoButton(
      key: const ValueKey('yo-media-review-cancel'),
      label: copy.text('Cancel', 'Anuluj'),
      variant: YoButtonVariant.ghost,
      height: 52,
      onPressed: _sending ? null : () => _finish(null),
    );
    final chooseAnother = blockedHint
        ? YoButton(
            key: const ValueKey('yo-media-review-choose-another'),
            label: copy.text('Choose another', 'Wybierz inny'),
            variant: YoButtonVariant.secondary,
            height: 52,
            onPressed: () => _finish(
              YoMediaSendDecision(YoMediaSendChoice.chooseAnother, _item),
            ),
          )
        : null;
    final send = Semantics(
      hint: blockedHint
          ? copy.text(
              'Unavailable until the problem above is fixed',
              'Niedostępne, dopóki problem powyżej nie zostanie rozwiązany',
            )
          : null,
      child: YoButton(
        key: const ValueKey('yo-media-review-send'),
        label: widget.sendLabel,
        height: 52,
        isLoading: _sending,
        onPressed: _canSend ? _send : null,
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          12 + (_dialog ? 4 : MediaQuery.viewPaddingOf(context).bottom),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 420) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  send,
                  const SizedBox(height: 8),
                  if (chooseAnother == null)
                    cancel
                  else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: cancel),
                        const SizedBox(width: 8),
                        Expanded(child: chooseAnother),
                      ],
                    ),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: cancel),
                if (chooseAnother != null) ...[
                  const SizedBox(width: 10),
                  Expanded(child: chooseAnother),
                ],
                const SizedBox(width: 10),
                Expanded(child: send),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.message, required this.danger, super.key});

  final String message;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final foreground = danger
        ? palette.dangerForeground
        : palette.warningForeground;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Semantics(
        liveRegion: true,
        container: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: danger ? palette.dangerSurface : palette.warningSurface,
            borderRadius: AppRadius.card,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  danger ? Icons.error_outline_rounded : Icons.info_outline,
                  size: 20,
                  color: foreground,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    style: AppTypography.bodyMedium.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w600,
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

IconData _documentIcon(String? contentType) {
  final type = contentType ?? '';
  if (type == 'application/pdf') return Icons.picture_as_pdf_outlined;
  if (type.startsWith('text/')) return Icons.description_outlined;
  if (type.startsWith('image/')) return Icons.image_outlined;
  return Icons.insert_drive_file_outlined;
}

String _documentTypeLabel(AppLocalizations copy, String? contentType) {
  final type = contentType ?? '';
  if (type == 'application/pdf') return 'PDF';
  if (type.startsWith('text/')) return copy.text('Text file', 'Plik tekstowy');
  return copy.text('File', 'Plik');
}

String _clock(Duration duration) =>
    formatVoiceClock((duration.inMilliseconds + 999) ~/ 1000);

/// A short human size ("840 KB", "12.4 MB"), with the locale's decimal
/// separator for Polish.
String formatMediaBytes(int bytes, AppLocalizations copy) {
  const kb = 1024;
  const mb = 1024 * 1024;
  if (bytes < mb) {
    final value = (bytes / kb).ceil().clamp(1, 1023);
    return '$value KB';
  }
  final value = bytes / mb;
  final text = value >= 100 || value == value.roundToDouble()
      ? value.round().toString()
      : value.toStringAsFixed(1);
  return '${copy.isPolish ? text.replaceAll('.', ',') : text} MB';
}
