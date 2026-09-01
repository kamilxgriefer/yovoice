import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/audio/ui_sound.dart';
import 'package:yovoice/core/audio/ui_sound_service.dart';
import 'package:yovoice/core/theme/space_identity.dart';
import 'package:yovoice/features/rooms/data/models/room_experience.dart';
import 'package:yovoice/features/rooms/data/models/room_metadata.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_experience_service.dart';
import 'package:yovoice/features/rooms/data/services/room_image_service.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/rooms/presentation/room_cover_editor.dart';
import 'package:yovoice/features/rooms/presentation/screens/room_entry_screen.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/theme/yo_immersive_dark_surface.dart';

/// Creating a Community or Podcast room, in three steps.
///
/// One screen serves both because they are the same shape of decision —
/// identity, then who it is for, then how it runs. What differs is the
/// [SpaceIdentity] it wears and the handful of options only one of them
/// supports, and both of those are read from the experience rather than
/// branched ad hoc through the layout.
///
/// Every value lives in this State, not in the step widgets, so moving
/// back and forth never loses what was typed.
class CreateRoomScreen extends StatefulWidget {
  const CreateRoomScreen({
    this.experience = RoomExperience.community,
    this.roomService,
    this.imageService,
    this.experienceService,
    this.coverEditor,
    super.key,
  });

  final RoomExperience experience;

  /// Injected in tests, as every other surface in this app does it.
  final RoomService? roomService;
  final RoomImageService? imageService;
  final RoomExperienceService? experienceService;
  final RoomCoverEditorCallback? coverEditor;

  @override
  State<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

enum _Step { identity, audience, experience }

class _CreateRoomScreenState extends State<CreateRoomScreen> {
  static const _background = Color(0xFF080711);
  static const _muted = Color(0xFFA69CAF);

  final _identityKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _topic = TextEditingController();
  final _guidelines = TextEditingController();
  final _tagInput = TextEditingController();

  late final RoomService _roomService = widget.roomService ?? RoomService();
  late final RoomImageService _imageService =
      widget.imageService ?? RoomImageService();
  _Step _step = _Step.identity;

  String _category = 'talk';
  String _visibility = 'public';
  String _language = 'English';
  int? _maxParticipants = 25;
  bool _handRaisingEnabled = true;
  TargetAudience _targetAudience = TargetAudience.everyone;
  final List<String> _tags = <String>[];
  ConversationStyle _conversationStyle = ConversationStyle.casual;
  bool _newcomerFriendly = false;
  RoomType _roomType = RoomType.community;
  ShowFormat _showFormat = ShowFormat.solo;

  Uint8List? _coverBytes;
  bool _pickingCover = false;
  String? _coverError;
  bool _busy = false;
  double? _uploadProgress;
  String? _roomCreationRequestId;

  bool get _isBroadcast => widget.experience == RoomExperience.broadcast;

  SpaceIdentity get _identity =>
      _isBroadcast ? SpaceIdentity.podcast : SpaceIdentity.community;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _topic.dispose();
    _guidelines.dispose();
    _tagInput.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------- cover

