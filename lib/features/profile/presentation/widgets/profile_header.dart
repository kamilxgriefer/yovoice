import 'package:flutter/material.dart';

import 'package:yovoice/features/achievements/data/models/achievement_definition.dart';
import 'package:yovoice/features/achievements/presentation/widgets/title_badge.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/shared/widgets/profile/profile_banner.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// The profile hero: banner, avatar, name, username, account badge and
/// the Edit button.
///
/// Public (not private to profile_screen.dart) so the same widget — not a
/// hand-mirrored copy — is rendered by the Profile screen, the
/// lib/dev/profile_preview.dart harness, and the width-matrix layout test
/// in test/profile_header_layout_test.dart. The mobile avatar-clipping
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

  @override
  Widget build(BuildContext context) {
    // Full-bleed banner on phones; on wide viewports the same banner
    // becomes a centered, rounded cover card so a 1440px browser window
    // doesn't stretch one image across the entire screen. Breakpoint via
    // LayoutBuilder, proportions via constraints — no scaling transforms.
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;

        final scrim = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: .05),
            const Color(0xFF09050F),
          ],
        );

        final bannerLayer = isWide
            ? Positioned.fill(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1100),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(26),
                        child: ProfileBanner(
                          bannerUrl: profile.bannerUrl,
                          overlay: scrim,
                        ),
                      ),
                    ),
                  ),
                ),
              )
            : Positioned.fill(
                child: ProfileBanner(
                  bannerUrl: profile.bannerUrl,
                  overlay: scrim,
                ),
              );

        return SizedBox(
          height: isWide ? 300 : 320,
          child: Stack(
            children: [bannerLayer, _headerContent(context, isWide)],
          ),
        );
      },
    );
  }

  Widget _headerContent(BuildContext context, bool isWide) {
    // ALWAYS wrapped in Positioned.fill. The inner Stack must fill the
    // header box so the identity row's `bottom: 20` anchors to the
    // header's bottom edge. When the mobile branch returned this Stack
    // unpositioned, it collapsed to the title row's height and the
    // avatar was drawn (and clipped) above the top of the page — the
    // production mobile bug.
    final content = Stack(children: [_titleRow(), _identityRow()]);

    if (!isWide) {
      return Positioned.fill(child: content);
    }

    // On wide screens the text/avatar content tracks the same 1100px cap
    // as the banner card so they read as one composition. SizedBox.expand
    // is load-bearing: ConstrainedBox only caps the WIDTH, and without a
    // tight height the inner Stack collapses to the title row exactly
    // like the mobile bug — the width-matrix layout test caught the wide
    // variant of the same failure at 1024/1440.
    return Positioned.fill(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: SizedBox.expand(child: content),
        ),
      ),
    );
  }

  Widget _titleRow() {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        child: Builder(
          builder: (context) => Row(
            children: [
              // A physical Back control whenever there IS somewhere to go
              // back to. Profile is pushed as a route from the avatar, the
              // profile card and More, and previously offered no way out
              // but a system gesture — which desktop web does not have.
              if (Navigator.of(context).canPop())
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: Colors.white,
                    tooltip: 'Back',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: .28),
                    ),
                  ),
                ),
              const Expanded(
                child: Text(
                  'Profile',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 31,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton.filled(
                onPressed: onEdit,
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFAE22FF),
                ),
                icon: const Icon(Icons.edit_rounded, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _identityRow() {
    return Positioned(
      left: 20,
      right: 20,
      bottom: 20,
      child: Row(
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
              radius: 55,
              photoUrl: profile.photoUrl,
              displayName: profile.displayName,
              backgroundColor: const Color(0xFF281133),
              premium: profile.premiumIdentity,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
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
                      fontSize: 29,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (profile.username.isNotEmpty)
                    Text(
                      '@${profile.username.replaceAll(' ', '').toLowerCase()}',
                      style: const TextStyle(
                        color: Color(0xFFB8ADC1),
                        fontSize: 15,
                      ),
                    ),
                  // The identity chips row (board screen 5): account type +
                  // the server-mirrored Premium mark. Only truthful chips —
                  // premiumIdentity is written by Cloud Functions, never
                  // computed locally.
                  if (profile.accountType != AccountType.personal ||
                      profile.premiumIdentity)
                    Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (profile.accountType != AccountType.personal)
                            AccountTypeBadge(accountType: profile.accountType),
                          if (profile.premiumIdentity)
                            const PremiumIdentityChip(),
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
      ),
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
            Text(
              'Premium',
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w800,
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
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
