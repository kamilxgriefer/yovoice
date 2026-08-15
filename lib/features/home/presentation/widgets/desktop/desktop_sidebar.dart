import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/sidebar_clock.dart';
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
/// Deliberately NOT a nav item: Profile. On desktop the signed-in user is
/// represented by the profile card pinned at the bottom of this rail
/// (tap = profile, gear = profile & account settings).
enum DesktopNavItem { home, discover, chats, notifications, friends, more }

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
    super.key,
  });

  /// Null while a More destination is open — no primary item highlights.
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

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 18),
      decoration: const BoxDecoration(
        color: Color(0xFF0C0814),
        border: Border(right: BorderSide(color: Color(0xFF241A33))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Wordmark(),
          const SizedBox(height: 26),
          // The rail must survive short desktop windows (a 1440x700
          // laptop): nine destinations plus two create actions overflow
          // a fixed column, so the navigation block scrolls while the
          // profile card stays pinned to the bottom.
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _NavTile(
                    item: DesktopNavItem.home,
                    icon: Icons.home_rounded,
                    label: 'Home',
                    active: active == DesktopNavItem.home,
                    onTap: onSelect,
                  ),
                  _NavTile(
                    item: DesktopNavItem.discover,
                    icon: Icons.explore_outlined,
                    label: 'Discover',
                    active: active == DesktopNavItem.discover,
                    onTap: onSelect,
                  ),
                  _NavTile(
                    item: DesktopNavItem.chats,
                    icon: Icons.chat_bubble_outline_rounded,
                    label: 'Chats',
                    badge: unreadConversationCount,
                    active: active == DesktopNavItem.chats,
                    onTap: onSelect,
                  ),
                  _NavTile(
                    item: DesktopNavItem.notifications,
                    icon: Icons.notifications_none_rounded,
                    label: 'Notifications',
                    badge: unreadNotificationCount,
                    active: active == DesktopNavItem.notifications,
                    onTap: onSelect,
                  ),
                  _NavTile(
                    item: DesktopNavItem.friends,
                    icon: Icons.people_alt_outlined,
                    label: 'Friends',
                    active: active == DesktopNavItem.friends,
                    onTap: onSelect,
                  ),
                  _NavTile(
                    key: moreItemKey,
                    item: DesktopNavItem.more,
                    icon: Icons.more_horiz_rounded,
                    label: 'More',
                    active: active == DesktopNavItem.more,
                    onTap: onSelect,
                  ),
                  const SizedBox(height: 18),
                  _CreateRoomButton(onTap: onCreateRoom),
                  const SizedBox(height: 10),
                  _CreateMomentButton(onTap: onCreateMoment),
                ],
              ),
            ),
          ),
          // The clock uses the space the rail already leaves above the
          // profile card. It sits OUTSIDE the scrolling nav column, so it
          // cannot push navigation off-screen at short heights, and the
          // profile card stays anchored to the bottom.
          const SidebarClock(),
          const SizedBox(height: 4),
          _ProfileCard(
            profileService: profileService,
            onTap: onOpenProfile,
            onSettings: onOpenProfileSettings,
          ),
        ],
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Row(
        children: [
          Image.asset(
            'assets/images/logo.png',
            width: 34,
            height: 34,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.graphic_eq_rounded,
              color: Color(0xFFD3A5FF),
              size: 28,
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'YO Voice',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
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
    super.key,
  });

  final DesktopNavItem item;
  final IconData icon;
  final String label;
  final bool active;
  final int badge;
  final ValueChanged<DesktopNavItem> onTap;

  @override
  State<_NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<_NavTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: () => widget.onTap(widget.item),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: active
                  ? AppColors.primary.withValues(alpha: .20)
                  : _hovered
                  ? Colors.white.withValues(alpha: .04)
                  : Colors.transparent,
              border: Border.all(
                color: active
                    ? AppColors.primary.withValues(alpha: .45)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  widget.icon,
                  size: 20,
                  color: active ? Colors.white : const Color(0xFF9A90AC),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Text(
                    widget.label,
                    style: TextStyle(
                      color: active ? Colors.white : const Color(0xFFC5BCD2),
                      fontSize: 14.5,
                      fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
                if (widget.badge > 0) _Badge(count: widget.badge),
              ],
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
      constraints: const BoxConstraints(minWidth: 22),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _CreateRoomButton extends StatelessWidget {
  const _CreateRoomButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            colors: [AppColors.primary, AppColors.secondary],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: .38),
              blurRadius: 22,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: const Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Create Room',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
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
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: double.infinity,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: _hovered
                ? AppColors.primary.withValues(alpha: .16)
                : Colors.white.withValues(alpha: .03),
            border: Border.all(
              color: _hovered
                  ? AppColors.primary.withValues(alpha: .55)
                  : const Color(0xFF2E2140),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: const Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.mic_none_rounded,
                  color: Color(0xFFD3A5FF),
                  size: 18,
                ),
                SizedBox(width: 8),
                // Flexible so the label ellipsises rather than overflowing
                // if the rail ever gets narrower (or the font wider) than
                // the 264px this is designed against.
                Flexible(
                  child: Text(
                    'Create Voice Moment',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Color(0xFFD3A5FF),
                      fontSize: 13.5,
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
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 8, 11),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white.withValues(alpha: .03),
        border: Border.all(color: const Color(0xFF2E2140)),
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
                        radius: 19,
                        photoUrl: profile?.photoUrl,
                        displayName: profile?.displayName,
                        premium: profile?.premiumIdentity ?? false,
                        fallbackIcon: Icons.person_rounded,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              profile?.displayName ?? 'Your profile',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            // The one shared identity rendering — same
                            // badges everyone else sees for this account,
                            // resolved from the public projection. An
                            // ordinary account shows USER, on purpose.
                            if (profile != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: UserIdentityBadges(uid: profile.uid),
                              ),
                            if (profile != null &&
                                profile.username.trim().isNotEmpty)
                              Text(
                                '@${profile.username.replaceAll(' ', '').toLowerCase()}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF9A90AC),
                                  fontSize: 11.5,
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
                  width: 34,
                  height: 34,
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
                    size: 18,
                    color: Color(0xFFD3A5FF),
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


