import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_gradients.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/moments/data/services/recorded_audio.dart';
import 'package:yovoice/features/moments/data/services/voice_moment_recorder.dart';
import 'package:yovoice/features/pages/data/models/page_views.dart';
import 'package:yovoice/features/pages/data/services/image_sanitizer.dart';
import 'package:yovoice/features/pages/data/services/page_post_publisher.dart';
import 'package:yovoice/features/pages/data/services/page_voice_player.dart';
import 'package:yovoice/features/pages/data/services/pages_service.dart';
import 'package:yovoice/features/pages/presentation/page_post_copy.dart';
import 'package:yovoice/features/pages/presentation/widgets/pages_focus_ink.dart';
import 'package:yovoice/features/pages/presentation/widgets/pages_state_views.dart';
import 'package:yovoice/shared/identity/public_identity.dart';
import 'package:yovoice/shared/widgets/badges/yo_progress_ring.dart';
import 'package:yovoice/shared/widgets/buttons/yo_button.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_disc.dart';
import 'package:yovoice/shared/widgets/buttons/yo_icon_button.dart';
import 'package:yovoice/shared/widgets/cards/yo_card.dart';
import 'package:yovoice/shared/widgets/identity/yo_vip_rosette.dart';
import 'package:yovoice/shared/widgets/inputs/yo_segmented_pill.dart';
import 'package:yovoice/shared/widgets/overlays/immersive_overlay_atoms.dart';
import 'package:yovoice/shared/widgets/overlays/yo_modal_sheet_chrome.dart';
import 'package:yovoice/shared/widgets/voice/voice_player_row.dart';
import 'package:yovoice/shared/widgets/waveform/yo_waveform.dart';

/// Who is posting: the owner's own Page (only the owner posts, O1).
@immutable
class PageComposerOwner {
  const PageComposerOwner({
    required this.pageId,
    required this.name,
    this.kind,
    this.publishedToday = 0,
  });

  final String pageId;
  final String name;
  final PageKind? kind;

  /// Posts this Page is known to have published today (UTC), from the
  /// owner's own wall. A lower bound of the server's daily count.
  final int publishedToday;
}

/// Picks up to `remaining` photos from the library. The app uses
/// `image_picker` with the §4.5 bounds; tests inject files.
typedef PagePhotoPicker = Future<List<XFile>> Function(int remaining);

/// Re-encodes one photo without metadata (the app runs
/// [stripAndReencodeJpeg] in a background isolate).
typedef PagePhotoSanitizer = Future<SanitizedJpeg> Function(Uint8List bytes);

Future<List<XFile>> _pickPhotos(int remaining) => ImagePicker().pickMultiImage(
  maxWidth: ImageSanitizer.maxEdge.toDouble(),
  maxHeight: ImageSanitizer.maxEdge.toDouble(),
  imageQuality: ImageSanitizer.quality,
  limit: remaining < 2 ? null : remaining,
);

/// Per-day, per-session count of the posts this client published, so the
/// budget line counts a post the owner's wall has not reloaded yet.
final Map<String, int> _publishedThisSession = <String, int>{};

String _utcDay(DateTime now) {
  final utc = now.toUtc();
  return '${utc.year}${utc.month.toString().padLeft(2, '0')}'
      '${utc.day.toString().padLeft(2, '0')}';
}

/// Opens the composer A "arkusz" (spec premium-pages §4.5, R3, §12): a
/// bottom sheet on phones and tablets, a centred 640 modal on desktop
/// (≥ 1100). Returns the published post, or null when the owner closed it.
Future<PagePostView?> showPageComposer(
  BuildContext context, {
  required PageComposerOwner owner,
  PagePostKind initialKind = PagePostKind.text,
  PagesService? service,
  PagePostPublisher? publisher,
  PagePhotoPicker? pickPhotos,
  PagePhotoSanitizer? sanitize,
  VoiceMomentRecorder Function()? recorderFactory,
  DateTime Function()? clock,
}) {
  final composer = PageComposer(
    owner: owner,
    initialKind: initialKind,
    service: service,
    publisher: publisher,
    pickPhotos: pickPhotos,
    sanitize: sanitize,
    recorderFactory: recorderFactory,
    clock: clock,
  );
  // One clip at a time (ADR-184): a voice post playing behind the composer
  // stops before anything is recorded or reviewed.
  unawaited(PageVoicePlayer.instance.pause());
  final width = MediaQuery.sizeOf(context).width;
  if (width >= YoModalSheetChrome.desktopBreakpoint) {
    return showDialog<PagePostView>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: PageComposer.desktopWidth,
            maxHeight: MediaQuery.sizeOf(dialogContext).height - 64,
          ),
          child: composer,
        ),
      ),
    );
  }
  return showModalBottomSheet<PagePostView>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    showDragHandle: false,
    constraints: BoxConstraints(
      maxWidth: width >= 600 ? PageComposer.desktopWidth : double.infinity,
    ),
    builder: (_) => composer,
  );
}

/// The composer body. Public so tests and capture harnesses can mount it
/// without a route; product code opens it through [showPageComposer].
class PageComposer extends StatefulWidget {
  const PageComposer({
    required this.owner,
    this.initialKind = PagePostKind.text,
    this.service,
    this.publisher,
    this.pickPhotos,
    this.sanitize,
    this.recorderFactory,
    this.clock,
    super.key,
  });

  final PageComposerOwner owner;
  final PagePostKind initialKind;
  final PagesService? service;
  final PagePostPublisher? publisher;
  final PagePhotoPicker? pickPhotos;
  final PagePhotoSanitizer? sanitize;
  final VoiceMomentRecorder Function()? recorderFactory;
  final DateTime Function()? clock;

  static const double desktopWidth = 640;
  static const int maxPhotos = 10;

  /// §1.1: 10 posts per Page per UTC day; the line shows from 3 left.
  static const int dailyPosts = 10;
  static const int budgetLineFrom = 3;

  /// D8: the recorder stops by itself at 60 s.
  static const Duration maxVoice = Duration(seconds: 60);

  /// "Zostało 10 sekund" is announced this long before the cap.
  static const Duration voiceWarningBefore = Duration(seconds: 10);

  @override
  State<PageComposer> createState() => _PageComposerState();
}

class _PhotoDraft {
  _PhotoDraft(this.id);

  final int id;
  SanitizedJpeg? jpeg;
  Uint8List? source;
  bool failed = false;

  bool get ready => jpeg != null;
}

