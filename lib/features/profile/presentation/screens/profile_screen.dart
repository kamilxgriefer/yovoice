import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/features/auth/data/auth_service.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final authService = AuthService();

    final username = user?.displayName?.trim().isNotEmpty == true
        ? user!.displayName!
        : 'YO Voice User';

    final email = user?.email ?? 'No email';

    return Scaffold(
      backgroundColor: const Color(0xFF0A0612),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topCenter,
            radius: 1.2,
            colors: [Color(0xFF26084A), Color(0xFF10081C), Color(0xFF08040E)],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 26, 20, 120),
            child: Column(
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Profile',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(
                        Icons.settings_outlined,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 35),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Color(0xFF6A00FF), Color(0xFFC026FF)],
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 52,
                    backgroundColor: const Color(0xFF241130),
                    child: Text(
                      username.characters.first.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 42,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  username,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  email,
                  style: const TextStyle(
                    color: Color(0xFFAFA5BC),
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 28),
                Row(
                  children: const [
                    Expanded(
                      child: _ProfileStat(value: '0', label: 'Friends'),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: _ProfileStat(value: '0', label: 'Followers'),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: _ProfileStat(value: '0', label: 'Rooms'),
                    ),
                  ],
                ),
                const SizedBox(height: 26),
                _ProfileOption(
                  icon: Icons.edit_outlined,
                  title: 'Edit profile',
                  onTap: () {},
                ),
                const SizedBox(height: 12),
                _ProfileOption(
                  icon: Icons.notifications_outlined,
                  title: 'Notifications',
                  onTap: () {},
                ),
                const SizedBox(height: 12),
                _ProfileOption(
                  icon: Icons.privacy_tip_outlined,
                  title: 'Privacy and safety',
                  onTap: () {},
                ),
                const SizedBox(height: 12),
                _ProfileOption(
                  icon: Icons.logout_rounded,
                  title: 'Log out',
                  iconColor: const Color(0xFFFF5C7C),
                  titleColor: const Color(0xFFFF8098),
                  onTap: () async {
                    await authService.signOut();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileStat extends StatelessWidget {
  const _ProfileStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 17),
      decoration: BoxDecoration(
        color: const Color(0xFF171021),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF382746)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: Color(0xFF968DA5), fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _ProfileOption extends StatelessWidget {
  const _ProfileOption({
    required this.icon,
    required this.title,
    required this.onTap,
    this.iconColor = const Color(0xFFA02BFF),
    this.titleColor = Colors.white,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Color iconColor;
  final Color titleColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF171021),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF382746)),
          ),
          child: Row(
            children: [
              Icon(icon, color: iconColor),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
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
