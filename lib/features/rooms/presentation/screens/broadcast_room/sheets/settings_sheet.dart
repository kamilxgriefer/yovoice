import 'package:flutter/material.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/rooms/data/models/room_metadata.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/rooms/presentation/screens/broadcast_room/broadcast_colors.dart';
import 'package:yovoice/shared/widgets/overlays/yo_modal_sheet_chrome.dart';

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
  late final TextEditingController _topic;
  late final TextEditingController _description;
  late final TextEditingController _guidelines;
  late final TextEditingController _category;
  late final TextEditingController _language;
  late final TextEditingController _capacity;
  late final TextEditingController _slowMode;

  late String _visibility;
  late ShowFormat _showFormat;
  late bool _handRaisingEnabled;
  late bool _approvalRequired;
  late bool _autoMuteNewUsers;
  late bool _membersCanStartVoice;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final room = widget.room;
    _name = TextEditingController(text: room.name);
    _topic = TextEditingController(text: room.topic);
    _description = TextEditingController(text: room.description);
    _guidelines = TextEditingController(text: room.roomGuidelines);
    _category = TextEditingController(text: room.category);
    _language = TextEditingController(text: room.language);
    _capacity = TextEditingController(
      text: room.maxParticipants?.toString() ?? '',
    );
    _slowMode = TextEditingController(text: room.slowModeSeconds.toString());
    _visibility = room.visibility;
    _showFormat = room.showFormat ?? ShowFormat.solo;
    _handRaisingEnabled = room.handRaisingEnabled;
    _approvalRequired = room.approvalRequired;
    _autoMuteNewUsers = room.autoMuteNewUsers;
    _membersCanStartVoice = room.membersCanStartVoice;
  }

  @override
  void dispose() {
    _name.dispose();
    _topic.dispose();
    _description.dispose();
    _guidelines.dispose();
    _category.dispose();
    _language.dispose();
    _capacity.dispose();
    _slowMode.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final copy = AppLocalizations.of(context);

    final capacityText = _capacity.text.trim();
    final capacity = capacityText.isEmpty ? null : int.tryParse(capacityText);
    final slowMode = int.tryParse(_slowMode.text.trim()) ?? 0;

    if (capacityText.isNotEmpty && (capacity == null || capacity <= 0)) {
      _showError(
        copy.text(
          'Capacity must be a positive number.',
          'Limit uczestników musi być liczbą dodatnią.',
        ),
      );
      return;
    }

    if (slowMode < 0) {
      _showError(
        copy.text(
          'Slow mode cannot be negative.',
          'Czas trybu spowolnionego nie może być ujemny.',
        ),
      );
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
        topic: _topic.text,
        showFormat: _showFormat,
        roomGuidelines: _guidelines.text,
        handRaisingEnabled: _handRaisingEnabled,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showError(
        friendlyErrorMessage(
          error,
          copy: copy,
          fallback: copy.text(
            'Could not save podcast settings. Please try again.',
            'Nie udało się zapisać ustawień podcastu. Spróbuj ponownie.',
          ),
        ),
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
    final copy = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          YoModalSheetChrome(
            sheetLabel: copy.text('podcast settings', 'ustawienia podcastu'),
            surfaceColor: BroadcastRoomColors.surface,
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    copy.text('Podcast settings', 'Ustawienia podcastu'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 23,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    copy.text(
                      'Shape the episode, the stage and the listener experience.',
                      'Dostosuj odcinek, scenę i wrażenia słuchaczy.',
                    ),
                    style: const TextStyle(color: BroadcastRoomColors.muted),
                  ),
                  const SizedBox(height: 20),
                  SettingsField(
                    controller: _name,
                    label: copy.text('Show name', 'Nazwa audycji'),
                    maxLength: 80,
                  ),
                  const SizedBox(height: 12),
                  SettingsField(
                    controller: _topic,
                    label: copy.text('Episode topic', 'Temat odcinka'),
                    maxLength: RoomMetadataLimits.maxPodcastTopicLength,
                  ),
                  const SizedBox(height: 12),
                  SettingsField(
                    controller: _description,
                    label: copy.text('Episode description', 'Opis odcinka'),
                    maxLines: 3,
                    maxLength: 300,
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<ShowFormat>(
                    initialValue: _showFormat,
                    dropdownColor: BroadcastRoomColors.surfaceSoft,
                    decoration: settingsDecoration(
                      copy.text('Show format', 'Format audycji'),
                    ),
                    style: const TextStyle(color: Colors.white),
                    items: [
                      for (final format in ShowFormat.values)
                        DropdownMenuItem(
                          value: format,
                          child: Text(_formatLabel(format, copy)),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _showFormat = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  SettingsField(
                    controller: _guidelines,
                    label: copy.text('Guest guidelines', 'Wskazówki dla gości'),
                    maxLines: 3,
                    maxLength: RoomMetadataLimits.maxGuidelinesLength,
                  ),
                  const SizedBox(height: 4),
                  SettingsSwitch(
                    title: copy.text(
                      'Listener stage requests',
                      'Zgłoszenia słuchaczy na scenę',
                    ),
                    subtitle: _handRaisingEnabled
                        ? copy.text(
                            'Listeners can ask to join the live conversation.',
                            'Słuchacze mogą poprosić o dołączenie do rozmowy na żywo.',
                          )
                        : copy.text(
                            'The audience stays in listening mode for this episode.',
                            'W tym odcinku publiczność pozostaje w trybie słuchania.',
                          ),
                    value: _handRaisingEnabled,
                    onChanged: (value) =>
                        setState(() => _handRaisingEnabled = value),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    copy.text('DISTRIBUTION', 'DOSTĘPNOŚĆ'),
                    style: const TextStyle(
                      color: BroadcastRoomColors.accentSoft,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.25,
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _visibility,
                    dropdownColor: BroadcastRoomColors.surfaceSoft,
                    decoration: settingsDecoration(
                      copy.text('Visibility', 'Widoczność'),
                    ),
                    style: const TextStyle(color: Colors.white),
                    items: [
                      DropdownMenuItem(
                        value: 'public',
                        child: Text(copy.text('Public', 'Publiczny')),
                      ),
                      DropdownMenuItem(
                        value: 'private',
                        child: Text(copy.text('Private', 'Prywatny')),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _visibility = value);
                    },
                  ),
                  const SizedBox(height: 10),
                  Theme(
                    data: Theme.of(context).copyWith(
                      dividerColor: Colors.transparent,
                      splashColor: BroadcastRoomColors.wash,
                    ),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: const EdgeInsets.only(bottom: 4),
                      iconColor: BroadcastRoomColors.accentSoft,
                      collapsedIconColor: BroadcastRoomColors.muted,
                      title: Text(
                        copy.text(
                          'Advanced controls',
                          'Ustawienia zaawansowane',
                        ),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      subtitle: Text(
                        copy.text(
                          'Capacity, chat pacing and compatibility settings.',
                          'Limit uczestników, tempo czatu i ustawienia zgodności.',
                        ),
                        style: const TextStyle(
                          color: BroadcastRoomColors.muted,
                          fontSize: 12,
                        ),
                      ),
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: SettingsField(
                                controller: _category,
                                label: copy.text('Category', 'Kategoria'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: SettingsField(
                                controller: _language,
                                label: copy.text('Language', 'Język'),
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
                                label: copy.text(
                                  'Capacity',
                                  'Limit uczestników',
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: SettingsField(
                                controller: _slowMode,
                                label: copy.text(
                                  'Chat slow mode (sec)',
                                  'Tryb spowolniony czatu (s)',
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        SettingsSwitch(
                          title: copy.text(
                            'Auto-mute new listeners',
                            'Automatycznie wyciszaj nowych słuchaczy',
                          ),
                          subtitle: copy.text(
                            'Everyone enters without a live microphone.',
                            'Każdy dołącza z wyłączonym mikrofonem.',
                          ),
                          value: _autoMuteNewUsers,
                          onChanged: (value) =>
                              setState(() => _autoMuteNewUsers = value),
                        ),
                        SettingsSwitch(
                          title: copy.text(
                            'Approval required',
                            'Wymagane zatwierdzenie',
                          ),
                          subtitle: copy.text(
                            'Reserved for invite approval workflows.',
                            'Przeznaczone dla zaproszeń wymagających akceptacji.',
                          ),
                          value: _approvalRequired,
                          onChanged: (value) =>
                              setState(() => _approvalRequired = value),
                        ),
                        SettingsSwitch(
                          title: copy.text(
                            'Members can start voice',
                            'Członkowie mogą uruchamiać rozmowę',
                          ),
                          subtitle: copy.text(
                            'Compatibility control for persistent rooms.',
                            'Ustawienie zgodności dla stałych pokoi.',
                          ),
                          value: _membersCanStartVoice,
                          onChanged: (value) =>
                              setState(() => _membersCanStartVoice = value),
                        ),
                      ],
                    ),
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
                    label: Text(
                      _saving
                          ? copy.text('Saving…', 'Zapisywanie…')
                          : copy.text('Update podcast', 'Zaktualizuj podcast'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatLabel(ShowFormat format, AppLocalizations copy) {
    if (!copy.isPolish) return format.label;
    return switch (format) {
      ShowFormat.solo => 'Solo',
      ShowFormat.interview => 'Wywiad',
      ShowFormat.panel => 'Panel',
      ShowFormat.qAndA => 'Pytania i odpowiedzi',
      ShowFormat.openDiscussion => 'Otwarta dyskusja',
    };
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
