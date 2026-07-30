import 'package:flutter/material.dart';
import 'package:yovoice/features/clubs/presentation/screens/clubs_screen.dart';
import 'package:yovoice/features/discover/presentation/screens/discover_screen.dart';
import 'package:yovoice/features/friends/presentation/screens/friends_screen.dart';

enum MoreDestination {
  friends,
  discover,
  clubs,
  notifications,
  achievements,
  creatorStudio,
  settings,
}

Future<MoreDestination?> showMoreSheet(BuildContext context) {
  return showModalBottomSheet<MoreDestination>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.72),
    builder: (_) => const MoreSheet(),
  );
}

Widget moreDestinationScreen(MoreDestination destination) {
  return switch (destination) {
    MoreDestination.friends => const FriendsScreen(),
    MoreDestination.discover => const DiscoverScreen(),
    MoreDestination.clubs => const ClubsScreen(),
    MoreDestination.notifications => const _MoreFeatureScreen(
      icon: Icons.notifications_rounded,
      title: 'Alerts',
      subtitle: 'Your friend requests, room invitations and app updates.',
      items: [
        'Friend requests and social activity',
        'Invitations to live rooms and clubs',
        'Important YoVoice announcements',
      ],
    ),
    MoreDestination.achievements => const _MoreFeatureScreen(
      icon: Icons.emoji_events_rounded,
      title: 'Awards',
      subtitle: 'Track achievements and your progress across YoVoice.',
      items: [
        'Unlocked achievements',
        'Voice and community milestones',
        'Upcoming rewards and challenges',
      ],
    ),
    MoreDestination.creatorStudio => const _MoreFeatureScreen(
      icon: Icons.auto_graph_rounded,
      title: 'Creator Studio',
      subtitle: 'Tools for creators, broadcasts and audience growth.',
      items: [
        'Broadcast and Voice Moment overview',
        'Followers and audience insights',
        'Creator profile tools',
      ],
    ),
    MoreDestination.settings => const _MoreFeatureScreen(
      icon: Icons.settings_rounded,
      title: 'Settings',
      subtitle: 'Manage your account, privacy and application preferences.',
      items: [
        'Account and profile preferences',
        'Privacy and notification controls',
        'Appearance and app behaviour',
      ],
    ),
  };
}

String moreDestinationLabel(MoreDestination destination) {
  return switch (destination) {
    MoreDestination.friends => 'Friends',
    MoreDestination.discover => 'Discover',
    MoreDestination.clubs => 'Clubs',
    MoreDestination.notifications => 'Alerts',
    MoreDestination.achievements => 'Awards',
    MoreDestination.creatorStudio => 'Creator Studio',
    MoreDestination.settings => 'Settings',
  };
}

class MoreDestinationPage extends StatelessWidget {
  const MoreDestinationPage({
    required this.destination,
    required this.child,
    super.key,
  });

  final MoreDestination destination;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080711),
      appBar: AppBar(
        backgroundColor: const Color(0xFF100B19),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
        ),
        title: Text(
          moreDestinationLabel(destination),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: Color(0xFF2B2436)),
        ),
      ),
      body: MediaQuery.removePadding(
        context: context,
        removeTop: true,
        child: child,
      ),
    );
  }
}

class _MoreFeatureScreen extends StatelessWidget {
  const _MoreFeatureScreen({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.items,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080711),
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-.85, -.95),
            radius: 1.25,
            colors: [Color(0xFF25103A), Color(0xFF100B1B), Color(0xFF080711)],
            stops: [0, .4, 1],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 30, 20, 40),
          children: [
            Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF9D20FF).withValues(alpha: .18),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFF5A2A75)),
              ),
              child: Icon(icon, color: const Color(0xFFD28AFF), size: 35),
            ),
            const SizedBox(height: 22),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(
                color: Color(0xFFA69CB2),
                fontSize: 15,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 28),
            ...items.map(
              (item) => Container(
                margin: const EdgeInsets.only(bottom: 11),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF181120),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFF382A46)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_outline_rounded,
                      color: Color(0xFFB348FF),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        item,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'This section is now part of the navigation and is ready for its full feature implementation in the next development stage.',
              style: TextStyle(
                color: Color(0xFF8F849B),
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MoreSheet extends StatelessWidget {
  const MoreSheet({super.key});

  static const _surface = Color(0xFF151020);
  static const _card = Color(0xFF20172C);
  static const _border = Color(0xFF3A2D49);
  static const _muted = Color(0xFFA69CB2);
  static const _primary = Color(0xFF9D20FF);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 22),
      decoration: const BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        border: Border(top: BorderSide(color: _border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: const Color(0xFF594C65),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(height: 18),
          const Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'More',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 27,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Everything else, kept one tap away.',
                      style: TextStyle(color: _muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 11,
            crossAxisSpacing: 11,
            childAspectRatio: .93,
            children: const [
              _MoreTile(
                destination: MoreDestination.friends,
                icon: Icons.people_rounded,
                label: 'Friends',
                subtitle: 'People',
              ),
              _MoreTile(
                destination: MoreDestination.discover,
                icon: Icons.explore_rounded,
                label: 'Discover',
                subtitle: 'Find rooms',
              ),
              _MoreTile(
                destination: MoreDestination.clubs,
                icon: Icons.groups_2_rounded,
                label: 'Clubs',
                subtitle: 'Communities',
              ),
              _MoreTile(
                destination: MoreDestination.notifications,
                icon: Icons.notifications_rounded,
                label: 'Alerts',
                subtitle: 'Updates',
              ),
              _MoreTile(
                destination: MoreDestination.achievements,
                icon: Icons.emoji_events_rounded,
                label: 'Awards',
                subtitle: 'Progress',
              ),
              _MoreTile(
                destination: MoreDestination.creatorStudio,
                icon: Icons.auto_graph_rounded,
                label: 'Creator',
                subtitle: 'Studio',
              ),
            ],
          ),
          const SizedBox(height: 11),
          _WideMoreTile(
            destination: MoreDestination.settings,
            icon: Icons.settings_rounded,
            label: 'Settings',
            subtitle: 'Privacy, account and application preferences',
          ),
        ],
      ),
    );
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({
    required this.destination,
    required this.icon,
    required this.label,
    required this.subtitle,
  });

  final MoreDestination destination;
  final IconData icon;
  final String label;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MoreSheet._card,
      borderRadius: BorderRadius.circular(21),
      child: InkWell(
        onTap: () => Navigator.pop(context, destination),
        borderRadius: BorderRadius.circular(21),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(21),
            border: Border.all(color: MoreSheet._border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 39,
                    height: 39,
                    decoration: BoxDecoration(
                      color: MoreSheet._primary.withValues(alpha: .18),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(icon, color: const Color(0xFFD28AFF), size: 22),
                  ),
                  const Spacer(),
                ],
              ),
              const Spacer(),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: MoreSheet._muted, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WideMoreTile extends StatelessWidget {
  const _WideMoreTile({
    required this.destination,
    required this.icon,
    required this.label,
    required this.subtitle,
  });

  final MoreDestination destination;
  final IconData icon;
  final String label;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MoreSheet._card,
      borderRadius: BorderRadius.circular(19),
      child: InkWell(
        onTap: () => Navigator.pop(context, destination),
        borderRadius: BorderRadius.circular(19),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(19),
            border: Border.all(color: MoreSheet._border),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: MoreSheet._primary.withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: const Color(0xFFD28AFF)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: MoreSheet._muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: MoreSheet._muted),
            ],
          ),
        ),
      ),
    );
  }
}
