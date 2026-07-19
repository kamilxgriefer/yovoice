import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/rooms/presentation/screens/room_screen.dart';

class CreateRoomScreen extends StatefulWidget {
  const CreateRoomScreen({super.key});

  @override
  State<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends State<CreateRoomScreen> {
  static const Color _background = Color(0xFF080711);
  static const Color _surface = Color(0xFF151020);
  static const Color _border = Color(0xFF352A43);
  static const Color _primary = Color(0xFFA226FF);
  static const Color _secondaryText = Color(0xFF9D95AD);
  static const Color _error = Color(0xFFFF5678);

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _roomNameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  final RoomService _roomService = RoomService();

  RoomCategory _selectedCategory = RoomCategory.talk;
  RoomVisibility _selectedVisibility = RoomVisibility.public;
  RoomLimit _selectedLimit = RoomLimit.twentyFive;

  String _selectedLanguage = 'English';

  bool _isCreating = false;

  static const List<String> _languages = [
    'English',
    'Polish',
    'Dutch',
    'German',
    'French',
    'Spanish',
    'Italian',
  ];

  @override
  void dispose() {
    _roomNameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _createRoom() async {
    FocusScope.of(context).unfocus();

    final isValid = _formKey.currentState?.validate() ?? false;

    if (!isValid || _isCreating) {
      return;
    }

    setState(() {
      _isCreating = true;
    });

    try {
      final createdRoom = await _roomService.createRoom(
        name: _roomNameController.text.trim(),
        description: _descriptionController.text.trim(),
        category: _selectedCategory.name,
        visibility: _selectedVisibility.name,
        language: _selectedLanguage,
        maxParticipants: _selectedLimit.value,
      );

      if (!mounted) {
        return;
      }

      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (context) {
            return RoomScreen(room: createdRoom);
          },
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isCreating = false;
      });

      _showErrorMessage(_getReadableErrorMessage(error));
    }
  }

  String _getReadableErrorMessage(Object error) {
    final message = error.toString();

    if (message.contains('permission-denied')) {
      return 'Firestore permission denied. Check your Firebase security rules.';
    }

    if (message.contains('unavailable')) {
      return 'Firebase is currently unavailable. Check your internet connection.';
    }

    if (message.contains('signed in')) {
      return 'You must be signed in before creating a room.';
    }

    return 'Could not create the room. Please try again.';
  }

