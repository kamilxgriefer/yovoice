import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
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
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/overlays/yo_modal_sheet_chrome.dart';

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
/// popover (Clubs, Creator Studio, Awards, Alerts, Settings) or from the
/// rail's profile card (Profile, and its gear → Settings).
///
/// Moments joined this set when it was promoted to primary navigation.
/// Note that `showDesktopMoreMenu`'s item list below is hand-written
/// rather than filtered through this set, so anything added here must
/// also be removed from there or it appears twice.
const Set<MoreDestination> desktopRailDestinations = {
  MoreDestination.moments,
  MoreDestination.discover,
  MoreDestination.findCreators,
  MoreDestination.friends,
};

Future<MoreDestination?> showMoreSheet(
  BuildContext context, {
  SubscriptionEntitlements entitlements = SubscriptionEntitlements.free,
  StaffCapabilityService? capabilityService,
  String? currentUid,
}) async {
  assert(debugCheckHasMediaQuery(context));
  assert(debugCheckHasMaterialLocalizations(context));

  final navigator = Navigator.of(context);
  final localizations = MaterialLocalizations.of(context);
  final route = ModalBottomSheetRoute<MoreDestination>(
    builder: (_) => MoreSheet(
      entitlements: entitlements,
      capabilityService: capabilityService,
      currentUid: currentUid,
    ),
    capturedThemes: InheritedTheme.capture(
      from: context,
      to: navigator.context,
    ),
    isScrollControlled: true,
    barrierLabel: localizations.scrimLabel,
    barrierOnTapHint: localizations.scrimOnTapHint(
      localizations.bottomSheetLabel,
    ),
    backgroundColor: Colors.transparent,
    constraints: ResponsiveContentFrame.adaptiveModalConstraints(context),
    modalBarrierColor: context.appPalette.scrim.withValues(alpha: 0.72),
    showDragHandle: false,
    useSafeArea: true,
  );

  final destination = await navigator.push(route);
  // Navigator.push completes when pop STARTS. Keep the caller's transition
  // guard armed until the reverse animation and modal barrier are actually
  // gone; otherwise a fast second tap can stack another More sheet beneath
  // the first destination.
  await route.completed;
  return destination;
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
    MoreDestination.moments => MomentsScreen(isRootTab: isRootTab),
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
  final palette = context.appPalette;
  final colors = Theme.of(context).colorScheme;
  final lockColor = Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFFFFC24D)
      : const Color(0xFF8C5A00);
  // Moments is deliberately absent: it is a rail item now, and listing
  // it here as well would show the same destination twice.
  final items = <(MoreDestination, IconData, String, String)>[
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
    color: palette.surfaceRaised,
    surfaceTintColor: Colors.transparent,
    elevation: 10,
    // The default fully-opaque shadow rendered as a hard black ring
    // around the panel on the dark Home surface; a translucent one
    // reads as depth instead.
    shadowColor: palette.shadow.withValues(alpha: .24),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(color: palette.border),
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
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 18, color: colors.primary),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textSecondary,
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
                  color: lockColor,
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
    final isVeryNarrow = MediaQuery.sizeOf(context).width <= 350;
    final palette = context.appPalette;
    final productEntries = <_MoreEntry>[
      const _MoreEntry(
        destination: MoreDestination.friends,
        icon: Icons.people_rounded,
        label: 'Friends',
        subtitle: 'Your circle',
      ),
      const _MoreEntry(
        destination: MoreDestination.profile,
        icon: Icons.person_rounded,
        label: 'Profile',
        subtitle: 'You',
      ),
      const _MoreEntry(
        destination: MoreDestination.discover,
        icon: Icons.explore_rounded,
        label: 'Discover',
        subtitle: 'Find rooms',
      ),
      const _MoreEntry(
        destination: MoreDestination.findCreators,
        icon: Icons.person_search_rounded,
        label: 'Find creators',
        subtitle: 'People to follow',
      ),
      _MoreEntry(
        destination: MoreDestination.clubs,
        icon: Icons.groups_2_rounded,
        label: 'Clubs',
        subtitle: 'Communities',
        isLocked: moreDestinationIsLocked(
          MoreDestination.clubs,
          widget.entitlements,
        ),
      ),
      const _MoreEntry(
        destination: MoreDestination.notifications,
        icon: Icons.notifications_rounded,
        label: 'Alerts',
        subtitle: 'Updates',
      ),
      const _MoreEntry(
        destination: MoreDestination.achievements,
        icon: Icons.emoji_events_rounded,
        label: 'Awards',
        subtitle: 'Progress',
      ),
      _MoreEntry(
        destination: MoreDestination.creatorStudio,
        icon: Icons.auto_graph_rounded,
        label: 'Creator',
        subtitle: 'Studio',
        isLocked: moreDestinationIsLocked(
          MoreDestination.creatorStudio,
          widget.entitlements,
        ),
      ),
    ];

    final content = Container(
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          YoModalSheetChrome(
            key: ValueKey('more-sheet-drag-handle'),
            sheetLabel: 'More menu',
            surfaceColor: palette.surfaceRaised,
          ),
          Flexible(
            child: SingleChildScrollView(
              key: const ValueKey('more-sheet-scroll-view'),
              padding: EdgeInsets.fromLTRB(
                16,
                isVeryNarrow ? 8 : 10,
                16,
                isVeryNarrow ? 8 : 16,
              ),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'More',
                              style: TextStyle(
                                color: palette.textPrimary,
                                fontSize: 27,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            if (!isVeryNarrow) ...[
                              const SizedBox(height: 3),
                              Text(
                                'Everything else, kept one tap away.',
                                style: TextStyle(
                                  color: palette.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: isVeryNarrow ? 8 : 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final scaler = MediaQuery.textScalerOf(context);
                      final textScale = scaler.scale(14) / 14;

                      // A dense launcher grid fits every ordinary action in
                      // the first expanded phone view. Enlarged text switches
                      // to intrinsic full-width rows instead of making fixed
                      // grid cells taller and narrower at the same time.
                      if (textScale > 1.3) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (
                              var index = 0;
                              index < productEntries.length;
                              index++
                            ) ...[
                              if (index > 0) const SizedBox(height: 8),
                              _WideMoreTile(
                                destination: productEntries[index].destination,
                                icon: productEntries[index].icon,
                                label: productEntries[index].label,
                                subtitle: productEntries[index].subtitle,
                                isLocked: productEntries[index].isLocked,
                              ),
                            ],
                          ],
                        );
                      }

                      final usesTwoColumns = constraints.maxWidth < 480;

                      return GridView.count(
                        crossAxisCount: usesTwoColumns ? 2 : 3,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        mainAxisExtent: 78,
                        children: [
                          // Moments took the dock slot Friends held, so
                          // Friends takes the grid slot Moments held — a
                          // 1:1 swap, still eight tiles, no layout churn.
                          // Friends also remains primary tab index 2 with
                          // its state alive, and one tap from Home's
                          // "Your circle".
                          for (final entry in productEntries)
                            _MoreTile(
                              destination: entry.destination,
                              icon: entry.icon,
                              label: entry.label,
                              subtitle: entry.subtitle,
                              isLocked: entry.isLocked,
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
                  const SizedBox(height: 8),
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

    final routeAnimation = ModalRoute.of(context)?.animation;
    if (routeAnimation == null) return content;
    return AnimatedBuilder(
      animation: routeAnimation,
      child: content,
      builder: (context, child) => AbsorbPointer(
        // The launcher's second tap can otherwise land on Settings/Creator
        // while the sheet is still sliding over the same screen coordinate.
        // Unlock only once the incoming route is completely stationary.
        absorbing: routeAnimation.status != AnimationStatus.completed,
        child: child,
      ),
    );
  }

  List<Widget> _staffSection() {
    final entries = staffEntriesFor(_capabilities);
    if (entries.isEmpty) return const [];
    final uid = _currentUid;
    return [
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Staff',
              style: TextStyle(
                color: context.appPalette.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: .3,
              ),
            ),
            // The signed-in account's own authoritative badges — same
            // shared components and repository as every other surface.
            if (uid.isNotEmpty) UserIdentityBadges(uid: uid),
          ],
        ),
      ),
      const SizedBox(height: 8),
      for (var index = 0; index < entries.length; index++) ...[
        if (index > 0) const SizedBox(height: 8),
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

class _MoreEntry {
  const _MoreEntry({
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
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final lockColor = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFFFC24D)
        : const Color(0xFF8C5A00);
    final semanticLabel = [
      label,
      subtitle,
      if (isLocked) 'Premium required',
    ].join(', ');
    void open() => Navigator.pop(context, destination);

    return Semantics(
      key: ValueKey('more-destination-${destination.name}'),
      button: true,
      enabled: true,
      label: semanticLabel,
      onTap: open,
      excludeSemantics: true,
      child: Material(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: open,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: palette.border),
            ),
            child: Stack(
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(icon, color: colors.primary, size: 20),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (isLocked)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Icon(
                      Icons.lock_rounded,
                      key: ValueKey('mobile-premium-lock-${destination.name}'),
                      color: lockColor,
                      size: 16,
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

class _WideMoreTile extends StatelessWidget {
  const _WideMoreTile({
    required this.destination,
    required this.icon,
    required this.label,
    required this.subtitle,
    this.accentColor,
    this.isLocked = false,
  });

  final MoreDestination destination;
  final IconData icon;
  final String label;
  final String subtitle;
  final bool isLocked;

  /// Staff entries carry their tier's color from the theme; everything
  /// else keeps the sheet's violet accent.
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final accent = accentColor ?? colors.primary;
    final lockColor = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFFFC24D)
        : const Color(0xFF8C5A00);
    final semanticLabel = [
      label,
      subtitle,
      if (isLocked) 'Premium required',
    ].join(', ');
    void open() => Navigator.pop(context, destination);

    return Semantics(
      key: ValueKey('more-destination-${destination.name}'),
      button: true,
      enabled: true,
      label: semanticLabel,
      onTap: open,
      excludeSemantics: true,
      child: Material(
        color: palette.surface,
        borderRadius: BorderRadius.circular(17),
        child: InkWell(
          onTap: open,
          borderRadius: BorderRadius.circular(17),
          child: Container(
            constraints: const BoxConstraints(minHeight: 58),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(17),
              border: Border.all(
                color: accentColor?.withValues(alpha: .5) ?? palette.border,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: (accentColor ?? colors.primary).withValues(
                      alpha: .18,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: accent, size: 21),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isLocked) ...[
                  const SizedBox(width: 6),
                  Icon(
                    Icons.lock_rounded,
                    key: ValueKey('mobile-premium-lock-${destination.name}'),
                    color: lockColor,
                    size: 17,
                  ),
                ],
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, color: palette.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
