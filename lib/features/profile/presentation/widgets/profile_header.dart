import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/achievements/data/models/achievement_definition.dart';
import 'package:yovoice/features/achievements/presentation/widgets/title_badge.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/profile_image_rules.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/identity/official_role_badge.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/profile/profile_banner.dart';
import 'package:yovoice/shared/widgets/profile/profile_photo_viewer.dart';
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
///
/// Slim redesign (phase 5): the header can also carry the profile's stats
/// row ([stats], drawn by [ProfileStatsRow]) and its action bar ([actions],
/// usually a [ProfileActionBar]). Both are optional so every existing host —
/// the layout tests, the crop editor's geometry, the dev preview — keeps the
/// compact header it measures. When [actions] is supplied it owns Edit, so
/// the toolbar drops its own Edit icon rather than offering the same action
/// twice.
class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    required this.profile,
    required this.onEdit,
    this.title,
    this.identityRepository,
    this.mediaService,
    this.stats,
    this.actions,
    super.key,
  });

  final UserProfile profile;
  final AchievementDefinition? title;
  final VoidCallback onEdit;

  /// Real counters only, in reading order. Null draws no stats row.
  final List<ProfileStat>? stats;

  /// The profile's primary / secondary / icon actions. Null keeps the
  /// toolbar's Edit icon as the header's only action.
  final Widget? actions;

  /// Test/preview seam. Production resolves through the shared singleton.
  final PublicIdentityRepository? identityRepository;

  /// Test/preview seam for the viewer-authorized media resolver. Production
  /// lets each media widget construct the shared service itself.
  final ProfileMediaService? mediaService;

  /// Matches the 18px gutter of the content panels below
  /// (profile_screen's SliverPadding), so the toolbar and banner card
  /// line up with the rest of the page instead of the screen edge.
  static const double gutter = 18;

  /// The band the header actually paints the banner into: a fixed height at
  /// content width, NOT the 16:9 the upload pipeline stores. Public because
  /// the crop editor has to mark the strip of that 16:9 which survives here;
  /// two hand-copied numbers are exactly how the crop and the header drifted
  /// apart in the first place.
  static const double bannerHeightCompact = 104;
  static const double bannerHeightWide = 132;

  /// Fraction of the stored banner's height that is still on screen at the
  /// WIDEST presentation, i.e. the part a user can rely on at every width.
  ///
  /// The band is drawn with `BoxFit.cover` and `Alignment.center`, so the
  /// wider the band gets the less of the 16:9 source fits inside it: roughly
  /// 52% of it survives on a 390pt phone and only ~23% at the 1040pt feed
  /// cap. Derived from the three sources that decide it — the stored ratio,
  /// the widest content measure and the wide band height — so a redesign
  /// that changes any of them moves the crop editor's guide with it.
  static final double bannerSafeBandFraction =
      ProfileImageRules.banner.aspectRatio /
      ((ResponsiveContentWidth.feed.maxWidth - gutter * 2) / bannerHeightWide);

  @override
  Widget build(BuildContext context) {
    // Breakpoint via LayoutBuilder — available width, never device
    // labels. Inside the screen's ResponsiveContentFrame (1040px feed
    // measure) the 1100 self-cap is a no-op; it exists so bare hosts
    // (the dev harness, tests) never stretch the header across 1440px.
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
        final bannerHeight = isWide ? bannerHeightWide : bannerHeightCompact;
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
                if (stats != null || actions != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(gutter, 12, gutter, 0),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      // On wide canvases the counters and buttons keep a
                      // readable measure instead of stretching to 1040 px.
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 640),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (stats != null)
                              ProfileStatsRow(
                                containerKey: const ValueKey(
                                  'profile-header-stats',
                                ),
                                stats: stats!,
                              ),
                            if (stats != null && actions != null)
                              const SizedBox(height: 12),
                            ?actions,
                          ],
                        ),
                      ),
                    ),
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
        padding: const EdgeInsets.fromLTRB(6, 6, gutter, 0),
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
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            // The action bar, when present, carries Edit as the primary CTA.
            if (actions == null)
              IconButton.filled(
                onPressed: onEdit,
                tooltip: copy.text('Edit profile', 'Edytuj profil'),
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                style: IconButton.styleFrom(backgroundColor: colors.primary),
                icon: Icon(Icons.edit_rounded, color: colors.onPrimary),
              )
            else
              // Keeps the toolbar row at its 44 px target height.
              const SizedBox(height: 44),
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
          left: gutter,
          right: gutter,
          height: bannerHeight,
          child: ProfileBannerButton(
            userId: profile.uid,
            displayName: profile.displayName,
            mediaRevision: profile.profileUpdatedAt,
            mediaService: mediaService,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ProfileBanner(
                userId: profile.uid,
                bannerUrl: profile.bannerUrl,
                mediaRevision: profile.profileUpdatedAt,
                mediaService: mediaService,
                overlay: scrim,
              ),
            ),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: bannerHeight - avatarOverlap),
            Padding(
              padding: const EdgeInsets.fromLTRB(gutter, 0, gutter, 0),
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
            ProfilePhotoButton(
              userId: profile.uid,
              displayName: profile.displayName,
              mediaRevision: profile.profileUpdatedAt,
              mediaService: mediaService,
              // The ring, not the disc: the cut-out ring is part of the
              // avatar, and a smaller minimum would clip the ripple inside it.
              minimumSize: Size(
                (avatarRadius + ringPadding) * 2,
                (avatarRadius + ringPadding) * 2,
              ),
              child: Container(
                key: const Key('profile-header-avatar'),
                padding: EdgeInsets.all(ringPadding),
                // Slim: a flat canvas-coloured cut-out with a 1 px hairline
                // separates the avatar from the banner. The ring stays free
                // of decorative gradients (it is not a Moment ring).
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: palette.background,
                  border: Border.all(color: palette.border),
                ),
                child: UserAvatar(
                  radius: avatarRadius,
                  userId: profile.uid,
                  photoUrl: profile.photoUrl,
                  mediaRevision: profile.profileUpdatedAt,
                  mediaService: mediaService,
                  displayName: profile.displayName,
                  backgroundColor: colors.primary,
                  premium: profile.premiumIdentity,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                // The plate rides over the banner band, and a decorated
                // Container does not answer hit tests — without this the
                // user's own name fell through and opened the banner viewer.
                // Opaque still lets the availability chip inside win first.
                child: MetaData(
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    key: const Key('profile-header-name-plate'),
                    constraints: const BoxConstraints(maxWidth: 420),
                    padding: const EdgeInsets.fromLTRB(10, 6, 10, 7),
                    decoration: BoxDecoration(
                      color: palette.surfaceRaised.withValues(alpha: .94),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: palette.border),
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
                              fontWeight: FontWeight.w800,
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
                              hitTargetSize: 44,
                            ),
                          ],
                        ),
                      ],
                    ),
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
                      const PremiumIdentityBadge(compact: true),
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
                          const PremiumIdentityBadge(compact: true),
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

