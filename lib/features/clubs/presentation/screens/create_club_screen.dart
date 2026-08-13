import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/space_identity.dart';
import 'package:image_picker/image_picker.dart';

import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/features/clubs/presentation/screens/club_created_screen.dart';

class CreateClubScreen extends StatefulWidget {
  const CreateClubScreen({
    this.type = ClubType.community,
    this.clubService,
    super.key,
  });

  /// Which space this screen is creating. A Family Room is the same club
  /// document with a private boundary, so it reuses this whole flow —
  /// only the wording, the accent and the privacy choice differ.
  final ClubType type;

  bool get isFamily => type == ClubType.family;

  /// Injected in tests, exactly as the Home surfaces do it: production
  /// passes nothing and the screen resolves its own, which needs a live
  /// Firebase app.
  final ClubService? clubService;

  @override
  State<CreateClubScreen> createState() => _CreateClubScreenState();
}

class _CreateClubScreenState extends State<CreateClubScreen> {
  /// Every colour on this screen comes from here. The Family flow used to
  /// inherit Club violet wholesale, which is exactly the failure a single
  /// identity source exists to prevent.
  SpaceIdentity get _identity =>
      widget.isFamily ? SpaceIdentity.family : SpaceIdentity.club;

  /// Focus rings, selected chips, benefit ticks and the CTA all read this.
  Color get _primary => _identity.primary;

  static const _background = Color(0xFF080711);
  static const _surface = Color(0xFF171121);
  static const _surfaceStrong = Color(0xFF21162D);
  static const _border = Color(0xFF3A2C49);
  static const _muted = Color(0xFFA69CAF);

  static const _languages = <String>[
    'English',
    'Polish',
    'Dutch',
    'German',
    'Spanish',
    'French',
    'Italian',
    'Portuguese',
    'Japanese',
    'Korean',
  ];

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  late final ClubService _clubService = widget.clubService ?? ClubService();
  final _picker = ImagePicker();

  ClubPrivacy _privacy = ClubPrivacy.public;
  String _language = 'English';
  bool _busy = false;
  bool _pickingImage = false;

  XFile? _avatarFile;
  XFile? _bannerFile;
  Uint8List? _avatarBytes;
  Uint8List? _bannerBytes;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickImage({required bool avatar}) async {
    if (_busy || _pickingImage) return;
    setState(() => _pickingImage = true);

    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
        maxWidth: avatar ? 1200 : 2200,
        maxHeight: avatar ? 1200 : 1200,
      );
      if (file == null) return;

      final bytes = await file.readAsBytes();
      if (bytes.length > 8 * 1024 * 1024) {
        throw StateError('The selected image must be smaller than 8 MB.');
      }

