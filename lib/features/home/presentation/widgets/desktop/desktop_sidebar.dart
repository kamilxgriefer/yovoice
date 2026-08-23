import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/timezone_world_map_card.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// The desktop-only left rail. Presentation shell for the SAME
/// destinations the mobile dock and More sheet already own — it holds no
/// navigation state of its own and creates no routes; every tap calls
/// back into `MainShell`, which remains the single source of truth.
///
/// Layout contract (the operator's reference design):
///
///  * TOP ROW, pinned: wordmark at the left, the notification BELL at
///    the right. The bell is the ONE entry point to the notifications
///    feed on desktop — there is deliberately no Notifications row in
///    the nav list below. It reports [DesktopNavItem.notifications]
///    through [onSelect] exactly like the old row did, so the shell's
///    routing, content slot and unread stream are untouched.
///  * NAV: compact rows — Home, Moments, Discover, Find creators,
///    Chats, Friends. The selected row gets a subtle violet surface, a
///    thin left accent bar and brighter icon/text.
///  * CREATE: a section label, the gradient "Create Room" primary CTA,
///    and the quieter outlined "Create Voice Moment" under it.
///  * MORE: a section label plus a single More row, which the shell
///    anchors its floating popover to (via [moreItemKey]).
///  * The compact local-time block and the profile card stay pinned at
///    the bottom; the middle section scrolls INTERNALLY when the window
///    is short, so the rail itself never overflows and never hands the
///    page a scrollbar.
///
/// Deliberately NOT a nav item: Profile. On desktop the signed-in user
/// is represented by the profile card pinned at the bottom of this rail
/// (tap = profile, gear = profile & account settings).
enum DesktopNavItem {
  home,
  moments,
  discover,
  findCreators,
  chats,
  notifications,
  friends,
  more,
}

/// THE RAIL IS A FIXED SURFACE. It is a `Row` child inside an `Expanded`
/// inside the shell's `Column` (main_shell.dart), so nothing above it can
/// translate it — and the browser document cannot scroll either, because
/// `flutter_bootstrap.js` initializes with no `hostElement` and the engine
/// pins `<body>` to `position: fixed; overflow: hidden`.
///
/// What DID move was the nav column's own scroll view, and the cause was
/// measured rather than guessed: the rail's fixed chrome plus the six
/// destinations, two Create buttons and More demand more height than the
/// rail gets once the window is short OR the mini player is mounted. At
/// 1440x768 `maxScrollExtent` is 0; at 720 it is 40; at 620 it is 82. Past
/// that threshold a wheel gesture with the pointer over the rail scrolls
/// it and it STAYS scrolled — which is what clips the Home tile under the
/// wordmark.
///
/// Two hypotheses were tested and REJECTED rather than carried:
///  * a shared `PrimaryScrollController` does NOT couple two scrollables —
///    each `Scrollable` keeps its own `ScrollPosition`, verified by driving
///    one and measuring the other (delta 0.0). It does still put two
///    positions on one controller, which `Scrollbar` asserts against — the
///    bug this file's sibling already hit and documented at
///    desktop_home.dart:478. That is closed below on principle, not as the
///    cause.
///  * macOS `BouncingScrollPhysics` does NOT rubber-band at zero extent:
///    a held pointer drag AND a trackpad pan-zoom both left `pixels` at
///    0.0. No physics override is warranted, so none is added.
class DesktopSidebar extends StatefulWidget {
  const DesktopSidebar({
    required this.active,
    required this.unreadConversationCount,
    required this.unreadNotificationCount,
    required this.onSelect,
    required this.onCreateRoom,
    required this.onCreateMoment,
    required this.onOpenProfile,
    required this.onOpenProfileSettings,
    this.profileService,
    this.moreItemKey,
    this.capabilityService,
    super.key,
  });

  /// Null while a pushed More destination is open — no primary item
  /// highlights. [DesktopNavItem.notifications] lights the BELL, since
  /// the feed no longer owns a nav row.
  final DesktopNavItem? active;
  final int unreadConversationCount;
  final int unreadNotificationCount;
  final ValueChanged<DesktopNavItem> onSelect;
  final VoidCallback onCreateRoom;

  /// The SAME Voice Moment recorder the Moments strip's "Your Moment"
  /// tile and the Moments destination open — MainShell passes one
  /// callback to all of them, so there is exactly one recorder in the app.
  final VoidCallback onCreateMoment;

  final VoidCallback onOpenProfile;
  final VoidCallback onOpenProfileSettings;
  final ProfileService? profileService;