/// One counter in a profile's stats row. [value] is always a real field the
/// caller already holds (`users/{uid}` on the own profile, the public
/// projection on someone else's); the row never invents or estimates one.
class ProfileStat {
  const ProfileStat({
    required this.value,
    required this.label,
    required this.keyName,
    this.keyPrefix = 'profile-stat',
    this.onTap,
  });

  final int value;
  final String label;

  /// Suffix of the stat's key: `<keyPrefix>-<keyName>`.
  final String keyName;
  final String keyPrefix;

  /// Null renders a plain labelled counter; otherwise the counter is a 44 px+
  /// tappable region (followers / following lists).
  final VoidCallback? onTap;

  Key get key => ValueKey('$keyPrefix-$keyName');
}

/// The profile's stats row, shared by the own profile and someone else's
/// profile (Slim redesign, phase 5): one flat 1 px `palette.border` band,
/// radius 12, counters side by side. It stacks into one counter per line
/// once a counter's cell would drop below [minCellWidth] or body text reaches
/// 21 px (≈150 % text), so labels are never squeezed and every tappable
/// counter keeps a 44 px target.
class ProfileStatsRow extends StatelessWidget {
  const ProfileStatsRow({required this.stats, this.containerKey, super.key});

  final List<ProfileStat> stats;

  /// Rides the decorated band itself, so a finder can read its decoration.
  final Key? containerKey;

  /// The narrowest counter cell the row accepts before it stacks.
  static const double minCellWidth = 64;

  /// Compact display for large counts (1.8K / 1.2M) — board screen 5.
  static String compact(int value) {
    String fmt(double v) {
      final d = (v * 10).truncate() / 10;
      return d == d.truncateToDouble() ? '${d.truncate()}' : '$d';
    }

    if (value >= 1000000) return '${fmt(value / 1000000)}M';
    if (value >= 1000) return '${fmt(value / 1000)}K';
    return '$value';
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final palette = context.appPalette;
        final scaledBodySize = MediaQuery.textScalerOf(context).scale(14);
        // Side by side while every counter keeps a readable cell; one per
        // line once a cell would drop below [minCellWidth] or text is large.
        final cellWidth = constraints.maxWidth / stats.length.clamp(1, 99);
        final shouldStack = cellWidth < minCellWidth || scaledBodySize >= 21;
        final cells = [for (final stat in stats) _ProfileStatCell(stat: stat)];
        return Container(
          key: containerKey,
          padding: EdgeInsets.symmetric(vertical: shouldStack ? 4 : 6),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: palette.border),
          ),
          child: shouldStack
              ? Column(
                  children: [
                    for (var index = 0; index < cells.length; index++) ...[
                      cells[index],
                      if (index < cells.length - 1)
                        Divider(
                          height: 1,
                          indent: 16,
                          endIndent: 16,
                          color: palette.border,
                        ),
                    ],
                  ],
                )
              : Row(
                  children: [for (final cell in cells) Expanded(child: cell)],
                ),
        );
      },
    );
  }
}

