import 'package:flutter/material.dart';
import 'package:yovoice/features/achievements/presentation/screens/achievements_screen.dart';
import 'package:yovoice/features/clubs/presentation/screens/clubs_screen.dart';
import 'package:yovoice/features/creator/presentation/screens/creator_studio_screen.dart';
import 'package:yovoice/features/discover/presentation/screens/discover_screen.dart';
import 'package:yovoice/features/friends/presentation/screens/friends_screen.dart';
import 'package:yovoice/features/moderation/presentation/screens/moderation_center_screen.dart';
import 'package:yovoice/features/moments/presentation/screens/moments_screen.dart';
import 'package:yovoice/features/notifications/presentation/screens/notification_preferences_screen.dart';
import 'package:yovoice/features/profile/presentation/screens/profile_screen.dart';
import 'package:yovoice/features/settings/presentation/screens/settings_screen.dart';

enum MoreDestination {
  friends,
  discover,
  clubs,
  moments,
  notifications,
  achievements,
  creatorStudio,
  settings,
  profile,

  /// DESKTOP + STAFF ONLY. Listed in the desktop More popover only when
  /// the signed-in account passes the staff check, and absent from the
  /// mobile sheet entirely — this milestone is desktop-only, and no
  /// mobile file was touched to add it.
  moderation,
}

/// Destinations the DESKTOP rail shows directly, so the desktop "More"
/// menu drops them and stays free of duplicates. Mobile keeps showing
/// them in its sheet — its dock has no room for them, and that layout is
/// deliberately untouched.
///
/// Everything NOT listed here is reachable from the desktop More
/// popover (Moments, Clubs, Creator Studio, Awards, Alerts, Settings) or
/// from the rail's profile card (Profile, and its gear → Settings).
const Set<MoreDestination> desktopRailDestinations = {
  MoreDestination.discover,
  MoreDestination.friends,
};

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

/// Builds a destination's screen.
///
/// [isRootTab] is true when the screen is rendered as the DESKTOP
/// shell's fixed content slot rather than pushed as a route — the
/// screens then hide their own back button, which would have nothing to
/// pop (Awards uses a Material AppBar, whose leading button already
/// appears only when `Navigator.canPop()`).
Widget moreDestinationScreen(
  MoreDestination destination, {
  bool isRootTab = false,
}) {
  return switch (destination) {
    MoreDestination.friends => FriendsScreen(isRootTab: isRootTab),
    MoreDestination.discover => DiscoverScreen(isRootTab: isRootTab),
    MoreDestination.clubs => ClubsScreen(isRootTab: isRootTab),
    MoreDestination.moments => const MomentsScreen(),
    MoreDestination.notifications => NotificationPreferencesScreen(
      isRootTab: isRootTab,
    ),
    MoreDestination.achievements => const AwardsHubScreen(),
    MoreDestination.creatorStudio => CreatorStudioScreen(
      isRootTab: isRootTab,
    ),
    MoreDestination.settings => SettingsScreen(isRootTab: isRootTab),
    MoreDestination.profile => const ProfileScreen(),
    // Re-checks staff authority on mount and renders an access-denied
    // state without querying anything if it fails. Menu visibility is
    // presentation; this and firestore.rules are the boundary.
    MoreDestination.moderation => ModerationCenterScreen(
      isRootTab: isRootTab,
    ),
  };
}

/// The DESKTOP "More": a compact popover anchored to the rail item —
/// no dimmed page, no drag handle, no bottom sheet. Lists only what the
/// rail does not already show, so nothing appears twice.
Future<MoreDestination?> showDesktopMoreMenu(
  BuildContext context, {
  required Offset anchor,
  // Staff-only entries are appended rather than always present: an
  // ordinary account never sees Moderation listed. That is a
  // presentation choice — the destination itself, firestore.rules and
  // the moderateReport callable each re-check authority.
  bool isStaff = false,
}) {
  final items = <(MoreDestination, IconData, String, String)>[
    (
      MoreDestination.moments,
      Icons.graphic_eq_rounded,
      'Moments',
      'Your voice posts and feed',
    ),
    (
      MoreDestination.clubs,
      Icons.groups_2_rounded,
      'Clubs',
      'Communities you belong to',
    ),
    (
      MoreDestination.creatorStudio,
      Icons.auto_graph_rounded,
      'Creator Studio',
      'Your rooms, clubs and Moments',
    ),
    (
      MoreDestination.achievements,
      Icons.emoji_events_rounded,
      'Awards',
      'Titles and progress',
    ),
    (
      MoreDestination.notifications,
      Icons.notifications_active_rounded,
      'Alerts',
      'Notification preferences',
    ),
    (
      MoreDestination.settings,
      Icons.settings_rounded,
      'Settings',
      'Privacy, account and app',
    ),
    if (isStaff)
      (
        MoreDestination.moderation,
        Icons.shield_rounded,
        'Moderation',
        'Review reported content',
      ),
  ];

  return showMenu<MoreDestination>(
    context: context,
    // Anchored beside the rail item, not centered over the page.
    position: RelativeRect.fromLTRB(
      anchor.dx,
      anchor.dy,
      anchor.dx + 280,
      anchor.dy + 320,
    ),
    color: const Color(0xFF171021),
    surfaceTintColor: Colors.transparent,
    elevation: 14,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: MoreSheet._border),
    ),
    constraints: const BoxConstraints(minWidth: 264, maxWidth: 300),
    items: [
      for (final (destination, icon, label, subtitle) in items)
        PopupMenuItem<MoreDestination>(
          value: destination,
          height: 58,
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: MoreSheet._primary.withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 18, color: const Color(0xFFD28AFF)),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
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
            ],
          ),
        ),
    ],
  );
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
              // Friends graduated to the primary bottom navigation;
              // Profile moved here in its place (still one tap away via
              // any of your own avatars too).
              _MoreTile(
                destination: MoreDestination.profile,
                icon: Icons.person_rounded,
                label: 'Profile',
                subtitle: 'You',
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
