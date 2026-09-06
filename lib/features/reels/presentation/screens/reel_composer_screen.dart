import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/reels/data/models/reel.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/data/services/reel_upload.dart';
import 'package:yovoice/features/reels/data/services/reel_video_probe.dart';
import 'package:yovoice/features/reels/presentation/reel_visuals.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_draft_preview.dart';
import 'package:yovoice/shared/widgets/buttons/yo_button.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/overlays/yo_modal_sheet_chrome.dart';

typedef ReelVideoDurationProbe = Future<int> Function(XFile file);
typedef ReelBackingAudioPicker = Future<ReelUploadPayload?> Function();

enum _ComposerStep { media, edit, review }

enum _EditorTool { crop, audio, text, filter }

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
  ReelAvailabilityChoice _availability = ReelAvailabilityChoice.fallback;
  bool _selecting = false;
  bool _publishing = false;
  double _progress = 0;
  String? _error;
  _ComposerStep _step = _ComposerStep.media;
  _EditorTool _tool = _EditorTool.crop;
  final _previewKey = GlobalKey<ReelDraftPreviewState>();
  bool _previewPlaying = false;
  bool _pickingAudio = false;
  bool _sourcePickerOpen = false;
  final _scroll = ScrollController();
  bool _allowExit = false;
  final _errorKey = GlobalKey();
  StreamSubscription<String?>? _identitySubscription;
  String? _ownerId;
  int _identityGeneration = 0;
  final Set<Route<dynamic>> _draftModals = {};

  @override
  void initState() {
    super.initState();
    _ownerId = _service.currentUserId;
    _identitySubscription = _service.identityChanges.listen(
      _identityChanged,
      onError: (Object _) => _identityChanged(null, force: true),
    );
  }

  bool _ownsDraft(int generation) =>
      mounted &&
      generation == _identityGeneration &&
      _ownerId == _service.currentUserId;

  void _identityChanged(String? uid, {bool force = false}) {
    if (!mounted || (!force && uid == _ownerId)) return;
    _identityGeneration++;
    unawaited(_previewKey.currentState?.pause());
    for (final route in _draftModals.toList()) {
      if (route.isActive) route.navigator?.removeRoute(route);
    }
    _draftModals.clear();
    setState(() {
      _ownerId = uid;
      _media = null;
      _backingAudio = null;
      _session = null;
      _composition = const ReelComposition(originalAudioVolume: 0);
      _availability = ReelAvailabilityChoice.fallback;
      _caption.clear();
      _step = _ComposerStep.media;
      _tool = _EditorTool.crop;
      _selecting = false;
      _pickingAudio = false;
      _publishing = false;
      _sourcePickerOpen = false;
      _previewPlaying = false;
      _allowExit = false;
      _error = null;
    });
  }

  Future<T?> _showDraftDialog<T>({
    required BuildContext context,
    required WidgetBuilder builder,
  }) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<T>(
      context: context,
      builder: builder,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      barrierColor: DialogTheme.of(context).barrierColor ?? Colors.black54,
      traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
    );
    _draftModals.add(route);
    try {
      final result = await navigator.push(route);
      // Popping resolves the result before the reverse transition unmounts its
      // text fields. Their local controllers must outlive that transition.
      await route.completed;
      return result;
    } finally {
      _draftModals.remove(route);
    }
  }

  Widget _rememberDraftModal(BuildContext context, Widget child) {
    final route = ModalRoute.of(context);
    _draftModals.removeWhere((entry) => !entry.isActive);
    if (route != null) _draftModals.add(route);
    return child;
  }

  void _showError(Object error) {
    if (!mounted) return;
    final generation = _identityGeneration;
    setState(() => _error = _friendly(context, error));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _errorKey.currentContext;
      if (!_ownsDraft(generation) || target == null) return;
      unawaited(
        Scrollable.ensureVisible(
          target,
          alignment: .5,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
        ),
      );
    });
  }

  bool get _draftContractLocked => _session != null || _publishing;

  @override
  void dispose() {
    _identityGeneration++;
    unawaited(_identitySubscription?.cancel());
    _scroll.dispose();
    _caption.dispose();
    super.dispose();
  }

  Future<void> _showSourcePicker() async {
    final generation = _identityGeneration;
    if (_draftContractLocked || _selecting || _sourcePickerOpen) return;
    _sourcePickerOpen = true;
    await _previewKey.currentState?.pause();
    if (!mounted || !_ownsDraft(generation)) return;
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    if (_media != null) {
      final replace = await _showDraftDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(copy.text('Replace media?', 'Zmienić multimedia?')),
          content: Text(
            copy.text(
              'Your caption, audio and overlays stay. Crop and video trim will reset.',
              'Opis, dźwięk i nakładki zostaną zachowane. Kadr i przycięcie filmu zostaną zresetowane.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(copy.text('Cancel', 'Anuluj')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(copy.text('Replace media', 'Zmień multimedia')),
            ),
          ],
        ),
      );
      if (!mounted || !_ownsDraft(generation)) return;
      if (replace != true) {
        _sourcePickerOpen = false;
        return;
      }
    }
    final source = await showModalBottomSheet<_SourceChoice>(
      context: context,
      showDragHandle: false,
      useSafeArea: true,
      isScrollControlled: true,
      constraints: ResponsiveContentFrame.adaptiveModalConstraints(context),
      backgroundColor: Colors.transparent,
      builder: (context) => _rememberDraftModal(
        context,
        Material(
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
                    const _SourceChoice(
                      ReelMediaKind.image,
                      ImageSource.camera,
                    ),
                  ),
                ),
                ListTile(
                  minTileHeight: 52,
                  leading: const Icon(Icons.photo_library_outlined),
                  title: Text(copy.text('Choose photo', 'Wybierz zdjęcie')),
                  onTap: () => Navigator.pop(
                    context,
                    const _SourceChoice(
                      ReelMediaKind.image,
                      ImageSource.gallery,
                    ),
                  ),
                ),
                ListTile(
                  minTileHeight: 52,
                  leading: const Icon(Icons.videocam_outlined),
                  title: Text(copy.text('Record video', 'Nagraj film')),
                  onTap: () => Navigator.pop(
                    context,
                    const _SourceChoice(
                      ReelMediaKind.video,
                      ImageSource.camera,
                    ),
                  ),
                ),
                ListTile(
                  minTileHeight: 52,
                  leading: const Icon(Icons.video_library_outlined),
                  title: Text(copy.text('Choose video', 'Wybierz film')),
                  onTap: () => Navigator.pop(
                    context,
                    const _SourceChoice(
                      ReelMediaKind.video,
                      ImageSource.gallery,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
    if (!_ownsDraft(generation)) return;
    _sourcePickerOpen = false;
    if (!_ownsDraft(generation) ||
        source == null ||
        _selecting ||
        _draftContractLocked) {
      return;
    }
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
      // The native picker/probe can complete after a publish attempt has
      // already reserved this draft. Discard that late result so it cannot
      // reset the retry-stable session or replace the frozen upload plan.
      if (!_ownsDraft(generation) || _draftContractLocked) return;
      final previousKind = _media?.mediaKind;
      setState(() {
        _media = payload;
        _session = null;
        _composition = _composition.copyWith(
          crop: const ReelCropTransform(),
          originalAudioVolume: payload.mediaKind == ReelMediaKind.video
              ? previousKind == ReelMediaKind.video
                    ? _composition.originalAudioVolume
                    : 100
              : 0,
          trimStartMs: 0,
          trimEndMs: payload.durationMs,
        );
        _step = _ComposerStep.edit;
      });
    } catch (error) {
      if (_ownsDraft(generation)) _showError(error);
    } finally {
      if (_ownsDraft(generation)) setState(() => _selecting = false);
    }
  }

  Future<void> _pickBackingAudio() async {
    final generation = _identityGeneration;
    if (_draftContractLocked || _pickingAudio || _media == null) return;
    setState(() {
      _pickingAudio = true;
      _error = null;
    });
    await _previewKey.currentState?.pause();
    if (!_ownsDraft(generation)) return;
    final picker = widget.backingAudioPicker ?? _pickLocalBackingAudio;
    try {
      final result = await picker();
      if (!_ownsDraft(generation) || result == null || _draftContractLocked) {
        return;
      }
      if (!result.contentType.startsWith('audio/')) {
        throw const FormatException('Choose a supported audio file.');
      }
      setState(() {
        _backingAudio = result;
        _session = null;
        _composition = _composition.copyWith(
          backingAudioVolume: 70,
          audioRightsAttested: false,
          audioTrimStartMs: 0,
          audioAttribution: '',
        );
      });
    } catch (error) {
      if (_ownsDraft(generation)) _showError(error);
    } finally {
      if (_ownsDraft(generation)) setState(() => _pickingAudio = false);
    }
  }

  Future<ReelUploadPayload?> _pickLocalBackingAudio() async {
    // iOS rejects a type group without UTIs (file_selector_ios throws an
    // ArgumentError before any picker appears) — which is why "choose your
    // own music" never opened on iPhone. Each platform reads its own field.
    final group = XTypeGroup(
      label: AppLocalizations.of(context).text('Audio', 'Dźwięk'),
      extensions: <String>['mp3', 'm4a', 'wav'],
      mimeTypes: <String>['audio/mpeg', 'audio/mp4', 'audio/wav'],
      uniformTypeIdentifiers: <String>[
        'public.mp3',
        'public.mpeg-4-audio',
        'com.apple.m4a-audio',
        'com.microsoft.waveform-audio',
      ],
    );
    final file = await openFile(acceptedTypeGroups: <XTypeGroup>[group]);
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
      await player
          .setSource(BytesSource(bytes, mimeType: contentType))
          .timeout(const Duration(seconds: 12));
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
    final generation = _identityGeneration;
    if (_draftContractLocked) return;
    final copy = AppLocalizations.of(context);
    final controller = TextEditingController();
    final text = await _showDraftDialog<String>(
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
    if (!_ownsDraft(generation) ||
        text == null ||
        text.isEmpty ||
        _draftContractLocked) {
      return;
    }
    setState(() {
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
    final generation = _identityGeneration;
    if (_draftContractLocked) return;
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final label = TextEditingController();
    final url = TextEditingController();
    String? validationError;
    final result = await _showDraftDialog<(String, String)>(
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
    if (!_ownsDraft(generation) || result == null || _draftContractLocked) {
      return;
    }
    final uri = Uri.tryParse(result.$2);
    if (uri == null || !isSafePublicHttpsUri(uri) || result.$1.isEmpty) return;
    setState(() {
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
    final generation = _identityGeneration;
    if (_draftContractLocked) return;
    final copy = AppLocalizations.of(context);
    final controller = TextEditingController(text: source.text);
    var x = source.x;
    var y = source.y;
    var scale = source.scale;
    var color = source.color;
    final result = await _showDraftDialog<ReelTextOverlay>(
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
    if (!_ownsDraft(generation) || result == null || _draftContractLocked) {
      return;
    }
    setState(() {
      _composition = _composition.copyWith(
        textOverlays: _composition.textOverlays
            .map((item) => item.id == result.id ? result : item)
            .toList(growable: false),
      );
    });
  }

  Future<void> _editLinkOverlay(ReelLinkOverlay source) async {
    final generation = _identityGeneration;
    if (_draftContractLocked) return;
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final label = TextEditingController(text: source.label);
    final url = TextEditingController(text: source.uri.toString());
    var x = source.x;
    var y = source.y;
    String? validationError;
    final result = await _showDraftDialog<ReelLinkOverlay>(
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
    if (!_ownsDraft(generation) || result == null || _draftContractLocked) {
      return;
    }
    setState(() {
      _composition = _composition.copyWith(
        linkOverlays: _composition.linkOverlays
            .map((item) => item.id == result.id ? result : item)
            .toList(growable: false),
      );
    });
  }

  Future<void> _publish() async {
    final generation = _identityGeneration;
    final media = _media;
    if (media == null || _publishing || _selecting || _pickingAudio) return;
    await _previewKey.currentState?.pause();
    if (!_ownsDraft(generation) || _publishing) return;
    final existingSession = _session;
    final plan =
        existingSession?.plan ??
        ReelDraftPlan(
          media: media,
          backingAudio: _backingAudio,
          composition: _composition.copyWith(caption: _caption.text),
          availability: _availability,
        );
    final problem = plan.validate();
    if (problem != null) {
      _showError(FormatException(problem));
      return;
    }
    final session = existingSession ?? ReelPublishSession(plan: plan);
    setState(() {
      _session = session;
      _publishing = true;
      _error = null;
      _progress = 0;
    });
    try {
      final reelId = await _service.publish(
        session,
        onProgress: (progress) {
          if (_ownsDraft(generation)) setState(() => _progress = progress);
        },
      );
      if (!mounted || !_ownsDraft(generation)) return;
      widget.onPublished?.call(reelId);
      if (Navigator.of(context).canPop()) Navigator.of(context).pop(reelId);
    } catch (error) {
      if (_ownsDraft(generation)) _showError(error);
    } finally {
      if (_ownsDraft(generation)) setState(() => _publishing = false);
    }
  }

  Future<void> _goTo(_ComposerStep step) async {
    final generation = _identityGeneration;
    if (_publishing || _selecting || _pickingAudio) return;
    await _previewKey.currentState?.pause();
    if (!_ownsDraft(generation)) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _step = step;
      _previewPlaying = false;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _back() async {
    final generation = _identityGeneration;
    if (_publishing || _selecting || _pickingAudio) return;
    if (_step != _ComposerStep.media) {
      await _goTo(_ComposerStep.values[_step.index - 1]);
      return;
    }
    if (_media != null) {
      final copy = AppLocalizations.of(context);
      final discard = await _showDraftDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(copy.text('Discard this draft?', 'Odrzucić ten szkic?')),
          content: Text(
            copy.text(
              'Your unpublished changes will be lost.',
              'Nieopublikowane zmiany zostaną utracone.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(copy.text('Cancel', 'Anuluj')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(copy.text('Discard', 'Odrzuć')),
            ),
          ],
        ),
      );
      if (!_ownsDraft(generation) || discard != true) return;
    }
    setState(() => _allowExit = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_ownsDraft(generation)) Navigator.of(context).maybePop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final busy = _publishing || _selecting || _pickingAudio;
    final labels = [
      copy.text('Media', 'Multimedia'),
      copy.text('Edit', 'Edytuj'),
      copy.text('Review', 'Sprawdź'),
    ];
    return PopScope(
      canPop: _allowExit || (_media == null && !busy),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_back());
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(copy.text('Create Reel', 'Utwórz Reel')),
          leading: IconButton(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: busy ? null : _back,
            icon: const BackButtonIcon(),
          ),
        ),
        body: DecoratedBox(
          decoration: BoxDecoration(gradient: palette.backgroundGradient),
          child: SafeArea(
            top: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 900;
                final compactHeight =
                    constraints.maxHeight < 380 ||
                    MediaQuery.textScalerOf(context).scale(14) > 24;
                final footer = _footer(copy, busy);
                final content = Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: wide ? 1120 : 720),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (
                                var index = 0;
                                index < labels.length;
                                index++
                              )
                                Semantics(
                                  selected: index == _step.index,
                                  child: Chip(
                                    avatar: Text('${index + 1}'),
                                    label: Text(labels[index]),
                                    backgroundColor: index == _step.index
                                        ? palette.surfaceRaised
                                        : palette.surface,
                                    side: BorderSide(
                                      color: index == _step.index
                                          ? palette.focus
                                          : palette.border,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (_step == _ComposerStep.media)
                            _mediaSelection(copy)
                          else
                            _workspace(copy, constraints, wide),
                          if (_error != null) ...[
                            const SizedBox(height: 16),
                            Semantics(
                              key: _errorKey,
                              liveRegion: true,
                              child: Text(
                                _error!,
                                key: const ValueKey('reel-composer-error'),
                                style: TextStyle(
                                  color: palette.dangerForeground,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                          if (compactHeight) ...[
                            const SizedBox(height: 20),
                            footer,
                          ],
                        ],
                      ),
                    ),
                  ),
                );
                return Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        key: const ValueKey('reel-composer-scroll'),
                        controller: _scroll,
                        child: content,
                      ),
                    ),
                    if (!compactHeight)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: palette.surface,
                          border: Border(
                            top: BorderSide(color: palette.border),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 720),
                              child: footer,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _mediaSelection(AppLocalizations copy) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 360 ? 16 : 24),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: palette.borderStrong),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.add_photo_alternate_outlined,
            size: 56,
            color: palette.textPrimary,
          ),
          const SizedBox(height: 20),
          FilledButton(
            key: const ValueKey('reel-choose-media'),
            onPressed: _selecting || _draftContractLocked
                ? null
                : _showSourcePicker,
            style:
                FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(58),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ).copyWith(
                  side: WidgetStateProperty.resolveWith(
                    (states) => BorderSide(
                      color: states.contains(WidgetState.focused)
                          ? colors.onPrimary
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
            child: Text(
              _selecting
                  ? copy.text('Opening media', 'Otwieranie multimediów')
                  : _media == null
                  ? copy.text('Choose media', 'Wybierz multimedia')
                  : copy.text('Replace media', 'Zmień multimedia'),
              textAlign: TextAlign.center,
              softWrap: true,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            copy.text(
              'Photos up to 10 MB. Videos: 1–90 seconds, up to 100 MB.',
              'Zdjęcia do 10 MB. Filmy: 1–90 sekund, do 100 MB.',
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _workspace(AppLocalizations copy, BoxConstraints bounds, bool wide) {
    final generation = _identityGeneration;
    final media = _media!;
    final previewHeight = wide
        ? math.min(560.0, math.max(280.0, bounds.maxHeight - 160))
        : math.min(350.0, math.max(180.0, bounds.maxHeight * .42));
    final preview = Center(
      child: SizedBox(
        width: previewHeight * 9 / 16,
        height: previewHeight,
        child: ReelDraftPreview(
          key: _previewKey,
          media: media,
          backingAudio: _backingAudio,
          composition: _composition,
          audioPlayerFactory: widget.audioPlayerFactory,
          active: !_publishing && !_selecting && !_pickingAudio,
          cropEnabled:
              _step == _ComposerStep.edit &&
              _tool == _EditorTool.crop &&
              !_draftContractLocked,
          onCropChanged: (crop) {
            if (_ownsDraft(generation) && !_draftContractLocked) {
              setState(() => _composition = _composition.copyWith(crop: crop));
            }
          },
          onPlayingChanged: (playing) {
            if (_ownsDraft(generation)) {
              setState(() => _previewPlaying = playing);
            }
          },
        ),
      ),
    );
    final tools = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_step == _ComposerStep.edit) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tool in _EditorTool.values)
                ChoiceChip(
                  key: ValueKey('reel-tool-${tool.name}'),
                  label: Text(switch (tool) {
                    _EditorTool.crop => copy.text('Crop', 'Kadr'),
                    _EditorTool.audio => copy.text('Audio', 'Dźwięk'),
                    _EditorTool.text => copy.text(
                      'Text and links',
                      'Tekst i linki',
                    ),
                    _EditorTool.filter => copy.text('Filter', 'Filtr'),
                  }),
                  selected: _tool == tool,
                  onSelected: _publishing
                      ? null
                      : (_) {
                          if (_ownsDraft(generation)) {
                            setState(() => _tool = tool);
                          }
                        },
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        _Editor(
          media: media,
          backingAudio: _backingAudio,
          composition: _composition,
          caption: _caption,
          availability: _availability,
          availabilityLocked: _draftContractLocked,
          draftLocked: _draftContractLocked,
          review: _step == _ComposerStep.review,
          tool: _tool,
          pickingAudio: _pickingAudio,
          previewPlaying: _previewPlaying,
          onPreview: () {
            if (_ownsDraft(generation)) {
              unawaited(_previewKey.currentState?.toggle());
            }
          },
          onCaptionChanged: (_) {
            if (_ownsDraft(generation) &&
                !_draftContractLocked &&
                _error != null) {
              setState(() => _error = null);
            }
          },
          onAvailabilityChanged: (value) {
            if (_ownsDraft(generation) && !_draftContractLocked) {
              setState(() => _availability = value);
            }
          },
          onComposition: (value) {
            if (_ownsDraft(generation) && !_draftContractLocked) {
              setState(() {
                _composition = value;
                _error = null;
              });
            }
          },
          onPickAudio: () {
            if (_ownsDraft(generation)) unawaited(_pickBackingAudio());
          },
          onRemoveAudio: () {
            if (!_ownsDraft(generation) || _draftContractLocked) return;
            setState(() {
              _backingAudio = null;
              _composition = _composition.copyWith(
                backingAudioVolume: 0,
                audioTrimStartMs: 0,
                audioRightsAttested: false,
                audioAttribution: '',
              );
            });
          },
          onAddText: () {
            if (_ownsDraft(generation)) unawaited(_addTextOverlay());
          },
          onAddLink: () {
            if (_ownsDraft(generation)) unawaited(_addLinkOverlay());
          },
          onEditText: (value) {
            if (_ownsDraft(generation)) unawaited(_editTextOverlay(value));
          },
          onEditLink: (value) {
            if (_ownsDraft(generation)) unawaited(_editLinkOverlay(value));
          },
        ),
      ],
    );
    return wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: preview),
              const SizedBox(width: 28),
              Expanded(child: tools),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [preview, const SizedBox(height: 18), tools],
          );
  }

  Widget _footer(AppLocalizations copy, bool busy) {
    final next = _step == _ComposerStep.review
        ? YoButton(
            key: const ValueKey('reel-publish'),
            label: _publishing
                ? copy.template(
                    'Publishing {percent}%',
                    'Publikowanie {percent}%',
                    values: {'percent': (_progress * 100).round()},
                  )
                : copy.text('Publish Reel', 'Opublikuj Reel'),
            onPressed: _media == null || busy ? null : _publish,
            isLoading: _publishing,
            icon: const Icon(Icons.publish_rounded),
          )
        : YoButton(
            key: const ValueKey('reel-next-step'),
            label: _step == _ComposerStep.edit
                ? copy.text('Preview Reel', 'Podgląd Reela')
                : copy.text('Next', 'Dalej'),
            onPressed: _media == null || busy
                ? null
                : () => _goTo(_ComposerStep.values[_step.index + 1]),
            icon: const Icon(Icons.arrow_forward_rounded),
          );
    if (_step == _ComposerStep.media) return next;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        next,
        const SizedBox(height: 4),
        TextButton(
          key: const ValueKey('reel-previous-step'),
          onPressed: busy ? null : _back,
          child: Text(copy.text('Back', 'Wstecz')),
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
    required this.availability,
    required this.availabilityLocked,
    required this.draftLocked,
    required this.review,
    required this.tool,
    required this.pickingAudio,
    required this.previewPlaying,
    required this.onPreview,
    required this.onCaptionChanged,
    required this.onAvailabilityChanged,
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
  final ReelAvailabilityChoice availability;
  final bool availabilityLocked;
  final bool draftLocked;
  final bool review;
  final _EditorTool tool;
  final bool pickingAudio;
  final bool previewPlaying;
  final VoidCallback onPreview;
  final ValueChanged<String> onCaptionChanged;
  final ValueChanged<ReelAvailabilityChoice> onAvailabilityChanged;
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
            if (review) ...[
              TextField(
                controller: caption,
                readOnly: draftLocked,
                onChanged: draftLocked ? null : onCaptionChanged,
                maxLength: 2200,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: copy.text('Caption', 'Opis'),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 14),
              _ReelAvailabilityPicker(
                value: availability,
                locked: availabilityLocked,
                onChanged: onAvailabilityChanged,
              ),
            ],
            if (!review && tool == _EditorTool.crop) ...[
              const SizedBox(height: 12),
              Text(copy.text('Crop and position', 'Kadr i położenie')),
              const SizedBox(height: 8),
              Text(
                copy.text(
                  'Pinch to zoom, drag to position.',
                  'Uszczypnij, aby powiększyć, i przeciągnij, aby ustawić kadr.',
                ),
              ),
              TextButton(
                key: const ValueKey('reel-reset-crop'),
                onPressed: draftLocked
                    ? null
                    : () => onComposition(
                        composition.copyWith(crop: const ReelCropTransform()),
                      ),
                child: Text(copy.text('Reset crop', 'Resetuj kadr')),
              ),
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
                  onChanged: media == null || draftLocked
                      ? null
                      : (value) => onComposition(
                          composition.copyWith(
                            crop: composition.crop.copyWith(scale: value),
                          ),
                        ),
                ),
              ),
              if (composition.crop.scale == 1)
                Text(
                  copy.text(
                    'Zoom in to reposition the frame.',
                    'Powiększ obraz, aby przesunąć kadr.',
                  ),
                ),
              Column(
                children: <Widget>[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        copy.text(
                          'Horizontal crop position',
                          'Pozioma pozycja kadru',
                        ),
                      ),
                      Semantics(
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
                          onChanged:
                              media == null ||
                                  draftLocked ||
                                  composition.crop.scale == 1
                              ? null
                              : (value) => onComposition(
                                  composition.copyWith(
                                    crop: composition.crop.copyWith(
                                      offsetX: value,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        copy.text(
                          'Vertical crop position',
                          'Pionowa pozycja kadru',
                        ),
                      ),
                      Semantics(
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
                          onChanged:
                              media == null ||
                                  draftLocked ||
                                  composition.crop.scale == 1
                              ? null
                              : (value) => onComposition(
                                  composition.copyWith(
                                    crop: composition.crop.copyWith(
                                      offsetY: value,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
            if (!review && tool == _EditorTool.filter) ...[
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
                        onSelected: media == null || draftLocked
                            ? null
                            : (_) => onComposition(
                                composition.copyWith(filter: filter),
                              ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ],
            if (!review &&
                media?.mediaKind == ReelMediaKind.video &&
                (tool == _EditorTool.crop ||
                    tool == _EditorTool.audio)) ...<Widget>[
              if (tool == _EditorTool.crop) ...[
                const SizedBox(height: 18),
                Text(copy.text('Trim video', 'Przytnij film')),
                Semantics(
                  label: copy.text(
                    'Video trim range',
                    'Zakres przycięcia filmu',
                  ),
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
                    onChanged: draftLocked
                        ? null
                        : (values) {
                            if (values.end - values.start < 1) return;
                            onComposition(
                              composition.copyWith(
                                trimStartMs: (values.start * 1000).round(),
                                trimEndMs: (values.end * 1000).round(),
                              ),
                            );
                          },
                  ),
                ),
              ],
              if (tool == _EditorTool.audio) ...[
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
                    onChanged: draftLocked
                        ? null
                        : (value) => onComposition(
                            composition.copyWith(
                              originalAudioVolume: value.round(),
                            ),
                          ),
                  ),
                ),
              ],
            ],
            if (!review && tool == _EditorTool.text) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed:
                        draftLocked || composition.textOverlays.length >= 8
                        ? null
                        : onAddText,
                    icon: const Icon(Icons.text_fields_rounded),
                    label: Text(copy.text('Add text', 'Dodaj tekst')),
                  ),
                  OutlinedButton.icon(
                    onPressed:
                        draftLocked || composition.linkOverlays.length >= 4
                        ? null
                        : onAddLink,
                    icon: const Icon(Icons.link_rounded),
                    label: Text(copy.text('Add link', 'Dodaj link')),
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
                        onPressed: draftLocked ? null : () => onEditText(item),
                        onDeleted: draftLocked
                            ? null
                            : () => onComposition(
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
                        onPressed: draftLocked ? null : () => onEditLink(item),
                        onDeleted: draftLocked
                            ? null
                            : () => onComposition(
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
            ],
            if (!review && tool == _EditorTool.audio) ...[
              Text(
                copy.text(
                  'Use your own MP3, M4A or WAV: 1–90 seconds, up to 15 MB.',
                  'Dodaj własny plik MP3, M4A lub WAV: 1–90 sekund, do 15 MB.',
                ),
              ),
              const SizedBox(height: 12),
              if (backingAudio == null)
                OutlinedButton.icon(
                  key: const ValueKey('reel-add-audio'),
                  onPressed: draftLocked || pickingAudio ? null : onPickAudio,
                  icon: pickingAudio
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.music_note_rounded),
                  label: Text(
                    pickingAudio
                        ? copy.text(
                            'Preparing audio',
                            'Przygotowywanie dźwięku',
                          )
                        : copy.text('Add your audio', 'Dodaj własny dźwięk'),
                  ),
                ),
              if (backingAudio != null) ...<Widget>[
                const SizedBox(height: 18),
                _BackingAudioControls(
                  payload: backingAudio!,
                  composition: composition,
                  playing: previewPlaying,
                  onPreview: onPreview,
                  editingEnabled: !draftLocked,
                  onComposition: onComposition,
                  onRemove: onRemoveAudio,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _ReelAvailabilityPicker extends StatelessWidget {
  const _ReelAvailabilityPicker({
    required this.value,
    required this.locked,
    required this.onChanged,
  });

  final ReelAvailabilityChoice value;
  final bool locked;
  final ValueChanged<ReelAvailabilityChoice> onChanged;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    const choices = <ReelAvailabilityChoice>[
      ReelAvailabilityChoice.hours24,
      ReelAvailabilityChoice.days7,
      ReelAvailabilityChoice.days30,
      ReelAvailabilityChoice.permanent,
    ];
    String label(ReelAvailabilityChoice choice) {
      if (choice == ReelAvailabilityChoice.hours24) {
        return copy.text('24 hours', '24 godziny');
      }
      if (choice == ReelAvailabilityChoice.days7) {
        return copy.text('7 days', '7 dni');
      }
      if (choice == ReelAvailabilityChoice.days30) {
        return copy.text('30 days', '30 dni');
      }
      if (choice.isPermanent) {
        return copy.text('Until deleted', 'Do usunięcia');
      }
      return copy.template(
        '{hours} hours',
        '{hours} godz.',
        values: <String, Object>{'hours': choice.hours!},
      );
    }

    final description = locked
        ? copy.text(
            'Availability is locked for this retry.',
            'Dostępność jest zablokowana dla tej ponownej próby.',
          )
        : copy.text(
            'Choose how long this Reel remains available.',
            'Wybierz, jak długo ten Reel ma być dostępny.',
          );
    return Semantics(
      key: const ValueKey<String>('reel-availability-picker'),
      container: true,
      label: copy.text('Available for', 'Dostępny przez'),
      value: label(value),
      hint: description,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            copy.text('Available for', 'Dostępny przez'),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: palette.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final choice in choices)
                ChoiceChip(
                  key: ValueKey<String>(
                    'reel-availability-${choice.hours ?? 'permanent'}',
                  ),
                  label: Text(label(choice)),
                  selected: value == choice,
                  onSelected: locked ? null : (_) => onChanged(choice),
                ),
              ChoiceChip(
                key: const ValueKey<String>('reel-availability-custom'),
                avatar: const Icon(Icons.tune_rounded, size: 18),
                label: Text(
                  choices.contains(value)
                      ? copy.text('Custom', 'Własny czas')
                      : copy.template(
                          'Custom · {hours}h',
                          'Własny · {hours} godz.',
                          values: <String, Object>{'hours': value.hours!},
                        ),
                ),
                selected: !choices.contains(value),
                onSelected: locked
                    ? null
                    : (_) async {
                        final selected = await _showCustomAvailabilityDialog(
                          context,
                          current: value,
                        );
                        if (selected != null) onChanged(selected);
                      },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _ReelAvailabilityUnit { hours, days }

Future<ReelAvailabilityChoice?> _showCustomAvailabilityDialog(
  BuildContext context, {
  required ReelAvailabilityChoice current,
}) async {
  final owner = context.findAncestorStateOfType<_ReelComposerScreenState>();
  if (owner == null) return null;
  final copy = AppLocalizations.of(context);
  final controller = TextEditingController(
    text: current.hours?.toString() ?? '24',
  );
  var unit = _ReelAvailabilityUnit.hours;
  String? error;
  final result = await owner._showDraftDialog<ReelAvailabilityChoice>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) {
        void submit() {
          final amount = int.tryParse(controller.text.trim());
          final hours = amount == null
              ? null
              : unit == _ReelAvailabilityUnit.hours
              ? amount
              : amount * 24;
          if (amount == null ||
              amount <= 0 ||
              hours == null ||
              hours < ReelAvailabilityChoice.minimumHours ||
              hours > ReelAvailabilityChoice.maximumHours) {
            setDialogState(() {
              error = copy.text(
                'Choose 24–720 whole hours or 1–30 whole days.',
                'Wybierz 24–720 pełnych godzin lub 1–30 pełnych dni.',
              );
            });
            return;
          }
          Navigator.of(context).pop(ReelAvailabilityChoice.timedHours(hours));
        }

        return AlertDialog(
          title: Text(copy.text('Custom availability', 'Własny czas')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  key: const ValueKey<String>('reel-availability-amount'),
                  controller: controller,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => submit(),
                  decoration: InputDecoration(
                    labelText: copy.text('Duration', 'Czas'),
                    errorText: error,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<_ReelAvailabilityUnit>(
                  key: const ValueKey<String>('reel-availability-unit'),
                  initialValue: unit,
                  decoration: InputDecoration(
                    labelText: copy.text('Unit', 'Jednostka'),
                  ),
                  items: <DropdownMenuItem<_ReelAvailabilityUnit>>[
                    DropdownMenuItem<_ReelAvailabilityUnit>(
                      value: _ReelAvailabilityUnit.hours,
                      child: Text(copy.text('Hours', 'Godziny')),
                    ),
                    DropdownMenuItem<_ReelAvailabilityUnit>(
                      value: _ReelAvailabilityUnit.days,
                      child: Text(copy.text('Days', 'Dni')),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() {
                      unit = value;
                      error = null;
                    });
                  },
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(copy.text('Cancel', 'Anuluj')),
            ),
            FilledButton(
              key: const ValueKey<String>('reel-availability-apply'),
              onPressed: submit,
              child: Text(copy.text('Apply', 'Zastosuj')),
            ),
          ],
        );
      },
    ),
  );
  controller.dispose();
  return result;
}

class _BackingAudioControls extends StatelessWidget {
  const _BackingAudioControls({
    required this.payload,
    required this.composition,
    required this.playing,
    required this.onPreview,
    required this.editingEnabled,
    required this.onComposition,
    required this.onRemove,
  });

  final ReelUploadPayload payload;
  final ReelComposition composition;
  final bool playing;
  final bool editingEnabled;
  final VoidCallback onPreview;
  final ValueChanged<ReelComposition> onComposition;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final maxTrimStartMs = math.max(0, payload.durationMs - 1000);
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
          children: [
            Row(
              children: [
                IconButton.filledTonal(
                  key: const ValueKey('reel-backing-audio-preview'),
                  tooltip: playing
                      ? copy.text('Pause preview', 'Wstrzymaj podgląd')
                      : copy.text('Play preview', 'Odtwórz podgląd'),
                  onPressed: onPreview,
                  constraints: const BoxConstraints.tightFor(
                    width: 48,
                    height: 48,
                  ),
                  icon: Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                        _formatDuration(
                          Duration(milliseconds: payload.durationMs),
                        ),
                        style: TextStyle(color: palette.textSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: copy.text('Remove audio', 'Usuń dźwięk'),
                  onPressed: editingEnabled ? onRemove : null,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(copy.text('Backing audio volume', 'Głośność podkładu')),
            Semantics(
              label: copy.text('Backing audio volume', 'Głośność podkładu'),
              value: '${composition.backingAudioVolume}%',
              child: Slider(
                value: composition.backingAudioVolume.toDouble(),
                min: 0,
                max: 100,
                divisions: 20,
                label: '${composition.backingAudioVolume}%',
                semanticFormatterCallback: (value) => '${value.round()}%',
                onChanged: editingEnabled
                    ? (value) => onComposition(
                        composition.copyWith(backingAudioVolume: value.round()),
                      )
                    : null,
              ),
            ),
            Text(copy.text('Audio start', 'Początek podkładu')),
            Semantics(
              label: copy.text(
                'Backing audio start position',
                'Początek podkładu dźwiękowego',
              ),
              value: '${composition.audioTrimStartMs ~/ 1000} s',
              child: Slider(
                value: composition.audioTrimStartMs
                    .clamp(0, maxTrimStartMs)
                    .toDouble(),
                min: 0,
                max: math.max(1, maxTrimStartMs).toDouble(),
                divisions: maxTrimStartMs <= 0
                    ? null
                    : math.min(90, math.max(1, maxTrimStartMs ~/ 1000)),
                label: '${composition.audioTrimStartMs ~/ 1000} s',
                semanticFormatterCallback: (value) =>
                    '${(value / 1000).round()} s',
                onChanged: maxTrimStartMs <= 0 || !editingEnabled
                    ? null
                    : (value) => onComposition(
                        composition.copyWith(audioTrimStartMs: value.round()),
                      ),
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: composition.audioRightsAttested,
              onChanged: editingEnabled
                  ? (value) => onComposition(
                      composition.copyWith(audioRightsAttested: value ?? false),
                    )
                  : null,
              title: Text(
                copy.text(
                  'I created this audio or have permission to use it.',
                  'Ten dźwięk jest mój lub mam zgodę na jego użycie.',
                ),
              ),
            ),
            TextFormField(
              key: ValueKey(payload),
              initialValue: composition.audioAttribution,
              readOnly: !editingEnabled,
              maxLength: 160,
              decoration: InputDecoration(
                labelText: copy.text(
                  'Audio credit (optional)',
                  'Autor dźwięku (opcjonalnie)',
                ),
              ),
              onChanged: editingEnabled
                  ? (value) => onComposition(
                      composition.copyWith(audioAttribution: value),
                    )
                  : null,
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

String _friendly(BuildContext context, Object error) {
  final copy = AppLocalizations.of(context);
  if (error is StateError &&
      error.message == 'This Reel draft belongs to an ended sign-in session.') {
    return copy.text(
      'This draft belongs to a previous session. Discard it and create a new Reel.',
      'Ten szkic pochodzi z poprzedniej sesji. Odrzuć go i utwórz nowego Reela.',
    );
  }
  if (error is FirebaseFunctionsException) {
    switch (error.code) {
      case 'unauthenticated':
        return copy.text(
          'Sign in again before publishing.',
          'Zaloguj się ponownie przed publikacją.',
        );
      case 'permission-denied':
        return copy.text(
          'Check your email verification and account permissions before publishing.',
          'Przed publikacją sprawdź weryfikację adresu e-mail i uprawnienia konta.',
        );
      case 'resource-exhausted':
        return copy.text(
          'You have reached the publishing limit. Try again later.',
          'Osiągnięto limit publikacji. Spróbuj ponownie później.',
        );
      case 'failed-precondition':
      case 'invalid-argument':
        return copy.text(
          'Check your media and audio rights, then try again.',
          'Sprawdź multimedia i prawa do dźwięku, a następnie spróbuj ponownie.',
        );
      case 'unavailable':
      case 'deadline-exceeded':
        return copy.text(
          'Check your connection and retry. Your draft is kept.',
          'Sprawdź połączenie i ponów próbę. Twój szkic został zachowany.',
        );
    }
  }
  if (error is TimeoutException) {
    return copy.text(
      'Check your connection and retry. Your draft is kept.',
      'Sprawdź połączenie i ponów próbę. Twój szkic został zachowany.',
    );
  }
  final message = error is FormatException ? error.message.toString() : '';
  if (message == 'Confirm that you may use the backing audio.') {
    return copy.text(
      'Confirm that you may use the backing audio.',
      'Potwierdź, że masz prawo użyć podkładu dźwiękowego.',
    );
  }
  if (message.toLowerCase().contains('audio') &&
      !message.toLowerCase().contains('original')) {
    return copy.text(
      'Use your own MP3, M4A or WAV: 1–90 seconds, up to 15 MB.',
      'Dodaj własny plik MP3, M4A lub WAV: 1–90 sekund, do 15 MB.',
    );
  }
  if (message.toLowerCase().contains('video') ||
      message.toLowerCase().contains('media') ||
      message.toLowerCase().contains('photo') ||
      message.toLowerCase().contains('image')) {
    return copy.text(
      'Photos up to 10 MB. Videos: 1–90 seconds, up to 100 MB.',
      'Zdjęcia do 10 MB. Filmy: 1–90 sekund, do 100 MB.',
    );
  }
  if (error is StateError &&
      (error.message.toString().contains('sign-in') ||
          error.message.toString().contains('Sign in'))) {
    return copy.text(
      'Sign in again before publishing.',
      'Zaloguj się ponownie przed publikacją.',
    );
  }
  return copy.text(
    'The Reel could not be prepared. Try again.',
    'Nie udało się przygotować Reela. Spróbuj ponownie.',
  );
}