enum _VoiceStage { idle, starting, recording, recorded }

class _PageComposerState extends State<PageComposer> {
  late final PagesService _service = widget.service ?? PagesService.instance;
  late final PagePostPublisher _publisher =
      widget.publisher ?? PagePostPublisher(service: _service);
  late final TextEditingController _text = TextEditingController();
  final FocusNode _textFocus = FocusNode();

  late PagePostKind _kind = widget.initialKind;
  bool _commentsEnabled = true;
  bool _publishing = false;
  String? _error;
  PagesFailure? _failure;
  List<int> _failedUploads = const <int>[];

  // Photos.
  final List<_PhotoDraft> _photos = <_PhotoDraft>[];
  int _photoSeq = 0;
  int _selected = 0;
  bool _picking = false;

  // Voice.
  VoiceMomentRecorder? _recorder;
  _VoiceStage _voiceStage = _VoiceStage.idle;
  RecordedAudio? _take;
  int _takeMs = 0;
  bool _autoStopped = false;
  String? _voiceProblem;
  Timer? _voiceTimer;
  Duration _elapsed = Duration.zero;
  StreamSubscription<Object>? _levelSub;
  final List<double> _levels = List<double>.filled(27, 0);
  bool _warnedEnd = false;
  final FocusNode _recordFocus = FocusNode(debugLabel: 'composer-record');
  final FocusNode _stopFocus = FocusNode(debugLabel: 'composer-stop');
  final FocusNode _rerecordFocus = FocusNode(debugLabel: 'composer-rerecord');
  AudioPlayer? _preview;
  bool _previewPlaying = false;
  Duration _previewPosition = Duration.zero;
  final int _voiceKey = 0;

