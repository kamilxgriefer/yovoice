import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    final displayName = user?.displayName?.trim().isNotEmpty == true
        ? user!.displayName!
        : 'there';

    return Scaffold(
      backgroundColor: const Color(0xFF0A0612),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topLeft,
            radius: 1.2,
            colors: [Color(0xFF250747), Color(0xFF10081C), Color(0xFF08040E)],
            stops: [0, 0.46, 1],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Header(displayName: displayName),
                const SizedBox(height: 28),
                const _WelcomeCard(),
                const SizedBox(height: 32),
                const _SectionHeader(
                  title: 'Trending rooms',
                  actionLabel: 'See all',
                ),
                const SizedBox(height: 16),
                const _RoomCard(
                  title: 'Late Night Chill',
                  category: 'Music & vibes',
                  listeners: 128,
                  icon: Icons.headphones_rounded,
                  accent: Color(0xFFA22BFF),
                  participants: ['A', 'M', 'J'],
                ),
                const SizedBox(height: 14),
                const _RoomCard(
                  title: 'Gaming Squad',
                  category: 'Games',
                  listeners: 84,
                  icon: Icons.sports_esports_rounded,
                  accent: Color(0xFF5669FF),
                  participants: ['K', 'R', 'S'],
                ),
                const SizedBox(height: 14),
                const _RoomCard(
                  title: 'Open Mic',
                  category: 'Talk & comedy',
                  listeners: 46,
                  icon: Icons.mic_rounded,
                  accent: Color(0xFFFF3D9A),
                  participants: ['L', 'P', 'T'],
                ),
                const SizedBox(height: 32),
                const _SectionHeader(
                  title: 'Friends online',
                  actionLabel: 'View all',
                ),
                const SizedBox(height: 16),
                const _FriendsRow(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.displayName});

  final String displayName;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF6A00FF), Color(0xFFC026FF)],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(
            Icons.graphic_eq_rounded,
            color: Colors.white,
            size: 30,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hello, $displayName',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              const Text(
                'What do you want to hear today?',
                style: TextStyle(color: Color(0xFFAAA0BA), fontSize: 14),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () {},
          icon: const Badge(
            smallSize: 8,
            child: Icon(
              Icons.notifications_none_rounded,
              color: Colors.white,
              size: 29,
            ),
          ),
        ),
      ],
    );
  }
}

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6B16C5), Color(0xFF341061), Color(0xFF191027)],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFF8F43D0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x553D0870),
            blurRadius: 25,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Create your own room',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Start talking and invite people to join your conversation.',
                  style: TextStyle(
                    color: Color(0xFFD4C9DF),
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Create room'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF4E108B),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Container(
            width: 86,
            height: 86,
            decoration: BoxDecoration(
              color: const Color(0x33FFFFFF),
              borderRadius: BorderRadius.circular(28),
            ),
            child: const Icon(Icons.mic_rounded, color: Colors.white, size: 48),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.actionLabel});

  final String title;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        TextButton(
          onPressed: () {},
          child: Text(
            actionLabel,
            style: const TextStyle(color: Color(0xFFAF4CFF)),
          ),
        ),
      ],
    );
  }
}

class _RoomCard extends StatelessWidget {
  const _RoomCard({
    required this.title,
    required this.category,
    required this.listeners,
    required this.icon,
    required this.accent,
    required this.participants,
  });

  final String title;
  final String category;
  final int listeners;
  final IconData icon;
  final Color accent;
  final List<String> participants;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF171021),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () {},
        child: Container(
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFF362746)),
          ),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, color: accent, size: 30),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      category,
                      style: const TextStyle(
                        color: Color(0xFF968DA5),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 9),
                    Row(
                      children: [
                        const Icon(
                          Icons.headset_mic_outlined,
                          size: 17,
                          color: Color(0xFFB8AEC6),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '$listeners listening',
                          style: const TextStyle(
                            color: Color(0xFFB8AEC6),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 73,
                height: 38,
                child: Stack(
                  children: List.generate(participants.length, (index) {
                    return Positioned(
                      left: index * 18,
                      child: CircleAvatar(
                        radius: 18,
                        backgroundColor: Color.lerp(
                          accent,
                          const Color(0xFF171021),
                          index * 0.18,
                        ),
                        child: Text(
                          participants[index],
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF81758F)),
            ],
          ),
        ),
      ),
    );
  }
}

class _FriendsRow extends StatelessWidget {
  const _FriendsRow();

  static const _friends = [
    ('Alex', 'A'),
    ('Mia', 'M'),
    ('Noah', 'N'),
    ('Lena', 'L'),
    ('Sam', 'S'),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _friends.length,
        separatorBuilder: (_, _) => const SizedBox(width: 18),
        itemBuilder: (context, index) {
          final friend = _friends[index];

          return Column(
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 29,
                    backgroundColor: const Color(0xFF6D25A8),
                    child: Text(
                      friend.$2,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 1,
                    bottom: 2,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: const Color(0xFF45D483),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF0A0612),
                          width: 3,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                friend.$1,
                style: const TextStyle(color: Color(0xFFD1C8DC), fontSize: 13),
              ),
            ],
          );
        },
      ),
    );
  }
}
