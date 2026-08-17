import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/features/achievements/presentation/screens/achievements_screen.dart';
import 'package:yovoice/features/clubs/presentation/screens/clubs_screen.dart';
import 'package:yovoice/features/creator/presentation/screens/creator_studio_screen.dart';
import 'package:yovoice/features/creator/presentation/screens/find_creators_screen.dart';
import 'package:yovoice/features/discover/presentation/screens/discover_screen.dart';
import 'package:yovoice/features/friends/presentation/screens/friends_screen.dart';
import 'package:yovoice/features/moderation/presentation/screens/moderation_center_screen.dart';
import 'package:yovoice/features/moments/presentation/screens/moments_screen.dart';
import 'package:yovoice/features/notifications/presentation/screens/notification_preferences_screen.dart';
import 'package:yovoice/features/premium/data/models/subscription_entitlements.dart';
import 'package:yovoice/features/premium/premium_gates.dart';
import 'package:yovoice/features/premium/presentation/widgets/premium_feature_gate.dart';
import 'package:yovoice/features/profile/presentation/screens/profile_screen.dart';
import 'package:yovoice/features/settings/presentation/screens/settings_screen.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';
import 'package:yovoice/features/staff/presentation/screens/staff_center_screen.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';

enum MoreDestination {
  friends,
  discover,
  findCreators,
  clubs,
  moments,
  notifications,
  achievements,
  creatorStudio,
  settings,
  profile,

  /// STAFF ONLY. On desktop, listed in the More popover behind the
  /// staff check; on mobile, surfaced through the sheet's
  /// capability-driven Staff section (moderation tier → violet
  /// Moderation Center card). The destination re-checks authority on
  /// mount regardless.
  moderation,

  /// On desktop, listed only for the owner; on mobile, the Staff
  /// section shows it for the owner (crimson) and the super-moderation
  /// tier (coral) — the screen itself renders only the sections each
  /// tier's SERVER capabilities back, and re-verifies on mount.
  staffCenter,
}

PremiumFeature? premiumFeatureForMoreDestination(MoreDestination destination) =>
    switch (destination) {
      MoreDestination.creatorStudio => PremiumFeature.creatorStudio,
      MoreDestination.clubs => PremiumFeature.clubs,
      _ => null,
    };

bool moreDestinationIsLocked(
  MoreDestination destination,
  SubscriptionEntitlements entitlements,
) {
  final feature = premiumFeatureForMoreDestination(destination);
  return feature != null && !feature.isEnabledBy(entitlements);
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
  MoreDestination.findCreators,
  MoreDestination.friends,
};

Future<MoreDestination?> showMoreSheet(
  BuildContext context, {
  SubscriptionEntitlements entitlements = SubscriptionEntitlements.free,
}) {
  return showModalBottomSheet<MoreDestination>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.72),
    builder: (_) => MoreSheet(entitlements: entitlements),
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
  final screen = switch (destination) {
    MoreDestination.friends => FriendsScreen(isRootTab: isRootTab),
    MoreDestination.discover => DiscoverScreen(isRootTab: isRootTab),
    MoreDestination.findCreators => FindCreatorsScreen(isRootTab: isRootTab),
    MoreDestination.clubs => ClubsScreen(isRootTab: isRootTab),
    MoreDestination.moments => const MomentsScreen(),
    MoreDestination.notifications => NotificationPreferencesScreen(
      isRootTab: isRootTab,
    ),
    MoreDestination.achievements => const AwardsHubScreen(),
    MoreDestination.creatorStudio => CreatorStudioScreen(isRootTab: isRootTab),
    MoreDestination.settings => SettingsScreen(isRootTab: isRootTab),
    MoreDestination.profile => const ProfileScreen(),
    // Re-checks staff authority on mount and renders an access-denied
    // state without querying anything if it fails. Menu visibility is
    // presentation; this and firestore.rules are the boundary.
    MoreDestination.staffCenter => StaffCenterScreen(isRootTab: isRootTab),
    MoreDestination.moderation => ModerationCenterScreen(isRootTab: isRootTab),
  };
  final feature = premiumFeatureForMoreDestination(destination);
  if (feature == null) return screen;
  return PremiumFeatureGate(
    feature: feature,
    isRootTab: isRootTab,
    child: screen,
  );
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
  bool isOwner = false,
  SubscriptionEntitlements entitlements = SubscriptionEntitlements.free,
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
    if (isOwner)
      (
        MoreDestination.staffCenter,
        Icons.admin_panel_settings_rounded,
        'Staff Center',
        'Roles and user management',
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
              if (moreDestinationIsLocked(destination, entitlements)) ...[
                const SizedBox(width: 8),
                Icon(
                  Icons.lock_rounded,
                  key: ValueKey('desktop-premium-lock-${destination.name}'),
                  color: const Color(0xFFFFC24D),
                  size: 16,
                ),
              ],
            ],
          ),
        ),
    ],
  );
}

