import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/achievements/presentation/screens/achievements_screen.dart';
import 'package:yovoice/features/bug_reports/presentation/bug_report_launcher.dart';
import 'package:yovoice/features/creator/presentation/screens/creator_studio_screen.dart';
import 'package:yovoice/features/creator/presentation/screens/find_creators_screen.dart';
import 'package:yovoice/features/friends/presentation/screens/friends_screen.dart';
import 'package:yovoice/features/moderation/presentation/screens/moderation_center_screen.dart';
import 'package:yovoice/features/moments/presentation/screens/moments_screen.dart';
import 'package:yovoice/features/notifications/presentation/screens/notification_preferences_screen.dart';
import 'package:yovoice/features/premium/data/models/subscription_entitlements.dart';
import 'package:yovoice/features/premium/premium_gates.dart';
import 'package:yovoice/features/premium/presentation/widgets/premium_feature_gate.dart';
import 'package:yovoice/features/profile/presentation/screens/profile_screen.dart';
import 'package:yovoice/features/reels/presentation/screens/reels_destination_screen.dart';
import 'package:yovoice/features/servers/presentation/screens/servers_screen.dart';
import 'package:yovoice/features/settings/presentation/screens/settings_screen.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';
import 'package:yovoice/features/staff/presentation/screens/staff_center_screen.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/layout/home_section_header.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/overlays/yo_modal_sheet_chrome.dart';
import 'package:yovoice/shared/widgets/profile/availability_picker.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';

enum MoreDestination {
  friends,

  /// Legacy route identity. It resolves to Servers and is never listed.
  discover,

  /// The account's own places (clubs and V1 servers) — a primary
  /// destination on both form factors: dock slot 1 and the desktop rail's
  /// second row. Owns content slot 13; the More sheet and popover do not
  /// list it, exactly like Moments.
  servers,
  findCreators,

