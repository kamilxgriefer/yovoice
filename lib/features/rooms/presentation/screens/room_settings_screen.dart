import 'package:flutter/material.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_image_service.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';

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
    super.key,
  });

  final VoiceRoom room;
  final RoomService? roomService;
  final RoomImageService? roomImageService;

  @override
  State<RoomSettingsScreen> createState() => _RoomSettingsScreenState();
}

class _RoomSettingsScreenState extends State<RoomSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final RoomService _service = widget.roomService ?? RoomService();
  late final RoomImageService _images =
      widget.roomImageService ?? RoomImageService();

  String? _imageUrl;
  bool _uploadingCover = false;

  /// The cover is part of the room's identity (stage backdrop + Home/
  /// Discover card). Uploaded immediately on pick — unlike the text
  /// fields it has its own storage lifecycle, and the card should update
  /// live for everyone as soon as the host confirms the picker.
  Future<void> _changeCover() async {
    if (_uploadingCover) return;
    try {
      final picked = await _images.pickImage();
      if (picked == null || !mounted) return;
      setState(() => _uploadingCover = true);
      final url = await _images.uploadRoomImage(
        roomId: widget.room.id,
        file: picked,
      );
      await _service.updateImageUrl(roomId: widget.room.id, imageUrl: url);
      if (!mounted) return;
      setState(() => _imageUrl = url);
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
      if (mounted) setState(() => _uploadingCover = false);
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
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _busy) return;
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
    if (_busy) return;
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
    if (!confirmed) return;
    setState(() => _busy = true);
    try {
      await _service.setRoomStatus(widget.room.id, status);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _delete() async {
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
    if (!confirmed || _busy) return;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
            onPressed: _busy ? null : _save,
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
                  OutlinedButton.icon(
                    onPressed: _uploadingCover ? null : _changeCover,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFF3A2C49)),
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: _uploadingCover
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.image_rounded, size: 18),
                    label: Text(
                      _uploadingCover
                          ? 'Uploading…'
                          : _imageUrl?.trim().isNotEmpty == true
                          ? 'Change cover'
                          : 'Add cover',
                    ),
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
                  if (!widget.room.isActive)
                    _ActionTile(
                      icon: Icons.lock_open_rounded,
                      title: 'Open room',
                      subtitle: 'Make this room available again.',
                      onTap: () => _setStatus(RoomStatus.active),
                    ),
                  if (!widget.room.isClosed)
                    _ActionTile(
                      icon: Icons.lock_rounded,
                      title: 'Close room',
                      subtitle: 'Pause access without deleting anything.',
                      onTap: () => _setStatus(RoomStatus.closed),
                    ),
                  if (!widget.room.isArchived)
                    _ActionTile(
                      icon: Icons.archive_rounded,
                      title: 'Archive room',
                      subtitle: 'Hide it from Discover and keep all data.',
                      onTap: () => _setStatus(RoomStatus.archived),
                    ),
                  _ActionTile(
                    icon: Icons.delete_forever_rounded,
                    title: 'Delete room',
                    subtitle: 'Permanently delete the room and its data.',
                    danger: true,
                    onTap: _delete,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
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
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: danger ? _danger : _primary),
        title: Text(
          title,
          style: TextStyle(
            color: danger ? _danger : Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Text(subtitle, style: const TextStyle(color: _muted)),
        trailing: const Icon(Icons.chevron_right_rounded, color: _muted),
        onTap: onTap,
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