/// What the MOBILE sheet's staff section shows for one account — derived
/// from SERVER capabilities alone, never from a local role string.
///
/// The tiers map to the doors that actually exist behind them:
///   owner (manageRoles)                    Moderation Center + Staff Center
///   super moderation (liftSuspensions /
///   viewAllQueues)                         Staff Center, coral — it opens
///                                          with exactly Reports, Rooms &
///                                          Spaces and Sanctions
///   moderation (handleAssignedReports)     Moderation Center, violet
///
/// Auditor, Support and Guide Master deliberately get NOTHING here: their
/// capabilities are flags whose surfaces have not shipped (see
/// utils/capabilities.js — "a capability is not a promise of a button"),
/// and an entry with no real backend read would be a decorative control.
/// VIP and ordinary accounts get no section and no empty gap.
List<
  ({MoreDestination destination, String label, String subtitle, Color color})
>
staffEntriesFor(StaffCapabilities capabilities) {
  final entries =
      <
        ({
          MoreDestination destination,
          String label,
          String subtitle,
          Color color,
        })
      >[];

  // Moderation is its own destination on desktop and mobile. Do not let
  // the broader Staff Center entry replace it for accounts that have both
  // capabilities (notably the owner and super moderators).
  if (capabilities.handleAssignedReports) {
    entries.add((
      destination: MoreDestination.moderation,
      label: 'Moderation',
      subtitle: 'Review reported content',
      color: AppColors.roleModerator,
    ));
  }

  if (capabilities.manageRoles) {
    entries.add((
      destination: MoreDestination.staffCenter,
      label: 'Staff Center',
      subtitle: 'Owner console — every section',
      color: AppColors.roleOwner,
    ));
  } else if (capabilities.liftSuspensions || capabilities.viewAllQueues) {
    entries.add((
      destination: MoreDestination.staffCenter,
      label: 'Staff Center',
      subtitle: 'Reports, rooms and sanctions',
      color: AppColors.roleSuperModerator,
    ));
  }
  return entries;
}

class MoreSheet extends StatefulWidget {
  const MoreSheet({
    this.capabilityService,
    this.currentUid,
    this.entitlements = SubscriptionEntitlements.free,
    super.key,
  });

  /// Injected in tests; production asks the shared service, whose cache
  /// is keyed by uid and cleared on account switch.
  final StaffCapabilityService? capabilityService;

  /// Injected in tests; production reads the signed-in session.
  final String? currentUid;

  /// Snapshot owned by MainShell's shared entitlement subscription. The
  /// destination re-checks the server before opening; this value only decides
  /// whether the tile displays its Premium lock.
  final SubscriptionEntitlements entitlements;

  static const _surface = Color(0xFF151020);
  static const _card = Color(0xFF20172C);
  static const _border = Color(0xFF3A2D49);
  static const _muted = Color(0xFFA69CB2);
  static const _primary = Color(0xFF9D20FF);

  @override
  State<MoreSheet> createState() => _MoreSheetState();
}

class _MoreSheetState extends State<MoreSheet> {
  StaffCapabilities _capabilities = StaffCapabilities.none;

  String get _currentUid {
    if (widget.currentUid != null) return widget.currentUid!;
    try {
      return FirebaseAuth.instance.currentUser?.uid ?? '';
    } catch (_) {
      return '';
    }
  }

