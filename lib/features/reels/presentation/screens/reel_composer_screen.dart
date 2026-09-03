import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/data/services/reel_upload.dart';
import 'package:yovoice/features/reels/data/services/reel_video_probe.dart';
import 'package:yovoice/features/reels/presentation/reel_visuals.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_composition_canvas.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_local_video_controller.dart';
import 'package:yovoice/shared/widgets/buttons/yo_button.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/overlays/yo_modal_sheet_chrome.dart';
import 'package:yovoice/shared/widgets/states/yo_loading_indicator.dart';

typedef ReelVideoDurationProbe = Future<int> Function(XFile file);
typedef ReelBackingAudioPicker = Future<ReelUploadPayload?> Function();

class ReelComposerScreen extends StatefulWidget {
  const ReelComposerScreen({
    this.service,
    this.imagePicker,
    this.videoDurationProbe,
    this.backingAudioPicker,
    this.audioPlayerFactory,
    this.onPublished,
    super.key,
  });

  final ReelService? service;
  final ImagePicker? imagePicker;

  /// Optional test/platform override. The default uses video_player to decode
  /// the selected file's real duration rather than trusting its filename.
  final ReelVideoDurationProbe? videoDurationProbe;

  /// Optional licensed/user-owned audio source supplied by the host app. No
  /// Spotify/Apple Music URL is downloaded or treated as an audio file.
  final ReelBackingAudioPicker? backingAudioPicker;
  final AudioPlayer Function()? audioPlayerFactory;
  final ValueChanged<String>? onPublished;

  @override
  State<ReelComposerScreen> createState() => _ReelComposerScreenState();
}

class _ReelComposerScreenState extends State<ReelComposerScreen> {
  late final ReelService _service = widget.service ?? ReelService();
  late final ImagePicker _picker = widget.imagePicker ?? ImagePicker();
  final TextEditingController _caption = TextEditingController();