      if (!mounted) return;
      setState(() {
        if (avatar) {
          _avatarFile = file;
          _avatarBytes = bytes;
        } else {
          _bannerFile = file;
          _bannerBytes = bytes;
        }
      });
    } catch (error) {
      if (!mounted) return;
      _showError(_readableError(error));
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  Future<void> _createClub() async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _busy = true);
    try {
      final club = widget.isFamily
          // Deterministic id, invite-only, no Premium requirement — the
          // service owns those invariants so no caller can get them
          // wrong.
          ? await _clubService.createFamilyRoom(
              name: _nameController.text,
              description: _descriptionController.text,
              defaultLanguage: _language,
              avatarFile: _avatarFile,
            )
          : await _clubService.createClub(
              name: _nameController.text,
              description: _descriptionController.text,
              privacy: _privacy,
              defaultLanguage: _language,
              avatarFile: _avatarFile,
              bannerFile: _bannerFile,
            );

      if (!mounted) return;
      await Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute<void>(builder: (_) => ClubCreatedScreen(club: club)),
      );
    } catch (error) {
      if (!mounted) return;
      _showError(_readableError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _readableError(Object error) {
    final message = error
        .toString()
        .replaceFirst('Bad state: ', '')
        .replaceFirst('Invalid argument(s): ', '');
    if (message.contains('permission-denied')) {
      return 'Firestore or Storage permission denied. Deploy the new rules from this stage.';
    }
    if (message.contains('object-not-found')) {
      return 'The uploaded image could not be found.';
    }
    if (message.contains('unauthorized')) {
      return 'Storage rejected the upload. Deploy storage.rules.';
    }
    return message;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF48203A),
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: Colors.white,
        centerTitle: true,
        title: Text(
          widget.isFamily ? 'Create Family Room' : 'Create Club',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 130),
          children: [
            _HeroCard(identity: _identity, isFamily: widget.isFamily),
            const SizedBox(height: 24),
            _SectionTitle(
              title: widget.isFamily ? 'Family identity' : 'Club identity',
              subtitle: widget.isFamily
                  ? 'Name the space your family will recognize.'
                  : 'Give your people a place they will recognize.',
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _MediaPickerCard(
                    icon: Icons.groups_2_rounded,
                    label: widget.isFamily ? 'Family avatar' : 'Club avatar',
                    helper: _avatarBytes == null
                        ? 'Choose image'
                        : 'Tap to replace',
                    bytes: _avatarBytes,
                    circularPreview: true,
                    onTap: () => _pickImage(avatar: true),
                    onRemove: _avatarBytes == null
                        ? null
                        : () => setState(() {
                            _avatarFile = null;
                            _avatarBytes = null;
                          }),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _MediaPickerCard(
                    icon: Icons.image_rounded,
                    label: widget.isFamily ? 'Family banner' : 'Club banner',
                    helper: _bannerBytes == null
                        ? 'Choose image'
                        : 'Tap to replace',
                    bytes: _bannerBytes,
                    onTap: () => _pickImage(avatar: false),
                    onRemove: _bannerBytes == null
                        ? null
                        : () => setState(() {
                            _bannerFile = null;
                            _bannerBytes = null;
                          }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _Field(
              controller: _nameController,
              label: widget.isFamily ? 'Family name' : 'Club name',
              hint: 'e.g. YO Voice Founders',
              maxLength: 40,
              validator: (value) {
                final length = value?.trim().length ?? 0;
                if (length < 3) return 'Enter at least 3 characters';
                return null;
              },
            ),
            const SizedBox(height: 14),
            _Field(
              controller: _descriptionController,
              label: 'Description',
              hint: 'What brings this club together?',
              maxLength: 220,
              maxLines: 4,
            ),
            const SizedBox(height: 26),
            // A Family Room has exactly one privacy model, so there is
            // nothing to choose: offering "Public" on a space defined as
            // private would be a lie the service would then ignore.
            if (!widget.isFamily) ...[
              const _SectionTitle(
                title: 'Privacy',
                subtitle: 'Choose how new members can enter.',
              ),
              const SizedBox(height: 14),
              _PrivacyChoice(
                title: 'Public',
                subtitle: 'Anyone can discover and join the club.',
                icon: Icons.public_rounded,
                value: ClubPrivacy.public,
                selectedValue: _privacy,
                onChanged: (value) => setState(() => _privacy = value),
              ),
              const SizedBox(height: 10),
              _PrivacyChoice(
                title: 'Private',
                subtitle: 'The club is hidden and members join by invitation.',
                icon: Icons.lock_rounded,
                value: ClubPrivacy.private,
                selectedValue: _privacy,
                onChanged: (value) => setState(() => _privacy = value),
              ),
              const SizedBox(height: 10),
              _PrivacyChoice(
                title: 'Invite only',
                subtitle: 'Visible club, but every member needs an invite.',
                icon: Icons.mail_rounded,
                value: ClubPrivacy.inviteOnly,
                selectedValue: _privacy,
                onChanged: (value) => setState(() => _privacy = value),
              ),
            ],
            const SizedBox(height: 26),
            _SectionTitle(
              title: widget.isFamily
                  ? 'Primary family language'
                  : 'Default language',
              subtitle: widget.isFamily
                  ? 'Everyone can still speak any language here.'
                  : 'Members can still use any language in the club.',
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _language,
              dropdownColor: _surfaceStrong,
              iconEnabledColor: _primary,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor: _surface,
                prefixIcon: Icon(Icons.language_rounded, color: _primary),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(color: _border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(color: _border),
                ),
              ),
              items: _languages
                  .map(
                    (language) => DropdownMenuItem<String>(
                      value: language,
                      child: Text(language),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value != null) setState(() => _language = value);
              },
            ),
            const SizedBox(height: 24),
            _WhatGetsCreatedCard(isFamily: widget.isFamily),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
          decoration: const BoxDecoration(
            color: Color(0xFF100B18),
            border: Border(top: BorderSide(color: Color(0xFF30243D))),
          ),
          child: SizedBox(
            height: 58,
            child: FilledButton.icon(
              onPressed: _busy || _pickingImage ? null : _createClub,
              style: FilledButton.styleFrom(
                backgroundColor: _primary,
                disabledBackgroundColor: _primary.withValues(alpha: .45),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(19),
                ),
              ),
              icon: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.add_business_rounded),
              label: Text(
                _busy
                    ? (widget.isFamily
                          ? 'Creating Family Room...'
                          : 'Creating club...')
                    : (widget.isFamily
                          ? 'Create Family Room'
                          : 'Create Club'),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.identity, required this.isFamily});

  final SpaceIdentity identity;
  final bool isFamily;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF35104F), Color(0xFF171121)],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFF7130A5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ClubMark(identity: identity),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Build your home on YO Voice',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  isFamily
                      ? 'A private, invite-only space for the people '
                            'closest to you.'
                      : 'A Club is permanent: members, roles, a main chat, '
                            'announcements and a private voice lounge.',
                  style: TextStyle(
                    color: Color(0xFFD1C4DA),
                    height: 1.42,
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

class _ClubMark extends StatelessWidget {
  const _ClubMark({required this.identity});

  final SpaceIdentity identity;

  @override
  Widget build(BuildContext context) => Container(
    width: 62,
    height: 62,
    decoration: BoxDecoration(
      color: identity.wash,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: identity.primary),
    ),
    child: Icon(identity.icon, color: identity.accent, size: 34),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 19,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        subtitle,
        style: const TextStyle(
          color: _CreateClubScreenState._muted,
          height: 1.35,
        ),
      ),
    ],
  );
}

class _MediaPickerCard extends StatelessWidget {
  const _MediaPickerCard({
    required this.icon,
    required this.label,
    required this.helper,
    required this.onTap,
    this.bytes,
    this.circularPreview = false,
    this.onRemove,
  });
  final IconData icon;
  final String label;
  final String helper;
  final VoidCallback onTap;
  final Uint8List? bytes;
  final bool circularPreview;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF171121),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: 150,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF3A2C49)),
          ),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (bytes == null)
                      Icon(icon, color: const Color(0xFFA226FF), size: 32)
                    else
                      ClipRRect(
                        borderRadius: BorderRadius.circular(
                          circularPreview ? 999 : 14,
                        ),
                        child: Image.memory(
                          bytes!,
                          width: circularPreview ? 64 : double.infinity,
                          height: 64,
                          fit: BoxFit.cover,
                        ),
                      ),
                    const SizedBox(height: 10),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      helper,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFA69CAF),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (onRemove != null)
                Positioned(
                  top: 0,
                  right: 0,
                  child: IconButton.filledTonal(
                    tooltip: 'Remove image',
                    visualDensity: VisualDensity.compact,
                    onPressed: onRemove,
                    icon: const Icon(Icons.close_rounded, size: 17),
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
    required this.maxLength,
    this.maxLines = 1,
    this.validator,
  });
  final TextEditingController controller;
  final String label;
  final String hint;
  final int maxLength;
  final int maxLines;
  final String? Function(String?)? validator;
  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    maxLength: maxLength,
    maxLines: maxLines,
    validator: validator,
    style: const TextStyle(color: Colors.white),
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      counterStyle: const TextStyle(color: Color(0xFF8F8598)),
      labelStyle: const TextStyle(color: Color(0xFFA69CAF)),
      hintStyle: const TextStyle(color: Color(0xFF756D82)),
      filled: true,
      fillColor: const Color(0xFF171121),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFF3A2C49)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFFA226FF), width: 1.5),
      ),
    ),
  );
}

