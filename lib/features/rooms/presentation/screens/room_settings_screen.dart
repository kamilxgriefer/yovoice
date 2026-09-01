import 'package:flutter/material.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_image_service.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/rooms/presentation/room_cover_editor.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/theme/yo_immersive_dark_surface.dart';

const _background = Color(0xFF080711);
const _surface = Color(0xFF151020);
const _border = Color(0xFF392B47);
const _muted = Color(0xFF9D95AD);
const _primary = Color(0xFFA226FF);
const _danger = Color(0xFFFF416C);

class RoomSettingsScreen extends StatefulWidget {
  const RoomSettingsScreen({
    required this.room,
    this.roomService,
    this.roomImageService,
    this.clubService,
    this.coverEditor,
    super.key,
  });

  final VoiceRoom room;
  final RoomService? roomService;
  final RoomImageService? roomImageService;
  final RoomCoverEditorCallback? coverEditor;

  /// Resolves club ownership when [room] is a club lounge. Optional: the
  /// screen constructs its own where Firebase allows; where it cannot, a
  /// lounge simply shows NO delete control — the fail-closed direction.
  final ClubService? clubService;

  @override
  State<RoomSettingsScreen> createState() => _RoomSettingsScreenState();
}

class _RoomSettingsScreenState extends State<RoomSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final RoomService _service = widget.roomService ?? RoomService();
  late final RoomImageService _images =
      widget.roomImageService ?? RoomImageService();

  String? _imageUrl;
  bool _changingCover = false;

  /// The cover is part of the room's identity (stage backdrop + Home/
  /// Discover card). The host first confirms a manual crop; only that final
  /// JPEG is uploaded and published. Lock before opening the picker so a fast
  /// double tap cannot stack pickers/crop screens or race two pointer updates.
  Future<void> _changeCover() async {
    if (_changingCover || _busy) return;
    setState(() => _changingCover = true);
    try {
      final editor = widget.coverEditor ?? RoomCoverEditor.pickAndCrop;
      final cover = await editor(context, _images);
      if (cover == null || !mounted) return;
      final upload = await _images.uploadRoomCover(
        roomId: widget.room.id,
        bytes: cover.bytes,
      );
      try {
        await _service.finalizeRoomCoverUpload(
          roomId: widget.room.id,
          storagePath: upload.storagePath,
          objectGeneration: upload.objectGeneration,
          reservationId: upload.reservationId,
        );
      } catch (error, stackTrace) {
        // A failed write acknowledgement can still mean the pointer committed.
        // Re-read before deleting so cleanup can never break a valid cover.
        var pointerRead = false;
        var committed = false;
        try {
          final canonical = await _service.getRoomFromServer(widget.room.id);
          pointerRead = true;
          committed =
              canonical.coverStoragePath == upload.storagePath &&
              canonical.coverGeneration == upload.objectGeneration;
        } catch (_) {
          // Ambiguous state: preserve the uploaded object and the original
          // error. A later room deletion still cleans the whole prefix.
        }
        if (!committed) {
          if (pointerRead) {
            await _images.deleteManagedRoomCoverPath(
              roomId: widget.room.id,
              storagePath: upload.storagePath,
            );
          }
          Error.throwWithStackTrace(error, stackTrace);
        }
      }
      String? nextImageUrl;
      try {
        nextImageUrl = (await _service.getRoom(widget.room.id)).imageUrl;
      } catch (_) {
        // The canonical pointer already committed. The room stream will
        // retry the short-lived render grant without treating this as an
        // upload failure.
      }
      if (!mounted) return;
      setState(() => _imageUrl = nextImageUrl);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            intentionalOrFriendly(
              error,
              fallback: "Couldn't update the room cover. Please try again.",
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _changingCover = false);
    }
  }

  late final TextEditingController _name;
  late final TextEditingController _description;
  late String _category;
  late String _visibility;
  late String _language;
  late int? _maxParticipants;
  late bool _approvalRequired;
  late int _slowModeSeconds;
  late bool _autoMuteNewUsers;
  late bool _membersCanStartVoice;

  /// Non-null only when this room is a club lounge whose club document can
  /// be watched. `deleteRoomSelf` refuses `club_lounge_*` rooms outright,
  /// so the delete control for a lounge must be the CLUB delete (owner-only
  /// `deleteClubSelf`) or nothing at all — never the room delete.
  ClubService? _clubService;
  Stream<Club>? _clubStream;

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final room = widget.room;
    _name = TextEditingController(text: room.name);
    _description = TextEditingController(text: room.description);
    _imageUrl = room.imageUrl;
    _category = room.category;
    _visibility = room.visibility;
    _language = room.language;
    _maxParticipants = room.maxParticipants;
    _approvalRequired = room.approvalRequired;
    _slowModeSeconds = room.slowModeSeconds;
    _autoMuteNewUsers = room.autoMuteNewUsers;
    _membersCanStartVoice = room.membersCanStartVoice;

    // `storedClubId`, NOT the prefix-derived `clubId`: authority (both
    // deleteClubSelf and the rules' Club branch) reads the document FIELD.
    final clubId = room.storedClubId;
    if (clubId != null) {
      try {
        _clubService = widget.clubService ?? ClubService();
        _clubStream = _clubService!.watchClub(clubId);
      } catch (_) {
        // No Firebase (widget tests, degraded startup): the lounge shows no
        // delete control rather than a broken one.
        _clubService = null;
        _clubStream = null;
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _busy || _changingCover) return;
    setState(() => _busy = true);
    try {
      await _service.updateRoomSettings(
        roomId: widget.room.id,
        name: _name.text,
        description: _description.text,
        category: _category,
        visibility: _visibility,
        language: _language,
        maxParticipants: _maxParticipants,
        approvalRequired: _approvalRequired,
        slowModeSeconds: _slowModeSeconds,
        autoMuteNewUsers: _autoMuteNewUsers,
        membersCanStartVoice: _membersCanStartVoice,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            intentionalOrFriendly(
              error,
              fallback: "The change couldn't be saved. Please try again.",
            ),
          ),
        ),
      );
    }
  }

  Future<void> _setStatus(RoomStatus status) async {
    if (_busy || _changingCover) return;
    final label = switch (status) {
      RoomStatus.active => 'open',
      RoomStatus.closed => 'close',
      RoomStatus.archived => 'archive',
      // Suspension is a moderation verdict, never a host choice; the
      // settings UI does not offer it and the server would refuse it.
      RoomStatus.suspended => 'suspend',
    };
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: _surface,
            title: Text(
              '${label[0].toUpperCase()}${label.substring(1)} room?',
              style: const TextStyle(color: Colors.white),
            ),
            content: Text(
              status == RoomStatus.active
                  ? 'The room will be visible and usable again.'
                  : status == RoomStatus.closed
                  ? 'Members will keep their membership, but voice and chat access can be paused until you reopen it.'
                  : 'The room will be hidden from Discover until you restore it.',
              style: const TextStyle(color: _muted),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(label.toUpperCase()),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || _busy || _changingCover) return;
    setState(() => _busy = true);
    try {
      await _service.setRoomStatus(widget.room.id, status);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            intentionalOrFriendly(
              error,
              fallback: "The room status couldn't change. Please try again.",
            ),
          ),
        ),
      );
    }
  }

  Future<void> _delete() async {
    // Unrepresentable, not merely unreachable: a club lounge never renders
    // the tile that leads here, and even if one did, this path must not
    // call deleteRoomSelf — the server refuses lounges and the user would
    // get a dialog whose Delete can only ever fail. Lounges go through
    // _deleteClub().
    if (widget.room.storedClubId != null || _busy || _changingCover) return;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: _surface,
            title: Text(
              'Delete "${widget.room.name}"?',
              style: const TextStyle(color: Colors.white),
            ),
            content: const Text(
              'Messages, members and room settings will be permanently '
              'removed. This cannot be undone.',
              style: TextStyle(color: _muted),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _danger),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || _busy || _changingCover) return;
    setState(() => _busy = true);
    try {
      await _service.deleteRoom(widget.room.id);
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            intentionalOrFriendly(
              error,
              fallback:
                  "The room couldn't be deleted. Please try again in a moment.",
            ),
          ),
        ),
      );
    }
  }

  /// The lounge counterpart of [_delete]: tears down the WHOLE Club through
  /// the owner-only `deleteClubSelf` callable. Same confirm shape, honest
  /// copy — the dialog names the Club and says what actually goes away.
  Future<void> _deleteClub(Club club) async {
    final service = _clubService;
    if (service == null || _busy || _changingCover) return;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: _surface,
            title: Text(
              'Delete the Club "${club.name}"?',
              style: const TextStyle(color: Colors.white),
            ),
            content: const Text(
              'This deletes the whole Club — its lounge, chat, channels, '
              'members and invites. This cannot be undone.',
              style: TextStyle(color: _muted),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _danger),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || _busy || _changingCover) return;
    setState(() => _busy = true);
    try {
      await service.deleteClub(club.id);
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            intentionalOrFriendly(
              error,
              fallback:
                  "The Club couldn't be deleted. Please try again in a moment.",
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: Colors.white,
        title: const Text(
          'Room settings',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          TextButton(
            onPressed: _busy || _changingCover ? null : _save,
            child: const Text(
              'SAVE',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
      body: ResponsiveContentFrame(
        width: ResponsiveContentWidth.form,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 80),
            children: [
              _Section(
                title: 'Room cover',
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: AspectRatio(
                      aspectRatio: 21 / 9,
                      child: _imageUrl?.trim().isNotEmpty == true
                          ? Image.network(
                              _imageUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const _CoverFallback(),
                            )
                          : const _CoverFallback(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (widget.room.isActive)
                    OutlinedButton.icon(
                      onPressed: _changingCover || _busy ? null : _changeCover,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFF3A2C49)),
                        minimumSize: const Size.fromHeight(46),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: _changingCover
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.image_rounded, size: 18),
                      label: Text(
                        _changingCover
                            ? 'Updating cover…'
                            : _imageUrl?.trim().isNotEmpty == true
                            ? 'Change cover'
                            : 'Add cover',
                      ),
                    )
                  else if (widget.room.status == RoomStatus.suspended)
                    const _CoverStatusNotice(
                      icon: Icons.gavel_rounded,
                      message:
                          'This room is suspended by moderation. Its cover '
                          "can't be changed until the suspension is lifted.",
                    )
                  else
                    _CoverStatusNotice(
                      icon: Icons.lock_open_rounded,
                      message: 'Reopen this room to edit its cover.',
                      actionLabel: 'Reopen room',
                      onAction: _busy || _changingCover
                          ? null
                          : () => _setStatus(RoomStatus.active),
                    ),
                  const SizedBox(height: 4),
                  const Text(
                    'The cover becomes the room card on Home and Discover '
                    'and the stage backdrop inside the room.',
                    style: TextStyle(color: Color(0xFF9E92A8), fontSize: 11.5),
                  ),
                ],
              ),
              _Section(
                title: 'General',
                children: [
                  _TextField(
                    controller: _name,
                    label: 'Room name',
                    maxLength: 50,
                    validator: (value) => (value?.trim().length ?? 0) < 3
                        ? 'Enter at least 3 characters'
                        : null,
                  ),
                  _TextField(
                    controller: _description,
                    label: 'Description',
                    maxLength: 160,
                    maxLines: 4,
                  ),
                  _Dropdown(
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
                  _Dropdown(
                    label: 'Language',
                    value: _language,
                    values: const [
                      'English',
                      'Polish',
                      'Dutch',
                      'German',
                      'French',
                      'Spanish',
                      'Italian',
                    ],
                    onChanged: (value) => setState(() => _language = value),
                  ),
                ],
              ),
              _Section(
                title: 'Privacy',
                children: [
                  _Dropdown(
                    label: 'Visibility',
                    value: _visibility,
                    values: const ['public', 'private'],
                    onChanged: (value) => setState(() => _visibility = value),
                  ),
                  SwitchListTile.adaptive(
                    value: _approvalRequired,
                    onChanged: (value) =>
                        setState(() => _approvalRequired = value),
                    title: const Text(
                      'Require approval to join',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: const Text(
                      'New members need owner approval.',
                      style: TextStyle(color: _muted),
                    ),
                    activeTrackColor: _primary,
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
              _Section(
                title: 'Voice',
                children: [
                  _Dropdown(
                    label: 'Voice capacity',
                    value: _maxParticipants?.toString() ?? 'Unlimited',
                    values: const ['10', '25', '50', '100', 'Unlimited'],
                    onChanged: (value) => setState(() {
                      _maxParticipants = value == 'Unlimited'
                          ? null
                          : int.parse(value);
                    }),
                  ),
                  SwitchListTile.adaptive(
                    value: _autoMuteNewUsers,
                    onChanged: (value) =>
                        setState(() => _autoMuteNewUsers = value),
                    title: const Text(
                      'Auto-mute new listeners',
                      style: TextStyle(color: Colors.white),
                    ),
                    activeTrackColor: _primary,
                    contentPadding: EdgeInsets.zero,
                  ),
                  SwitchListTile.adaptive(
                    value: _membersCanStartVoice,
                    onChanged: (value) =>
                        setState(() => _membersCanStartVoice = value),
                    title: const Text(
                      'Members can start voice',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: const Text(
                      'Otherwise only the owner can start a session.',
                      style: TextStyle(color: _muted),
                    ),
                    activeTrackColor: _primary,
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
              _Section(
                title: 'Chat',
                children: [
                  _Dropdown(
                    label: 'Slow mode',
                    value: '$_slowModeSeconds',
                    values: const ['0', '5', '10', '30', '60'],
                    labels: const {
                      '0': 'Off',
                      '5': '5 seconds',
                      '10': '10 seconds',
                      '30': '30 seconds',
                      '60': '1 minute',
                    },
                    onChanged: (value) =>
                        setState(() => _slowModeSeconds = int.parse(value)),
                  ),
                ],
              ),
              _Section(
                title: 'Room status',
                children: [
                  if (widget.room.isClosed || widget.room.isArchived)
                    _ActionTile(
                      icon: Icons.lock_open_rounded,
                      title: 'Open room',
                      subtitle: 'Make this room available again.',
                      onTap: _busy || _changingCover
                          ? null
                          : () => _setStatus(RoomStatus.active),
                    ),
                  if (widget.room.status != RoomStatus.suspended &&
                      !widget.room.isClosed)
                    _ActionTile(
                      icon: Icons.lock_rounded,
                      title: 'Close room',
                      subtitle: 'Pause access without deleting anything.',
                      onTap: _busy || _changingCover
                          ? null
                          : () => _setStatus(RoomStatus.closed),
                    ),
                  if (widget.room.status != RoomStatus.suspended &&
                      !widget.room.isArchived)
                    _ActionTile(
                      icon: Icons.archive_rounded,
                      title: 'Archive room',
                      subtitle: 'Hide it from Discover and keep all data.',
                      onTap: _busy || _changingCover
                          ? null
                          : () => _setStatus(RoomStatus.archived),
                    ),
                  if (widget.room.storedClubId == null)
                    _ActionTile(
                      icon: Icons.delete_forever_rounded,
                      title: 'Delete room',
                      subtitle: 'Permanently delete the room and its data.',
                      danger: true,
                      onTap: _busy || _changingCover ? null : _delete,
                    )
                  else if (_clubStream != null)
                    // A club lounge is deleted only by deleting its Club,
                    // and only its owner may do that. Ownership comes from
                    // the club DOCUMENT (Club.ownerId), never the room's
                    // possibly-stale hostId; while it is loading, errored
                    // or belongs to someone else there is no delete control
                    // at all — mirroring how a non-host sees an ordinary
                    // room.
                    StreamBuilder<Club>(
                      stream: _clubStream,
                      builder: (context, snapshot) {
                        final club = snapshot.data;
                        final uid = _clubService?.currentUserId ?? '';
                        if (club == null ||
                            uid.isEmpty ||
                            club.ownerId != uid) {
                          return const SizedBox.shrink();
                        }
                        return _ActionTile(
                          icon: Icons.delete_forever_rounded,
                          title: 'Delete club',
                          subtitle:
                              'Permanently delete the whole Club — its '
                              'lounge, chat, channels, members and invites.',
                          danger: true,
                          onTap: _busy || _changingCover
                              ? null
                              : () => _deleteClub(club),
                        );
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return YoImmersiveDarkSurface(child: content);
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: _muted,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 10),
          Material(
            color: _surface,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: const BorderSide(color: _border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: children),
            ),
          ),
        ],
      ),
    );
  }
}

class _TextField extends StatelessWidget {
  const _TextField({
    required this.controller,
    required this.label,
    this.maxLength,
    this.maxLines = 1,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final int? maxLength;
  final int maxLines;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        maxLength: maxLength,
        maxLines: maxLines,
        validator: validator,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: _muted),
          counterStyle: const TextStyle(color: _muted),
          enabledBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: _border),
          ),
          focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: _primary),
          ),
        ),
      ),
    );
  }
}

class _Dropdown extends StatelessWidget {
  const _Dropdown({
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
    this.labels = const {},
  });

  final String label;
  final String value;
  final List<String> values;
  final ValueChanged<String> onChanged;
  final Map<String, String> labels;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        dropdownColor: _surface,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: _muted),
          enabledBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: _border),
          ),
          focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: _primary),
          ),
        ),
        items: values
            .map(
              (item) => DropdownMenuItem(
                value: item,
                child: Text(labels[item] ?? item),
              ),
            )
            .toList(growable: false),
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final actionColor = danger ? _danger : _primary;
    return Material(
      color: Colors.transparent,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        enabled: enabled,
        leading: Icon(icon, color: enabled ? actionColor : _muted),
        title: Text(
          title,
          style: TextStyle(
            color: enabled ? (danger ? _danger : Colors.white) : _muted,
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Text(subtitle, style: const TextStyle(color: _muted)),
        trailing: Icon(
          Icons.chevron_right_rounded,
          color: enabled ? _muted : _muted.withValues(alpha: .45),
        ),
        onTap: onTap,
      ),
    );
  }
}

class _CoverStatusNotice extends StatelessWidget {
  const _CoverStatusNotice({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF100C19),
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 20, color: _muted),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(color: _muted, height: 1.35),
                  ),
                ),
              ],
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 2),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.lock_open_rounded, size: 18),
                  label: Text(actionLabel!),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Typed placeholder shown when the room has no cover yet.
class _CoverFallback extends StatelessWidget {
  const _CoverFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3A1657), Color(0xFF150F20)],
        ),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.image_outlined,
        size: 38,
        color: Colors.white.withValues(alpha: .25),
      ),
    );
  }
}