  @override
  void initState() {
    super.initState();
    // Until the server answers, the sheet is exactly the ordinary
    // layout — the staff section appears only on a positive answer, so
    // an ordinary account never sees a flash or a gap.
    (widget.capabilityService ?? StaffCapabilityService())
        .load()
        .then((capabilities) {
          if (mounted) setState(() => _capabilities = capabilities);
        })
        .catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: MoreSheet._surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        border: Border(top: BorderSide(color: MoreSheet._border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Container(
              key: const ValueKey('more-sheet-drag-handle'),
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFF594C65),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              key: const ValueKey('more-sheet-scroll-view'),
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                              style: TextStyle(
                                color: MoreSheet._muted,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final textScale = MediaQuery.textScalerOf(
                        context,
                      ).scale(1);
                      final usesTwoColumns =
                          constraints.maxWidth < 400 || textScale > 1.3;
                      final baseExtent = usesTwoColumns
                          ? (constraints.maxWidth < 350 ? 176.0 : 160.0)
                          : 170.0;
                      final tileExtent =
                          (baseExtent + ((textScale - 1).clamp(0, 1.5) * 104))
                              .clamp(baseExtent, 272)
                              .toDouble();

                      return GridView.count(
                        crossAxisCount: usesTwoColumns ? 2 : 3,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 11,
                        crossAxisSpacing: 11,
                        mainAxisExtent: tileExtent,
                        children: [
                          // Friends graduated to the primary bottom navigation;
                          // Profile moved here in its place (still one tap away via
                          // any of your own avatars too).
                          const _MoreTile(
                            destination: MoreDestination.profile,
                            icon: Icons.person_rounded,
                            label: 'Profile',
                            subtitle: 'You',
                          ),
                          const _MoreTile(
                            destination: MoreDestination.discover,
                            icon: Icons.explore_rounded,
                            label: 'Discover',
                            subtitle: 'Find rooms',
                          ),
                          const _MoreTile(
                            destination: MoreDestination.findCreators,
                            icon: Icons.person_search_rounded,
                            label: 'Find creators',
                            subtitle: 'People to follow',
                          ),
                          _MoreTile(
                            destination: MoreDestination.clubs,
                            icon: Icons.groups_2_rounded,
                            label: 'Clubs',
                            subtitle: 'Communities',
                            isLocked: moreDestinationIsLocked(
                              MoreDestination.clubs,
                              widget.entitlements,
                            ),
                          ),
                          const _MoreTile(
                            destination: MoreDestination.moments,
                            icon: Icons.graphic_eq_rounded,
                            label: 'Moments',
                            subtitle: 'Voice feed',
                          ),
                          const _MoreTile(
                            destination: MoreDestination.notifications,
                            icon: Icons.notifications_rounded,
                            label: 'Alerts',
                            subtitle: 'Updates',
                          ),
                          const _MoreTile(
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
                            isLocked: moreDestinationIsLocked(
                              MoreDestination.creatorStudio,
                              widget.entitlements,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  // The staff section: BELOW the destination grid, ABOVE Settings, and
                  // present only when the server-derived capabilities back a
                  // real door. Ordinary and VIP accounts render the exact layout
                  // this sheet always had.
                  ..._staffSection(),
                  const SizedBox(height: 11),
                  const _WideMoreTile(
                    destination: MoreDestination.settings,
                    icon: Icons.settings_rounded,
                    label: 'Settings',
                    subtitle: 'Privacy, account and application preferences',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _staffSection() {
    final entries = staffEntriesFor(_capabilities);
    if (entries.isEmpty) return const [];
    final uid = _currentUid;
    return [
      const SizedBox(height: 14),
      Row(
        children: [
          const Text(
            'Staff',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: .3,
            ),
          ),
          const SizedBox(width: 8),
          // The signed-in account's own authoritative badges — same
          // shared components and repository as every other surface.
          if (uid.isNotEmpty) Flexible(child: UserIdentityBadges(uid: uid)),
        ],
      ),
      const SizedBox(height: 9),
      for (var index = 0; index < entries.length; index++) ...[
        if (index > 0) const SizedBox(height: 9),
        _WideMoreTile(
          destination: entries[index].destination,
          icon: entries[index].destination == MoreDestination.staffCenter
              ? Icons.admin_panel_settings_rounded
              : Icons.shield_rounded,
          label: entries[index].label,
          subtitle: entries[index].subtitle,
          accentColor: entries[index].color,
        ),
      ],
    ];
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({
    required this.destination,
    required this.icon,
    required this.label,
    required this.subtitle,
    this.isLocked = false,
  });

  final MoreDestination destination;
  final IconData icon;
  final String label;
  final String subtitle;
  final bool isLocked;

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
                  if (isLocked)
                    Icon(
                      Icons.lock_rounded,
                      key: ValueKey('mobile-premium-lock-${destination.name}'),
                      color: const Color(0xFFFFC24D),
                      size: 17,
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                label,
                maxLines: 2,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 2,
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
    this.accentColor,
  });

  final MoreDestination destination;
  final IconData icon;
  final String label;
  final String subtitle;

  /// Staff entries carry their tier's color from the theme; everything
  /// else keeps the sheet's violet accent.
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? const Color(0xFFD28AFF);
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
            border: Border.all(
              color: accentColor?.withValues(alpha: .5) ?? MoreSheet._border,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: (accentColor ?? MoreSheet._primary).withValues(
                    alpha: .18,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: accent),
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