class _PrivacyChoice extends StatelessWidget {
  const _PrivacyChoice({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.value,
    required this.selectedValue,
    required this.onChanged,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final ClubPrivacy value;
  final ClubPrivacy selectedValue;
  final ValueChanged<ClubPrivacy> onChanged;
  @override
  Widget build(BuildContext context) {
    final selected = value == selectedValue;
    return Material(
      color: selected ? const Color(0xFF261438) : const Color(0xFF171121),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: () => onChanged(value),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? const Color(0xFFA226FF)
                  : const Color(0xFF3A2C49),
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: selected
                    ? const Color(0xFFBE63FF)
                    : const Color(0xFFA69CAF),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFFA69CAF),
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected
                      ? const Color(0xFFA226FF)
                      : Colors.transparent,
                  border: Border.all(
                    color: selected
                        ? const Color(0xFFA226FF)
                        : const Color(0xFF70657A),
                    width: 2,
                  ),
                ),
                child: selected
                    ? const Icon(
                        Icons.check_rounded,
                        size: 16,
                        color: Colors.white,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WhatGetsCreatedCard extends StatelessWidget {
  const _WhatGetsCreatedCard({required this.isFamily});

  final bool isFamily;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      color: const Color(0xFF14101C),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFF33283E)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Created automatically',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 12),
        _CreatedItem(
          icon: Icons.tag_rounded,
          text: isFamily ? 'Family chat' : 'General chat',
        ),
        _CreatedItem(
          icon: Icons.campaign_rounded,
          text: isFamily ? 'Announcements' : 'Announcements channel',
        ),
        _CreatedItem(
          icon: Icons.graphic_eq_rounded,
          text: isFamily ? 'Family Lounge' : 'Private Club Lounge',
        ),
        if (isFamily)
          _CreatedItem(
            icon: Icons.waving_hand_rounded,
            text: 'Quick check-ins',
          ),
        _CreatedItem(
          icon: Icons.admin_panel_settings_rounded,
          text: isFamily
              ? 'Organizer role and membership'
              : 'Owner role and membership',
        ),
      ],
    ),
  );
}

class _CreatedItem extends StatelessWidget {
  const _CreatedItem({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Row(
      children: [
        Icon(icon, color: const Color(0xFFBE63FF), size: 19),
        const SizedBox(width: 10),
        // Unconstrained, this Text overflowed the row on a 390pt phone —
        // the longest of these lines does not fit beside the icon.
        Expanded(
          child: Text(text, style: const TextStyle(color: Color(0xFFD0C7D6))),
        ),
      ],
    ),
  );
}
