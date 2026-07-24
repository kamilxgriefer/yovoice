import 'package:flutter/material.dart';

import 'package:yovoice/features/rooms/data/models/room_experience.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_experience_service.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/rooms/presentation/screens/room_entry_screen.dart';

class CreateRoomScreen extends StatefulWidget {
  const CreateRoomScreen({
    this.experience = RoomExperience.community,
    super.key,
  });

  final RoomExperience experience;

  @override
  State<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends State<CreateRoomScreen> {
  static const _background = Color(0xFF080711);
  static const _surface = Color(0xFF171121);
  static const _border = Color(0xFF3A2C49);
  static const _primary = Color(0xFFA226FF);
  static const _muted = Color(0xFFA69CAF);

  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _topic = TextEditingController();
  final _roomService = RoomService();
  final _experienceService = RoomExperienceService();

  String _category = 'talk';
  String _visibility = 'public';
  String _language = 'English';
  int? _maxParticipants = 25;
  bool _handRaisingEnabled = true;
  bool _busy = false;

  bool get _isPodcast => widget.experience == RoomExperience.podcast;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _topic.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);

    try {
      final room = await _roomService.createRoom(
        name: _name.text,
        description: _description.text,
        category: _category,
        visibility: _visibility,
        language: _language,
        maxParticipants: _maxParticipants,
        roomType: RoomType.temporary,
      );

      await _experienceService.configureRoom(
        roomId: room.id,
        experience: widget.experience,
        topic: _isPodcast ? _topic.text : '',
        audienceCanSpeak: !_isPodcast,
        handRaisingEnabled: _isPodcast && _handRaisingEnabled,
      );

      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => RoomEntryScreen(room: room)),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _isPodcast ? const Color(0xFFFF3F8E) : _primary;
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: Colors.white,
        centerTitle: true,
        title: Text(
          _isPodcast ? 'Create Podcast Room' : 'Create Community Room',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 130),
          children: [
            _IntroCard(isPodcast: _isPodcast, accent: accent),
            const SizedBox(height: 22),
            _Field(
              controller: _name,
              label: _isPodcast ? 'Show title' : 'Room name',
              hint: _isPodcast ? 'e.g. Flutter Weekly' : 'e.g. Late Night Talk',
              maxLength: 50,
              validator: (value) => (value?.trim().length ?? 0) < 3
                  ? 'Enter at least 3 characters'
                  : null,
            ),
            const SizedBox(height: 14),
            if (_isPodcast) ...[
              _Field(
                controller: _topic,
                label: 'Episode topic',
                hint: 'What are you discussing today?',
                maxLength: 100,
                validator: (value) => (value?.trim().length ?? 0) < 3
                    ? 'Add a short topic'
                    : null,
              ),
              const SizedBox(height: 14),
            ],
            _Field(
              controller: _description,
              label: 'Description',
              hint: 'Tell people what to expect',
              maxLength: 160,
              maxLines: 3,
            ),
            const SizedBox(height: 18),
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
            const SizedBox(height: 14),
            _Dropdown(
              label: 'Visibility',
              value: _visibility,
              values: const ['public', 'private'],
              onChanged: (value) => setState(() => _visibility = value),
            ),
            const SizedBox(height: 14),
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
              ],
              onChanged: (value) => setState(() => _language = value),
            ),
            const SizedBox(height: 14),
            _Dropdown(
              label: _isPodcast ? 'Audience capacity' : 'Voice capacity',
              value: _maxParticipants?.toString() ?? 'Unlimited',
              values: const ['10', '25', '50', '100', 'Unlimited'],
              onChanged: (value) => setState(
                () => _maxParticipants = value == 'Unlimited'
                    ? null
                    : int.parse(value),
              ),
            ),
            if (_isPodcast) ...[
              const SizedBox(height: 18),
              SwitchListTile.adaptive(
                value: _handRaisingEnabled,
                onChanged: (value) =>
                    setState(() => _handRaisingEnabled = value),
                activeTrackColor: accent,
                title: const Text(
                  'Allow audience to raise hands',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                subtitle: const Text(
                  'The host can invite selected listeners to the stage.',
                  style: TextStyle(color: _muted),
                ),
                tileColor: _surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: const BorderSide(color: _border),
                ),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(
          18,
          12,
          18,
          12 + MediaQuery.paddingOf(context).bottom,
        ),
        color: _surface,
        child: FilledButton(
          onPressed: _busy ? null : _create,
          style: FilledButton.styleFrom(
            backgroundColor: accent,
            minimumSize: const Size.fromHeight(56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          child: _busy
              ? const CircularProgressIndicator(color: Colors.white)
              : Text(
                  _isPodcast ? 'Go live with podcast' : 'Start community room',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
        ),
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.isPodcast, required this.accent});
  final bool isPodcast;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF171121),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF3A2C49)),
      ),
      child: Row(
        children: [
          Icon(
            isPodcast ? Icons.podcasts_rounded : Icons.groups_rounded,
            color: accent,
            size: 34,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              isPodcast
                  ? 'You control the stage. Listeners can request to speak.'
                  : 'A free-flowing room where everyone can join the conversation.',
              style: const TextStyle(color: Colors.white, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    this.maxLength,
    this.maxLines = 1,
    this.validator,
  });
  final TextEditingController controller;
  final String label;
  final String hint;
  final int? maxLength;
  final int maxLines;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator,
      maxLength: maxLength,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        counterText: '',
        filled: true,
        fillColor: const Color(0xFF171121),
        labelStyle: const TextStyle(color: Color(0xFFB8AFC2)),
        hintStyle: const TextStyle(color: Color(0xFF746A80)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
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
  });
  final String label;
  final String value;
  final List<String> values;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      dropdownColor: const Color(0xFF21172D),
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: const Color(0xFF171121),
        labelStyle: const TextStyle(color: Color(0xFFB8AFC2)),
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
