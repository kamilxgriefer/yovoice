import 'package:flutter/material.dart';

import 'package:yovoice/features/rooms/data/models/room_experience.dart';
import 'package:yovoice/features/rooms/presentation/screens/create_room_screen.dart';

class RoomTypeSelectorScreen extends StatelessWidget {
  const RoomTypeSelectorScreen({super.key});

  static const _background = Color(0xFF080711);
  static const _primary = Color(0xFFA226FF);
  static const _muted = Color(0xFFA69CAF);

  void _open(BuildContext context, RoomExperience experience) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => CreateRoomScreen(experience: experience),
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
        title: const Text(
          'Choose room type',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
        children: [
          const Text(
            'How do you want people to talk?',
            style: TextStyle(
              color: Colors.white,
              fontSize: 27,
              fontWeight: FontWeight.w900,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Each room type has its own experience and moderation tools.',
            style: TextStyle(color: _muted, height: 1.45),
          ),
          const SizedBox(height: 26),
          _RoomChoice(
            title: 'Community Room',
            subtitle: 'A relaxed conversation where everyone can speak.',
            icon: Icons.groups_rounded,
            accent: _primary,
            features: const [
              'Free conversation',
              'Live chat and reactions',
              'Voice energy and orbital view',
            ],
            onTap: () => _open(context, RoomExperience.community),
          ),
          const SizedBox(height: 16),
          _RoomChoice(
            title: 'Podcast Room',
            subtitle: 'A hosted show with a stage, audience and requests.',
            icon: Icons.podcasts_rounded,
            accent: const Color(0xFFFF3F8E),
            features: const [
              'Host and speaker stage',
              'Audience raise hand queue',
              'Invite to stage and moderation',
            ],
            onTap: () => _open(context, RoomExperience.podcast),
          ),
        ],
      ),
    );
  }
}

class _RoomChoice extends StatelessWidget {
  const _RoomChoice({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.features,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final List<String> features;
  final VoidCallback onTap;

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
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: const Color(0xFF3A2C49)),
          ),
          child: Column(
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
              const SizedBox(height: 18),
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
