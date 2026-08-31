import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
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
///  * TOP ROW, pinned: wordmark at the left, then HOME and the notification
///    BELL as compact icon buttons. Those are the only desktop entry points
///    to their destinations — neither is duplicated in the nav list below.
///  * NAV: compact rows — Moments, Discover, Find creators, Chats, Friends.
///    The selected row gets a subtle violet surface, a thin left accent bar
///    and brighter icon/text.
///  * CREATE: a section label, the gradient "Create Room" primary CTA,
///    and the quieter outlined "Create Voice Moment" under it.
///  * MORE: a section label plus a single More row, which the shell
///    anchors its floating popover to (via [moreItemKey]).
///  * The compact local-time block and the profile card stay pinned at the
///    bottom. The menu NEVER scrolls. On a short rail the optional time card
///    yields so every navigation and creation action remains visible.
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
/// The former implementation put the entire middle column in a
/// `SingleChildScrollView`. That kept short layouts from overflowing, but it
/// also let a wheel gesture leave primary navigation visibly displaced. The
/// header Home action and the short-height time-card tier recover that space,
/// so the menu can now be a fixed Column with no scroll position at all.
class DesktopSidebar extends StatelessWidget {
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
    this.tourItemKeys,
    this.tourCreateKey,
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

  /// Optional anchors for the guided tour. They never own navigation state;
  /// MainShell supplies them only to the currently rendered production rail.
  final Map<DesktopNavItem, GlobalKey>? tourItemKeys;
  final GlobalKey? tourCreateKey;

  static const double width = 264;

  /// Enlarged text needs real horizontal room, not an ellipsis that merely
  /// keeps the render tree green. The ordinary visual design remains 264 px;
  /// accessibility text sizes receive enough width for Polish primary labels.
  static const double enlargedTextWidth = 528;

  /// Below this logical height the shell uses its existing mobile navigation
  /// instead of compressing or clipping a desktop rail.
  static const double minimumSupportedHeight = 620;

  /// Below this measured rail height the creation actions share one row.
  static const double compactCreateActionsBelow = 700;

  /// Text/icon actions use a brightness-aware foreground rather than the
  /// button-fill brand swatch, whose Dark-theme contrast is intentionally
  /// tuned for white content instead of small copy on dark surfaces.
  static Color _interactiveAccent(BuildContext context) =>
      context.appPalette.interactiveForeground;

  Widget _tourItemAnchor(DesktopNavItem item, Widget child) {
    final key = tourItemKeys?[item];
    return key == null ? child : KeyedSubtree(key: key, child: child);
  }