  Future<void> _pickCover() async {
    if (_pickingCover || _busy) return;
    setState(() {
      _pickingCover = true;
      _coverError = null;
    });
    try {
      final editor = widget.coverEditor ?? RoomCoverEditor.pickAndCrop;
      final cover = await editor(context, _imageService);
      // Null means the picker or crop screen was cancelled. A cancelled
      // Replace keeps the previous composition rather than blanking it.
      if (!mounted || cover == null) return;
      setState(() {
        _coverBytes = cover.bytes;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _coverError = _readable(error));
    } finally {
      if (mounted) setState(() => _pickingCover = false);
    }
  }

  void _removeCover() {
    setState(() {
      _coverBytes = null;
      _coverError = null;
    });
  }

  String _readable(Object error) {
    if (error is FirebaseFunctionsException) {
      final message = error.message?.trim();
      if (message != null && message.isNotEmpty) return message;
      return 'Something went wrong. Please try again.';
    }
    return error
        .toString()
        .replaceFirst('Bad state: ', '')
        .replaceFirst('Invalid argument(s): ', '');
  }

  // -------------------------------------------------------------- tags

  void _addTag() {
    final tag = _tagInput.text.trim();
    if (tag.isEmpty) return;
    if (_tags.length >= RoomMetadataLimits.maxTopicTags) return;
    if (tag.length > RoomMetadataLimits.maxTopicTagLength) return;
    if (_tags.any((existing) => existing.toLowerCase() == tag.toLowerCase())) {
      return;
    }
    setState(() {
      _tags.add(tag);
      _tagInput.clear();
    });
  }

  // ------------------------------------------------------- step control

  /// The Identity form only exists while its step is on screen, so
  /// `_identityKey.currentState` is null from step two onward. Validating
  /// through it there silently returned false and Create did nothing.
  /// The step gate validates the live form; everything after checks the
  /// values themselves.
  bool get _identityValid => _identityKey.currentState?.validate() ?? false;

  bool get _identityComplete =>
      _name.text.trim().length >= 3 &&
      (!_isBroadcast || _topic.text.trim().length >= 3);

  void _next() {
    if (_step == _Step.identity && !_identityValid) return;
    setState(() {
      _step = switch (_step) {
        _Step.identity => _Step.audience,
        _Step.audience => _Step.experience,
        _Step.experience => _Step.experience,
      };
    });
  }

  void _back() {
    setState(() {
      _step = switch (_step) {
        _Step.experience => _Step.audience,
        _Step.audience => _Step.identity,
        _Step.identity => _Step.identity,
      };
    });
  }

  // ------------------------------------------------------------ create

  Future<void> _create() async {
    if (_busy || !_identityComplete) {
      if (!_identityComplete) setState(() => _step = _Step.identity);
      return;
    }
    setState(() {
      _busy = true;
      _coverError = null;
    });

    try {
      final requestId = _roomCreationRequestId ??= _roomService
          .newRoomCreationRequestId();
      final room = await _roomService.createRoom(
        name: _name.text,
        description: _description.text,
        category: _category,
        visibility: _visibility,
        language: _language,
        maxParticipants: _maxParticipants,
        roomType: _isBroadcast ? RoomType.temporary : _roomType,
        targetAudience: _targetAudience,
        topicTags: _tags,
        roomGuidelines: _guidelines.text,
        // Type-scoped: a community room never carries a show format and a
        // broadcast room never carries a conversation style.
        conversationStyle: _isBroadcast ? null : _conversationStyle,
        newcomerFriendly: _isBroadcast ? false : _newcomerFriendly,
        showFormat: _isBroadcast ? _showFormat : null,
        experience: widget.experience,
        topic: _isBroadcast ? _topic.text : '',
        audienceCanSpeak: !_isBroadcast,
        handRaisingEnabled: _isBroadcast && _handRaisingEnabled,
        requestId: requestId,
      );
      // The server acknowledged this exact idempotent operation. Cover
      // upload retries are a separate reservation flow and must never reuse
      // the room-create key.
      _roomCreationRequestId = null;

      // The cover is uploaded AFTER the room exists, because the Storage
      // path is keyed by room id and rules authorise it against the room's
      // host. Nothing is uploaded if creation is abandoned, so a cancelled
      // flow cannot leave an orphaned object behind. A failure here leaves
      // a usable room with no cover, which the host can set from room
      // settings — it is reported, not swallowed.
      var roomForEntry = room;
      if (_coverBytes != null) {
        setState(() => _uploadProgress = 0);
        try {
          final upload = await _imageService.uploadRoomCover(
            roomId: room.id,
            bytes: _coverBytes!,
          );
          try {
            await _roomService.finalizeRoomCoverUpload(
              roomId: room.id,
              storagePath: upload.storagePath,
              objectGeneration: upload.objectGeneration,
              reservationId: upload.reservationId,
            );
          } catch (error, stackTrace) {
            // The Firestore SDK can lose an acknowledgement after committing.
            // Only delete the new object when a successful re-read proves the
            // pointer did not move; an ambiguous read leaves it recoverable.
            var pointerRead = false;
            var committed = false;
            try {
              final canonical = await _roomService.getRoomFromServer(room.id);
              pointerRead = true;
              committed =
                  canonical.coverStoragePath == upload.storagePath &&
                  canonical.coverGeneration == upload.objectGeneration;
              if (committed) roomForEntry = canonical;
            } catch (_) {
              // Preserve the original write failure and uploaded object.
            }
            if (!committed) {
              if (pointerRead) {
                await _imageService.deleteManagedRoomCoverPath(
                  roomId: room.id,
                  storagePath: upload.storagePath,
                );
              }
              Error.throwWithStackTrace(error, stackTrace);
            }
          }
          // `createRoom` returned before the pointer flip. Re-read so the
          // very first room frame gets the confirmed cover instead of waiting
          // for its stream to emit a second document.
          try {
            roomForEntry = await _roomService.getRoom(room.id);
          } catch (_) {
            // The pointer already committed; RoomEntryScreen's canonical
            // room stream will converge even if this best-effort refresh did
            // not answer.
          }
        } catch (error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'The room was created, but the cover did not upload: '
                  '${_readable(error)}',
                ),
              ),
            );
          }
        } finally {
          if (mounted) setState(() => _uploadProgress = null);
        }
      }