class _ProfileStatCell extends StatelessWidget {
  const _ProfileStatCell({required this.stat});

  final ProfileStat stat;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final content = ExcludeSemantics(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  ProfileStatsRow.compact(stat.value),
                  maxLines: 1,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 17,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                // A long single word ("Obserwujący") shrinks a little on a
                // five-counter phone row instead of clipping.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    stat.label,
                    maxLines: 1,
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 12,
                      height: 1.3,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final semanticLabel = '${stat.label}: ${stat.value}';
    final onTap = stat.onTap;
    if (onTap == null) {
      return Semantics(key: stat.key, label: semanticLabel, child: content);
    }
    return AccessibleTapRegion(
      key: stat.key,
      onTap: onTap,
      semanticLabel: semanticLabel,
      borderRadius: 12,
      child: content,
    );
  }
}

/// The profile's action bar: exactly one primary CTA, an optional secondary
/// CTA and an optional icon action, in that order (Slim redesign, phase 5).
///
/// The caller builds the buttons (keys, callbacks, busy states and copy stay
/// with the screen that owns them); this widget owns only the arrangement.
/// Below [stackBelowWidth] or at ≈150 % text the primary and secondary stack
/// full-width, the icon rides beside the last one, and nothing truncates.
class ProfileActionBar extends StatelessWidget {
  const ProfileActionBar({
    required this.primary,
    this.secondary,
    this.icon,
    super.key,
  });

  final Widget primary;
  final Widget? secondary;
  final Widget? icon;

  /// The shared minimum height of every profile CTA (a 44 px target).
  static const double buttonHeight = 44;

  /// Radius shared by the CTAs: the Slim card / input radius.
  static const double radius = 12;

  /// Below this width two labelled CTAs and the icon no longer fit on one
  /// line without truncating Polish labels, so they stack.
  static const double stackBelowWidth = 340;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaledBodySize = MediaQuery.textScalerOf(context).scale(14);
        final shouldStack =
            constraints.maxWidth < stackBelowWidth || scaledBodySize >= 21;
        final secondary = this.secondary;
        final icon = this.icon;
        Widget lastLine(Widget button) {
          if (icon == null) return button;
          return Row(
            children: [
              Expanded(child: button),
              const SizedBox(width: 8),
              icon,
            ],
          );
        }

        if (secondary == null) return lastLine(primary);
        if (shouldStack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [primary, const SizedBox(height: 8), lastLine(secondary)],
          );
        }
        return Row(
          children: [
            Expanded(child: primary),
            const SizedBox(width: 8),
            Expanded(child: secondary),
            if (icon != null) ...[const SizedBox(width: 8), icon],
          ],
        );
      },
    );
  }
}

/// The icon action of a [ProfileActionBar]: a 44 px outlined square.
class ProfileActionIconButton extends StatelessWidget {
  const ProfileActionIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      constraints: const BoxConstraints(
        minWidth: ProfileActionBar.buttonHeight,
        minHeight: ProfileActionBar.buttonHeight,
      ),
      style: IconButton.styleFrom(
        foregroundColor: palette.textPrimary,
        side: BorderSide(color: palette.borderStrong),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ProfileActionBar.radius),
        ),
      ),
      icon: Icon(icon, size: 22),
    );
  }
}

/// The canonical public Premium mark — rendered only from
/// `profile.premiumIdentity`, the server-written public mirror of the
/// entitlement. The check means Premium membership; Creator eligibility and
/// age verification are separate state and deliberately absent from its copy.
class PremiumIdentityBadge extends StatelessWidget {
  const PremiumIdentityBadge({this.compact = false, super.key});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final label = copy.text(
      'YO Voice Premium member',
      'Użytkownik YO Voice Premium',
    );
    final size = compact ? 24.0 : 28.0;
    return Semantics(
      container: true,
      image: true,
      label: label,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: ExcludeSemantics(
          child: Container(
            key: const ValueKey('premium-identity-badge'),
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primary, AppColors.secondary],
              ),
              border: Border.all(color: AppColors.white.withValues(alpha: .28)),
              boxShadow: [
                BoxShadow(
                  color: AppColors.secondary.withValues(alpha: .24),
                  blurRadius: compact ? 8 : 10,
                  spreadRadius: .5,
                ),
              ],
            ),
            child: Icon(
              // A plain check inside YO Voice's violet circle. The rosette
              // style `verified` glyph is reserved for Official identity so
              // Premium membership cannot be mistaken for age/identity
              // verification.
              Icons.check_rounded,
              size: compact ? 15 : 18,
              color: AppColors.white,
            ),
          ),
        ),
      ),
    );
  }
}

/// Source-compatible alias for older call sites. New surfaces should use
/// [PremiumIdentityBadge], which reflects the mark's circular presentation.
@Deprecated('Use PremiumIdentityBadge')
class PremiumIdentityChip extends PremiumIdentityBadge {
  const PremiumIdentityChip({super.compact, super.key});
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
            // Account-type labels still shrink, never
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