  Widget _tourCreateAnchor(Widget child) {
    final key = tourCreateKey;
    return key == null ? child : KeyedSubtree(key: key, child: child);
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    // ONE measurement of the rail's true height, taken here because this is
    // the only place that has it. MainShell now keeps content-only chrome in
    // the content column, but direct preview/test hosts can still constrain
    // the rail independently of the window.
    return LayoutBuilder(
      builder: (context, constraints) {
        final railHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : null;
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final railWidth = textScale >= 2
            ? enlargedTextWidth
            : textScale > 1
            ? width * textScale
            : width;
        final useCompactCreateActions =
            railHeight != null && railHeight < compactCreateActionsBelow;
        final showTimezoneCard =
            textScale <= 1 || railHeight == null || railHeight >= 900;
        final showSectionLabels =
            textScale <= 1 || railHeight == null || railHeight >= 900;
        return Container(
          key: const ValueKey('desktop-sidebar-surface'),
          width: railWidth,
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
          decoration: BoxDecoration(
            color: palette.navigationSurface,
            border: Border(right: BorderSide(color: palette.navigationOutline)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Pinned header: identity left, then the two compact primary
              // actions. Home moved here so the menu below never needs to
              // trade visual stability for one more full-width row.
              Row(
                children: [
                  const Expanded(child: _Wordmark()),
                  _HeaderNavButton(
                    activeIcon: Icons.home_rounded,
                    inactiveIcon: Icons.home_outlined,
                    active: active == DesktopNavItem.home,
                    label: copy.home,
                    onTap: () => onSelect(DesktopNavItem.home),
                  ),
                  const SizedBox(width: 2),
                  _HeaderNavButton(
                    activeIcon: Icons.notifications_rounded,
                    inactiveIcon: Icons.notifications_none_rounded,
                    count: unreadNotificationCount,
                    active: active == DesktopNavItem.notifications,
                    label: copy.notifications,
                    unreadWord: copy.text('unread', 'nieprzeczytane'),
                    onTap: () => onSelect(DesktopNavItem.notifications),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Fixed, deliberately non-scrollable navigation. At short
              // heights the time card below yields instead of making primary
              // destinations move under the pointer.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Moments sits directly above Discover: the rail is
                    // where the two coexist, and a discovery surface for
                    // voice belongs ahead of a discovery surface for rooms.
                    _tourItemAnchor(
                      DesktopNavItem.moments,
                      _NavTile(
                        item: DesktopNavItem.moments,
                        icon: Icons.graphic_eq_rounded,
                        label: copy.moments,
                        active: active == DesktopNavItem.moments,
                        onTap: onSelect,
                      ),
                    ),
                    _NavTile(
                      item: DesktopNavItem.discover,
                      icon: Icons.explore_outlined,
                      label: copy.discover,
                      active: active == DesktopNavItem.discover,
                      onTap: onSelect,
                    ),
                    _NavTile(
                      item: DesktopNavItem.findCreators,
                      icon: Icons.person_search_outlined,
                      label: copy.findCreators,
                      active: active == DesktopNavItem.findCreators,
                      onTap: onSelect,
                    ),
                    _tourItemAnchor(
                      DesktopNavItem.chats,
                      _NavTile(
                        item: DesktopNavItem.chats,
                        icon: Icons.chat_bubble_outline_rounded,
                        label: copy.chats,
                        badge: unreadConversationCount,
                        active: active == DesktopNavItem.chats,
                        onTap: onSelect,
                      ),
                    ),
                    _NavTile(
                      item: DesktopNavItem.friends,
                      icon: Icons.people_alt_outlined,
                      label: copy.friends,
                      active: active == DesktopNavItem.friends,
                      onTap: onSelect,
                    ),
                    SizedBox(height: useCompactCreateActions ? 8 : 12),
                    if (showSectionLabels)
                      _SectionLabel(
                        copy.text('CREATE', 'TWORZENIE'),
                        compact: useCompactCreateActions,
                      ),
                    _tourCreateAnchor(
                      useCompactCreateActions
                          ? Row(
                              children: [
                                Expanded(
                                  child: _CreateRoomButton(onTap: onCreateRoom),
                                ),
                                const SizedBox(width: 8),
                                _CreateMomentButton(
                                  onTap: onCreateMoment,
                                  compact: true,
                                ),
                              ],
                            )
                          : Column(
                              children: [
                                _CreateRoomButton(onTap: onCreateRoom),
                                const SizedBox(height: 6),
                                _CreateMomentButton(onTap: onCreateMoment),
                              ],
                            ),
                    ),
                    SizedBox(height: useCompactCreateActions ? 8 : 12),
                    if (showSectionLabels)
                      _SectionLabel(
                        copy.text('MORE', 'WIĘCEJ'),
                        compact: useCompactCreateActions,
                      ),
                    _tourItemAnchor(
                      DesktopNavItem.more,
                      _NavTile(
                        key: moreItemKey,
                        item: DesktopNavItem.more,
                        icon: Icons.more_horiz_rounded,
                        label: copy.more,
                        active: active == DesktopNavItem.more,
                        trailingChevron: true,
                        onTap: onSelect,
                      ),
                    ),
                  ],
                ),
              ),
              // The map inside the time card already yields below 800 px. At
              // large text scale the whole informational card yields on short
              // rails so primary actions never clip or become unreachable.
              if (showTimezoneCard) ...[
                TimezoneWorldMapCard(railHeight: railHeight),
                const SizedBox(height: 6),
              ],
              _ProfileCard(
                profileService: profileService,
                onTap: onOpenProfile,
                onSettings: onOpenProfileSettings,
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
    final accent = DesktopSidebar._interactiveAccent(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        children: [
          Image.asset(
            'assets/images/logo.png',
            width: 30,
            height: 30,
            errorBuilder: (_, __, ___) =>
                Icon(Icons.graphic_eq_rounded, color: accent, size: 26),
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

/// A compact primary destination in the pinned header. Home and Notifications
/// share this control so their hit targets, selected state, focus treatment
/// and screen-reader output cannot drift apart.
class _HeaderNavButton extends StatefulWidget {
  const _HeaderNavButton({
    required this.activeIcon,
    required this.inactiveIcon,
    required this.active,
    required this.label,
    required this.onTap,
    this.count = 0,
    this.unreadWord,
  });

  final IconData activeIcon;
  final IconData inactiveIcon;
  final int count;
  final bool active;
  final String? unreadWord;
  final String label;
  final VoidCallback onTap;

  @override
  State<_HeaderNavButton> createState() => _HeaderNavButtonState();
}

class _HeaderNavButtonState extends State<_HeaderNavButton> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final accent = DesktopSidebar._interactiveAccent(context);
    final active = widget.active;
    return Semantics(
      button: true,
      selected: active,
      excludeSemantics: true,
      onTap: widget.onTap,
      label: widget.count > 0 && widget.unreadWord != null
          ? '${widget.label}, ${widget.count} ${widget.unreadWord}'
          : widget.label,
      child: Tooltip(
        message: widget.label,
        child: SizedBox.square(
          dimension: 44,
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onHover: (value) => setState(() => _hovered = value),
              onFocusChange: (value) => setState(() => _focused = value),
              onTap: widget.onTap,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: active
                          ? accent.withValues(alpha: .18)
                          : _hovered || _focused
                          ? colors.onSurface.withValues(alpha: .08)
                          : colors.onSurface.withValues(alpha: .04),
                      border: Border.all(
                        width: _focused ? 2 : 1,
                        color: active || _focused
                            ? accent
                            : colors.outlineVariant,
                      ),
                    ),
                    child: Icon(
                      active ? widget.activeIcon : widget.inactiveIcon,
                      size: 19,
                      color: active ? accent : colors.onSurfaceVariant,
                    ),
                  ),
                  if (widget.count > 0)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 18),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: colors.primary,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: colors.surface, width: 1.5),
                        ),
                        child: Text(
                          widget.count > 99 ? '99+' : '${widget.count}',
                          style: TextStyle(
                            color: colors.onPrimary,
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
      ),
    );
  }
}

/// Small uppercase section heading ("CREATE", "MORE"). Distinct strings
/// from the nav row labels on purpose, so tests and screen readers never
/// confuse a heading with the tappable row under it.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label, {this.compact = false});

  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, compact ? 4 : 8),
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
  late final FocusNode _focusNode = FocusNode(
    debugLabel: 'Desktop ${widget.item.name}',
  );
  bool _hovered = false;
  bool _focused = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    final colors = Theme.of(context).colorScheme;
    final palette = context.appPalette;
    final accent = DesktopSidebar._interactiveAccent(context);
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
            focusNode: _focusNode,
            borderRadius: BorderRadius.circular(10),
            onHover: (value) => setState(() => _hovered = value),
            onFocusChange: (value) => setState(() => _focused = value),
            onTap: () => widget.onTap(widget.item),
            child: AnimatedContainer(
              key: ValueKey('desktop-nav-focus-${widget.item.name}'),
              duration: const Duration(milliseconds: 140),
              // 44, the project's own minimum for interactive targets
              // (docs/UI.md) — the rail rows sat at 40.
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 9),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: active
                    ? colors.primaryContainer
                    : _hovered
                    ? palette.surfaceMuted
                    : Colors.transparent,
                border: Border.all(
                  color: _focused ? palette.focus : Colors.transparent,
                  width: 2,
                ),
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
                      color: active ? accent : Colors.transparent,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Icon(
                    widget.icon,
                    size: 19,
                    color: active
                        ? colors.onPrimaryContainer
                        : colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: active
                            ? colors.onPrimaryContainer
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
    final colors = Theme.of(context).colorScheme;
    return Container(
      // Explicit height: inside the fixed-height nav row an aligned
      // Container would otherwise stretch to the row's full height and
      // render as a tall pill instead of a compact badge.
      height: 18,
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.primary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: TextStyle(
          color: colors.onPrimary,
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
class _CreateRoomButton extends StatefulWidget {
  const _CreateRoomButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_CreateRoomButton> createState() => _CreateRoomButtonState();
}

class _CreateRoomButtonState extends State<_CreateRoomButton> {
  late final FocusNode _focusNode = FocusNode(
    debugLabel: 'Desktop create room',
  );
  bool _focused = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: DecoratedBox(
        key: const ValueKey('desktop-create-room-focus'),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(colors: [colors.primary, colors.secondary]),
          border: Border.all(
            color: _focused ? colors.onPrimary : Colors.transparent,
            width: 2,
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
            focusNode: _focusNode,
            borderRadius: BorderRadius.circular(14),
            onFocusChange: (value) => setState(() => _focused = value),
            onTap: widget.onTap,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_rounded, color: colors.onPrimary, size: 19),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      AppLocalizations.of(
                        context,
                      ).text('Create Room', 'Utwórz pokój'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.onPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
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
  const _CreateMomentButton({required this.onTap, this.compact = false});

  final VoidCallback onTap;
  final bool compact;

  @override
  State<_CreateMomentButton> createState() => _CreateMomentButtonState();
}

class _CreateMomentButtonState extends State<_CreateMomentButton> {
  late final FocusNode _focusNode = FocusNode(
    debugLabel: 'Desktop create Voice Moment',
  );
  bool _hovered = false;
  bool _focused = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = context.appPalette;
    final accent = DesktopSidebar._interactiveAccent(context);
    final label = AppLocalizations.of(
      context,
    ).text('Create Voice Moment', 'Nagraj Voice Moment');
    final button = Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        focusNode: _focusNode,
        borderRadius: BorderRadius.circular(12),
        onHover: (value) => setState(() => _hovered = value),
        onFocusChange: (value) => setState(() => _focused = value),
        onTap: widget.onTap,
        child: AnimatedContainer(
          key: const ValueKey('desktop-create-moment-focus'),
          duration: const Duration(milliseconds: 140),
          width: widget.compact ? 46 : double.infinity,
          height: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: _hovered ? colors.primaryContainer : palette.surfaceRaised,
            border: Border.all(
              color: _focused
                  ? palette.focus
                  : _hovered
                  ? accent
                  : palette.borderStrong,
              width: _focused ? 2 : 1,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.mic_none_rounded, color: accent, size: 17),
                if (!widget.compact) ...[
                  const SizedBox(width: 7),
                  // Flexible so the label ellipsises rather than overflowing
                  // if the rail ever gets narrower (or the font wider) than
                  // the 264px this is designed against.
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
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
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: widget.onTap,
      child: widget.compact ? Tooltip(message: label, child: button) : button,
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
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: palette.surfaceRaised,
        border: Border.all(color: palette.border),
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
                tooltip: copy.text('Profile settings', 'Ustawienia profilu'),
                visualDensity: VisualDensity.compact,
                icon: Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.primaryContainer,
                    border: Border.all(
                      color: colors.primary.withValues(alpha: .55),
                    ),
                  ),
                  child: Icon(
                    Icons.settings_rounded,
                    size: 17,
                    color: colors.onPrimaryContainer,
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