  void _showErrorMessage(String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF481C30),
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  void _showLanguagePicker() {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (context) {
        var temporaryLanguage = _selectedLanguage;

        return Container(
          height: 330,
          decoration: const BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 12, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Room language',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        onPressed: () {
                          setState(() {
                            _selectedLanguage = temporaryLanguage;
                          });

                          Navigator.of(context).pop();
                        },
                        child: const Text(
                          'Done',
                          style: TextStyle(
                            color: _primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: _border),
                Expanded(
                  child: CupertinoPicker(
                    backgroundColor: _surface,
                    itemExtent: 44,
                    scrollController: FixedExtentScrollController(
                      initialItem: _languages.indexOf(_selectedLanguage),
                    ),
                    onSelectedItemChanged: (index) {
                      temporaryLanguage = _languages[index];
                    },
                    children: _languages.map((language) {
                      return Center(
                        child: Text(
                          language,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leadingWidth: 64,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: IconButton(
            onPressed: _isCreating
                ? null
                : () {
                    Navigator.of(context).pop();
                  },
            icon: const Icon(
              Icons.close_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
        ),
        title: const Text(
          'Create room',
          style: TextStyle(
            color: Colors.white,
            fontSize: 19,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: true,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.85, -0.95),
            radius: 1.2,
            colors: [Color(0xFF25103E), Color(0xFF100B1A), _background],
            stops: [0, 0.42, 1],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 140),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _RoomHero(),
                  const SizedBox(height: 30),
                  const _SectionLabel(title: 'ROOM DETAILS'),
                  const SizedBox(height: 12),
                  _RoomTextField(
                    controller: _roomNameController,
                    label: 'Room name',
                    hintText: 'Give your room a name',
                    icon: Icons.graphic_eq_rounded,
                    textInputAction: TextInputAction.next,
                    maxLength: 50,
                    validator: (value) {
                      final roomName = value?.trim() ?? '';

                      if (roomName.isEmpty) {
                        return 'Enter a room name';
                      }

                      if (roomName.length < 3) {
                        return 'Room name must have at least 3 characters';
                      }

                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  _RoomTextField(
                    controller: _descriptionController,
                    label: 'Description',
                    hintText: 'What will people talk about?',
                    icon: Icons.notes_rounded,
                    textInputAction: TextInputAction.newline,
                    maxLength: 140,
                    maxLines: 4,
                  ),
                  const SizedBox(height: 28),
                  const _SectionLabel(title: 'CATEGORY'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: RoomCategory.values.map((category) {
                      return _CategoryChip(
                        category: category,
                        isSelected: category == _selectedCategory,
                        onPressed: () {
                          setState(() {
                            _selectedCategory = category;
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 28),
                  const _SectionLabel(title: 'VISIBILITY'),
                  const SizedBox(height: 12),
                  Row(
                    children: RoomVisibility.values.map((visibility) {
                      final isLast = visibility == RoomVisibility.values.last;

                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(right: isLast ? 0 : 10),
                          child: _VisibilityCard(
                            visibility: visibility,
                            isSelected: visibility == _selectedVisibility,
                            onPressed: () {
                              setState(() {
                                _selectedVisibility = visibility;
                              });
                            },
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 28),
                  const _SectionLabel(title: 'ROOM SIZE'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 9,
                    runSpacing: 9,
                    children: RoomLimit.values.map((limit) {
                      return _LimitChip(
                        limit: limit,
                        isSelected: limit == _selectedLimit,
                        onPressed: () {
                          setState(() {
                            _selectedLimit = limit;
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 28),
                  const _SectionLabel(title: 'LANGUAGE'),
                  const SizedBox(height: 12),
                  _LanguageSelector(
                    value: _selectedLanguage,
                    onPressed: _showLanguagePicker,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(
          18,
          14,
          18,
          14 + MediaQuery.paddingOf(context).bottom,
        ),
        decoration: const BoxDecoration(
          color: Color(0xF5151020),
          border: Border(top: BorderSide(color: _border)),
        ),
        child: _CreateRoomButton(
          isLoading: _isCreating,
          onPressed: _createRoom,
        ),
      ),
    );
  }
}

class _RoomHero extends StatelessWidget {
  const _RoomHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF54137F), Color(0xFF32104E), Color(0xFF1A1026)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF7330A5)),
      ),
      child: const Row(
        children: [
          _HeroIcon(),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Start a conversation',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Create a live voice room and invite people to join.',
                  style: TextStyle(
                    color: Color(0xFFD2C4DD),
                    fontSize: 13,
                    height: 1.45,
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

class _HeroIcon extends StatelessWidget {
  const _HeroIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFC63AFF), Color(0xFF7512F1)],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(color: Color(0x668D20FF), blurRadius: 22, spreadRadius: 1),
        ],
      ),
      child: const Icon(Icons.groups_2_rounded, color: Colors.white, size: 31),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: Color(0xFFA89FB6),
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _RoomTextField extends StatelessWidget {
  const _RoomTextField({
    required this.controller,
    required this.label,
    required this.hintText,
    required this.icon,
    required this.textInputAction,
    required this.maxLength,
    this.validator,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final String hintText;
  final IconData icon;
  final TextInputAction textInputAction;
  final int maxLength;
  final int maxLines;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator,
      textInputAction: textInputAction,
      maxLength: maxLength,
      maxLines: maxLines,
      minLines: maxLines > 1 ? 3 : 1,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
      cursorColor: _CreateRoomScreenState._primary,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        counterStyle: const TextStyle(
          color: _CreateRoomScreenState._secondaryText,
          fontSize: 11,
        ),
        labelStyle: const TextStyle(color: Color(0xFFB8AFC4), fontSize: 14),
        hintStyle: const TextStyle(color: Color(0xFF696172), fontSize: 14),
        prefixIcon: Padding(
          padding: EdgeInsets.only(
            left: 4,
            right: 2,
            bottom: maxLines > 1 ? 64 : 0,
          ),
          child: Icon(icon, color: const Color(0xFFAF4BFF), size: 22),
        ),
        filled: true,
        fillColor: _CreateRoomScreenState._surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: _CreateRoomScreenState._border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(
            color: _CreateRoomScreenState._primary,
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: _CreateRoomScreenState._error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(
            color: _CreateRoomScreenState._error,
            width: 1.5,
          ),
        ),
        errorStyle: const TextStyle(
          color: _CreateRoomScreenState._error,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.category,
    required this.isSelected,
    required this.onPressed,
  });

  final RoomCategory category;
  final bool isSelected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected
          ? _CreateRoomScreenState._primary
          : _CreateRoomScreenState._surface,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(15),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFFC65BFF)
                  : _CreateRoomScreenState._border,
            ),
            boxShadow: isSelected
                ? const [BoxShadow(color: Color(0x449D20FF), blurRadius: 14)]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                category.icon,
                color: isSelected ? Colors.white : const Color(0xFFB7AECA),
                size: 18,
              ),
              const SizedBox(width: 7),
              Text(
                category.label,
                style: TextStyle(
                  color: isSelected ? Colors.white : const Color(0xFFD1C9DB),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VisibilityCard extends StatelessWidget {
  const _VisibilityCard({
    required this.visibility,
    required this.isSelected,
    required this.onPressed,
  });

  final RoomVisibility visibility;
  final bool isSelected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected
          ? const Color(0xFF28123B)
          : _CreateRoomScreenState._surface,
      borderRadius: BorderRadius.circular(19),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(19),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(19),
            border: Border.all(
              color: isSelected
                  ? _CreateRoomScreenState._primary
                  : _CreateRoomScreenState._border,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    visibility.icon,
                    color: isSelected
                        ? const Color(0xFFBE4AFF)
                        : const Color(0xFFA69CAD),
                    size: 22,
                  ),
                  const Spacer(),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 19,
                    height: 19,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? _CreateRoomScreenState._primary
                          : Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected
                            ? _CreateRoomScreenState._primary
                            : const Color(0xFF645A6E),
                        width: 2,
                      ),
                    ),
                    child: isSelected
                        ? const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 13,
                          )
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 13),
              Text(
                visibility.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                visibility.description,
                style: const TextStyle(
                  color: _CreateRoomScreenState._secondaryText,
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

class _LimitChip extends StatelessWidget {
  const _LimitChip({
    required this.limit,
    required this.isSelected,
    required this.onPressed,
  });

  final RoomLimit limit;
  final bool isSelected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected
          ? _CreateRoomScreenState._primary
          : _CreateRoomScreenState._surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          constraints: const BoxConstraints(minWidth: 62),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFFC65BFF)
                  : _CreateRoomScreenState._border,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            limit.label,
            style: TextStyle(
              color: isSelected ? Colors.white : const Color(0xFFC9C1D3),
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _LanguageSelector extends StatelessWidget {
  const _LanguageSelector({required this.value, required this.onPressed});

  final String value;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _CreateRoomScreenState._surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _CreateRoomScreenState._border),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.language_rounded,
                color: Color(0xFFAF4BFF),
                size: 22,
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Color(0xFF8D8498),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreateRoomButton extends StatelessWidget {
  const _CreateRoomButton({required this.isLoading, required this.onPressed});

  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF6A00FF), Color(0xFFA12BFF), Color(0xFFC026FF)],
          ),
          borderRadius: BorderRadius.circular(19),
          boxShadow: const [
            BoxShadow(
              color: Color(0x559D20FF),
              blurRadius: 22,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: isLoading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            foregroundColor: Colors.white,
            disabledForegroundColor: Colors.white,
            disabledBackgroundColor: Colors.transparent,
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(19),
            ),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: isLoading
                ? const SizedBox(
                    key: ValueKey('loading'),
                    width: 23,
                    height: 23,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : const Row(
                    key: ValueKey('label'),
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.mic_rounded, size: 22),
                      SizedBox(width: 9),
                      Text(
                        'CREATE ROOM',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
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

enum RoomCategory {
  talk,
  music,
  gaming,
  chill,
  study,
  business;

  String get label {
    switch (this) {
      case RoomCategory.talk:
        return 'Talk';
      case RoomCategory.music:
        return 'Music';
      case RoomCategory.gaming:
        return 'Gaming';
      case RoomCategory.chill:
        return 'Chill';
      case RoomCategory.study:
        return 'Study';
      case RoomCategory.business:
        return 'Business';
    }
  }

  IconData get icon {
    switch (this) {
      case RoomCategory.talk:
        return Icons.forum_outlined;
      case RoomCategory.music:
        return Icons.music_note_rounded;
      case RoomCategory.gaming:
        return Icons.sports_esports_rounded;
      case RoomCategory.chill:
        return Icons.nightlife_rounded;
      case RoomCategory.study:
        return Icons.school_outlined;
      case RoomCategory.business:
        return Icons.work_outline_rounded;
    }
  }
}

enum RoomVisibility {
  public,
  private;

  String get label {
    switch (this) {
      case RoomVisibility.public:
        return 'Public';
      case RoomVisibility.private:
        return 'Private';
    }
  }

  String get description {
    switch (this) {
      case RoomVisibility.public:
        return 'Anyone can discover and join';
      case RoomVisibility.private:
        return 'Only invited people can join';
    }
  }

  IconData get icon {
    switch (this) {
      case RoomVisibility.public:
        return Icons.public_rounded;
      case RoomVisibility.private:
        return Icons.lock_outline_rounded;
    }
  }
}

enum RoomLimit {
  ten,
  twentyFive,
  fifty,
  oneHundred,
  unlimited;

  String get label {
    switch (this) {
      case RoomLimit.ten:
        return '10';
      case RoomLimit.twentyFive:
        return '25';
      case RoomLimit.fifty:
        return '50';
      case RoomLimit.oneHundred:
        return '100';
      case RoomLimit.unlimited:
        return '∞';
    }
  }

  int? get value {
    switch (this) {
      case RoomLimit.ten:
        return 10;
      case RoomLimit.twentyFive:
        return 25;
      case RoomLimit.fifty:
        return 50;
      case RoomLimit.oneHundred:
        return 100;
      case RoomLimit.unlimited:
        return null;
    }
  }
}

class RoomDraft {
  const RoomDraft({
    required this.name,
    required this.description,
    required this.category,
    required this.visibility,
    required this.limit,
    required this.language,
  });

  final String name;
  final String description;
  final RoomCategory category;
  final RoomVisibility visibility;
  final RoomLimit limit;
  final String language;
}