  /// Legacy route identity. It resolves to Servers and is never listed.
  clubs,
  moments,
  reels,
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
/// popover (Friends, Find creators, Creator Studio,
/// Awards, Alerts, Settings) or from the rail's profile card (Profile, and
/// its gear → Settings).
///
/// The rail is Start · Serwery · Czaty · Momenty · Więcej: Moments joined
/// this set when it was promoted to primary navigation and Servers when it
/// took the second row; Friends, Discover and Find creators moved from the
/// rail into the popover (kept, never deleted). Note that
/// `showDesktopMoreMenu`'s item list below is hand-written rather than
/// filtered through this set, so anything added here must also be removed
/// from there or it appears twice.
const Set<MoreDestination> desktopRailDestinations = {
  MoreDestination.moments,
  MoreDestination.servers,
};

Future<MoreDestination?> showMoreSheet(
  BuildContext context, {
  SubscriptionEntitlements entitlements = SubscriptionEntitlements.free,
  StaffCapabilityService? capabilityService,
  String? currentUid,
  // Forwarded to [MoreSheet.profileService]; capture harnesses and tests
  // only. Production passes nothing and the sheet keeps its default.
  @visibleForTesting ProfileService? profileService,
}) async {
  assert(debugCheckHasMediaQuery(context));
  assert(debugCheckHasMaterialLocalizations(context));

  final navigator = Navigator.of(context);
  final localizations = MaterialLocalizations.of(context);
  // "Report a bug" is an ACTION, not a MoreDestination: it closes the sheet
  // with no destination (the shell does nothing) and opens the reporter once
  // the sheet has fully left the screen, so the screenshot shows the page and
  // not the sheet.
  var reportBugRequested = false;
  final route = ModalBottomSheetRoute<MoreDestination>(
    builder: (_) => MoreSheet(
      entitlements: entitlements,
      capabilityService: capabilityService,
      currentUid: currentUid,
      profileService: profileService,
      onReportBug: () => reportBugRequested = true,
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
  if (reportBugRequested && navigator.mounted) {
    unawaited(BugReportLauncher.open(navigator.context));
    return null;
  }
  return destination;
}

/// Builds a destination's screen.
///
/// [isRootTab] is true when the screen is rendered as the DESKTOP
/// shell's fixed content slot rather than pushed as a route — the
/// screens then hide their own back button, which would have nothing to
/// pop (Awards uses a Material AppBar, whose leading button already
/// appears only when `Navigator.canPop()`).
/// [serversVisible] is the shell's answer to "is the retained content slot
/// hosting this screen the one on screen?". It matters for exactly one
/// destination: a joined server conversation lives inside the Servers slot,
/// the desktop and mobile shells keep their built slots alive in an
/// `IndexedStack`, and a hidden slot would otherwise keep the microphone open
/// behind a dock nobody can see. Moments solves the same problem the same way
/// (`MomentsScreen(isVisible:)`), but it is built directly by the shell; the
/// servers destination is built here, so the listenable has to travel through
/// this function. Null — every pushed route — keeps meaning "always visible",
/// because a route ends its conversation by being popped.
Widget moreDestinationScreen(
  MoreDestination destination, {
  bool isRootTab = false,
  Future<void> Function()? onReplayGuidedOnboarding,
  ValueListenable<bool>? serversVisible,
}) {
  final screen = switch (destination) {
    MoreDestination.friends => FriendsScreen(isRootTab: isRootTab),
    // Old Discover/Club links remain parseable, but the former standalone
    // products no longer have a user-facing surface.
    MoreDestination.discover ||
    MoreDestination.clubs ||
    MoreDestination.servers => ServersScreen(
      isRootTab: isRootTab,
      isVisible: serversVisible,
    ),
    MoreDestination.findCreators => FindCreatorsScreen(isRootTab: isRootTab),
    MoreDestination.moments => MomentsScreen(isRootTab: isRootTab),
    MoreDestination.reels => ReelsDestinationScreen(isRootTab: isRootTab),
    MoreDestination.notifications => NotificationPreferencesScreen(
      isRootTab: isRootTab,
    ),
    MoreDestination.achievements => const AwardsHubScreen(),
    MoreDestination.creatorStudio => CreatorStudioScreen(isRootTab: isRootTab),
    MoreDestination.settings => SettingsScreen(
      isRootTab: isRootTab,
      onReplayGuidedOnboarding: onReplayGuidedOnboarding,
    ),
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
}) async {
  final palette = context.appPalette;
  final colors = Theme.of(context).colorScheme;
  final copy = AppLocalizations.of(context);
  final lockColor = palette.warningForeground;
  // Moments and Servers are deliberately absent: they are rail items, and
  // listing them here as well would show the same destination twice.
  // Friends and Find creators remain secondary destinations in this popover.
  final items = <(MoreDestination, IconData, String, String)>[
    (
      MoreDestination.friends,
      Icons.people_rounded,
      copy.friends,
      copy.text('Your circle', 'Twój krąg'),
    ),
    (
      MoreDestination.findCreators,
      Icons.person_search_rounded,
      copy.findCreators,
      copy.text('People to follow', 'Osoby warte obserwowania'),
    ),
    (
      MoreDestination.creatorStudio,
      Icons.auto_graph_rounded,
      copy.text('Creator Studio', 'Studio twórcy'),
      copy.text('Your servers and Moments', 'Twoje serwery i Momenty'),
    ),
    (
      MoreDestination.achievements,
      Icons.emoji_events_rounded,
      copy.text('Awards', 'Nagrody'),
      copy.text('Titles and progress', 'Tytuły i postępy'),
    ),
    (
      MoreDestination.notifications,
      Icons.notifications_active_rounded,
      copy.text('Alerts', 'Powiadomienia'),
      copy.text('Notification preferences', 'Ustawienia powiadomień'),
    ),
    (
      MoreDestination.settings,
      Icons.settings_rounded,
      copy.settings,
      copy.text('Privacy, account and app', 'Prywatność, konto i aplikacja'),
    ),
    if (isStaff)
      (
        MoreDestination.moderation,
        Icons.shield_rounded,
        copy.text('Moderation', 'Moderacja'),
        copy.text('Review reported content', 'Przeglądaj zgłoszone treści'),
      ),
    if (isOwner)
      (
        MoreDestination.staffCenter,
        Icons.admin_panel_settings_rounded,
        copy.text('Staff Center', 'Panel zespołu'),
        copy.text(
          'Roles and user management',
          'Role i zarządzanie użytkownikami',
        ),
      ),
  ];

  // "Report a bug" closes the popover with no destination, then waits for
  // the popover's own exit animation (not just the pop) before capturing.
  var reportBugRequested = false;
  ModalRoute<Object?>? menuRoute;
  final destination = await showMenu<MoreDestination>(
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
    // Slim: radius 12 and a tonal glyph (container pair), so the popover
    // adds no second violet accent next to the rail's selected item.
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
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
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 22, color: colors.onPrimaryContainer),
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
                      // Explicit w500: the menu item's inherited label
                      // weight made the secondary line as heavy as the title.
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
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
      const PopupMenuDivider(height: 9),
      PopupMenuItem<MoreDestination>(
        key: const ValueKey('desktop-more-report-bug'),
        height: 48,
        onTap: () => reportBugRequested = true,
        child: Builder(
          builder: (itemContext) {
            menuRoute = ModalRoute.of(itemContext);
            return Row(
              children: [
                SizedBox(
                  width: 34,
                  child: Icon(
                    Icons.bug_report_outlined,
                    size: 20,
                    color: palette.textSecondary,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    copy.text('Report a bug', 'Zgłoś błąd'),
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ],
  );
  if (reportBugRequested) {
    await menuRoute?.completed;
    if (context.mounted) unawaited(BugReportLauncher.open(context));
    return null;
  }
  return destination;
}

/// What the MOBILE sheet's staff section shows for one account — derived
/// from SERVER capabilities alone, never from a local role string.
///
/// The tiers map to the doors that actually exist behind them:
///   owner (manageRoles)                    Moderation Center + Staff Center
///   super moderation (liftSuspensions /
///   viewAllQueues)                         Staff Center, coral — it opens
///                                          with Reports, Servers & Sanctions
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
      subtitle: 'Reports, servers and sanctions',
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
    this.profileService,
    this.onReportBug,
  });

  /// Set by [showMoreSheet]: marks that "Report a bug" was chosen, just before
  /// the sheet closes with no destination. Null (a bare sheet in a harness)
  /// leaves the row out, so the launcher grid is exactly what it always was.
  final VoidCallback? onReportBug;

  /// Injected by tests and previews; production uses the default service.
  final ProfileService? profileService;

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
    final copy = AppLocalizations.of(context);
    final productEntries = <_MoreEntry>[
      _MoreEntry(
        destination: MoreDestination.friends,
        icon: Icons.people_rounded,
        label: copy.friends,
        subtitle: copy.text('Your circle', 'Twój krąg'),
      ),
      _MoreEntry(
        destination: MoreDestination.profile,
        icon: Icons.person_rounded,
        label: copy.profile,
        subtitle: copy.text('You', 'Ty'),
      ),
      _MoreEntry(
        destination: MoreDestination.findCreators,
        icon: Icons.person_search_rounded,
        label: copy.findCreators,
        // The launcher tile is the narrowest place this subtitle appears —
        // ~110dp on a 392dp phone, less on a 360dp one. "Osoby warte
        // obserwowania" (which the roomier desktop popover keeps) needs a
        // third line there once text is enlarged; this says the same thing
        // in two. The English key is unchanged, so every other locale reads
        // the same catalog phrase it always did.
        subtitle: copy.text('People to follow', 'Warto obserwować'),
      ),
      _MoreEntry(
        destination: MoreDestination.notifications,
        icon: Icons.notifications_rounded,
        label: copy.text('Alerts', 'Powiadomienia'),
        subtitle: copy.text('Updates', 'Aktualizacje'),
      ),
      _MoreEntry(
        destination: MoreDestination.achievements,
        icon: Icons.emoji_events_rounded,
        label: copy.text('Awards', 'Nagrody'),
        subtitle: copy.text('Progress', 'Postępy'),
      ),
      _MoreEntry(
        destination: MoreDestination.creatorStudio,
        icon: Icons.auto_graph_rounded,
        label: copy.text('Creator', 'Twórca'),
        subtitle: copy.text('Studio', 'Studio'),
        isLocked: moreDestinationIsLocked(
          MoreDestination.creatorStudio,
          widget.entitlements,
        ),
      ),
    ];

    // The sheet used to fill the screen and sit ON TOP of the dock, so the
    // control that opened it disappeared underneath. It now floats: a bounded
    // card that ends above the dock, rounded on all four corners, sized to
    // its own content up to a share of the viewport.
    final media = MediaQuery.of(context);
    final dockClearance = 84 + media.viewPadding.bottom;
    final content = Container(
      margin: EdgeInsets.fromLTRB(10, 0, 10, dockClearance),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: palette.border),
        boxShadow: [
          BoxShadow(
            color: palette.shadow.withValues(alpha: .34),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      // Slim: the floating sheet is one flat surface. The page scenery that
      // used to be repeated inside it (`YoAtmosphereArt`) stays on the canvas
      // behind the sheet, where the brief keeps decoration.
      child: Stack(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              YoModalSheetChrome(
                key: ValueKey('more-sheet-drag-handle'),
                sheetLabel: copy.text('More menu', 'Menu Więcej'),
                surfaceColor: palette.surfaceRaised,
                // In the chrome band, opposite Close: it adds no height, so
                // the compact sheet still fits 320x568 without scrolling.
                leading: widget.onReportBug == null
                    ? null
                    : _ReportBugAction(
                        onTap: () {
                          widget.onReportBug!();
                          Navigator.pop(context);
                        },
                      ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  key: const ValueKey('more-sheet-scroll-view'),
                  padding: EdgeInsets.fromLTRB(
                    14,
                    isVeryNarrow ? 6 : 8,
                    14,
                    isVeryNarrow ? 8 : 12,
                  ),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _AvailabilityRow(
                                  profileService: widget.profileService,
                                ),
                                // The sheet's one headline: 20 px w800.
                                Text(
                                  copy.more,
                                  style: TextStyle(
                                    color: palette.textPrimary,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
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
                          final columns = constraints.maxWidth < 480 ? 2 : 3;
                          // Roughly what a tile gives its words: the cell,
                          // less the 8+8 padding, the 34 icon and the 8 gap
                          // beside it (the 1dp border either side is slack).
                          // On a 320dp phone that is ~74dp, which a two-line
                          // enlarged title cannot use — the answer there is
                          // the full width of the sheet, not a narrower
                          // column.
                          final labelWidth =
                              (constraints.maxWidth - 8 * (columns - 1)) /
                                  columns -
                              58;

                          // A dense launcher grid fits every ordinary action in
                          // the first expanded phone view. Enlarged text switches
                          // to intrinsic full-width rows instead of making fixed
                          // grid cells taller and narrower at the same time.
                          if (textScale > 1.3 ||
                              labelWidth < scaler.scale(14) * 5) {
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
                                    destination:
                                        productEntries[index].destination,
                                    icon: productEntries[index].icon,
                                    label: productEntries[index].label,
                                    subtitle: productEntries[index].subtitle,
                                    isLocked: productEntries[index].isLocked,
                                  ),
                                ],
                              ],
                            );
                          }

                          final rowSpacing = isVeryNarrow ? 6.0 : 8.0;

                          // Rows of equal-height tiles rather than a grid of
                          // fixed-extent cells. A fixed 62dp cell could only
                          // ever show one line per label, which clipped
                          // "Znajdź twórców", "Osoby warte obserwowania" and
                          // "Powiadomienia" on a 392dp phone — and any cell
                          // tall enough for two lines at 1.3x text would be
                          // mostly empty at 1x. Each row now takes the height
                          // its own tallest tile asks for; `_MoreTile` keeps
                          // the compact 62dp launcher density as its minimum
                          // and a 44px+ touch target with it. IntrinsicHeight
                          // plus a stretched cross axis keeps the tiles in a
                          // row the same height, exactly as the grid did.
                          //
                          // Moments took the dock slot Friends held, so
                          // Friends takes the grid slot Moments held — a 1:1
                          // swap without changing the route contract. Friends
                          // also remains primary tab index 2 with its state
                          // alive, and one tap from Home's "Your circle".
                          final rows = <Widget>[];
                          for (
                            var start = 0;
                            start < productEntries.length;
                            start += columns
                          ) {
                            rows.add(
                              IntrinsicHeight(
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    for (
                                      var column = 0;
                                      column < columns;
                                      column++
                                    ) ...[
                                      if (column > 0) const SizedBox(width: 8),
                                      Expanded(
                                        child:
                                            start + column <
                                                productEntries.length
                                            ? _MoreTile(
                                                destination:
                                                    productEntries[start +
                                                            column]
                                                        .destination,
                                                icon:
                                                    productEntries[start +
                                                            column]
                                                        .icon,
                                                label:
                                                    productEntries[start +
                                                            column]
                                                        .label,
                                                subtitle:
                                                    productEntries[start +
                                                            column]
                                                        .subtitle,
                                                isLocked:
                                                    productEntries[start +
                                                            column]
                                                        .isLocked,
                                              )
                                            // The last row of an odd count
                                            // keeps its column width instead
                                            // of stretching the final tile.
                                            : const SizedBox.shrink(),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          }

                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (
                                var index = 0;
                                index < rows.length;
                                index++
                              ) ...[
                                if (index > 0) SizedBox(height: rowSpacing),
                                rows[index],
                              ],
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
                      _WideMoreTile(
                        destination: MoreDestination.settings,
                        icon: Icons.settings_rounded,
                        label: copy.settings,
                        subtitle: copy.text(
                          'Privacy, account and application preferences',
                          'Prywatność, konto i ustawienia aplikacji',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
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
    final copy = AppLocalizations.of(context);
    return [
      // The staff section's heading is THE section heading (ADR-209): its
      // 24 / 16 rhythm replaces the private 12 + label + 8 spacing, and the
      // account's badges ride the trailer slot, centred on the title.
      HomeSectionHeader(
        title: copy.text('Staff', 'Zespół'),
        // The signed-in account's own authoritative badges — same
        // shared components and repository as every other surface.
        trailing: uid.isNotEmpty ? UserIdentityBadges(uid: uid) : null,
      ),
      for (var index = 0; index < entries.length; index++) ...[
        if (index > 0) const SizedBox(height: 8),
        _WideMoreTile(
          destination: entries[index].destination,
          icon: entries[index].destination == MoreDestination.staffCenter
              ? Icons.admin_panel_settings_rounded
              : Icons.shield_rounded,
          label: copy.text(
            entries[index].label,
            entries[index].destination == MoreDestination.moderation
                ? 'Moderacja'
                : 'Panel zespołu',
          ),
          subtitle: copy.text(
            entries[index].subtitle,
            entries[index].destination == MoreDestination.moderation
                ? 'Przeglądaj zgłoszone treści'
                : entries[index].subtitle.startsWith('Owner')
                ? 'Panel właściciela — wszystkie sekcje'
                : 'Zgłoszenia, serwery i sankcje',
          ),
          accentColor: entries[index].color,
        ),
      ],
    ];
  }
}

/// "Report a bug" in the mobile sheet: a quiet action in the chrome band,
/// not a launcher tile — it is an action for testers, not a destination, and
/// it carries no chevron because it opens a sheet over the current page
/// rather than navigating anywhere. Enlarged text keeps the glyph and drops
/// the visible words (the accessible label always carries them).
class _ReportBugAction extends StatelessWidget {
  const _ReportBugAction({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final label = copy.text('Report a bug', 'Zgłoś błąd');
    final compact = MediaQuery.textScalerOf(context).scale(14) / 14 > 1.3;
    return Semantics(
      key: const ValueKey('more-report-bug'),
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          // Never reaches the centred drag handle, even on a 320 px phone.
          constraints: const BoxConstraints(
            minHeight: 44,
            minWidth: 44,
            maxWidth: 124,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.bug_report_outlined,
                  size: 20,
                  color: palette.textSecondary,
                ),
                if (!compact) ...[
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
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
    final lockColor = palette.warningForeground;
    final copy = AppLocalizations.of(context);
    final semanticLabel = [
      label,
      subtitle,
      if (isLocked) copy.text('Premium required', 'Wymagane Premium'),
    ].join(', ');
    void open() => Navigator.pop(context, destination);

    return Semantics(
      key: ValueKey('more-destination-${destination.name}'),
      button: true,
      enabled: true,
      label: semanticLabel,
      onTap: open,
      excludeSemantics: true,
      // Slim tile: one flat layer (1 px `palette.border`, radius 12) with a
      // tonal 22 px glyph — the sheet carries no violet accent of its own.
      child: Material(
        color: palette.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: open,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            // The launcher's compact density, as a floor rather than a fixed
            // height: short labels keep the 62dp row the grid always drew and
            // a comfortable 44px+ touch target, longer ones grow the row.
            constraints: const BoxConstraints(minHeight: 62),
            // 6 + 32 + 8 (was 8 + 34 + 8): four more pixels for the label,
            // so "Powiadomienia" stays one word on a 390 px phone. The
            // column-count estimate above still subtracts the old 58, which
            // keeps every grid/fallback branch decision exactly as it was.
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: palette.border),
            ),
            child: Stack(
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        icon,
                        color: colors.onPrimaryContainer,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Two lines each: the tile column is ~110dp wide on
                          // a 392dp phone, which is narrower than "Znajdź
                          // twórców", "Powiadomienia" or "Osoby warte
                          // obserwowania" — and narrower still on a 360dp one
                          // or at 1.3x text. The row grows to hold them; the
                          // ellipsis stays as the bound for a longer locale.
                          Text(
                            label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            subtitle,
                            maxLines: 2,
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
    // Ordinary rows are tonal (container pair); staff rows keep their tier's
    // role colour, which is identity, not a decorative accent.
    final accent = accentColor ?? colors.onPrimaryContainer;
    final glyphSurface =
        accentColor?.withValues(alpha: .18) ?? colors.primaryContainer;
    final lockColor = palette.warningForeground;
    final copy = AppLocalizations.of(context);
    final semanticLabel = [
      label,
      subtitle,
      if (isLocked) copy.text('Premium required', 'Wymagane Premium'),
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
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: open,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            constraints: const BoxConstraints(minHeight: 58),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
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
                    color: glyphSurface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: accent, size: 22),
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
                          fontWeight: FontWeight.w700,
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

/// "● Available ▾" above the More title: the one place every user passes
/// through, so the availability picker is never more than two taps away.
class _AvailabilityRow extends StatelessWidget {
  const _AvailabilityRow({this.profileService});

  final ProfileService? profileService;

  Stream<UserProfile>? _stream() {
    try {
      return (profileService ?? ProfileService()).watchCurrentProfile();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<UserProfile>(
      stream: _stream(),
      builder: (context, snapshot) {
        final profile = snapshot.data;
        if (profile == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: AvailabilityChip(
              availability: profile.availability,
              hitTargetSize: 44,
            ),
          ),
        );
      },
    );
  }
}