  PageComposerOwner get _owner => widget.owner;
  DateTime _now() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _text.addListener(_onTextChanged);
    _publisher.addListener(_onPublisherChanged);
    if (_kind == PagePostKind.photo) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _photos.isEmpty) unawaited(_addPhotos());
      });
    } else if (_kind == PagePostKind.text) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // With large text the field sits low enough that focusing it would
        // scroll "Nowy post" half under the sheet's top row; the sheet then
        // opens at its top and the field waits for a tap.
        if (!mounted) return;
        final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
        if (scale < 1.3) _textFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _text
      ..removeListener(_onTextChanged)
      ..dispose();
    _textFocus.dispose();
    _recordFocus.dispose();
    _stopFocus.dispose();
    _rerecordFocus.dispose();
    _publisher.removeListener(_onPublisherChanged);
    if (widget.publisher == null) _publisher.dispose();
    _voiceTimer?.cancel();
    unawaited(_levelSub?.cancel());
    final recorder = _recorder;
    if (recorder != null) {
      unawaited(recorder.cancel().then((_) => recorder.dispose()));
    }
    unawaited(_preview?.dispose());
    final take = _take;
    if (take != null) unawaited(take.discard());
    super.dispose();
  }

  void _onTextChanged() => setState(() {});
  void _onPublisherChanged() {
    if (mounted) setState(() {});
  }

  // ------------------------------------------------------------ state

  bool get _dirty =>
      _text.text.trim().isNotEmpty ||
      _photos.isNotEmpty ||
      _take != null ||
      _voiceStage == _VoiceStage.recording;

  bool get _locked => _publishing || _publisher.hasReservation;

  int get _remainingToday {
    final session =
        _publishedThisSession['${_owner.pageId}/${_utcDay(_now())}'] ?? 0;
    final used = math.max(_owner.publishedToday, session);
    return math.max(0, PageComposer.dailyPosts - used);
  }

  bool get _canPublish {
    if (_publishing) return false;
    final text = _text.text;
    if (text.length > PagesService.maxPostText) return false;
    switch (_kind) {
      case PagePostKind.text:
        return text.trim().isNotEmpty;
      case PagePostKind.photo:
        return _photos.isNotEmpty && _photos.every((p) => p.ready);
      case PagePostKind.voice:
        return _take != null && _voiceStage == _VoiceStage.recorded;
    }
  }

  // ------------------------------------------------------------ close

  Future<void> _close() async {
    if (_publishing) return;
    if (!_dirty) {
      Navigator.of(context).pop();
      return;
    }
    final discard = await _confirmDiscard();
    if (discard && mounted) Navigator.of(context).pop();
  }

  Future<bool> _confirmDiscard() async {
    final copy = PagePostCopy(AppLocalizations.of(context));
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(copy.discardTitle),
        content: Text(copy.discardBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(copy.keepEditing),
          ),
          TextButton(
            key: const ValueKey('page-composer-discard'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(copy.discard),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // ------------------------------------------------------------ modes

  void _selectKind(int index) {
    if (_locked) return;
    final next = PagePostKind.values[index];
    if (next == _kind) return;
    if (_voiceStage == _VoiceStage.recording) unawaited(_stopRecording());
    unawaited(_pausePreview());
    setState(() {
      _kind = next;
      _error = null;
      _failure = null;
    });
    if (next == PagePostKind.photo && _photos.isEmpty) {
      unawaited(_addPhotos());
    }
  }

  // ------------------------------------------------------------ photos

  Future<void> _addPhotos() async {
    if (_picking || _locked) return;
    final remaining = PageComposer.maxPhotos - _photos.length;
    if (remaining <= 0) return;
    setState(() => _picking = true);
    List<XFile> files;
    try {
      files = await (widget.pickPhotos ?? _pickPhotos)(remaining);
    } on PlatformException {
      files = const <XFile>[];
    } finally {
      if (mounted) setState(() => _picking = false);
    }
    if (!mounted || files.isEmpty) return;
    final added = <_PhotoDraft>[];
    final count = math.min(files.length, remaining);
    for (var i = 0; i < count; i++) {
      added.add(_PhotoDraft(++_photoSeq));
    }
    setState(() {
      _photos.addAll(added);
      _selected = _photos.length - added.length;
      _error = null;
    });
    for (var i = 0; i < added.length; i++) {
      unawaited(_prepare(added[i], files[i]));
    }
  }

  Future<void> _prepare(_PhotoDraft draft, XFile? file) async {
    try {
      final bytes = draft.source ?? await file!.readAsBytes();
      draft.source = bytes;
      final jpeg = await (widget.sanitize ?? stripAndReencodeJpeg)(bytes);
      if (!mounted) return;
      setState(() {
        draft
          ..jpeg = jpeg
          ..failed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => draft.failed = true);
    }
  }

  void _retryPhoto(_PhotoDraft draft) {
    setState(() => draft.failed = false);
    unawaited(_prepare(draft, null));
  }

  void _removePhoto(int index) {
    if (_publishing) return;
    setState(() {
      _photos.removeAt(index);
      if (_selected >= _photos.length) {
        _selected = math.max(0, _photos.length - 1);
      }
    });
  }

  // ------------------------------------------------------------ voice

  VoiceMomentRecorder _newRecorder() =>
      widget.recorderFactory?.call() ?? VoiceMomentRecorder();

  Future<void> _startRecording() async {
    if (_locked || _voiceStage == _VoiceStage.starting) return;
    await _pausePreview();
    await PageVoicePlayer.instance.pause();
    final previous = _take;
    final recorder = _recorder ??= _newRecorder();
    setState(() {
      _voiceStage = _VoiceStage.starting;
      _voiceProblem = null;
      _autoStopped = false;
    });
    try {
      await recorder.start();
    } on VoiceRecordingException catch (error) {
      if (!mounted) return;
      setState(() {
        _voiceStage = previous == null
            ? _VoiceStage.idle
            : _VoiceStage.recorded;
        _voiceProblem = PagePostCopy(
          AppLocalizations.of(context),
        ).recordingProblem(error.problem);
      });
      return;
    }
    if (!mounted) {
      await recorder.cancel();
      return;
    }
    if (previous != null) {
      _take = null;
      unawaited(previous.discard());
    }
    _levels.fillRange(0, _levels.length, 0);
    _levelSub = recorder.amplitudes().listen((amplitude) {
      if (!mounted) return;
      setState(() {
        // Fixed-length meter: shift left in place, newest level last.
        _levels
          ..setRange(0, _levels.length - 1, _levels, 1)
          ..[_levels.length - 1] = VoiceMomentRecorder.normalizeAmplitude(
            amplitude.current,
          );
      });
    }, onError: (Object _) {});
    _elapsed = Duration.zero;
    _warnedEnd = false;
    _voiceTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      final elapsed = recorder.elapsed;
      setState(() => _elapsed = elapsed);
      // The 1:00 cap is announced ahead, not only after it has cut in.
      if (!_warnedEnd &&
          elapsed >= PageComposer.maxVoice - PageComposer.voiceWarningBefore) {
        _warnedEnd = true;
        announcePages(
          context,
          PagePostCopy(AppLocalizations.of(context)).tenSecondsLeft,
          assertive: true,
        );
      }
      if (elapsed >= PageComposer.maxVoice) {
        unawaited(_stopRecording(auto: true));
      }
    });
    final keyboardOnRecord = _recordFocus.hasFocus;
    setState(() => _voiceStage = _VoiceStage.recording);
    // The record control became Stop: keyboard focus goes with it.
    if (keyboardOnRecord) _focusAfterFrame(_stopFocus);
  }

  void _focusAfterFrame(FocusNode node) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && node.context != null) node.requestFocus();
    });
  }

  Future<void> _stopRecording({bool auto = false}) async {
    final recorder = _recorder;
    if (recorder == null || _voiceStage != _VoiceStage.recording) return;
    final keyboardOnStop = _stopFocus.hasFocus;
    _voiceTimer?.cancel();
    _voiceTimer = null;
    // Not awaited: a level stream's cancel may complete only after its
    // pending events drain, and Stop must never wait on the meter.
    unawaited(_levelSub?.cancel());
    _levelSub = null;
    try {
      final audio = await recorder.stop();
      if (!mounted) {
        await audio.discard();
        return;
      }
      final ms = math.min(
        recorder.elapsed.inMilliseconds,
        PageComposer.maxVoice.inMilliseconds,
      );
      setState(() {
        _take = audio;
        _takeMs = math.max(1000, ms);
        _autoStopped = auto;
        _voiceStage = _VoiceStage.recorded;
        _previewPosition = Duration.zero;
      });
      // Stop became the take: focus lands on "Nagraj ponownie".
      if (keyboardOnStop) _focusAfterFrame(_rerecordFocus);
    } on VoiceRecordingException catch (error) {
      if (!mounted) return;
      setState(() {
        _voiceStage = _VoiceStage.idle;
        _voiceProblem = PagePostCopy(
          AppLocalizations.of(context),
        ).recordingProblem(error.problem);
      });
    }
  }

  Future<void> _deleteTake() async {
    if (_locked) return;
    await _pausePreview();
    final take = _take;
    setState(() {
      _take = null;
      _voiceStage = _VoiceStage.idle;
      _autoStopped = false;
    });
    if (take != null) await take.discard();
  }

  Future<void> _togglePreview() async {
    final take = _take;
    if (take == null) return;
    var player = _preview;
    if (player == null) {
      player = _preview = AudioPlayer();
      player.onPositionChanged.listen((position) {
        if (mounted) setState(() => _previewPosition = position);
      });
      player.onPlayerComplete.listen((_) {
        if (mounted) {
          setState(() {
            _previewPlaying = false;
            _previewPosition = Duration.zero;
          });
        }
      });
    }
    try {
      if (_previewPlaying) {
        await player.pause();
        setState(() => _previewPlaying = false);
      } else {
        await PageVoicePlayer.instance.pause();
        setState(() => _previewPlaying = true);
        if (_previewPosition > Duration.zero) {
          await player.resume();
        } else {
          await player.play(take.playbackSource);
        }
      }
    } catch (_) {
      if (mounted) setState(() => _previewPlaying = false);
    }
  }

  Future<void> _pausePreview() async {
    if (!_previewPlaying) return;
    try {
      await _preview?.pause();
    } catch (_) {}
    if (mounted) setState(() => _previewPlaying = false);
  }

  // ------------------------------------------------------------ publish

  Future<void> _publish() async {
    if (!_canPublish) return;
    final copy = PagePostCopy(AppLocalizations.of(context));
    await _pausePreview();
    setState(() {
      _publishing = true;
      _error = null;
      _failure = null;
      _failedUploads = const <int>[];
    });
    final text = _text.text.trim();
    try {
      final PagePostView post;
      switch (_kind) {
        case PagePostKind.text:
          post = await _publisher.publishText(
            text: text,
            commentsEnabled: _commentsEnabled,
          );
        case PagePostKind.photo:
          post = await _publisher.publishPhotos(
            keys: [for (final photo in _photos) photo.id],
            photos: [for (final photo in _photos) photo.jpeg!],
            text: text,
            commentsEnabled: _commentsEnabled,
          );
        case PagePostKind.voice:
          post = await _publisher.publishVoice(
            key: _voiceKey,
            audio: _take!,
            durationMs: _takeMs,
            text: text,
            commentsEnabled: _commentsEnabled,
          );
      }
      final key = '${_owner.pageId}/${_utcDay(_now())}';
      _publishedThisSession[key] = (_publishedThisSession[key] ?? 0) + 1;
      if (!mounted) return;
      Navigator.of(context).pop(post);
    } on PageUploadException catch (error) {
      if (!mounted) return;
      setState(() {
        _failedUploads = error.failedIndexes;
        _error = _kind == PagePostKind.voice
            ? copy.recordingUploadFailed
            : copy.photoUploadFailed(error.failedIndexes.first + 1);
      });
    } on PagesException catch (error) {
      if (!mounted) return;
      setState(() {
        _failure = error.failure;
        _error = copy.publishError(error.failure);
      });
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = PagePostCopy(AppLocalizations.of(context));
    final desktop =
        MediaQuery.sizeOf(context).width >=
        YoModalSheetChrome.desktopBreakpoint;
    final gutter = desktop ? 24.0 : 20.0;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight = MediaQuery.sizeOf(context).height * (desktop ? 1 : .94);

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          copy.newPost,
          style: AppTypography.titleLarge.copyWith(
            color: palette.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        _AsPage(owner: _owner, copy: copy),
        const SizedBox(height: 16),
        IgnorePointer(
          ignoring: _locked,
          child: Opacity(
            opacity: _locked ? .5 : 1,
            child: _KindPill(
              copy: copy,
              selectedIndex: _kind.index,
              onSelected: _selectKind,
            ),
          ),
        ),
        const SizedBox(height: 16),
        ..._modeBody(context, copy, wide: desktop),
        if (!desktop) ...[
          const SizedBox(height: 4),
          _CommentsSwitch(
            value: _commentsEnabled,
            // Locked while publishing, but drawn in its real state: a
            // disabled switch reads as OFF (A_arkusz_publikowanie keeps it
            // violet-on).
            onChanged: (value) {
              if (_publishing || _publisher.publishUnresolved) return;
              setState(() => _commentsEnabled = value);
            },
            copy: copy,
          ),
        ],
        const SizedBox(height: 8),
      ],
    );

    final remaining = _remainingToday;
    final showBudget =
        remaining <= PageComposer.budgetLineFrom &&
        _failure != PagesFailure.budget;
    final publishLabel = _publishing
        ? switch (_kind) {
            PagePostKind.photo => copy.sendingPhotos,
            PagePostKind.voice => copy.sendingRecording,
            PagePostKind.text => copy.publishing,
          }
        : copy.publish;
    final footer = Container(
      padding: EdgeInsets.fromLTRB(gutter, 12, gutter, 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: palette.hairline)),
      ),
      child: desktop
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showBudget) ...[
                  _Note(
                    copy.postsLeftToday(remaining),
                    icon: Icons.event_available_outlined,
                  ),
                  const SizedBox(height: 8),
                ],
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  runSpacing: 8,
                  children: [
                    _CommentsSwitch(
                      compact: true,
                      value: _commentsEnabled,
                      onChanged: (value) {
                        if (_publishing || _publisher.publishUnresolved) {
                          return;
                        }
                        setState(() => _commentsEnabled = value);
                      },
                      copy: copy,
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 160),
                      child: YoButton(
                        key: const ValueKey('page-composer-publish'),
                        label: publishLabel,
                        height: 48,
                        fullWidth: false,
                        onPressed: _canPublish ? _publish : null,
                      ),
                    ),
                  ],
                ),
              ],
            )
          : SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (showBudget) ...[
                    _Note(
                      copy.postsLeftToday(remaining),
                      icon: Icons.event_available_outlined,
                    ),
                    const SizedBox(height: 12),
                  ],
                  YoButton(
                    key: const ValueKey('page-composer-publish'),
                    label: publishLabel,
                    height: 52,
                    onPressed: _canPublish ? _publish : null,
                  ),
                ],
              ),
            ),
    );

    final content = ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          YoModalSheetChrome(
            sheetLabel: copy.newPost,
            surfaceColor: palette.surfaceRaised,
            onClose: _publishing ? () {} : () => unawaited(_close()),
          ),
          Flexible(
            child: SingleChildScrollView(
              key: const ValueKey('page-composer-scroll'),
              padding: EdgeInsets.symmetric(horizontal: gutter),
              child: body,
            ),
          ),
          footer,
        ],
      ),
    );

    return PopScope(
      canPop: !_dirty && !_publishing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_close());
      },
      child: Padding(
        padding: EdgeInsets.only(bottom: desktop ? 0 : bottomInset),
        child: Material(
          key: const ValueKey('page-composer'),
          color: palette.surfaceRaised,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: desktop
                ? AppRadius.xl
                : const BorderRadius.vertical(top: Radius.circular(28)),
            side: MediaQuery.highContrastOf(context)
                ? BorderSide(color: palette.borderStrong)
                : BorderSide.none,
          ),
          child: content,
        ),
      ),
    );
  }

  List<Widget> _modeBody(
    BuildContext context,
    PagePostCopy copy, {
    required bool wide,
  }) {
    final field = _Field(
      controller: _text,
      focusNode: _textFocus,
      hint: switch (_kind) {
        PagePostKind.text => copy.writeSomething,
        PagePostKind.photo => copy.addCaption,
        PagePostKind.voice => copy.voiceTranscript,
      },
      helper: _kind == PagePostKind.voice ? copy.voiceTranscriptHelper : null,
      minLines: _kind == PagePostKind.text ? 5 : 2,
      // An unresolved publish is retried with the same input (the server
      // may already have the post), so the text waits for that answer.
      enabled: !_publishing && !_publisher.publishUnresolved,
      copy: copy,
    );
    final banner = _error == null
        ? null
        : _Banner(
            key: const ValueKey('page-composer-error'),
            text: _error!,
            tone: _BannerTone.danger,
            icon: Icons.error_outline_rounded,
            action:
                _failure == PagesFailure.budget ||
                    _failure == PagesFailure.accessRequired ||
                    _failure == PagesFailure.notEnabled ||
                    _failure == PagesFailure.paused
                ? null
                : copy.retry,
            onAction: _canPublish ? () => unawaited(_publish()) : null,
          );
    switch (_kind) {
      case PagePostKind.text:
        return [
          field,
          if (banner != null) ...[const SizedBox(height: 12), banner],
        ];
      case PagePostKind.photo:
        return [
          ..._photoBody(context, copy, wide: wide, banner: banner),
          field,
        ];
      case PagePostKind.voice:
        return [
          ..._voiceBody(context, copy),
          if (banner != null) ...[banner, const SizedBox(height: 12)],
          field,
        ];
    }
  }

  List<Widget> _photoBody(
    BuildContext context,
    PagePostCopy copy, {
    required bool wide,
    required Widget? banner,
  }) {
    if (_photos.isEmpty) {
      return [
        _EmptyPhotos(
          busy: _picking,
          copy: copy,
          onPick: _locked ? null : () => unawaited(_addPhotos()),
        ),
        const SizedBox(height: 12),
        _Note(copy.metadataNote, icon: Icons.location_off_outlined),
        const SizedBox(height: 12),
      ];
    }
    final selected = _photos[_selected.clamp(0, _photos.length - 1)];
    final uploading = _publishing || _failedUploads.isNotEmpty;
    final states = _publisher.states;
    final progress = _publisher.progress;
    final prepareFailed = _photos.indexWhere((p) => p.failed);
    return [
      if (!uploading) ...[
        _Stage(
          height: wide ? 300 : 186,
          draft: selected,
          index: _selected,
          total: _photos.length,
          copy: copy,
        ),
        const SizedBox(height: 12),
      ],
      SizedBox(
        height: _Thumb.cellHeight,
        child: ListView.builder(
          key: const ValueKey('page-composer-thumbs'),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsetsDirectional.only(end: 8),
          itemCount: _photos.length + (_photos.length < 10 && !_locked ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == _photos.length) {
              return Padding(
                padding: const EdgeInsets.only(top: _Thumb.removeOutset),
                child: _AddTile(
                  label: '${_photos.length}/${PageComposer.maxPhotos}',
                  tooltip: copy.addPhotos,
                  onTap: _picking ? null : () => unawaited(_addPhotos()),
                ),
              );
            }
            final draft = _photos[index];
            // From the moment the reservation starts every thumb shows its
            // own state: waiting (ring at 0) until its upload reports.
            final state = !uploading
                ? null
                : index < states.length
                ? states[index]
                : PageUploadState.waiting;
            return _Thumb(
              key: ValueKey('page-composer-photo-${draft.id}'),
              draft: draft,
              index: index,
              selected: !uploading && index == _selected,
              uploadState: state,
              progress:
                  state == PageUploadState.uploading && index < progress.length
                  ? progress[index]
                  : null,
              showIndex: !uploading,
              copy: copy,
              total: _photos.length,
              onSelect: () => setState(() => _selected = index),
              onRemove: _publishing ? null : () => _removePhoto(index),
            );
          },
        ),
      ),
      const SizedBox(height: 12),
      if (prepareFailed >= 0 && !uploading) ...[
        _Banner(
          key: const ValueKey('page-composer-prepare-error'),
          text: copy.photoPrepareFailed(prepareFailed + 1),
          tone: _BannerTone.danger,
          icon: Icons.error_outline_rounded,
          action: copy.retry,
          onAction: () => _retryPhoto(_photos[prepareFailed]),
        ),
        const SizedBox(height: 12),
      ],
      if (banner != null) ...[banner, const SizedBox(height: 12)],
      if (!uploading) ...[
        _Note(
          _publisher.hasReservation ? copy.photosLocked : copy.metadataNote,
          icon: Icons.location_off_outlined,
        ),
        const SizedBox(height: 12),
      ],
    ];
  }

  List<Widget> _voiceBody(BuildContext context, PagePostCopy copy) {
    final palette = context.appPalette;
    final widgets = <Widget>[];
    if (_autoStopped && _voiceStage == _VoiceStage.recorded) {
      widgets
        ..add(
          _Banner(
            key: const ValueKey('page-composer-voice-cap'),
            text: copy.autoStopped,
            tone: _BannerTone.warning,
            icon: Icons.timer_outlined,
          ),
        )
        ..add(const SizedBox(height: 12));
    }
    if (_voiceProblem != null) {
      widgets
        ..add(
          _Banner(
            text: _voiceProblem!,
            tone: _BannerTone.danger,
            icon: Icons.mic_off_outlined,
          ),
        )
        ..add(const SizedBox(height: 12));
    }
    final Widget card;
    switch (_voiceStage) {
      case _VoiceStage.idle:
      case _VoiceStage.starting:
        final starting = _voiceStage == _VoiceStage.starting;
        card = YoCard(
          key: const ValueKey('page-composer-voice-idle'),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          semanticButton: false,
          child: Row(
            children: [
              Semantics(
                button: true,
                label: copy.startRecording,
                excludeSemantics: true,
                onTap: _locked || starting ? null : _startRecording,
                child: Tooltip(
                  message: copy.startRecording,
                  excludeFromSemantics: true,
                  child: InkResponse(
                    key: const ValueKey('page-composer-record'),
                    focusNode: _recordFocus,
                    onTap: _locked || starting
                        ? null
                        : () => unawaited(_startRecording()),
                    radius: 32,
                    child: YoGradientDisc(
                      size: 56,
                      gloss: true,
                      emphasis: YoDiscEmphasis.lift,
                      status: starting ? YoDiscStatus.busy : YoDiscStatus.idle,
                      icon: Icons.mic_rounded,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppRhythm.item),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      copy.recordTitle,
                      style: AppTypography.rowTitle.copyWith(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      copy.recordHint,
                      style: AppTypography.bodySmall.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      case _VoiceStage.recording:
        final seconds = _elapsed.inSeconds.clamp(0, 60);
        card = YoCard(
          key: const ValueKey('page-composer-voice-recording'),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          semanticButton: false,
          child: Row(
            children: [
              Semantics(
                button: true,
                label: copy.stopRecording,
                excludeSemantics: true,
                onTap: () => unawaited(_stopRecording()),
                child: Tooltip(
                  message: copy.stopRecording,
                  excludeFromSemantics: true,
                  child: InkResponse(
                    key: const ValueKey('page-composer-stop'),
                    focusNode: _stopFocus,
                    onTap: () => unawaited(_stopRecording()),
                    radius: 32,
                    child: const YoGradientDisc(
                      size: 56,
                      gloss: true,
                      tone: YoDiscTone.live,
                      icon: Icons.stop_rounded,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppRhythm.item),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ExcludeSemantics(child: _Meter(levels: _levels)),
                    const SizedBox(height: 4),
                    Semantics(
                      liveRegion: false,
                      label: copy.recording,
                      child: Text(
                        '${_clock(seconds * 1000)} / 1:00',
                        textAlign: TextAlign.end,
                        style: AppTypography.bodySmall.copyWith(
                          color: palette.textSecondary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      case _VoiceStage.recorded:
        final progress = _takeMs > 0 && _previewPosition > Duration.zero
            ? (_previewPosition.inMilliseconds / _takeMs).clamp(0.0, 1.0)
            : null;
        card = YoCard(
          key: const ValueKey('page-composer-voice-take'),
          padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
          semanticButton: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Take(
                durationMs: _takeMs,
                playing: _previewPlaying,
                progress: progress,
                copy: copy,
                onToggle: () => unawaited(_togglePreview()),
                onDelete: _locked ? null : () => unawaited(_deleteTake()),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: PagesTonalButton(
                  key: const ValueKey('page-composer-rerecord'),
                  focusNode: _rerecordFocus,
                  label: copy.recordAgain,
                  icon: Icons.mic_none_rounded,
                  onPressed: _locked
                      ? null
                      : () => unawaited(_startRecording()),
                ),
              ),
              if (_publisher.hasReservation) ...[
                const SizedBox(height: 8),
                _Note(copy.recordingLocked, icon: Icons.lock_outline_rounded),
              ],
            ],
          ),
        );
    }
    widgets
      ..add(card)
      ..add(const SizedBox(height: 12));
    return widgets;
  }
}

/// Tekst · Zdjęcia · Głos. Every label stays whole: icon + label while
/// both fit a third of the width, the label alone when only it fits, and
/// the icon alone (the label still its semantics name) at 320 px / 200 %.
class _KindPill extends StatelessWidget {
  const _KindPill({
    required this.copy,
    required this.selectedIndex,
    required this.onSelected,
  });

  final PagePostCopy copy;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const double _fontSize = 13;
  static const double _iconSize = 17;

  @override
  Widget build(BuildContext context) {
    final items = <(Key, String, IconData)>[
      (
        const ValueKey('page-composer-kind-text'),
        copy.modeText,
        Icons.notes_rounded,
      ),
      (
        const ValueKey('page-composer-kind-photo'),
        copy.modePhotos,
        Icons.photo_library_outlined,
      ),
      (
        const ValueKey('page-composer-kind-voice'),
        copy.modeVoice,
        Icons.mic_none_rounded,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaler = MediaQuery.textScalerOf(context);
        final base = DefaultTextStyle.of(context).style.merge(
          const TextStyle(fontSize: _fontSize, fontWeight: FontWeight.w700),
        );
        var widest = 0.0;
        for (final item in items) {
          final painter = TextPainter(
            text: TextSpan(text: item.$2, style: base),
            textScaler: scaler,
            textDirection: Directionality.of(context),
            maxLines: 1,
          )..layout();
          widest = math.max(widest, painter.width);
          painter.dispose();
        }
        // A segment's 12 px side padding each way, and 1 px of slack.
        final room = constraints.maxWidth / items.length - 24 - 1;
        final withIcon = widest + _iconSize + 7 <= room;
        final labelOnly = !withIcon && widest <= room;
        return YoSegmentedPill(
          key: const ValueKey('page-composer-kind'),
          segments: [
            for (final (key, label, icon) in items)
              YoSegmentedPillSegment(
                key: key,
                label: withIcon || labelOnly ? label : '',
                semanticLabel: label,
                icon: withIcon || !labelOnly ? icon : null,
              ),
          ],
          selectedIndex: selectedIndex,
          onSelected: onSelected,
          segmentMinHeight: 44,
          fontSize: _fontSize,
          iconSize: _iconSize,
        );
      },
    );
  }
}

String _clock(int milliseconds) {
  final seconds = (milliseconds / 1000).round();
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------------------
// Atoms (ported from the approved composer A render).
// ---------------------------------------------------------------------------

/// "jako Kawiarnia Pod Lipą ✔".
class _AsPage extends StatelessWidget {
  const _AsPage({required this.owner, required this.copy});

  final PageComposerOwner owner;
  final PagePostCopy copy;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final style = AppTypography.bodySmall.copyWith(
      color: palette.textSecondary,
      fontSize: 13,
      height: 1.2,
    );
    final (before, after) = copy.asPage();
    // One node ("jako Kawiarnia Pod Lipą, VIP"); the name wraps onto a
    // second line at 320 px / 200 % instead of being cut.
    return MergeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (before.isNotEmpty) Text(before, style: style),
          Flexible(
            child: NameWithVipMark(
              uid: owner.pageId,
              name: owner.name,
              maxLines: 2,
              style: style.copyWith(
                color: palette.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (after.isNotEmpty) Text(after, style: style),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.minLines,
    required this.enabled,
    required this.copy,
    this.helper,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;

  /// A persistent line under the field (voice mode's transcript prompt).
  final String? helper;
  final int minLines;
  final bool enabled;
  final PagePostCopy copy;

  static const int _counterFrom = 4500;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final length = controller.text.length;
    final over = length > PagesService.maxPostText;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(24),
      borderSide: BorderSide(color: palette.borderStrong),
    );
    return TextField(
      key: const ValueKey('page-composer-text'),
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      minLines: minLines,
      maxLines: 12,
      keyboardType: TextInputType.multiline,
      textCapitalization: TextCapitalization.sentences,
      style: AppTypography.bodyLarge.copyWith(
        color: palette.textPrimary,
        height: 1.45,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppTypography.bodyLarge.copyWith(
          color: palette.textTertiary,
          height: 1.45,
        ),
        helperText: helper,
        helperMaxLines: 3,
        helperStyle: AppTypography.bodySmall.copyWith(
          color: palette.textSecondary,
        ),
        filled: true,
        fillColor: palette.surface,
        contentPadding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
        border: border,
        enabledBorder: border,
        disabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(
            color: palette.interactiveForeground.withValues(alpha: .7),
            width: 1.5,
          ),
        ),
        counterText: length >= _counterFrom
            ? copy.characters(length, PagesService.maxPostText)
            : null,
        counterStyle: AppTypography.bodySmall.copyWith(
          color: over ? palette.dangerForeground : palette.textTertiary,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _CommentsSwitch extends StatelessWidget {
  const _CommentsSwitch({
    required this.value,
    required this.onChanged,
    required this.copy,
    this.compact = false,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final PagePostCopy copy;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final label = Text(
      value ? copy.commentsOn : copy.commentsOff,
      style: AppTypography.bodyMedium.copyWith(
        color: palette.textPrimary,
        fontWeight: FontWeight.w600,
      ),
    );
    return MergeSemantics(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 20,
              color: palette.textSecondary,
            ),
            const SizedBox(width: 12),
            if (compact) Flexible(child: label) else Expanded(child: label),
            const SizedBox(width: 12),
            Switch(
              key: const ValueKey('page-composer-comments'),
              value: value,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text, {required this.icon});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Icon(icon, size: 18, color: palette.textSecondary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: AppTypography.bodySmall.copyWith(
              color: palette.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

enum _BannerTone { warning, danger }

class _Banner extends StatelessWidget {
  const _Banner({
    required this.text,
    required this.tone,
    required this.icon,
    this.action,
    this.onAction,
    super.key,
  });

  final String text;
  final _BannerTone tone;
  final IconData icon;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final (background, ink) = switch (tone) {
      _BannerTone.danger => (palette.dangerSurface, palette.dangerForeground),
      _BannerTone.warning => (
        palette.warningSurface,
        palette.warningForeground,
      ),
    };
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: EdgeInsetsDirectional.fromSTEB(
          14,
          10,
          action == null ? 14 : 4,
          10,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: AppRadius.md,
          border: Border.all(color: ink.withValues(alpha: .35)),
        ),
        child: Row(
          children: [
            ExcludeSemantics(child: Icon(icon, size: 20, color: ink)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: AppTypography.bodySmall.copyWith(
                  color: palette.textPrimary,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ),
            if (action != null)
              TextButton(
                key: const ValueKey('page-composer-retry'),
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: ink,
                  minimumSize: const Size(44, 44),
                  textStyle: AppTypography.labelMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: Text(action!),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyPhotos extends StatelessWidget {
  const _EmptyPhotos({
    required this.busy,
    required this.copy,
    required this.onPick,
  });

  final bool busy;
  final PagePostCopy copy;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Container(
      key: const ValueKey('page-composer-photos-empty'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      decoration: BoxDecoration(
        color: palette.surfaceSunken,
        borderRadius: AppRadius.card,
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: [
          ExcludeSemantics(
            child: Icon(
              Icons.add_photo_alternate_outlined,
              size: 30,
              color: palette.interactiveForeground,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            copy.choosePhotosTitle,
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: palette.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          PagesTonalButton(
            key: const ValueKey('page-composer-pick'),
            label: copy.choosePhotos,
            icon: Icons.photo_library_outlined,
            accent: true,
            onPressed: busy ? null : onPick,
          ),
        ],
      ),
    );
  }
}

Widget _plate(String text, {IconData? icon}) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
  decoration: const BoxDecoration(
    color: overlayPlateColor,
    borderRadius: AppRadius.pill,
  ),
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (icon != null) ...[
        Icon(icon, size: 13, color: Colors.white),
        const SizedBox(width: 4),
      ],
      Flexible(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.labelMedium.copyWith(
            color: Colors.white,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    ],
  ),
);

/// The review stage: the selected photo as it will be sent (after the
/// metadata strip), its position, its real size and "Bez lokalizacji".
class _Stage extends StatelessWidget {
  const _Stage({
    required this.height,
    required this.draft,
    required this.index,
    required this.total,
    required this.copy,
  });

  final double height;
  final _PhotoDraft draft;
  final int index;
  final int total;
  final PagePostCopy copy;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final jpeg = draft.jpeg;
    return Container(
      key: const ValueKey('page-composer-stage'),
      height: height,
      decoration: BoxDecoration(
        color: palette.surfaceSunken,
        borderRadius: AppRadius.card,
        border: Border.all(color: palette.border),
      ),
      child: ClipRRect(
        borderRadius: AppRadius.card,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (jpeg != null)
              Semantics(
                image: true,
                label: copy.showPhoto(index + 1, total),
                child: Image.memory(
                  jpeg.bytes,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  excludeFromSemantics: true,
                ),
              )
            else
              Center(
                child: draft.failed
                    ? Icon(
                        Icons.broken_image_outlined,
                        size: 32,
                        color: palette.textTertiary,
                      )
                    : Semantics(
                        label: copy.preparingPhoto,
                        child: const SizedBox.square(
                          dimension: 28,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        ),
                      ),
              ),
            PositionedDirectional(
              start: 8,
              top: 8,
              child: ExcludeSemantics(child: _plate('${index + 1} / $total')),
            ),
            if (jpeg != null) ...[
              PositionedDirectional(
                start: 8,
                bottom: 8,
                child: _plate(
                  copy.megabytes(jpeg.bytes.length),
                  icon: Icons.sd_storage_outlined,
                ),
              ),
              PositionedDirectional(
                end: 8,
                bottom: 8,
                child: _plate(
                  copy.noLocation,
                  icon: Icons.location_off_outlined,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A thumbnail with its index and a remove ✕ (the visible dot is 24, the
/// target 44); while publishing it carries the upload ring, ✓ or !.
class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.draft,
    required this.index,
    required this.total,
    required this.selected,
    required this.uploadState,
    required this.progress,
    required this.showIndex,
    required this.copy,
    required this.onSelect,
    required this.onRemove,
    super.key,
  });

  final _PhotoDraft draft;
  final int index;
  final int total;
  final bool selected;
  final PageUploadState? uploadState;
  final double? progress;
  final bool showIndex;
  final PagePostCopy copy;
  final VoidCallback onSelect;
  final VoidCallback? onRemove;

  static const double size = 72;

  /// How far the remove button's 44 px target reaches past the thumbnail's
  /// top and end. The cell reserves it, so the WHOLE target is inside the
  /// cell and hit-testable (a Stack only hit-tests inside its own size).
  static const double removeOutset = 16;

  /// The cell: thumbnail + the remove target's reach (+ the 12 px gap to
  /// the next thumbnail, which the reach already covers).
  static const double cellWidth = size + 12;
  static const double cellHeight = size + removeOutset;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final jpeg = draft.jpeg;
    final busy = uploadState != null;
    Widget overlay() {
      switch (uploadState) {
        case PageUploadState.failed:
          return Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: palette.dangerForeground,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.priority_high_rounded,
              size: 20,
              color: Colors.white,
            ),
          );
        case PageUploadState.done:
          return Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: palette.successForeground,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              size: 20,
              color: Colors.black,
            ),
          );
        case PageUploadState.uploading:
        case PageUploadState.waiting:
        case null:
          return YoProgressRing(
            value: progress ?? 0,
            size: 30,
            stroke: 3,
            trackColor: Colors.white.withValues(alpha: .28),
            arcColor: Colors.white,
          );
      }
    }

    Widget atThumb(Widget child) => PositionedDirectional(
      start: 0,
      top: removeOutset,
      width: size,
      height: size,
      child: child,
    );
    return SizedBox(
      width: cellWidth,
      height: cellHeight,
      child: Stack(
        children: [
          atThumb(
            Semantics(
              button: true,
              selected: selected,
              label: copy.showPhoto(index + 1, total),
              excludeSemantics: true,
              onTap: busy ? null : onSelect,
              // Focusable with the 2 px ring: Tab reaches every thumbnail
              // and Enter shows it on the stage.
              child: PagesFocusInk(
                key: ValueKey('page-composer-thumb-$index'),
                onTap: busy ? null : onSelect,
                borderRadius: AppRadius.card,
                child: Container(
                  foregroundDecoration: BoxDecoration(
                    borderRadius: AppRadius.card,
                    border: Border.all(color: palette.hairline),
                  ),
                  child: ClipRRect(
                    borderRadius: AppRadius.card,
                    child: jpeg != null
                        ? Image.memory(
                            jpeg.bytes,
                            fit: BoxFit.cover,
                            cacheWidth: 216,
                            gaplessPlayback: true,
                          )
                        : ColoredBox(
                            color: palette.surfaceMuted,
                            child: Center(
                              child: draft.failed
                                  ? Icon(
                                      Icons.error_outline_rounded,
                                      size: 22,
                                      color: palette.dangerForeground,
                                    )
                                  : const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
          if (busy)
            atThumb(
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(
                      alpha: uploadState == PageUploadState.done ? .25 : .5,
                    ),
                    borderRadius: AppRadius.card,
                  ),
                  child: Center(child: overlay()),
                ),
              ),
            ),
          if (selected)
            atThumb(
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: AppRadius.card,
                    border: Border.all(
                      color: palette.interactiveForeground,
                      width: 2.5,
                    ),
                  ),
                ),
              ),
            ),
          if (showIndex)
            PositionedDirectional(
              start: 6,
              bottom: 6,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: const BoxDecoration(
                    color: overlayPlateColor,
                    borderRadius: AppRadius.pill,
                  ),
                  child: Text(
                    '${index + 1}',
                    style: AppTypography.count.copyWith(
                      color: Colors.white,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ),
          if (!busy && onRemove != null)
            // The 44 px target sits wholly inside the cell; its 24 px dot
            // overlaps the thumbnail's top-end corner as rendered.
            PositionedDirectional(
              end: 0,
              top: 0,
              width: 44,
              height: 44,
              child: Semantics(
                button: true,
                label: copy.removePhoto(index + 1),
                excludeSemantics: true,
                onTap: onRemove,
                child: InkResponse(
                  key: ValueKey('page-composer-remove-$index'),
                  onTap: onRemove,
                  radius: 22,
                  child: SizedBox.square(
                    dimension: 44,
                    child: Center(
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: palette.surfaceRaised,
                          shape: BoxShape.circle,
                          border: Border.all(color: palette.borderStrong),
                        ),
                        child: Icon(
                          Icons.close_rounded,
                          size: 15,
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  final String label;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: '$tooltip, $label',
        excludeSemantics: true,
        onTap: onTap,
        child: InkWell(
          key: const ValueKey('page-composer-add'),
          onTap: onTap,
          borderRadius: AppRadius.card,
          child: Container(
            width: _Thumb.size,
            height: _Thumb.size,
            decoration: BoxDecoration(
              color: palette.glass,
              borderRadius: AppRadius.card,
              border: Border.all(color: palette.hairlineControl),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.add_photo_alternate_outlined,
                  size: 22,
                  color: palette.interactiveForeground,
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: AppTypography.count.copyWith(
                    color: palette.textSecondary,
                    fontSize: 11,
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

/// A finished take: the play bead, the silhouette, the clock, delete.
class _Take extends StatelessWidget {
  const _Take({
    required this.durationMs,
    required this.playing,
    required this.progress,
    required this.copy,
    required this.onToggle,
    required this.onDelete,
  });

  final int durationMs;
  final bool playing;
  final double? progress;
  final PagePostCopy copy;
  final VoidCallback onToggle;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final scheme = Theme.of(context).colorScheme;
    final label = playing ? copy.pauseRecording : copy.playRecording;
    return Row(
      children: [
        Semantics(
          button: true,
          label: '$label, ${_clock(durationMs)}',
          excludeSemantics: true,
          onTap: onToggle,
          child: Tooltip(
            message: label,
            excludeFromSemantics: true,
            child: InkResponse(
              key: const ValueKey('page-composer-preview'),
              onTap: onToggle,
              radius: 28,
              child: YoGradientDisc(
                size: 48,
                gloss: true,
                glyph: VoiceBeadGlyph(playing: playing),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppRhythm.item),
        Expanded(
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                YoWaveform(
                  color: palette.waveUnplayed,
                  progress: progress,
                  playedGradient: AppGradients.voicePlayed(scheme, palette),
                  continuousProgress: true,
                  gradientSpan: YoWaveformGradientSpan.full,
                  height: 36,
                  barWidth: 3,
                  barGap: 2,
                  barRadius: 1.5,
                ),
                const SizedBox(height: 4),
                Text(
                  _clock(durationMs),
                  style: AppTypography.bodySmall.copyWith(
                    color: palette.textSecondary,
                    height: 1.1,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 4),
        YoIconButton(
          key: const ValueKey('page-composer-delete-take'),
          icon: Icons.delete_outline_rounded,
          onPressed: onDelete,
          tooltip: copy.deleteRecording,
          size: 44,
          iconSize: 20,
        ),
      ],
    );
  }
}

/// The recorder's live level meter.
class _Meter extends StatelessWidget {
  const _Meter({required this.levels});

  final List<double> levels;

  @override
  Widget build(BuildContext context) {
    const height = 40.0;
    return SizedBox(
      height: height,
      child: Row(
        children: [
          for (final level in levels)
            Expanded(
              child: Center(
                child: Container(
                  width: 4,
                  height: 6 + level * (height - 6),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [AppColors.primary, AppColors.secondary],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
