import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_image_service.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/rooms/presentation/screens/room_screen.dart';

class CreateRoomScreen extends StatefulWidget {
  const CreateRoomScreen({super.key});

  @override
  State<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends State<CreateRoomScreen> {
  static const _background = Color(0xFF080711);
  static const _surface = Color(0xFF151020);
  static const _border = Color(0xFF352A43);
  static const _primary = Color(0xFFA226FF);
  static const _muted = Color(0xFF9D95AD);

  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _service = RoomService();
  final _imageService = RoomImageService();

  RoomType _type = RoomType.community;
  String _category = 'talk';
  String _visibility = 'public';
  String _language = 'English';
  int? _maxParticipants = 25;
  XFile? _image;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final image = await _imageService.pickImage();
    if (image != null && mounted) {
      setState(() => _image = image);
    }
  }

  Future<void> _create() async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _busy = true);

    try {
      var room = await _service.createRoom(
        name: _name.text,
        description: _description.text,
        category: _category,
        visibility: _visibility,
        language: _language,
        maxParticipants: _maxParticipants,
        roomType: _type,
      );

      if (_image != null) {
        final imageUrl = await _imageService.uploadRoomImage(
          roomId: room.id,
          file: _image!,
        );
        await _service.updateImageUrl(roomId: room.id, imageUrl: imageUrl);
        room = room;
      }

      if (!mounted) return;

      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => RoomScreen(room: room)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF481C30),
        ),
      );
      setState(() => _busy = false);
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
          'Create room',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        centerTitle: true,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 130),
          children: [
            const Text(
              'ROOM TYPE',
              style: TextStyle(
                color: _muted,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _TypeCard(
                    title: 'Community',
                    subtitle: 'Persistent server with saved chat',
                    icon: Icons.hub_rounded,
                    selected: _type == RoomType.community,
                    onTap: () => setState(() => _type = RoomType.community),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _TypeCard(
                    title: 'Temporary',
                    subtitle: 'Quick live conversation',
                    icon: Icons.bolt_rounded,
                    selected: _type == RoomType.temporary,
                    onTap: () => setState(() => _type = RoomType.temporary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 26),
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                height: 160,
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: _border),
                ),
                child: _image == null
                    ? const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_photo_alternate_rounded,
                            color: _primary,
                            size: 42,
                          ),
                          SizedBox(height: 10),
                          Text(
                            'Add room image',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Optional — you can add it later',
                            style: TextStyle(color: _muted, fontSize: 12),
                          ),
                        ],
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(23),
                        child: Image.network(
                          _image!.path,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Center(
                            child: Icon(
                              Icons.image_rounded,
                              color: _primary,
                              size: 46,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 22),
            _Field(
              controller: _name,
              label: 'Room name',
              hint: 'e.g. Gaming Lounge',
              maxLength: 50,
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.length < 3) return 'Enter at least 3 characters';
                return null;
              },
            ),
            const SizedBox(height: 14),
            _Field(
              controller: _description,
              label: 'Description',
              hint: 'Tell people what this room is about',
              maxLength: 160,
              maxLines: 4,
            ),
            const SizedBox(height: 22),
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
                'Italian',
              ],
              onChanged: (value) => setState(() => _language = value),
            ),
            const SizedBox(height: 14),
            _Dropdown(
              label: 'Voice capacity',
              value: _maxParticipants?.toString() ?? 'Unlimited',
              values: const ['10', '25', '50', '100', 'Unlimited'],
              onChanged: (value) {
                setState(() {
                  _maxParticipants = value == 'Unlimited'
                      ? null
                      : int.parse(value);
                });
              },
            ),
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
        decoration: const BoxDecoration(
          color: _surface,
          border: Border(top: BorderSide(color: _border)),
        ),
        child: FilledButton(
          onPressed: _busy ? null : _create,
          style: FilledButton.styleFrom(
            backgroundColor: _primary,
            minimumSize: const Size.fromHeight(56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          child: _busy
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Colors.white,
                  ),
                )
              : Text(
                  _type == RoomType.community
                      ? 'Create community'
                      : 'Start temporary room',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
        ),
      ),
    );
  }
}

class _TypeCard extends StatelessWidget {
  const _TypeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFF2A153C) : const Color(0xFF151020),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: 150,
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? const Color(0xFFA226FF)
                  : const Color(0xFF352A43),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: const Color(0xFFC75CFF), size: 30),
              const Spacer(),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Color(0xFF9D95AD),
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
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
        labelStyle: const TextStyle(color: Color(0xFFB6AFC0)),
        hintStyle: const TextStyle(color: Color(0xFF766D82)),
        filled: true,
        fillColor: const Color(0xFF151020),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFF352A43)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFF352A43)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFA226FF)),
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
        labelStyle: const TextStyle(color: Color(0xFFB6AFC0)),
        filled: true,
        fillColor: const Color(0xFF151020),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
      ),
      items: values
          .map(
            (item) => DropdownMenuItem<String>(value: item, child: Text(item)),
          )
          .toList(growable: false),
      onChanged: (item) {
        if (item != null) onChanged(item);
      },
    );
  }
}
