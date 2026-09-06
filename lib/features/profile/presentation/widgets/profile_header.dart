import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/achievements/data/models/achievement_definition.dart';
import 'package:yovoice/features/achievements/presentation/widgets/title_badge.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';
import 'package:yovoice/shared/widgets/identity/official_role_badge.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/profile/profile_banner.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';
import 'package:yovoice/shared/widgets/profile/availability_picker.dart';

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
    this.identityRepository,
    super.key,
  });

  final UserProfile profile;
  final AchievementDefinition? title;
  final VoidCallback onEdit;

  /// Test/preview seam. Production resolves through the shared singleton.
  final PublicIdentityRepository? identityRepository;

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
        final (avatarRadius, ringPadding) = switch (constraints.maxWidth) {
          < 360 => (33.0, 3.0),
          < 600 => (37.0, 3.0),
          < 900 => (41.0, 3.0),
          _ => (44.0, 4.0),
        };
        final avatarOverlap = avatarRadius + ringPadding;

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
                  context: context,
                  bannerHeight: bannerHeight,
                  avatarOverlap: avatarOverlap,
                  avatarRadius: avatarRadius,
                  ringPadding: ringPadding,
                  isWide: isWide,
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
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
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
                  color: palette.textPrimary,
                  tooltip: copy.text('Back', 'Wstecz'),
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: palette.surfaceRaised.withValues(
                      alpha: .92,
                    ),
                  ),
                ),
              )
            else
              // Keeps the title on the 18px content gutter when there is
              // no Back button (6 + 12 = 18).
              const SizedBox(width: 12),
            Expanded(
              child: Text(
                copy.profile,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            IconButton.filled(
              onPressed: onEdit,
              tooltip: copy.text('Edit profile', 'Edytuj profil'),
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              style: IconButton.styleFrom(backgroundColor: colors.primary),
              icon: Icon(Icons.edit_rounded, color: colors.onPrimary),
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
    required BuildContext context,
    required double bannerHeight,
    required double avatarOverlap,
    required double avatarRadius,
    required double ringPadding,
    required bool isWide,
  }) {
    final palette = context.appPalette;
    // Bottom-weighted scrim: keeps the banner's lower edge dark enough
    // that the name stays legible when it rides over the card's bottom
    // seam, on the gradient fallback and on user-uploaded images alike.
    final scrim = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      stops: const [0, .55, 1],
      colors: [
        palette.scrim.withValues(alpha: .04),
        palette.scrim.withValues(alpha: .16),
        palette.scrim.withValues(alpha: .68),
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
            child: ProfileBanner(
              userId: profile.uid,
              bannerUrl: profile.bannerUrl,
              mediaRevision: profile.profileUpdatedAt,
              overlay: scrim,
            ),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: bannerHeight - avatarOverlap),
            Padding(
              padding: const EdgeInsets.fromLTRB(_gutter, 0, _gutter, 0),
              child: _identityBlock(
                context,
                avatarRadius: avatarRadius,
                ringPadding: ringPadding,
                isWide: isWide,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _identityBlock(
    BuildContext context, {
    required double avatarRadius,
    required double ringPadding,
    required bool isWide,
  }) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final nameSize = isWide ? 27.0 : 22.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          key: const Key('profile-header-identity-row'),
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              key: const Key('profile-header-avatar'),
              padding: EdgeInsets.all(ringPadding),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [colors.primary, colors.secondary],
                ),
              ),
              child: UserAvatar(
                radius: avatarRadius,
                userId: profile.uid,
                photoUrl: profile.photoUrl,
                mediaRevision: profile.profileUpdatedAt,
                displayName: profile.displayName,
                backgroundColor: colors.primary,
                premium: profile.premiumIdentity,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  key: const Key('profile-header-name-plate'),
                  constraints: const BoxConstraints(maxWidth: 420),
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 7),
                  decoration: BoxDecoration(
                    color: palette.surfaceRaised.withValues(alpha: .94),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: palette.border),
                    boxShadow: [
                      BoxShadow(
                        color: palette.shadow.withValues(alpha: .16),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          profile.displayName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontSize: nameSize,
                            height: 1.02,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -.35,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      // Availability sits on the username line so the
                      // plate keeps its height budget (profile_header_compact_test).
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (profile.username.isNotEmpty) ...[
                            Text(
                              '@${profile.username.replaceAll(' ', '').toLowerCase()}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: palette.textSecondary,
                                fontSize: isWide ? 14 : 13,
                                fontWeight: FontWeight.w600,
                                letterSpacing: .1,
                              ),
                            ),
                          ],
                          AvailabilityChip(
                            availability: profile.availability,
                            dense: true,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        // One shared, full-width identity rail. The previous nested column
        // forced role, VIP, account type, Premium and achievement title into
        // as many as four floors beside the avatar. Two intentional levels
        // now keep authority (official role + VIP) separate from product and
        // achievement identity. Each level owns the whole content width;
        // enlarged text may wrap further rather than hide identity.
        const SizedBox(height: 8),
        SizedBox(
          key: const Key('profile-header-badge-rail'),
          width: double.infinity,
          child: title == null
              ? Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    UserIdentityBadges(
                      uid: profile.uid,
                      variant: IdentityBadgeVariant.compact,
                      repository: identityRepository,
                    ),
                    if (profile.accountType != AccountType.personal)
                      AccountTypeBadge(
                        accountType: profile.accountType,
                        compact: true,
                      ),
                    if (profile.premiumIdentity)
                      const PremiumIdentityChip(compact: true),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        UserIdentityBadges(
                          uid: profile.uid,
                          variant: IdentityBadgeVariant.compact,
                          repository: identityRepository,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (profile.accountType != AccountType.personal)
                          AccountTypeBadge(
                            accountType: profile.accountType,
                            compact: true,
                          ),
                        if (profile.premiumIdentity)
                          const PremiumIdentityChip(compact: true),
                        TitleBadge(achievement: title!, compact: true),
                      ],
                    ),
                  ],
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
  const PremiumIdentityChip({this.compact = false, super.key});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final color = colors.primary;
    return Tooltip(
      message: copy.text(
        'YO Voice Premium member',
        'Użytkownik YO Voice Premium',
      ),
      child: Container(
        constraints: BoxConstraints(minHeight: compact ? 24 : 28),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 7 : 9,
          vertical: compact ? 2 : 4,
        ),
        decoration: BoxDecoration(
          color: colors.primaryContainer,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: colors.primary.withValues(alpha: .5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.workspace_premium_rounded,
              size: compact ? 11 : 13,
              color: color,
            ),
            SizedBox(width: compact ? 3 : 4),
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
                  fontSize: compact ? 9.5 : 11,
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
  const AccountTypeBadge({
    required this.accountType,
    this.compact = false,
    super.key,
  });

  final AccountType accountType;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final (icon, label, surface, foreground, border) = switch (accountType) {
      AccountType.official => (
        Icons.verified_rounded,
        copy.text('Official', 'Oficjalne'),
        palette.infoSurface,
        palette.infoForeground,
        Color.alphaBlend(
          palette.infoForeground.withValues(alpha: .38),
          palette.border,
        ),
      ),
      AccountType.creator => (
        Icons.auto_awesome_rounded,
        copy.text('Creator', 'Twórca'),
        colors.primaryContainer,
        colors.onPrimaryContainer,
        Color.alphaBlend(colors.primary.withValues(alpha: .42), palette.border),
      ),
      AccountType.personal => (
        Icons.person_rounded,
        copy.text('Personal', 'Osobiste'),
        palette.surfaceMuted,
        palette.textSecondary,
        palette.borderStrong,
      ),
    };

    return Tooltip(
      message: copy.text('$label account', 'Konto: $label'),
      child: Container(
        key: ValueKey('profile-account-type-${accountType.name}'),
        constraints: BoxConstraints(minHeight: compact ? 24 : 28),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 7 : 9,
          vertical: compact ? 2 : 4,
        ),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: compact ? 11 : 13, color: foreground),
            SizedBox(width: compact ? 3 : 4),
            // Same rationale as PremiumIdentityChip: shrink, never
            // overflow, when text scaling outgrows the badges column.
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foreground,
                  fontSize: compact ? 9.5 : 11,
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