  ReelUploadPayload? _media;
  ReelUploadPayload? _backingAudio;
  ReelComposition _composition = const ReelComposition(originalAudioVolume: 0);
  ReelPublishSession? _session;
  bool _selecting = false;
  bool _publishing = false;
  double _progress = 0;
  String? _error;

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _showSourcePicker() async {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final source = await showModalBottomSheet<_SourceChoice>(
      context: context,
      showDragHandle: false,
      useSafeArea: true,
      isScrollControlled: true,
      constraints: ResponsiveContentFrame.adaptiveModalConstraints(context),
      backgroundColor: Colors.transparent,
      builder: (context) => Material(
        color: palette.surfaceRaised,
        clipBehavior: Clip.antiAlias,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              YoModalSheetChrome(
                sheetLabel: copy.text(
                  'Choose Reel media',
                  'Wybierz multimedia Reela',
                ),
                surfaceColor: palette.surfaceRaised,
              ),
              ListTile(
                minTileHeight: 52,
                leading: const Icon(Icons.photo_camera_outlined),
                title: Text(copy.text('Take photo', 'Zrób zdjęcie')),
                onTap: () => Navigator.pop(
                  context,
                  const _SourceChoice(ReelMediaKind.image, ImageSource.camera),
                ),
              ),
              ListTile(
                minTileHeight: 52,
                leading: const Icon(Icons.photo_library_outlined),
                title: Text(copy.text('Choose photo', 'Wybierz zdjęcie')),
                onTap: () => Navigator.pop(
                  context,
                  const _SourceChoice(ReelMediaKind.image, ImageSource.gallery),
                ),
              ),
              ListTile(
                minTileHeight: 52,
                leading: const Icon(Icons.videocam_outlined),
                title: Text(copy.text('Record video', 'Nagraj film')),
                onTap: () => Navigator.pop(
                  context,
                  const _SourceChoice(ReelMediaKind.video, ImageSource.camera),
                ),
              ),
              ListTile(
                minTileHeight: 52,
                leading: const Icon(Icons.video_library_outlined),
                title: Text(copy.text('Choose video', 'Wybierz film')),
                onTap: () => Navigator.pop(
                  context,
                  const _SourceChoice(ReelMediaKind.video, ImageSource.gallery),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
    if (source == null || _selecting) return;
    setState(() {
      _selecting = true;
      _error = null;
    });
    try {
      final XFile? file = source.kind == ReelMediaKind.image
          ? await _picker.pickImage(source: source.source, imageQuality: 94)
          : await _picker.pickVideo(
              source: source.source,
              maxDuration: const Duration(seconds: 90),
            );
      if (file == null) return;
      var durationMs = 0;
      if (source.kind == ReelMediaKind.video) {
        final probe =
            widget.videoDurationProbe ?? probeSelectedReelVideoDuration;
        durationMs = await probe(file);
      }
      final payload = await ReelUploadPayload.fromXFile(
        file,
        durationMs: durationMs,
      );
      if (!mounted) return;
      setState(() {
        _media = payload;
        _backingAudio = null;
        _session = null;
        _composition = ReelComposition(
          originalAudioVolume: payload.mediaKind == ReelMediaKind.video
              ? 100
              : 0,
          trimEndMs: payload.durationMs,
        );
        _caption.clear();
      });
    } catch (error) {
      if (mounted) setState(() => _error = _friendly(error));
    } finally {
      if (mounted) setState(() => _selecting = false);
    }
  }

  Future<void> _pickBackingAudio() async {
    final picker = widget.backingAudioPicker ?? _pickLocalBackingAudio;
    try {
      final result = await picker();
      if (!mounted || result == null) return;
      if (!result.contentType.startsWith('audio/')) {
        throw const FormatException('Choose a supported audio file.');
      }
      setState(() {
        _backingAudio = result;
        _session = null;
        _composition = _composition.copyWith(
          backingAudioVolume: 70,
          audioRightsAttested: false,
        );
      });
    } catch (error) {
      if (mounted) setState(() => _error = _friendly(error));
    }
  }

  Future<ReelUploadPayload?> _pickLocalBackingAudio() async {
    const group = XTypeGroup(
      label: 'Audio',
      extensions: <String>['mp3', 'm4a', 'wav'],
      mimeTypes: <String>['audio/mpeg', 'audio/mp4', 'audio/wav'],
    );
    final file = await openFile(acceptedTypeGroups: const <XTypeGroup>[group]);
    if (file == null) return null;
    final declaredLength = await file.length();
    if (declaredLength < 512 || declaredLength > maxReelBackingAudioBytes) {
      throw const FormatException('Choose an audio file smaller than 15 MB.');
    }
    final bytes = await file.readAsBytes();
    if (bytes.lengthInBytes != declaredLength) {
      throw const FormatException('The selected audio could not be read.');
    }
    final contentType = sniffReelContentType(bytes);
    if (contentType == null || !contentType.startsWith('audio/')) {
      throw const FormatException('Choose an MP3, M4A or WAV file.');
    }
    final player = AudioPlayer();
    try {
      await player.setSource(BytesSource(bytes, mimeType: contentType));
      final duration =
          await player.getDuration() ??
          await player.onDurationChanged.first.timeout(
            const Duration(seconds: 8),
          );
      return ReelUploadPayload.backingAudio(
        bytes: bytes,
        durationMs: duration.inMilliseconds,
      );
    } finally {
      await player.dispose();
    }
  }

  Future<void> _addTextOverlay() async {
    final copy = AppLocalizations.of(context);
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(copy.text('Add text', 'Dodaj tekst')),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 120,
          maxLines: 3,
          decoration: InputDecoration(labelText: copy.text('Text', 'Tekst')),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(copy.text('Cancel', 'Anuluj')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(copy.text('Add', 'Dodaj')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text == null || text.isEmpty) return;
    setState(() {
      _session = null;
      _composition = _composition.copyWith(
        textOverlays: <ReelTextOverlay>[
          ..._composition.textOverlays,
          ReelTextOverlay(
            id: 'text_${DateTime.now().microsecondsSinceEpoch}',
            text: text,
            x: .5,
            y: .42,
          ),
        ],
      );
    });
  }

  Future<void> _addLinkOverlay() async {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final label = TextEditingController();
    final url = TextEditingController();
    String? validationError;
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(copy.text('Add link', 'Dodaj link')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: label,
                  maxLength: 60,
                  decoration: InputDecoration(
                    labelText: copy.text('Button label', 'Nazwa przycisku'),
                  ),
                ),
                TextField(
                  controller: url,
                  keyboardType: TextInputType.url,
                  autofillHints: const <String>[AutofillHints.url],
                  decoration: const InputDecoration(labelText: 'https://'),
                ),
                if (validationError != null) ...<Widget>[
                  const SizedBox(height: 10),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      validationError!,
                      style: TextStyle(
                        color: palette.dangerForeground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(copy.text('Cancel', 'Anuluj')),
            ),
            FilledButton(
              onPressed: () {
                final cleanLabel = label.text.trim();
                final cleanUrl = url.text.trim();
                final uri = Uri.tryParse(cleanUrl);
                if (cleanLabel.isEmpty ||
                    uri == null ||
                    !isSafePublicHttpsUri(uri)) {
                  setDialogState(() {
                    validationError = copy.text(
                      'Enter a label and a public HTTPS link.',
                      'Wpisz nazwę i publiczny link HTTPS.',
                    );
                  });
                  return;
                }
                Navigator.pop(context, (cleanLabel, cleanUrl));
              },
              child: Text(copy.text('Add', 'Dodaj')),
            ),
          ],
        ),
      ),
    );
    label.dispose();
    url.dispose();
    if (result == null) return;
    final uri = Uri.tryParse(result.$2);
    if (uri == null || !isSafePublicHttpsUri(uri) || result.$1.isEmpty) return;
    setState(() {
      _session = null;
      _composition = _composition.copyWith(
        linkOverlays: <ReelLinkOverlay>[
          ..._composition.linkOverlays,
          ReelLinkOverlay(
            id: 'link_${DateTime.now().microsecondsSinceEpoch}',
            label: result.$1,
            uri: uri,
            x: .5,
            y: .62,
          ),
        ],
      );
    });
  }

  Future<void> _editTextOverlay(ReelTextOverlay source) async {
    final copy = AppLocalizations.of(context);
    final controller = TextEditingController(text: source.text);
    var x = source.x;
    var y = source.y;
    var scale = source.scale;
    var color = source.color;
    final result = await showDialog<ReelTextOverlay>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(copy.text('Edit text', 'Edytuj tekst')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(controller: controller, maxLength: 120, maxLines: 3),
                _PositionSlider(
                  label: copy.text('Horizontal position', 'Pozycja pozioma'),
                  value: x,
                  onChanged: (value) => setDialogState(() => x = value),
                ),
                _PositionSlider(
                  label: copy.text('Vertical position', 'Pozycja pionowa'),
                  value: y,
                  onChanged: (value) => setDialogState(() => y = value),
                ),
                Semantics(
                  label: copy.text('Text size', 'Rozmiar tekstu'),
                  value: '${scale.toStringAsFixed(2)}×',
                  child: Slider(
                    value: scale,
                    min: .75,
                    max: 2,
                    divisions: 25,
                    label: '${scale.toStringAsFixed(2)}×',
                    semanticFormatterCallback: (value) =>
                        '${value.toStringAsFixed(2)}×',
                    onChanged: (value) => setDialogState(() => scale = value),
                  ),
                ),
                DropdownButtonFormField<ReelOverlayColor>(
                  initialValue: color,
                  decoration: InputDecoration(
                    labelText: copy.text('Colour', 'Kolor'),
                  ),
                  items: ReelOverlayColor.values
                      .map(
                        (value) => DropdownMenuItem<ReelOverlayColor>(
                          value: value,
                          child: Text(localizedReelOverlayColor(copy, value)),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value != null) setDialogState(() => color = value);
                  },
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(copy.text('Cancel', 'Anuluj')),
            ),
            FilledButton(
              onPressed: () {
                final text = controller.text.trim();
                if (text.isEmpty) return;
                Navigator.pop(
                  context,
                  ReelTextOverlay(
                    id: source.id,
                    text: text,
                    x: x,
                    y: y,
                    scale: scale,
                    color: color,
                  ),
                );
              },
              child: Text(copy.text('Save', 'Zapisz')),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result == null) return;
    setState(() {
      _session = null;
      _composition = _composition.copyWith(
        textOverlays: _composition.textOverlays
            .map((item) => item.id == result.id ? result : item)
            .toList(growable: false),
      );
    });
  }

  Future<void> _editLinkOverlay(ReelLinkOverlay source) async {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final label = TextEditingController(text: source.label);
    final url = TextEditingController(text: source.uri.toString());
    var x = source.x;
    var y = source.y;
    String? validationError;
    final result = await showDialog<ReelLinkOverlay>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(copy.text('Edit link', 'Edytuj link')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(controller: label, maxLength: 60),
                TextField(
                  controller: url,
                  keyboardType: TextInputType.url,
                  autofillHints: const <String>[AutofillHints.url],
                ),
                if (validationError != null) ...<Widget>[
                  const SizedBox(height: 10),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      validationError!,
                      style: TextStyle(
                        color: palette.dangerForeground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                _PositionSlider(
                  label: copy.text('Horizontal position', 'Pozycja pozioma'),
                  value: x,
                  onChanged: (value) => setDialogState(() => x = value),
                ),
                _PositionSlider(
                  label: copy.text('Vertical position', 'Pozycja pionowa'),
                  value: y,
                  onChanged: (value) => setDialogState(() => y = value),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(copy.text('Cancel', 'Anuluj')),
            ),
            FilledButton(
              onPressed: () {
                final uri = Uri.tryParse(url.text.trim());
                if (label.text.trim().isEmpty ||
                    uri == null ||
                    !isSafePublicHttpsUri(uri)) {
                  setDialogState(() {
                    validationError = copy.text(
                      'Enter a label and a public HTTPS link.',
                      'Wpisz nazwę i publiczny link HTTPS.',
                    );
                  });
                  return;
                }
                Navigator.pop(
                  context,
                  ReelLinkOverlay(
                    id: source.id,
                    label: label.text.trim(),
                    uri: uri,
                    x: x,
                    y: y,
                  ),
                );
              },
              child: Text(copy.text('Save', 'Zapisz')),
            ),
          ],
        ),
      ),
    );
    label.dispose();
    url.dispose();
    if (result == null) return;
    setState(() {
      _session = null;
      _composition = _composition.copyWith(
        linkOverlays: _composition.linkOverlays
            .map((item) => item.id == result.id ? result : item)
            .toList(growable: false),
      );
    });
  }

  Future<void> _publish() async {
    final media = _media;
    if (media == null || _publishing) return;
    final composition = _composition.copyWith(caption: _caption.text);
    final plan = ReelDraftPlan(
      media: media,
      backingAudio: _backingAudio,
      composition: composition,
    );
    final problem = plan.validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _publishing = true;
      _error = null;
      _progress = 0;
    });
    try {
      final session = _session ??= ReelPublishSession(plan: plan);
      final reelId = await _service.publish(
        session,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
      if (!mounted) return;
      widget.onPublished?.call(reelId);
      if (Navigator.of(context).canPop()) Navigator.of(context).pop(reelId);
    } catch (error) {
      if (mounted) setState(() => _error = _friendly(error));
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    return Scaffold(
      appBar: AppBar(title: Text(copy.text('Create Reel', 'Utwórz Reel'))),
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: palette.backgroundGradient),
        child: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final preview = _Preview(
                media: _media,
                composition: _composition,
                selecting: _selecting,
                onSelect: _showSourcePicker,
              );
              final editor = _Editor(
                media: _media,
                backingAudio: _backingAudio,
                composition: _composition,
                caption: _caption,
                canPickAudio: true,
                audioPlayerFactory: widget.audioPlayerFactory,
                onCaptionChanged: (_) {
                  if (_session != null) setState(() => _session = null);
                },
                onComposition: (value) {
                  setState(() {
                    _composition = value;
                    _session = null;
                  });
                },
                onPickAudio: _pickBackingAudio,
                onRemoveAudio: () {
                  setState(() {
                    _backingAudio = null;
                    _session = null;
                    _composition = _composition.copyWith(
                      backingAudioVolume: 0,
                      audioTrimStartMs: 0,
                      audioRightsAttested: false,
                      audioAttribution: '',
                    );
                  });
                },
                onAddText: _addTextOverlay,
                onAddLink: _addLinkOverlay,
                onEditText: _editTextOverlay,
                onEditLink: _editLinkOverlay,
              );
              final content = constraints.maxWidth >= 900
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(child: preview),
                        const SizedBox(width: 28),
                        Expanded(child: editor),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        preview,
                        const SizedBox(height: 24),
                        editor,
                      ],
                    );
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1120),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        content,
                        if (_error != null) ...<Widget>[
                          const SizedBox(height: 16),
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: palette.dangerForeground,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        YoButton(
                          label: _publishing
                              ? copy.template(
                                  'Publishing {percent}%',
                                  'Publikowanie {percent}%',
                                  values: <String, Object>{
                                    'percent': (_progress * 100).round(),
                                  },
                                )
                              : copy.text('Publish Reel', 'Opublikuj Reel'),
                          onPressed: _media == null || _publishing
                              ? null
                              : _publish,
                          isLoading: _publishing,
                          icon: const Icon(Icons.publish_rounded),
                        ),
                      ],
                    ),
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

