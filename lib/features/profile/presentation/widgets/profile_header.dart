import 'package:flutter/material.dart';

import 'package:yovoice/features/achievements/data/models/achievement_definition.dart';
import 'package:yovoice/features/achievements/presentation/widgets/title_badge.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/shared/widgets/identity/official_role_badge.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/profile/profile_banner.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// The profile hero — compact edition: a toolbar row (Back when the
/// route can pop, the screen title, Edit), a SLIM banner accent card,
/// and one readable identity block (avatar + name + username + badges).
///
/// The previous incarnation was a fixed 300–320px banner Stack: at
/// desktop sizes most of it was empty gradient with a lone Back arrow
/// floating in the corner. The banner is now a bounded accent (104px on
/// phones, 132px wide) that the avatar overlaps, and the header sizes
/// itself to its content instead of claiming a fixed viewport share.
///
/// Public (not private to profile_screen.dart) so the same widget — not a
/// hand-mirrored copy — is rendered by the Profile screen, the
/// lib/dev/profile_preview.dart harness, and the layout tests in
/// test/profile_header_layout_test.dart and
/// test/profile_header_compact_test.dart. The mobile avatar-clipping
/// regression shipped precisely because the harness mirrored this layout
/// instead of importing it: the real screen collapsed while the mirror
/// looked plausible.
class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    required this.profile,
    required this.onEdit,
    this.title,
    super.key,
  });

  final UserProfile profile;
  final AchievementDefinition? title;
  final VoidCallback onEdit;

  /// Matches the 18px gutter of the content panels below
  /// (profile_screen's SliverPadding), so the toolbar and banner card
  /// line up with the rest of the page instead of the screen edge.
  static const double _gutter = 18;

  @override
  Widget build(BuildContext context) {
    // Breakpoint via LayoutBuilder — available width, never device
    // labels. Inside the screen's ResponsiveContentFrame (1040px feed
    // measure) the 1100 self-cap is a no-op; it exists so bare hosts
    // (the dev harness, tests) never stretch the header across 1440px.
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
        final bannerHeight = isWide ? 132.0 : 104.0;
        final avatarOverlap = isWide ? 44.0 : 40.0;

        return Align(
          alignment: Alignment.topCenter,
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _toolbar(context),
                const SizedBox(height: 6),
                _bannerAndIdentity(
                  bannerHeight: bannerHeight,
                  avatarOverlap: avatarOverlap,
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _toolbar(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 6, _gutter, 0),
        child: Row(
          children: [
            // A physical Back control whenever there IS somewhere to go
            // back to. Profile is pushed as a route from the avatar, the
            // profile card and More, and previously offered no way out
            // but a system gesture — which desktop web does not have.
            if (canPop)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                  color: Colors.white,
                  tooltip: 'Back',
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: .28),
                  ),
                ),
              )
            else
              // Keeps the title on the 18px content gutter when there is
              // no Back button (6 + 12 = 18).
              const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Profile',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            IconButton.filled(
              onPressed: onEdit,
              tooltip: 'Edit profile',
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFFAE22FF),
              ),
              icon: const Icon(Icons.edit_rounded, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  /// Slim banner accent + identity block. The Stack is sized by the
  /// (non-positioned) Column, never by the banner: the banner is a
  /// Positioned backdrop with an explicit height, so this layout cannot
  /// reproduce the collapsed-Stack avatar-clipping bug.
  Widget _bannerAndIdentity({
    required double bannerHeight,
    required double avatarOverlap,
  }) {
    // Bottom-weighted scrim: keeps the banner's lower edge dark enough
    // that the name stays legible when it rides over the card's bottom
    // seam, on the gradient fallback and on user-uploaded images alike.
    final scrim = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      stops: const [0, .55, 1],
      colors: [
        Colors.black.withValues(alpha: .04),
        Colors.black.withValues(alpha: .16),
        const Color(0xFF09050F).withValues(alpha: .68),
      ],
    );

    return Stack(
      children: [
        Positioned(
          top: 0,
          left: _gutter,
          right: _gutter,
          height: bannerHeight,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: ProfileBanner(bannerUrl: profile.bannerUrl, overlay: scrim),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: bannerHeight - avatarOverlap),
            Padding(
              padding: const EdgeInsets.fromLTRB(_gutter + 12, 0, _gutter, 0),
              child: _identityBlock(),
            ),
          ],
        ),
      ],
    );
  }

  Widget _identityBlock() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          key: const Key('profile-header-avatar'),
          padding: const EdgeInsets.all(4),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [Color(0xFF6A00FF), Color(0xFFD12CFF)],
            ),
          ),
          child: UserAvatar(
            radius: 44,
            photoUrl: profile.photoUrl,
            displayName: profile.displayName,
            backgroundColor: const Color(0xFF281133),
            premium: profile.premiumIdentity,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  profile.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (profile.username.isNotEmpty)
                  Text(
                    '@${profile.username.replaceAll(' ', '').toLowerCase()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFB8ADC1),
                      fontSize: 14,
                    ),
                  ),
                // The identity chips row (board screen 5). The official
                // role badge leads and ALWAYS renders — an ordinary
                // account reads USER — with VIP beside it when held,
                // both resolved from the server-written public badge
                // projection. After them: account type + the
                // server-mirrored Premium mark. Only truthful chips —
                // premiumIdentity is written by Cloud Functions, never
                // computed locally.
                Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      UserIdentityBadges(
                        uid: profile.uid,
                        variant: IdentityBadgeVariant.full,
                      ),
                      if (profile.accountType != AccountType.personal)
                        AccountTypeBadge(accountType: profile.accountType),
                      if (profile.premiumIdentity) const PremiumIdentityChip(),
                    ],
                  ),
                ),
                if (title != null) ...[
                  const SizedBox(height: 8),
                  TitleBadge(achievement: title!),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The Premium mark on a profile — rendered only from
/// `profile.premiumIdentity`, the server-written public mirror of the
/// entitlement. Companion to [AccountTypeBadge] in the header chips row.
class PremiumIdentityChip extends StatelessWidget {
  const PremiumIdentityChip({super.key});

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFFE9B8FF);
    return Tooltip(
      message: 'YO Voice Premium member',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFC026FF).withValues(alpha: .16),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: const Color(0xFFC026FF).withValues(alpha: .5),
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.workspace_premium_rounded, size: 13, color: color),
            SizedBox(width: 4),
            // Flexible + ellipsis: at 2.0 text scale on a 320px viewport
            // the badges column is narrower than the scaled label, and a
            // rigid Text overflows the chip.
            Flexible(
              child: Text(
                'Premium',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Marks a Creator (or Official) account on the profile header.
///
/// The account type already persisted to Firestore and already drove
/// Creator Studio and Settings, but nothing on the profile itself said
/// which kind of account you were looking at.
class AccountTypeBadge extends StatelessWidget {
  const AccountTypeBadge({required this.accountType, super.key});

  final AccountType accountType;

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = switch (accountType) {
      AccountType.official => (
        Icons.verified_rounded,
        'Official',
        const Color(0xFF4DA3FF),
      ),
      AccountType.creator => (
        Icons.auto_awesome_rounded,
        'Creator',
        const Color(0xFFD3A5FF),
      ),
      AccountType.personal => (
        Icons.person_rounded,
        'Personal',
        const Color(0xFFB8ADC1),
      ),
    };

    return Tooltip(
      message: '$label account',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: color.withValues(alpha: .45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            // Same rationale as PremiumIdentityChip: shrink, never
            // overflow, when text scaling outgrows the badges column.
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