      if (!mounted) return;
      unawaited(UiSoundService.instance.play(UiSound.roomCreated));
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) =>
              RoomEntryScreen(room: roomForEntry, playInitialJoinSound: false),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_readable(error))));
    }
  }

  // ------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final identity = _identity;
    final content = Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: Colors.white,
        centerTitle: true,
        title: Text(
          _isBroadcast ? 'Create Podcast Room' : 'Create Community Room',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            // Readable measure on a wide monitor; full width on a phone.
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              children: [
                _StepBar(step: _step, identity: identity),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
                    children: [
                      switch (_step) {
                        _Step.identity => _identityStep(identity),
                        _Step.audience => _audienceStep(identity),
                        _Step.experience => _experienceStep(identity),
                      },
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: _BottomBar(
        identity: identity,
        step: _step,
        busy: _busy,
        onBack: _step == _Step.identity ? null : _back,
        onNext: _step == _Step.experience ? null : _next,
        onCreate: _step == _Step.experience ? _create : null,
        createLabel: _isBroadcast ? 'Create Podcast Room' : 'Create Room',
      ),
    );
    return YoImmersiveDarkSurface(child: content);
  }

  // ---------------------------------------------------- step: identity

  Widget _identityStep(SpaceIdentity identity) {
    return Form(
      key: _identityKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Hero(identity: identity, isBroadcast: _isBroadcast),
          const SizedBox(height: 20),
          _SectionLabel(_isBroadcast ? 'Show cover' : 'Room cover', identity),
          const SizedBox(height: 10),
          _CoverPicker(
            identity: identity,
            bytes: _coverBytes,
            busy: _pickingCover,
            progress: _uploadProgress,
            error: _coverError,
            onPick: _pickCover,
            onRemove: _coverBytes == null ? null : _removeCover,
          ),
          const SizedBox(height: 18),
          _Field(
            controller: _name,
            identity: identity,
            label: _isBroadcast ? 'Show title' : 'Room name',
            hint: _isBroadcast ? 'e.g. Flutter Weekly' : 'e.g. Late Night Talk',
            maxLength: 50,
            validator: (value) => (value?.trim().length ?? 0) < 3
                ? 'Enter at least 3 characters'
                : null,
          ),
          if (_isBroadcast) ...[
            const SizedBox(height: 14),
            _Field(
              controller: _topic,
              identity: identity,
              label: 'Episode topic',
              hint: 'What are you discussing today?',
              maxLength: RoomMetadataLimits.maxPodcastTopicLength,
              validator: (value) =>
                  (value?.trim().length ?? 0) < 3 ? 'Add a short topic' : null,
            ),
          ],
          const SizedBox(height: 14),
          _Field(
            controller: _description,
            identity: identity,
            label: 'Description',
            hint: 'Tell people what to expect',
            maxLength: 160,
            maxLines: 3,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------- step: audience

  Widget _audienceStep(SpaceIdentity identity) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel('Category', identity),
        const SizedBox(height: 10),
        _Dropdown(
          identity: identity,
          label: 'Category',
          value: _category,
          values: const [
            'talk',
            'music',
            'gaming',
            'chill',
            'study',
            'business',
          ],
          onChanged: (value) => setState(() => _category = value),
        ),
        const SizedBox(height: 18),
        _SectionLabel('Topic tags', identity),
        const SizedBox(height: 6),
        Text(
          'Up to ${RoomMetadataLimits.maxTopicTags}. These help people find '
          'the room; they never decide who may join.',
          style: const TextStyle(color: _muted, fontSize: 12.5, height: 1.35),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _Field(
                controller: _tagInput,
                identity: identity,
                label: 'Add a tag',
                hint: 'e.g. flutter',
                maxLength: RoomMetadataLimits.maxTopicTagLength,
                onSubmitted: (_) => _addTag(),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 48,
              child: OutlinedButton(
                onPressed: _tags.length >= RoomMetadataLimits.maxTopicTags
                    ? null
                    : _addTag,
                style: OutlinedButton.styleFrom(
                  foregroundColor: identity.accent,
                  side: BorderSide(color: identity.primary),
                  shape: const StadiumBorder(),
                ),
                child: const Text('Add'),
              ),
            ),
          ],
        ),
        if (_tags.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in _tags)
                Chip(
                  label: Text(tag),
                  labelStyle: TextStyle(color: identity.accent),
                  backgroundColor: identity.wash,
                  side: BorderSide(color: identity.primary),
                  deleteIconColor: identity.accent,
                  onDeleted: () => setState(() => _tags.remove(tag)),
                ),
            ],
          ),
        ],
        const SizedBox(height: 20),
        _SectionLabel('Intended audience', identity),
        const SizedBox(height: 6),
        const Text(
          'Descriptive only. Anyone may still join a public room.',
          style: TextStyle(color: _muted, fontSize: 12.5, height: 1.35),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final audience in TargetAudience.values)
              _ChoiceChip(
                identity: identity,
                label: audience.label,
                selected: _targetAudience == audience,
                onTap: () => setState(() => _targetAudience = audience),
              ),
          ],
        ),
        const SizedBox(height: 20),
        _SectionLabel('Visibility', identity),
        const SizedBox(height: 10),
        _Dropdown(
          identity: identity,
          label: 'Visibility',
          value: _visibility,
          values: const ['public', 'private'],
          onChanged: (value) => setState(() => _visibility = value),
        ),
        const SizedBox(height: 14),
        _Dropdown(
          identity: identity,
          label: 'Language',
          value: _language,
          values: const [
            'English',
            'Polish',
            'Dutch',
            'German',
            'French',
            'Spanish',
          ],
          onChanged: (value) => setState(() => _language = value),
        ),
      ],
    );
  }

  // -------------------------------------------------- step: experience

  Widget _experienceStep(SpaceIdentity identity) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(
          _isBroadcast ? 'Audience capacity' : 'Voice capacity',
          identity,
        ),
        const SizedBox(height: 10),
        _Dropdown(
          identity: identity,
          label: _isBroadcast ? 'Audience capacity' : 'Voice capacity',
          value: _maxParticipants?.toString() ?? 'Unlimited',
          values: const ['10', '25', '50', '100', 'Unlimited'],
          onChanged: (value) => setState(
            () => _maxParticipants = value == 'Unlimited'
                ? null
                : int.parse(value),
          ),
        ),
        const SizedBox(height: 20),
        if (!_isBroadcast) ...[
          _SectionLabel('Room lifecycle', identity),
          const SizedBox(height: 10),
          _LifecycleChoice(
            identity: identity,
            selected: _roomType == RoomType.community,
            icon: Icons.all_inclusive_rounded,
            title: 'Stay open',
            subtitle:
                'People can keep talking after you leave. Voice sleeps when '
                'the room becomes empty.',
            onTap: () => setState(() => _roomType = RoomType.community),
          ),
          const SizedBox(height: 10),
          _LifecycleChoice(
            identity: identity,
            selected: _roomType == RoomType.temporary,
            icon: Icons.person_off_outlined,
            title: 'End with host',
            subtitle: 'Everyone is disconnected when you leave the room.',
            onTap: () => setState(() => _roomType = RoomType.temporary),
          ),
          const SizedBox(height: 20),
          _SectionLabel('Conversation style', identity),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final style in ConversationStyle.values)
                _ChoiceChip(
                  identity: identity,
                  label: style.label,
                  selected: _conversationStyle == style,
                  onTap: () => setState(() => _conversationStyle = style),
                ),
            ],
          ),
          const SizedBox(height: 14),
          _SwitchTile(
            identity: identity,
            value: _newcomerFriendly,
            title: 'Newcomer friendly',
            subtitle: 'Signals that first-time guests are welcome here.',
            onChanged: (value) => setState(() => _newcomerFriendly = value),
          ),
        ] else ...[
          _SectionLabel('Show format', identity),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final format in ShowFormat.values)
                _ChoiceChip(
                  identity: identity,
                  label: format.label,
                  selected: _showFormat == format,
                  onTap: () => setState(() => _showFormat = format),
                ),
            ],
          ),
          const SizedBox(height: 14),
          _SwitchTile(
            identity: identity,
            value: _handRaisingEnabled,
            title: 'Allow audience to raise hands',
            subtitle: 'The host can invite selected listeners to the stage.',
            onChanged: (value) => setState(() => _handRaisingEnabled = value),
          ),
        ],
        const SizedBox(height: 20),
        _SectionLabel('Room guidelines', identity),
        const SizedBox(height: 10),
        _Field(
          controller: _guidelines,
          identity: identity,
          label: 'Guidelines',
          hint: 'One or two lines on how this room runs',
          maxLength: RoomMetadataLimits.maxGuidelinesLength,
          maxLines: 3,
        ),
        const SizedBox(height: 22),
        _Summary(identity: identity, lines: _summaryLines()),
      ],
    );
  }

  List<(String, String)> _summaryLines() {
    return <(String, String)>[
      (_isBroadcast ? 'Show' : 'Room', _name.text.trim()),
      if (_isBroadcast) ('Episode', _topic.text.trim()),
      ('Cover', _coverBytes == null ? 'None' : 'Selected'),
      ('Category', _category),
      if (_tags.isNotEmpty) ('Tags', _tags.join(', ')),
      ('Audience', _targetAudience.label),
      ('Visibility', _visibility),
      ('Language', _language),
      ('Capacity', _maxParticipants?.toString() ?? 'Unlimited'),
      if (!_isBroadcast) ('Style', _conversationStyle.label),
      if (!_isBroadcast)
        (
          'Lifecycle',
          _roomType == RoomType.community ? 'Stay open' : 'End with host',
        ),
      if (!_isBroadcast)
        ('Newcomer friendly', _newcomerFriendly ? 'Yes' : 'No'),
      if (_isBroadcast) ('Format', _showFormat.label),
      if (_isBroadcast)
        ('Raise hands', _handRaisingEnabled ? 'Allowed' : 'Off'),
    ];
  }
}