class _Preview extends StatelessWidget {
  const _Preview({
    required this.media,
    required this.composition,
    required this.selecting,
    required this.onSelect,
  });

  final ReelUploadPayload? media;
  final ReelComposition composition;
  final bool selecting;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    return AspectRatio(
      aspectRatio: 9 / 16,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.surfaceSunken,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: palette.borderStrong),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(27),
          child: media == null
              ? Center(
                  child: YoButton(
                    label: selecting
                        ? copy.text('Opening media', 'Otwieranie multimediów')
                        : copy.text('Choose media', 'Wybierz multimedia'),
                    onPressed: selecting ? null : onSelect,
                    fullWidth: false,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                  ),
                )
              : Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    if (media!.mediaKind == ReelMediaKind.image)
                      ReelCompositionCanvas(
                        composition: composition,
                        media: Image.memory(
                          media!.bytes,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.high,
                        ),
                      )
                    else
                      _LocalReelVideoPreview(
                        media: media!,
                        composition: composition,
                      ),
                    PositionedDirectional(
                      top: 12,
                      end: 12,
                      child: IconButton.filledTonal(
                        tooltip: copy.text('Replace media', 'Zmień multimedia'),
                        onPressed: onSelect,
                        icon: const Icon(Icons.swap_horiz_rounded),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _LocalReelVideoPreview extends StatefulWidget {
  const _LocalReelVideoPreview({
    required this.media,
    required this.composition,
  });

  final ReelUploadPayload media;
  final ReelComposition composition;

  @override
  State<_LocalReelVideoPreview> createState() => _LocalReelVideoPreviewState();
}

class _LocalReelVideoPreviewState extends State<_LocalReelVideoPreview> {
  VideoPlayerController? _controller;
  Object? _error;
  bool _seekingToStart = false;
  bool _wasPlaying = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void didUpdateWidget(covariant _LocalReelVideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.media.sourcePath != widget.media.sourcePath) {
      _disposeController();
      _initialize();
      return;
    }
    if (oldWidget.composition.originalAudioVolume !=
        widget.composition.originalAudioVolume) {
      unawaited(
        _controller?.setVolume(widget.composition.originalAudioVolume / 100),
      );
    }
    if (oldWidget.composition.trimStartMs != widget.composition.trimStartMs ||
        oldWidget.composition.trimEndMs != widget.composition.trimEndMs) {
      final position = _controller?.value.position.inMilliseconds ?? 0;
      if (position < widget.composition.trimStartMs ||
          position >= widget.composition.trimEndMs) {
        unawaited(
          _controller?.seekTo(
            Duration(milliseconds: widget.composition.trimStartMs),
          ),
        );
      }
    }
  }

  Future<void> _initialize() async {
    final sourcePath = widget.media.sourcePath?.trim() ?? '';
    if (sourcePath.isEmpty) {
      setState(() => _error = StateError('Missing local video preview.'));
      return;
    }
    final controller = createReelLocalVideoController(sourcePath);
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setLooping(false);
      await controller.setVolume(widget.composition.originalAudioVolume / 100);
      await controller.seekTo(
        Duration(milliseconds: widget.composition.trimStartMs),
      );
      _wasPlaying = controller.value.isPlaying;
      controller.addListener(_handlePlayback);
      if (mounted) setState(() => _error = null);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  void _handlePlayback() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final end = widget.composition.trimEndMs;
    if (!_seekingToStart &&
        end > 0 &&
        controller.value.position.inMilliseconds >= end) {
      _seekingToStart = true;
      unawaited(_rewind(controller));
      return;
    }
    final isPlaying = controller.value.isPlaying;
    if (mounted && isPlaying != _wasPlaying) {
      _wasPlaying = isPlaying;
      setState(() {});
    }
  }

  Future<void> _rewind(VideoPlayerController controller) async {
    try {
      await controller.pause();
      await controller.seekTo(
        Duration(milliseconds: widget.composition.trimStartMs),
      );
    } finally {
      _seekingToStart = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _toggle() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      final position = controller.value.position.inMilliseconds;
      if (position < widget.composition.trimStartMs ||
          position >= widget.composition.trimEndMs) {
        await controller.seekTo(
          Duration(milliseconds: widget.composition.trimStartMs),
        );
      }
      await controller.play();
    }
    if (mounted) setState(() {});
  }

  void _disposeController() {
    final controller = _controller;
    _controller = null;
    _wasPlaying = false;
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
    Widget media;
    if (_error != null) {
      media = ColoredBox(
        color: palette.surfaceSunken,
        child: Center(
          child: TextButton.icon(
            onPressed: () {
              _disposeController();
              setState(() => _error = null);
              _initialize();
            },
            icon: const Icon(Icons.refresh_rounded),
            label: Text(
              copy.text('Retry video preview', 'Ponów podgląd filmu'),
            ),
          ),
        ),
      );
    } else if (controller == null || !controller.value.isInitialized) {
      media = YoLoadingIndicator(
        message: copy.text(
          'Preparing video preview',
          'Przygotowywanie podglądu',
        ),
      );
    } else {
      media = FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: controller.value.size.width,
          height: controller.value.size.height,
          child: VideoPlayer(controller),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        ReelCompositionCanvas(composition: widget.composition, media: media),
        if (controller != null && controller.value.isInitialized)
          Center(
            child: IconButton.filled(
              key: const ValueKey('reel-local-video-playback'),
              tooltip: controller.value.isPlaying
                  ? copy.text('Pause video preview', 'Wstrzymaj podgląd filmu')
                  : copy.text('Play video preview', 'Odtwórz podgląd filmu'),
              onPressed: _toggle,
              iconSize: 30,
              constraints: const BoxConstraints.tightFor(width: 52, height: 52),
              icon: Icon(
                controller.value.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
              ),
            ),
          ),
      ],
    );
  }
}

class _Editor extends StatelessWidget {
  const _Editor({
    required this.media,
    required this.backingAudio,
    required this.composition,
    required this.caption,
    required this.canPickAudio,
    required this.audioPlayerFactory,
    required this.onCaptionChanged,
    required this.onComposition,
    required this.onPickAudio,
    required this.onRemoveAudio,
    required this.onAddText,
    required this.onAddLink,
    required this.onEditText,
    required this.onEditLink,
  });

