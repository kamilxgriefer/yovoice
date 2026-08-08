import 'package:flutter/material.dart';

import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/rooms/presentation/screens/broadcast_room/broadcast_colors.dart';

class BroadcastSettingsSheet extends StatefulWidget {
  const BroadcastSettingsSheet({
    super.key,
    required this.room,
    required this.service,
  });

  final VoiceRoom room;
  final RoomService service;

  @override
  State<BroadcastSettingsSheet> createState() => _BroadcastSettingsSheetState();
}

class _BroadcastSettingsSheetState extends State<BroadcastSettingsSheet> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _category;
  late final TextEditingController _language;
  late final TextEditingController _capacity;
  late final TextEditingController _slowMode;

  late String _visibility;
  late bool _approvalRequired;
  late bool _autoMuteNewUsers;
  late bool _membersCanStartVoice;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final room = widget.room;
    _name = TextEditingController(text: room.name);
    _description = TextEditingController(text: room.description);
    _category = TextEditingController(text: room.category);
    _language = TextEditingController(text: room.language);
    _capacity = TextEditingController(
      text: room.maxParticipants?.toString() ?? '',
    );
    _slowMode = TextEditingController(text: room.slowModeSeconds.toString());
    _visibility = room.visibility;
    _approvalRequired = room.approvalRequired;
    _autoMuteNewUsers = room.autoMuteNewUsers;
    _membersCanStartVoice = room.membersCanStartVoice;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _category.dispose();
    _language.dispose();
    _capacity.dispose();
    _slowMode.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;

    final capacityText = _capacity.text.trim();
    final capacity = capacityText.isEmpty ? null : int.tryParse(capacityText);
    final slowMode = int.tryParse(_slowMode.text.trim()) ?? 0;

    if (capacityText.isNotEmpty && (capacity == null || capacity <= 0)) {
      _showError('Capacity must be a positive number.');
      return;
    }

    if (slowMode < 0) {
      _showError('Slow mode cannot be negative.');
      return;
    }

    setState(() => _saving = true);

    try {
      await widget.service.updateRoomSettings(
        roomId: widget.room.id,
        name: _name.text,
        description: _description.text,
        category: _category.text.trim().isEmpty
            ? widget.room.category
            : _category.text.trim(),
        visibility: _visibility,
        language: _language.text.trim().isEmpty
            ? widget.room.language
            : _language.text.trim(),
        maxParticipants: capacity,
        approvalRequired: _approvalRequired,
        slowModeSeconds: slowMode,
        autoMuteNewUsers: _autoMuteNewUsers,
        membersCanStartVoice: _membersCanStartVoice,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showError(
        error
            .toString()
            .replaceFirst('Bad state: ', '')
            .replaceFirst('Invalid argument(s): ', ''),
      );
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 18,
        right: 18,
        top: 10,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const Text(
              'Room settings',
              style: TextStyle(
                color: Colors.white,
                fontSize: 23,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 5),
            const Text(
              'Changes are saved directly to this broadcast.',
              style: TextStyle(color: BroadcastRoomColors.muted),
            ),
            const SizedBox(height: 20),
            SettingsField(controller: _name, label: 'Room name', maxLength: 80),
            const SizedBox(height: 12),
            SettingsField(
              controller: _description,
              label: 'Description',
              maxLines: 3,
              maxLength: 300,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SettingsField(
                    controller: _category,
                    label: 'Category',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SettingsField(
                    controller: _language,
                    label: 'Language',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SettingsField(
                    controller: _capacity,
                    label: 'Capacity',
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SettingsField(
                    controller: _slowMode,
                    label: 'Slow mode (sec)',
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _visibility,
              dropdownColor: BroadcastRoomColors.surfaceSoft,
              decoration: settingsDecoration('Visibility'),
              style: const TextStyle(color: Colors.white),
              items: const [
                DropdownMenuItem(value: 'public', child: Text('Public')),
                DropdownMenuItem(value: 'private', child: Text('Private')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _visibility = value);
              },
            ),
            const SizedBox(height: 14),
            SettingsSwitch(
              title: 'Auto-mute new listeners',
              subtitle: 'New participants enter without an active microphone.',
              value: _autoMuteNewUsers,
              onChanged: (value) => setState(() => _autoMuteNewUsers = value),
            ),
            SettingsSwitch(
              title: 'Approval required',
              subtitle: 'Keep this option ready for invite approval workflows.',
              value: _approvalRequired,
              onChanged: (value) => setState(() => _approvalRequired = value),
            ),
            SettingsSwitch(
              title: 'Members can start voice',
              subtitle: 'Stored for compatibility with the shared room model.',
              value: _membersCanStartVoice,
              onChanged: (value) =>
                  setState(() => _membersCanStartVoice = value),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: BroadcastRoomColors.accent,
                minimumSize: const Size.fromHeight(54),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(17),
                ),
              ),
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_rounded),
              label: Text(_saving ? 'Saving…' : 'Save settings'),
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsField extends StatelessWidget {
  const SettingsField({
    super.key,
    required this.controller,
    required this.label,
    this.maxLines = 1,
    this.maxLength,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String label;
  final int maxLines;
  final int? maxLength;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      maxLength: maxLength,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      cursorColor: BroadcastRoomColors.accent,
      decoration: settingsDecoration(label),
    );
  }
}

InputDecoration settingsDecoration(String label) {
  return InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: BroadcastRoomColors.muted),
    filled: true,
    fillColor: BroadcastRoomColors.surfaceSoft,
    counterStyle: const TextStyle(color: BroadcastRoomColors.muted),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: BroadcastRoomColors.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(
        color: BroadcastRoomColors.accent,
        width: 1.4,
      ),
    ),
  );
}

class SettingsSwitch extends StatelessWidget {
  const SettingsSwitch({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      activeTrackColor: BroadcastRoomColors.accent,
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: BroadcastRoomColors.muted, fontSize: 12),
      ),
      value: value,
      onChanged: onChanged,
    );
  }
}