// ------------------------------------------------------------- widgets

class _LifecycleChoice extends StatelessWidget {
  const _LifecycleChoice({
    required this.identity,
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final SpaceIdentity identity;
  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$title. $subtitle',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: selected
                  ? identity.primary.withValues(alpha: .13)
                  : const Color(0xFF171121),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected ? identity.primary : const Color(0xFF392C43),
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: selected ? identity.wash : const Color(0xFF251A30),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, color: identity.accent, size: 21),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Color(0xFFB6A9C2),
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected ? identity.accent : const Color(0xFF756A80),
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StepBar extends StatelessWidget {
  const _StepBar({required this.step, required this.identity});

  final _Step step;
  final SpaceIdentity identity;

  static const _labels = ['Identity', 'Audience', 'Experience'];

  @override
  Widget build(BuildContext context) {
    final index = _Step.values.indexOf(step);
    return Semantics(
      label: 'Step ${index + 1} of 3, ${_labels[index]}',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
        child: Row(
          children: [
            for (var i = 0; i < _labels.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 4,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: i <= index
                            ? identity.primary
                            : const Color(0xFF2E2438),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _labels[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: i <= index
                            ? identity.accent
                            : const Color(0xFF7E7490),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.identity,
    required this.step,
    required this.busy,
    required this.onBack,
    required this.onNext,
    required this.onCreate,
    required this.createLabel,
  });

  final SpaceIdentity identity;
  final _Step step;
  final bool busy;
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final VoidCallback? onCreate;
  final String createLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF171121),
      child: ResponsiveContentFrame(
        width: ResponsiveContentWidth.form,
        fillHeight: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            12,
            18,
            12 + MediaQuery.paddingOf(context).bottom,
          ),
          child: Row(
            children: [
              if (onBack != null) ...[
                SizedBox(
                  height: 52,
                  child: OutlinedButton(
                    onPressed: busy ? null : onBack,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFF3A2C49)),
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                    ),
                    child: const Text('Back'),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      gradient: identity.ctaGradient,
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: busy ? null : (onCreate ?? onNext),
                        child: Center(
                          child: busy
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  onCreate != null ? createLabel : 'Continue',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                  ),
                                ),
                        ),
                      ),
                    ),
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

class _Hero extends StatelessWidget {
  const _Hero({required this.identity, required this.isBroadcast});

  final SpaceIdentity identity;
  final bool isBroadcast;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: identity.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: identity.border),
        boxShadow: [
          BoxShadow(color: identity.glow, blurRadius: 24, spreadRadius: 1),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: identity.wash,
              borderRadius: BorderRadius.circular(17),
            ),
            child: Icon(identity.icon, color: identity.primary, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              isBroadcast
                  ? 'You control the stage. Listeners can request to speak.'
                  : 'A free-flowing room where everyone can join the '
                        'conversation.',
              style: const TextStyle(color: Colors.white, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// The cover picker.
///
/// The type's gradient sits UNDER the preview, so an image that is still
/// decoding — or one that fails — shows the room's own colours rather
/// than a broken-image glyph.
class _CoverPicker extends StatelessWidget {
  const _CoverPicker({
    required this.identity,
    required this.bytes,
    required this.busy,
    required this.progress,
    required this.error,
    required this.onPick,
    required this.onRemove,
  });

  final SpaceIdentity identity;
  final Uint8List? bytes;
  final bool busy;
  final double? progress;
  final String? error;
  final VoidCallback onPick;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AccessibleCoverPickerAction(
          enabled: !busy,
          busy: busy,
          label: bytes == null ? 'Choose a cover image' : 'Replace cover image',
          onTap: onPick,
          child: AspectRatio(
            aspectRatio: 21 / 9,
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: identity.border),
                gradient: LinearGradient(
                  colors: [identity.primary, identity.accent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (bytes != null)
                    Image.memory(
                      bytes!,
                      fit: BoxFit.cover,
                      // Never a broken-image glyph: a preview that cannot
                      // decode falls back to the type's own gradient.
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  if (bytes == null || busy)
                    Container(
                      color: Colors.black.withValues(alpha: .32),
                      alignment: Alignment.center,
                      child: busy
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.add_photo_alternate_rounded,
                                  color: Colors.white,
                                  size: 30,
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Choose cover',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    height: 1.2,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  if (progress != null)
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: LinearProgressIndicator(
                        color: identity.accent,
                        backgroundColor: Colors.black26,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  error!,
                  style: const TextStyle(
                    color: Color(0xFFFF9BB0),
                    fontSize: 12.5,
                  ),
                ),
              ),
              TextButton(
                onPressed: onPick,
                style: TextButton.styleFrom(foregroundColor: identity.accent),
                child: const Text('Retry'),
              ),
            ],
          ),
        ],
        if (onRemove != null) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton.icon(
                onPressed: onPick,
                icon: Icon(Icons.swap_horiz_rounded, color: identity.accent),
                label: Text(
                  'Replace',
                  style: TextStyle(color: identity.accent),
                ),
              ),
              TextButton.icon(
                onPressed: onRemove,
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: Color(0xFFB6ACBB),
                ),
                label: const Text(
                  'Remove',
                  style: TextStyle(color: Color(0xFFB6ACBB)),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _AccessibleCoverPickerAction extends StatefulWidget {
  const _AccessibleCoverPickerAction({
    required this.enabled,
    required this.busy,
    required this.label,
    required this.onTap,
    required this.child,
  });

  final bool enabled;
  final bool busy;
  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<_AccessibleCoverPickerAction> createState() =>
      _AccessibleCoverPickerActionState();
}

class _AccessibleCoverPickerActionState
    extends State<_AccessibleCoverPickerAction> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final onTap = widget.enabled ? widget.onTap : null;
    return Semantics(
      excludeSemantics: true,
      container: true,
      button: true,
      enabled: widget.enabled,
      liveRegion: widget.busy,
      label: widget.label,
      value: widget.busy ? 'Processing cover. Please wait.' : null,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        canRequestFocus: widget.enabled,
        onFocusChange: (focused) {
          if (mounted && focused != _focused) {
            setState(() => _focused = focused);
          }
        },
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            widget.child,
            if (_focused)
              Positioned.fill(
                child: IgnorePointer(
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: DecoratedBox(
                      key: const ValueKey('cover-picker-focus-ring-dark'),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: const Color(0xFF09050F),
                          width: 5,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: DecoratedBox(
                          key: const ValueKey('cover-picker-focus-ring-light'),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white, width: 2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, this.identity);

  final String text;
  final SpaceIdentity identity;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: Colors.white,
      fontSize: 15,
      fontWeight: FontWeight.w800,
    ),
  );
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.identity,
    required this.label,
    required this.hint,
    this.maxLength,
    this.maxLines = 1,
    this.validator,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final SpaceIdentity identity;
  final String label;
  final String hint;
  final int? maxLength;
  final int maxLines;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator,
      maxLength: maxLength,
      maxLines: maxLines,
      onFieldSubmitted: onSubmitted,
      style: const TextStyle(color: Colors.white),
      cursorColor: identity.primary,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        counterText: '',
        filled: true,
        fillColor: const Color(0xFF171121),
        labelStyle: const TextStyle(color: Color(0xFFB8AFC2)),
        floatingLabelStyle: TextStyle(color: identity.accent),
        hintStyle: const TextStyle(color: Color(0xFF746A80)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFF3A2C49)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: identity.focusBorder, width: 1.6),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );
  }
}

class _Dropdown extends StatelessWidget {
  const _Dropdown({
    required this.identity,
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
  });

  final SpaceIdentity identity;
  final String label;
  final String value;
  final List<String> values;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      dropdownColor: const Color(0xFF21172D),
      iconEnabledColor: identity.accent,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: const Color(0xFF171121),
        labelStyle: const TextStyle(color: Color(0xFFB8AFC2)),
        floatingLabelStyle: TextStyle(color: identity.accent),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFF3A2C49)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: identity.focusBorder, width: 1.6),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
      ),
      items: values
          .map((item) => DropdownMenuItem(value: item, child: Text(item)))
          .toList(growable: false),
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.identity,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final SpaceIdentity identity;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? identity.selected : const Color(0xFF171121),
        shape: StadiumBorder(
          side: BorderSide(
            color: selected ? identity.primary : const Color(0xFF3A2C49),
            width: selected ? 1.6 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Padding(
            // 44pt minimum target height on a phone.
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? identity.accent : const Color(0xFFCFC6DC),
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.identity,
    required this.value,
    required this.title,
    required this.subtitle,
    required this.onChanged,
  });

  final SpaceIdentity identity;
  final bool value;
  final String title;
  final String subtitle;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      value: value,
      onChanged: onChanged,
      activeTrackColor: identity.primary,
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: Color(0xFFA69CAF)),
      ),
      tileColor: const Color(0xFF171121),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFF3A2C49)),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.identity, required this.lines});

  final SpaceIdentity identity;
  final List<(String, String)> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: identity.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: identity.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Before you create',
            style: TextStyle(
              color: identity.accent,
              fontWeight: FontWeight.w900,
              fontSize: 13,
              letterSpacing: .6,
            ),
          ),
          const SizedBox(height: 10),
          for (final (label, value) in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 132,
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Color(0xFF9A90AC),
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      value.isEmpty ? '—' : value,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