  final ReelUploadPayload? media;
  final ReelUploadPayload? backingAudio;
  final ReelComposition composition;
  final TextEditingController caption;
  final bool canPickAudio;
  final AudioPlayer Function()? audioPlayerFactory;
  final ValueChanged<String> onCaptionChanged;
  final ValueChanged<ReelComposition> onComposition;
  final VoidCallback onPickAudio;
  final VoidCallback onRemoveAudio;
  final VoidCallback onAddText;
  final VoidCallback onAddLink;
  final ValueChanged<ReelTextOverlay> onEditText;
  final ValueChanged<ReelLinkOverlay> onEditLink;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: palette.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              controller: caption,
              onChanged: onCaptionChanged,
              maxLength: 2200,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: copy.text('Caption', 'Opis'),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            Text(copy.text('Crop and position', 'Kadr i położenie')),
            Semantics(
              label: copy.text('Crop zoom', 'Powiększenie kadru'),
              value: '${composition.crop.scale.toStringAsFixed(1)}×',
              child: Slider(
                value: composition.crop.scale,
                min: 1,
                max: 8,
                divisions: 28,
                label: '${composition.crop.scale.toStringAsFixed(1)}×',
                semanticFormatterCallback: (value) =>
                    '${value.toStringAsFixed(1)}×',
                onChanged: media == null
                    ? null
                    : (value) => onComposition(
                        composition.copyWith(
                          crop: composition.crop.copyWith(scale: value),
                        ),
                      ),
              ),
            ),
            Row(
              children: <Widget>[
                Expanded(
                  child: Semantics(
                    label: copy.text(
                      'Horizontal crop position',
                      'Pozioma pozycja kadru',
                    ),
                    value: '${(composition.crop.offsetX * 100).round()}%',
                    child: Slider(
                      value: composition.crop.offsetX,
                      min: -1,
                      max: 1,
                      semanticFormatterCallback: (value) =>
                          '${(value * 100).round()}%',
                      onChanged: media == null
                          ? null
                          : (value) => onComposition(
                              composition.copyWith(
                                crop: composition.crop.copyWith(offsetX: value),
                              ),
                            ),
                    ),
                  ),
                ),
                Expanded(
                  child: Semantics(
                    label: copy.text(
                      'Vertical crop position',
                      'Pionowa pozycja kadru',
                    ),
                    value: '${(composition.crop.offsetY * 100).round()}%',
                    child: Slider(
                      value: composition.crop.offsetY,
                      min: -1,
                      max: 1,
                      semanticFormatterCallback: (value) =>
                          '${(value * 100).round()}%',
                      onChanged: media == null
                          ? null
                          : (value) => onComposition(
                              composition.copyWith(
                                crop: composition.crop.copyWith(offsetY: value),
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(copy.text('Filter', 'Filtr')),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ReelFilter.values
                  .map(
                    (filter) => ChoiceChip(
                      label: Text(localizedReelFilter(copy, filter)),
                      selected: composition.filter == filter,
                      onSelected: media == null
                          ? null
                          : (_) => onComposition(
                              composition.copyWith(filter: filter),
                            ),
                    ),
                  )
                  .toList(growable: false),
            ),
            if (media?.mediaKind == ReelMediaKind.video) ...<Widget>[
              const SizedBox(height: 18),
              Text(copy.text('Trim video', 'Przytnij film')),
              Semantics(
                label: copy.text('Video trim range', 'Zakres przycięcia filmu'),
                value:
                    '${composition.trimStartMs ~/ 1000}–${composition.trimEndMs ~/ 1000} s',
                child: RangeSlider(
                  values: RangeValues(
                    composition.trimStartMs / 1000,
                    composition.trimEndMs / 1000,
                  ),
                  min: 0,
                  max: media!.durationMs / 1000,
                  labels: RangeLabels(
                    '${composition.trimStartMs ~/ 1000}s',
                    '${composition.trimEndMs ~/ 1000}s',
                  ),
                  onChanged: (values) => onComposition(
                    composition.copyWith(
                      trimStartMs: (values.start * 1000).round(),
                      trimEndMs: (values.end * 1000).round(),
                    ),
                  ),
                ),
              ),
              Text(copy.text('Original video audio', 'Dźwięk z filmu')),
              Semantics(
                label: copy.text(
                  'Original video audio volume',
                  'Głośność dźwięku z filmu',
                ),
                value: '${composition.originalAudioVolume}%',
                child: Slider(
                  value: composition.originalAudioVolume.toDouble(),
                  min: 0,
                  max: 100,
                  divisions: 20,
                  label: '${composition.originalAudioVolume}%',
                  semanticFormatterCallback: (value) => '${value.round()}%',
                  onChanged: (value) => onComposition(
                    composition.copyWith(originalAudioVolume: value.round()),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: composition.textOverlays.length >= 8
                      ? null
                      : onAddText,
                  icon: const Icon(Icons.text_fields_rounded),
                  label: Text(copy.text('Add text', 'Dodaj tekst')),
                ),
                OutlinedButton.icon(
                  onPressed: composition.linkOverlays.length >= 4
                      ? null
                      : onAddLink,
                  icon: const Icon(Icons.link_rounded),
                  label: Text(copy.text('Add link', 'Dodaj link')),
                ),
                if (canPickAudio && backingAudio == null)
                  OutlinedButton.icon(
                    onPressed: onPickAudio,
                    icon: const Icon(Icons.music_note_rounded),
                    label: Text(
                      copy.text('Add your audio', 'Dodaj własny dźwięk'),
                    ),
                  ),
              ],
            ),
            if (composition.textOverlays.isNotEmpty ||
                composition.linkOverlays.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: <Widget>[
                  ...composition.textOverlays.map(
                    (item) => InputChip(
                      label: Text(item.text),
                      onPressed: () => onEditText(item),
                      onDeleted: () => onComposition(
                        composition.copyWith(
                          textOverlays: composition.textOverlays
                              .where((entry) => entry.id != item.id)
                              .toList(growable: false),
                        ),
                      ),
                    ),
                  ),
                  ...composition.linkOverlays.map(
                    (item) => InputChip(
                      avatar: const Icon(Icons.link_rounded, size: 18),
                      label: Text(item.label),
                      onPressed: () => onEditLink(item),
                      onDeleted: () => onComposition(
                        composition.copyWith(
                          linkOverlays: composition.linkOverlays
                              .where((entry) => entry.id != item.id)
                              .toList(growable: false),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (backingAudio != null) ...<Widget>[
              const SizedBox(height: 18),
              _BackingAudioControls(
                payload: backingAudio!,
                composition: composition,
                playerFactory: audioPlayerFactory,
                onComposition: onComposition,
                onRemove: onRemoveAudio,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BackingAudioControls extends StatefulWidget {
  const _BackingAudioControls({
    required this.payload,
    required this.composition,
    required this.onComposition,
    required this.onRemove,
    this.playerFactory,
  });

  final ReelUploadPayload payload;
  final ReelComposition composition;
  final ValueChanged<ReelComposition> onComposition;
  final VoidCallback onRemove;
  final AudioPlayer Function()? playerFactory;

  @override
  State<_BackingAudioControls> createState() => _BackingAudioControlsState();
}

class _BackingAudioControlsState extends State<_BackingAudioControls> {
  late final AudioPlayer _player =
      widget.playerFactory?.call() ?? AudioPlayer();
  StreamSubscription<PlayerState>? _stateSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  bool _sourceLoaded = false;
  bool _loading = false;
  bool _playing = false;
  bool _enforcingEnd = false;
  Duration _position = Duration.zero;
  Object? _playbackError;

  int get _previewEndMs {
    final selectedVideoMs =
        widget.composition.trimEndMs - widget.composition.trimStartMs;
    final requestedEnd = selectedVideoMs > 0
        ? widget.composition.audioTrimStartMs + selectedVideoMs
        : widget.payload.durationMs;
    return math.min(widget.payload.durationMs, requestedEnd);
  }

  @override
  void initState() {
    super.initState();
    _stateSubscription = _player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() => _playing = state == PlayerState.playing);
    });
    _positionSubscription = _player.onPositionChanged.listen((position) {
      if (!mounted) return;
      setState(() => _position = position);
      if (!_enforcingEnd && position.inMilliseconds >= _previewEndMs) {
        _enforcingEnd = true;
        unawaited(_rewindPreview());
      }
    });
  }

  @override
  void didUpdateWidget(covariant _BackingAudioControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.payload.bytes, widget.payload.bytes)) {
      _sourceLoaded = false;
      _position = Duration.zero;
      _playbackError = null;
      unawaited(_player.stop());
    }
    if (oldWidget.composition.backingAudioVolume !=
        widget.composition.backingAudioVolume) {
      unawaited(_player.setVolume(widget.composition.backingAudioVolume / 100));
    }
    if (oldWidget.composition.audioTrimStartMs !=
        widget.composition.audioTrimStartMs) {
      final start = Duration(milliseconds: widget.composition.audioTrimStartMs);
      _position = start;
      if (_sourceLoaded) unawaited(_player.seek(start));
    }
  }

  Future<void> _rewindPreview() async {
    try {
      await _player.pause();
      final start = Duration(milliseconds: widget.composition.audioTrimStartMs);
      await _player.seek(start);
      if (mounted) setState(() => _position = start);
    } finally {
      _enforcingEnd = false;
    }
  }

  Future<void> _togglePreview() async {
    if (_loading) return;
    if (_playing) {
      await _player.pause();
      return;
    }
    setState(() {
      _loading = true;
      _playbackError = null;
    });
    try {
      var sourceWasLoadedNow = false;
      if (!_sourceLoaded) {
        await _player.setSource(
          BytesSource(
            widget.payload.bytes,
            mimeType: widget.payload.contentType,
          ),
        );
        _sourceLoaded = true;
        sourceWasLoadedNow = true;
      }
      await _player.setVolume(widget.composition.backingAudioVolume / 100);
      final startMs = widget.composition.audioTrimStartMs;
      if (sourceWasLoadedNow ||
          _position.inMilliseconds < startMs ||
          _position.inMilliseconds >= _previewEndMs) {
        final start = Duration(milliseconds: startMs);
        await _player.seek(start);
        _position = start;
      }
      await _player.resume();
    } catch (error) {
      if (mounted) setState(() => _playbackError = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    unawaited(_stateSubscription?.cancel());
    unawaited(_positionSubscription?.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final maxTrimStartMs = math.max(0, widget.payload.durationMs - 1000);
    return Material(
      color: palette.surfaceRaised,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: palette.borderStrong),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                IconButton.filledTonal(
                  key: const ValueKey('reel-backing-audio-preview'),
                  tooltip: _playing
                      ? copy.text('Pause backing audio', 'Wstrzymaj podkład')
                      : copy.text('Preview backing audio', 'Odsłuchaj podkład'),
                  onPressed: _loading ? null : _togglePreview,
                  constraints: const BoxConstraints.tightFor(
                    width: 44,
                    height: 44,
                  ),
                  icon: _loading
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        copy.text(
                          'Your backing audio',
                          'Twój podkład dźwiękowy',
                        ),
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '${_formatDuration(_position)} / '
                        '${_formatDuration(Duration(milliseconds: widget.payload.durationMs))}',
                        style: TextStyle(color: palette.textSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: copy.text('Remove audio', 'Usuń dźwięk'),
                  onPressed: widget.onRemove,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            if (_playbackError != null) ...<Widget>[
              const SizedBox(height: 8),
              Semantics(
                liveRegion: true,
                child: Text(
                  copy.text(
                    'This audio cannot be previewed. Try again.',
                    'Nie można odsłuchać tego dźwięku. Spróbuj ponownie.',
                  ),
                  style: TextStyle(
                    color: palette.dangerForeground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(copy.text('Backing audio volume', 'Głośność podkładu')),
            Semantics(
              label: copy.text('Backing audio volume', 'Głośność podkładu'),
              value: '${widget.composition.backingAudioVolume}%',
              child: Slider(
                value: widget.composition.backingAudioVolume.toDouble(),
                min: 0,
                max: 100,
                divisions: 20,
                label: '${widget.composition.backingAudioVolume}%',
                semanticFormatterCallback: (value) => '${value.round()}%',
                onChanged: (value) => widget.onComposition(
                  widget.composition.copyWith(
                    backingAudioVolume: value.round(),
                  ),
                ),
              ),
            ),
            Text(copy.text('Audio start', 'Początek podkładu')),
            Semantics(
              label: copy.text(
                'Backing audio start position',
                'Początek podkładu dźwiękowego',
              ),
              value: '${widget.composition.audioTrimStartMs ~/ 1000} s',
              child: Slider(
                value: widget.composition.audioTrimStartMs
                    .clamp(0, maxTrimStartMs)
                    .toDouble(),
                min: 0,
                max: math.max(1, maxTrimStartMs).toDouble(),
                divisions: maxTrimStartMs <= 0
                    ? null
                    : math.min(90, math.max(1, maxTrimStartMs ~/ 1000)),
                label: '${widget.composition.audioTrimStartMs ~/ 1000} s',
                semanticFormatterCallback: (value) =>
                    '${(value / 1000).round()} s',
                onChanged: maxTrimStartMs <= 0
                    ? null
                    : (value) => widget.onComposition(
                        widget.composition.copyWith(
                          audioTrimStartMs: value.round(),
                        ),
                      ),
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: widget.composition.audioRightsAttested,
              onChanged: (value) => widget.onComposition(
                widget.composition.copyWith(
                  audioRightsAttested: value ?? false,
                ),
              ),
              title: Text(
                copy.text(
                  'I created this audio or have permission to use it.',
                  'Ten dźwięk jest mój lub mam zgodę na jego użycie.',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDuration(Duration duration) {
  final total = duration.inSeconds;
  return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
}

@immutable
class _SourceChoice {
  const _SourceChoice(this.kind, this.source);

  final ReelMediaKind kind;
  final ImageSource source;
}

class _PositionSlider extends StatelessWidget {
  const _PositionSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      value: '${(value * 100).round()}%',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(label),
          Slider(
            value: value,
            min: 0,
            max: 1,
            divisions: 20,
            semanticFormatterCallback: (value) => '${(value * 100).round()}%',
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

String _friendly(Object error) {
  if (error is FormatException) return error.message.toString();
  if (error is StateError) return error.message;
  return 'The Reel could not be prepared. Try again.';
}
