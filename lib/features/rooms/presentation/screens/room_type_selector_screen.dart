import 'package:flutter/material.dart';

import 'package:yovoice/features/clubs/presentation/screens/create_club_screen.dart';
import 'package:yovoice/features/rooms/data/models/room_experience.dart';
import 'package:yovoice/features/rooms/presentation/screens/create_room_screen.dart';

class RoomTypeSelectorScreen extends StatelessWidget {
  const RoomTypeSelectorScreen({super.key});

  static const _background = Color(0xFF080711);
  static const _primary = Color(0xFFA226FF);
  static const _muted = Color(0xFFA69CAF);

  void _openRoom(BuildContext context, RoomExperience experience) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => CreateRoomScreen(experience: experience),
      ),
    );
  }

  void _openClub(BuildContext context) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const CreateClubScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: Colors.white,
        title: const Text(
          'Create',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
        children: [
          const Text(
            'What do you want to build?',
            style: TextStyle(
              color: Colors.white,
              fontSize: 27,
              fontWeight: FontWeight.w900,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Start a conversation, host an audience or build a permanent home for your people.',
            style: TextStyle(color: _muted, height: 1.45),
          ),
          const SizedBox(height: 26),
          _RoomChoice(
            title: 'Community Room',
            eyebrow: 'OPEN CONVERSATION',
            subtitle: 'A relaxed live room where everyone can speak.',
            icon: Icons.groups_rounded,
            accent: _primary,
            features: const [
              'Free-flowing voice conversation',
              'Live chat and reactions',
              'Cosmic orbital room experience',
            ],
            onTap: () => _openRoom(context, RoomExperience.community),
          ),
          const SizedBox(height: 16),
          _RoomChoice(
            title: 'Podcast Room',
            eyebrow: 'HOST + AUDIENCE',
            subtitle: 'A hosted show with a stage, audience and requests.',
            icon: Icons.podcasts_rounded,
            accent: const Color(0xFFFF426E),
            features: const [
              'Host and speaker stage',
              'Audience raise-hand queue',
              'Invite to stage and moderation',
            ],
            onTap: () => _openRoom(context, RoomExperience.broadcast),
          ),
          const SizedBox(height: 16),
          _RoomChoice(
            title: 'Club',
            eyebrow: 'PERMANENT COMMUNITY',
            subtitle: 'Members, roles, chat, announcements and a Club Lounge.',
            icon: Icons.shield_rounded,
            accent: const Color(0xFFB94DFF),
            highlighted: true,
            features: const [
              'Invite friends and manage members',
              'Owner, Co-owner, Admin and more',
              'Persistent chat and private voice lounge',
            ],
            onTap: () => _openClub(context),
          ),
        ],
      ),
    );
  }
}

class _RoomChoice extends StatelessWidget {
  const _RoomChoice({
    required this.title,
    required this.eyebrow,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.features,
    required this.onTap,
    this.highlighted = false,
  });

  final String title;
  final String eyebrow;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final List<String> features;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF171121),
      borderRadius: BorderRadius.circular(26),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(26),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: highlighted
                ? const LinearGradient(
                    colors: [Color(0xFF281238), Color(0xFF171121)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: highlighted
                  ? const Color(0xFF7E35AD)
                  : const Color(0xFF3A2C49),
              width: highlighted ? 1.5 : 1,
            ),
            boxShadow: highlighted
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: .12),
                      blurRadius: 24,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: .17),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(icon, color: accent, size: 30),
                  ),
                  const Spacer(),
                  if (highlighted)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: .15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: accent.withValues(alpha: .55),
                        ),
                      ),
                      child: Text(
                        'NEW',
                        style: TextStyle(
                          color: accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                eyebrow,
                style: TextStyle(
                  color: accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.25,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Icon(Icons.arrow_forward_rounded, color: accent),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: const TextStyle(color: Color(0xFFA69CAF), height: 1.4),
              ),
              const SizedBox(height: 17),
              ...features.map(
                (feature) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_rounded, color: accent, size: 17),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          feature,
                          style: const TextStyle(
                            color: Color(0xFFD7D0DE),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
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
