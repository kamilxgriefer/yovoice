import 'package:flutter/material.dart';

import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/features/clubs/presentation/screens/club_created_screen.dart';

class CreateClubScreen extends StatefulWidget {
  const CreateClubScreen({super.key});

  @override
  State<CreateClubScreen> createState() => _CreateClubScreenState();
}

class _CreateClubScreenState extends State<CreateClubScreen> {
  static const _background = Color(0xFF080711);
  static const _surface = Color(0xFF171121);
  static const _surfaceStrong = Color(0xFF21162D);
  static const _border = Color(0xFF3A2C49);
  static const _primary = Color(0xFFA226FF);
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
  final _clubService = ClubService();

  ClubPrivacy _privacy = ClubPrivacy.public;
  String _language = 'English';
  bool _busy = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _createClub() async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _busy = true);
    try {
      final club = await _clubService.createClub(
        name: _nameController.text,
        description: _descriptionController.text,
        privacy: _privacy,
        defaultLanguage: _language,
      );

      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => ClubCreatedScreen(club: club)),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error
                .toString()
                .replaceFirst('Bad state: ', '')
                .replaceFirst('Invalid argument(s): ', ''),
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
        centerTitle: true,
        title: const Text(
          'Create Club',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 130),
          children: [
            const _HeroCard(),
            const SizedBox(height: 24),
            const _SectionTitle(
              title: 'Club identity',
              subtitle: 'Give your people a place they will recognize.',
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _MediaPlaceholder(
                    icon: Icons.groups_2_rounded,
                    label: 'Club avatar',
                    helper: 'Available next stage',
                    onTap: _showMediaInfo,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _MediaPlaceholder(
                    icon: Icons.image_rounded,
                    label: 'Club banner',
                    helper: 'Available next stage',
                    onTap: _showMediaInfo,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _Field(
              controller: _nameController,
              label: 'Club name',
              hint: 'e.g. YoVoice Founders',
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
            const SizedBox(height: 26),
            const _SectionTitle(
              title: 'Default language',
              subtitle: 'Members can still use any language in the club.',
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
                prefixIcon: const Icon(Icons.language_rounded, color: _primary),
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
            const _WhatGetsCreatedCard(),
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
              onPressed: _busy ? null : _createClub,
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
                _busy ? 'Creating club...' : 'Create Club',
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

  void _showMediaInfo() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Avatar and banner upload will be connected in the next Clubs stage.',
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF35104F), Color(0xFF171121)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFF7130A5)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ClubMark(),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Build your home on YoVoice',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'A Club is permanent: members, roles, a main chat, announcements and a private voice lounge.',
                  style: TextStyle(color: Color(0xFFD1C4DA), height: 1.42),
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
  const _ClubMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 62,
      height: 62,
      decoration: BoxDecoration(
        color: const Color(0xFFA226FF).withValues(alpha: .18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFA226FF)),
      ),
      child: const Icon(
        Icons.shield_rounded,
        color: Color(0xFFBE63FF),
        size: 34,
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
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
}

class _MediaPlaceholder extends StatelessWidget {
  const _MediaPlaceholder({
    required this.icon,
    required this.label,
    required this.helper,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String helper;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF171121),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: 126,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF3A2C49)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: const Color(0xFFA226FF), size: 30),
              const SizedBox(height: 10),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                helper,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF81768C), fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
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

  bool get _selected => value == selectedValue;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF171121),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: () => onChanged(value),
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _selected
                  ? const Color(0xFFA226FF)
                  : const Color(0xFF3A2C49),
              width: _selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(
                    0xFFA226FF,
                  ).withValues(alpha: _selected ? .2 : .09),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: const Color(0xFFB94DFF)),
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
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: _CreateClubScreenState._muted,
                        height: 1.3,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                _selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: _selected
                    ? const Color(0xFFA226FF)
                    : const Color(0xFF6F6479),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WhatGetsCreatedCard extends StatelessWidget {
  const _WhatGetsCreatedCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF15101E),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF3A2C49)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Created automatically',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 14),
          _FeatureRow(icon: Icons.chat_bubble_rounded, text: '# general chat'),
          SizedBox(height: 11),
          _FeatureRow(icon: Icons.campaign_rounded, text: '# announcements'),
          SizedBox(height: 11),
          _FeatureRow(icon: Icons.mic_rounded, text: 'Club Lounge'),
          SizedBox(height: 11),
          _FeatureRow(
            icon: Icons.workspace_premium_rounded,
            text: 'You as Owner',
          ),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFFB94DFF), size: 20),
        const SizedBox(width: 11),
        Text(
          text,
          style: const TextStyle(
            color: Color(0xFFD7D0DE),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
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
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFF3A2C49)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFA226FF), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFFF5B86)),
        ),
      ),
    );
  }
}