  /// Retained for construction compatibility. The profile card's role
  /// and VIP badges now come from the shared identity components
  /// (UserIdentityBadges) rather than a capability lookup.
  final StaffCapabilityService? capabilityService;

  /// Anchors the desktop More popover to the rail item.
  final GlobalKey? moreItemKey;

  static const double width = 264;

  /// The rail's bright violet accent tint (established in this file long
  /// before this redesign) — readable on the dark surface where the
  /// saturated brand primary would sink.
  static const Color _accentTint = Color(0xFFD3A5FF);

  @override
  State<DesktopSidebar> createState() => _DesktopSidebarState();
}

class _DesktopSidebarState extends State<DesktopSidebar> {
  /// The rail's OWN scroll position, never the ambient primary one.
  ///
  /// `primary: false` is what actually severs the inheritance; the
  /// controller is what makes the ownership legible and assertable — a
  /// test can read `position.maxScrollExtent` and pin "the rail does not
  /// scroll at this height" instead of inferring it from pixels on screen.
  /// Same pattern, same reason, as `_RosterListState` in desktop_home.dart.
  final ScrollController _railScroll = ScrollController();

  @override
  void dispose() {
    _railScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    // ONE measurement of the rail's true height, taken here because this
    // is the only place that has it. The window is the wrong number:
    // RoomMiniBar (~118 px with a live room) and the verification banner
    // (~38 px) both shrink the rail without changing the window, and the
    // card's own slot inside the Column is vertically unbounded.
    return LayoutBuilder(
      builder: (context, constraints) {
        final railHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : null;
        return Container(
          width: DesktopSidebar.width,
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(right: BorderSide(color: colors.outlineVariant)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Pinned header: identity left, the bell right. The bell is
              // the single notifications entry point at desktop width.
              Row(
                children: [
                  const Expanded(child: _Wordmark()),
                  _BellButton(
                    count: widget.unreadNotificationCount,
                    active: widget.active == DesktopNavItem.notifications,
                    label: copy.notifications,
                    unreadWord: copy.text('unread', 'nieprzeczytane'),
                    onTap: () => widget.onSelect(DesktopNavItem.notifications),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              // The rail must survive short desktop windows (a 1280x620
              // laptop): six destinations, two create actions and the More
              // row overflow a fixed column, so this block scrolls while the
              // header, clock and profile card stay pinned.
              Expanded(
                child: SingleChildScrollView(
                  controller: _railScroll,
                  primary: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _NavTile(
                        item: DesktopNavItem.home,
                        icon: Icons.home_rounded,
                        label: copy.home,
                        active: widget.active == DesktopNavItem.home,
                        onTap: widget.onSelect,
                      ),
                      // Moments sits directly above Discover: the rail is
                      // where the two coexist, and a discovery surface for
                      // voice belongs ahead of a discovery surface for rooms.
                      _NavTile(
                        item: DesktopNavItem.moments,
                        icon: Icons.graphic_eq_rounded,
                        label: copy.moments,
                        active: widget.active == DesktopNavItem.moments,
                        onTap: widget.onSelect,
                      ),
                      _NavTile(
                        item: DesktopNavItem.discover,
                        icon: Icons.explore_outlined,
                        label: copy.discover,
                        active: widget.active == DesktopNavItem.discover,
                        onTap: widget.onSelect,
                      ),
                      _NavTile(
                        item: DesktopNavItem.findCreators,
                        icon: Icons.person_search_outlined,
                        label: copy.findCreators,
                        active: widget.active == DesktopNavItem.findCreators,
                        onTap: widget.onSelect,
                      ),
                      _NavTile(
                        item: DesktopNavItem.chats,
                        icon: Icons.chat_bubble_outline_rounded,
                        label: copy.chats,
                        badge: widget.unreadConversationCount,
                        active: widget.active == DesktopNavItem.chats,
                        onTap: widget.onSelect,
                      ),
                      _NavTile(
                        item: DesktopNavItem.friends,
                        icon: Icons.people_alt_outlined,
                        label: copy.friends,
                        active: widget.active == DesktopNavItem.friends,
                        onTap: widget.onSelect,
                      ),
                      const SizedBox(height: 16),
                      _SectionLabel(copy.text('CREATE', 'TWORZENIE')),
                      _CreateRoomButton(onTap: widget.onCreateRoom),
                      const SizedBox(height: 8),
                      _CreateMomentButton(onTap: widget.onCreateMoment),
                      const SizedBox(height: 16),
                      _SectionLabel(copy.text('MORE', 'WIĘCEJ')),
                      _NavTile(
                        key: widget.moreItemKey,
                        item: DesktopNavItem.more,
                        icon: Icons.more_horiz_rounded,
                        label: copy.more,
                        active: widget.active == DesktopNavItem.more,
                        trailingChevron: true,
                        onTap: widget.onSelect,
                      ),
                    ],
                  ),
                ),
              ),
              // The timezone card uses the space the rail already leaves above
              // the profile card. It sits OUTSIDE the scrolling nav column, so
              // it cannot push navigation off-screen at short heights, and the
              // profile card stays anchored to the bottom. It REPLACES the
              // plain clock block that used to live here — there is exactly one
              // local time in the rail, not two.
              TimezoneWorldMapCard(railHeight: railHeight),
              const SizedBox(height: 6),
              _ProfileCard(
                profileService: widget.profileService,
                onTap: widget.onOpenProfile,
                onSettings: widget.onOpenProfileSettings,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        children: [
          Image.asset(
            'assets/images/logo.png',
            width: 30,
            height: 30,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.graphic_eq_rounded,
              color: DesktopSidebar._accentTint,
              size: 26,
            ),
          ),
          const SizedBox(width: 9),
          Flexible(
            child: Text(
              'YO Voice',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 16.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The compact circular notification bell in the pinned header — the ONE
/// desktop entry point to the notifications feed, carrying the same live
/// unread count the old nav row displayed.
class _BellButton extends StatefulWidget {
  const _BellButton({
    required this.count,
    required this.active,
    required this.label,
    required this.unreadWord,
    required this.onTap,
  });

  final int count;
  final bool active;
  final String unreadWord;
  final String label;
  final VoidCallback onTap;

  @override
  State<_BellButton> createState() => _BellButtonState();
}

class _BellButtonState extends State<_BellButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final active = widget.active;
    return Semantics(
      button: true,
      selected: active,
      // `unreadLabel` comes through the same copy mechanism as every
      // other rail string — the literal English 'unread' was the one
      // unlocalized word on an otherwise bilingual rail.
      label: widget.count > 0
          ? '${widget.label}, ${widget.count} ${widget.unreadWord}'
          : widget.label,
      child: Tooltip(
        message: widget.label,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onHover: (value) => setState(() => _hovered = value),
            onTap: widget.onTap,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active
                        ? AppColors.primary.withValues(alpha: .22)
                        : _hovered
                        ? colors.onSurface.withValues(alpha: .07)
                        : colors.onSurface.withValues(alpha: .04),
                    border: Border.all(
                      color: active
                          ? AppColors.primary.withValues(alpha: .55)
                          : colors.outlineVariant,
                    ),
                  ),
                  child: Icon(
                    active
                        ? Icons.notifications_rounded
                        : Icons.notifications_none_rounded,
                    size: 19,
                    color: active
                        ? DesktopSidebar._accentTint
                        : colors.onSurfaceVariant,
                  ),
                ),
                if (widget.count > 0)
                  Positioned(
                    top: -3,
                    right: -3,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 18),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: colors.surface, width: 1.5),
                      ),
                      child: Text(
                        widget.count > 99 ? '99+' : '${widget.count}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          height: 1,
                        ),
                      ),
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

/// Small uppercase section heading ("CREATE", "MORE"). Distinct strings
/// from the nav row labels on purpose, so tests and screen readers never
/// confuse a heading with the tappable row under it.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: colors.onSurfaceVariant.withValues(alpha: .75),
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _NavTile extends StatefulWidget {
  const _NavTile({
    required this.item,
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.badge = 0,
    this.trailingChevron = false,
    super.key,
  });

  final DesktopNavItem item;
  final IconData icon;
  final String label;
  final bool active;
  final int badge;

  /// The More row hints that it opens a popover rather than swapping the
  /// content slot.
  final bool trailingChevron;

  final ValueChanged<DesktopNavItem> onTap;

  @override
  State<_NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<_NavTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: Semantics(
          button: true,
          // The wash and the 3px bar are visual-only; without this a
          // screen-reader user tabbing the rail cannot tell which
          // destination is current.
          selected: active,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onHover: (value) => setState(() => _hovered = value),
            onTap: () => widget.onTap(widget.item),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              // 44, the project's own minimum for interactive targets
              // (docs/UI.md) — the rail rows sat at 40.
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 9),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: active
                    ? AppColors.primary.withValues(alpha: .16)
                    : _hovered
                    ? colors.onSurface.withValues(alpha: .05)
                    : Colors.transparent,
              ),
              child: Row(
                children: [
                  // Thin left accent — always laid out so icons stay
                  // aligned; painted only on the selected row.
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    width: 3,
                    height: 16,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      color: active
                          ? DesktopSidebar._accentTint
                          : Colors.transparent,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Icon(
                    widget.icon,
                    size: 19,
                    color: active ? colors.onSurface : colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: active
                            ? colors.onSurface
                            : colors.onSurfaceVariant,
                        fontSize: 13.5,
                        fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                  ),
                  if (widget.badge > 0) _Badge(count: widget.badge),
                  if (widget.trailingChevron)
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 17,
                      color: colors.onSurfaceVariant.withValues(alpha: .8),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      // Explicit height: inside the fixed-height nav row an aligned
      // Container would otherwise stretch to the row's full height and
      // render as a tall pill instead of a compact badge.
      height: 18,
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}

/// THE primary CTA of the rail: full-width, YO purple gradient, visibly
/// heavier than everything else in the Create section.
class _CreateRoomButton extends StatelessWidget {
  const _CreateRoomButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(
            colors: [AppColors.primary, AppColors.secondary],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: .32),
              blurRadius: 18,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_rounded, color: Colors.white, size: 19),
                  SizedBox(width: 7),
                  Text(
                    AppLocalizations.of(
                      context,
                    ).text('Create Room', 'Utwórz pokój'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The rail's SECOND creation action, under the gradient Create Room.
///
/// Deliberately quieter than Create Room — outlined rather than filled,
/// shorter, violet text on the rail's own surface — because room creation
/// is the primary act and this is the one-tap alternative beside it. It
/// opens the existing recorder; there is no second recording screen.
class _CreateMomentButton extends StatefulWidget {
  const _CreateMomentButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_CreateMomentButton> createState() => _CreateMomentButtonState();
}

class _CreateMomentButtonState extends State<_CreateMomentButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onHover: (value) => setState(() => _hovered = value),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: double.infinity,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: _hovered
                ? AppColors.primary.withValues(alpha: .16)
                : colors.onSurface.withValues(alpha: .035),
            border: Border.all(
              color: _hovered
                  ? AppColors.primary.withValues(alpha: .55)
                  : colors.outlineVariant,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.mic_none_rounded,
                  color: DesktopSidebar._accentTint,
                  size: 17,
                ),
                SizedBox(width: 7),
                // Flexible so the label ellipsises rather than overflowing
                // if the rail ever gets narrower (or the font wider) than
                // the 264px this is designed against.
                Flexible(
                  child: Text(
                    AppLocalizations.of(
                      context,
                    ).text('Create Voice Moment', 'Nagraj Voice Moment'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: DesktopSidebar._accentTint,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
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

/// The signed-in user's card — the desktop replacement for a Profile nav
/// item. Body opens the profile; the violet gear opens the existing
/// profile & account settings screen.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.onTap,
    required this.onSettings,
    this.profileService,
  });

  final VoidCallback onTap;
  final VoidCallback onSettings;
  final ProfileService? profileService;

  /// The signed-in profile stream, or null when there is no usable
  /// session (sign-out in flight, dev harness). The card then renders its
  /// static shell instead of a red error box — a nav rail must never be
  /// the thing that crashes.
  Stream<UserProfile>? _profileStream() {
    try {
      return (profileService ?? ProfileService()).watchCurrentProfile();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: colors.onSurface.withValues(alpha: .035),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: StreamBuilder<UserProfile>(
        stream: _profileStream(),
        builder: (context, snapshot) {
          final profile = snapshot.data;
          return Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(12),
                  child: Row(
                    children: [
                      UserAvatar(
                        radius: 18,
                        photoUrl: profile?.photoUrl,
                        displayName: profile?.displayName,
                        premium: profile?.premiumIdentity ?? false,
                        fallbackIcon: Icons.person_rounded,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              profile?.displayName ?? 'Your profile',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.onSurface,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            // The one shared identity rendering — same
                            // badges everyone else sees for this account,
                            // resolved from the public projection. An
                            // ordinary account shows USER, on purpose.
                            // FittedBox keeps a long badge combination
                            // (OWNER + SUPER ADMIN + VIP) on ONE scaled
                            // line, so the pinned card can never grow
                            // past its lane or break the rail layout.
                            if (profile != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: UserIdentityBadges(uid: profile.uid),
                                  ),
                                ),
                              ),
                            if (profile != null &&
                                profile.username.trim().isNotEmpty)
                              Text(
                                '@${profile.username.replaceAll(' ', '').toLowerCase()}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                  fontSize: 11,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                onPressed: onSettings,
                tooltip: 'Profile settings',
                visualDensity: VisualDensity.compact,
                icon: Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withValues(alpha: .18),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: .45),
                    ),
                  ),
                  child: const Icon(
                    Icons.settings_rounded,
                    size: 17,
                    color: DesktopSidebar._accentTint,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
