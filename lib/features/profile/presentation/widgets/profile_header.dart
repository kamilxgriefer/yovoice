import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/achievements/data/models/achievement_definition.dart';
import 'package:yovoice/features/achievements/presentation/widgets/title_badge.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/identity/official_role_badge.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/profile/profile_hero_backdrop.dart';
import 'package:yovoice/shared/widgets/profile/profile_photo_viewer.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';
import 'package:yovoice/shared/widgets/profile/availability_picker.dart';

/// The profile hero: the user's banner is the full-bleed background of the
/// whole header — edge to edge, under the status bar — with the toolbar
/// (Back when the route can pop, Edit) floating over it on a scrim, and the
/// identity block (avatar + name + username + badges) standing in the
/// photo's blurred bottom melt. See [ProfileHeroLayout] and
/// [ProfileHeroBackdrop] for the geometry and the layers; the decision is
/// recorded in docs/Decisions.md ("The profile banner is the header's
/// full-bleed background").
///
/// History: a fixed 300–320px banner Stack (mostly empty gradient on
/// desktop) became, in the Slim redesign, a 104/132px inset rounded card
/// below a separate toolbar row. That read as "a rectangle"; the photo now
/// owns the whole top panel while the header still sizes itself to its
/// content instead of claiming a fixed viewport share.
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
  /// (profile_screen's measured SliverPadding), so the identity, stats and
  /// actions line up with the rest of the page. The photo alone ignores it.
  static const double gutter = 18;

  /// Fraction of the stored banner's height that is still on screen at the
  /// WIDEST presentation, i.e. the part a user can rely on at every width.
  ///
  /// The hero draws the 16:9 source with `BoxFit.cover` and
  /// `Alignment.center`. Phones show all of it (the hero is never narrower
  /// than 16:9); wider heroes crop top and bottom, down to ~29% from 1440pt
  /// up. Derived in [ProfileHeroGeometry] from the stored ratio, the wide
  /// reference width and its height, so a redesign that changes any of them
  /// moves the crop editor's guide with it.
  static final double bannerSafeBandFraction =
      ProfileHeroGeometry.alwaysVisibleFraction;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    // Breakpoints come from the content column the host actually hands the
    // header — available width, never device labels. The photo runs across
    // the whole host; everything readable stays on the 1040pt feed measure.
    return ProfileHeroLayout(
      contentMaxWidth: ResponsiveContentWidth.feed.maxWidth,
      backdrop: (context, frame) => ProfileBannerButton(
        userId: profile.uid,
        displayName: profile.displayName,
        mediaRevision: profile.profileUpdatedAt,
        mediaService: mediaService,
        // A full-bleed band: square focus ring, two-tone because the photo's
        // luminance is unknown.
        borderRadius: 0,
        focusContrastColor: palette.scrim,
        child: ProfileHeroBackdrop(
          geometry: frame.geometry,
          userId: profile.uid,
          mediaRevision: profile.profileUpdatedAt,
          mediaService: mediaService,
        ),
      ),
      toolbar: (context, frame) => Padding(
        // Back sits 6px inside the content column, as it always has; Edit
        // keeps the 18px gutter.
        padding: frame.inset(start: 6, end: gutter),
        child: _toolbar(context),
      ),
      identity: (context, frame) {
        final (avatarRadius, ringPadding) = switch (frame.columnWidth) {
          < 360 => (33.0, 3.0),
          < 600 => (37.0, 3.0),
          < 900 => (41.0, 3.0),
          _ => (44.0, 4.0),
        };
        return Padding(
          padding: frame.inset(start: gutter, end: gutter),
          child: _identityBlock(
            context,
            avatarRadius: avatarRadius,
            ringPadding: ringPadding,
            isWide: frame.columnWidth >= 900,
          ),
        );
      },
      footer: (context, frame) => Padding(
        padding: frame.inset(start: gutter, end: gutter),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (stats != null || actions != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
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
  }

  Widget _toolbar(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final canPop = Navigator.of(context).canPop();
    return Row(
      children: [
        // A physical Back control whenever there IS somewhere to go back
        // to. Profile is pushed as a route from the avatar, the profile card
        // and More, and previously offered no way out but a system gesture —
        // which desktop web does not have. Its raised fill keeps it legible
        // on any photo.
        if (canPop)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_rounded),
              color: palette.textPrimary,
              tooltip: copy.text('Back', 'Wstecz'),
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              style: IconButton.styleFrom(
                backgroundColor: palette.surfaceRaised.withValues(alpha: .92),
              ),
            ),
          )
        else
          // Keeps the toolbar's start on the 18px content gutter when there
          // is no Back button (6 + 12 = 18).
          const SizedBox(width: 12),
        // No visible title over the photo: an ink title cannot be guaranteed
        // legible over an arbitrary image, and the display name below is the
        // page's one headline. Screen readers still hear the page named.
        Expanded(
          child: Semantics(
            container: true,
            namesRoute: true,
            label: copy.profile,
            child: const SizedBox(height: 44),
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
          // Top-anchored on the hero's text line: a two-line name or 200%
          // text grows downward, never back up over the photo.
          crossAxisAlignment: CrossAxisAlignment.start,
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
                // separates the avatar from the photo's melt. The ring stays
                // free of decorative gradients (it is not a Moment ring).
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
                // The name block starts on the hero's text line, where the
                // photo has melted to at most 10% under the page canvas, so
                // it needs no plate of its own (the former raised plate was
                // a card-in-card whose only job was legibility over the old
                // band). It still rides over the banner's tap target: opaque
                // keeps a tap between its words from opening the banner
                // viewer, while the availability chip inside still wins
                // first.
                child: MetaData(
                  behavior: HitTestBehavior.opaque,
                  child: ConstrainedBox(
                    key: const Key('profile-header-name-plate'),
                    constraints: const BoxConstraints(maxWidth: 420),
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
                        // name block keeps its height budget
                        // (profile_header_compact_test).
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

/// How loudly a [ProfileQuickAction] speaks: the screen's one violet accent,
/// or a neutral hairline tile.
enum ProfileQuickActionEmphasis { primary, neutral }

/// One slot of [ProfileQuickActions]. The caller owns the key, the callback,
/// the busy state and every string (ADR-209: the primitive only draws).
class ProfileQuickAction {
  const ProfileQuickAction({
    required this.key,
    required this.icon,
    required this.label,
    required this.semanticLabel,
    required this.onPressed,
    this.emphasis = ProfileQuickActionEmphasis.neutral,
    this.busy = false,
    this.busyLabel,
    this.disabledHint,
    this.iconOnlyWhenWide = false,
  });

  final Key key;
  final IconData icon;
  final String label;

  /// The spoken name, which carries the person's name ("Call Ola").
  final String semanticLabel;

  /// Null renders the slot disabled.
  final VoidCallback? onPressed;
  final ProfileQuickActionEmphasis emphasis;

  /// Swaps the icon for a spinner and the label for [busyLabel], announced
  /// as a live region.
  final bool busy;
  final String? busyLabel;

  /// Why a disabled slot is disabled, exposed as the semantic hint.
  final String? disabledHint;

  /// The trailing "More" slot: a 44 px square icon button on wide layouts.
  final bool iconOnlyWhenWide;
}

/// The friend profile's quick actions row (call, video, message, more).
///
/// Layout comes from the available width and the text scale, never a device
/// label:
/// * scaled body >= 21 (about 150 % text and up): one full-width row per
///   action, labels wrap, nothing truncates;
/// * width >= [wideFromWidth]: a start-aligned toolbar of 44 px icon + label
///   buttons that hug their labels (tablet and desktop — not four phone tiles
///   stretched across 840 px);
/// * width < [gridBelowWidth]: the compact tiles in a 2 x 2 grid;
/// * otherwise: one row of equal 64 px tiles.
class ProfileQuickActions extends StatelessWidget {
  const ProfileQuickActions({required this.actions, super.key});

  final List<ProfileQuickAction> actions;

  static const double wideFromWidth = 560;
  static const double gridBelowWidth = 300;
  static const double tileHeight = 64;
  static const double listRowHeight = 52;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaledBody = MediaQuery.textScalerOf(context).scale(14);
        if (scaledBody >= 21) return _list(context);
        if (constraints.maxWidth >= wideFromWidth) return _wide(context);
        if (constraints.maxWidth < gridBelowWidth) return _grid(context);
        // Equal-height tiles even when one label is busy or scaled down.
        return IntrinsicHeight(child: _tileRow(context, actions));
      },
    );
  }

  ButtonStyle _style(
    BuildContext context,
    ProfileQuickAction action, {
    required Size minimumSize,
    required EdgeInsetsGeometry padding,
    AlignmentGeometry? alignment,
  }) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final primary = action.emphasis == ProfileQuickActionEmphasis.primary;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(ProfileActionBar.radius),
    );
    // A busy slot is disabled but keeps its own colours, so the spinner
    // reads as progress rather than as "unavailable".
    final busy = action.busy;
    final background = primary ? colors.primary : palette.surface;
    final foreground = primary ? colors.onPrimary : palette.textPrimary;
    return ButtonStyle(
      minimumSize: WidgetStatePropertyAll(minimumSize),
      padding: WidgetStatePropertyAll(padding),
      alignment: alignment,
      shape: WidgetStatePropertyAll(shape),
      elevation: const WidgetStatePropertyAll(0),
      tapTargetSize: MaterialTapTargetSize.padded,
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled) && !busy
            ? palette.surfaceMuted
            : background,
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled) && !busy
            ? palette.textTertiary
            : foreground,
      ),
      overlayColor: WidgetStatePropertyAll(foreground.withValues(alpha: .08)),
      side: WidgetStateProperty.resolveWith(
        (states) => primary || (states.contains(WidgetState.disabled) && !busy)
            ? BorderSide.none
            : BorderSide(color: palette.border),
      ),
    );
  }

  Widget _spinner(double size) => SizedBox(
    width: size,
    height: size,
    child: const CircularProgressIndicator(strokeWidth: 2),
  );

  Widget _button(
    BuildContext context,
    ProfileQuickAction action, {
    required ButtonStyle style,
    required Widget child,
    bool tooltip = false,
  }) {
    final label = action.busy
        ? (action.busyLabel ?? action.semanticLabel)
        : action.semanticLabel;
    final hint = action.onPressed == null && !action.busy
        ? action.disabledHint
        : null;
    Widget button = TextButton(
      key: action.key,
      onPressed: action.onPressed,
      style: style,
      child: Semantics(
        label: label,
        hint: hint,
        liveRegion: action.busy,
        child: ExcludeSemantics(child: child),
      ),
    );
    if (tooltip) {
      button = Tooltip(
        message: action.semanticLabel,
        excludeFromSemantics: true,
        child: button,
      );
    }
    return button;
  }

  Widget _tile(BuildContext context, ProfileQuickAction action) {
    final text = action.busy
        ? (action.busyLabel ?? action.label)
        : action.label;
    return _button(
      context,
      action,
      style: _style(
        context,
        action,
        minimumSize: const Size(0, tileHeight),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 22,
            child: Center(
              child: action.busy ? _spinner(18) : Icon(action.icon, size: 22),
            ),
          ),
          const SizedBox(height: 4),
          // Fits the tile at 100 % text the same way ProfileStatsRow fits
          // its labels; larger text switches to the list layout instead.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              text,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 12,
                height: 16 / 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tileRow(BuildContext context, List<ProfileQuickAction> slots) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < slots.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: _tile(context, slots[i])),
        ],
      ],
    );
  }

  Widget _grid(BuildContext context) {
    final rows = <List<ProfileQuickAction>>[
      for (var i = 0; i < actions.length; i += 2)
        actions.sublist(i, i + 2 > actions.length ? actions.length : i + 2),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          IntrinsicHeight(child: _tileRow(context, rows[i])),
        ],
      ],
    );
  }

  Widget _list(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _button(
            context,
            actions[i],
            style: _style(
              context,
              actions[i],
              minimumSize: const Size(0, listRowHeight),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              alignment: AlignmentDirectional.centerStart,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: Center(
                    child: actions[i].busy
                        ? _spinner(18)
                        : Icon(actions[i].icon, size: 22),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    actions[i].busy
                        ? (actions[i].busyLabel ?? actions[i].label)
                        : actions[i].label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _wide(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final action in actions)
            if (action.iconOnlyWhenWide)
              ProfileActionIconButton(
                key: action.key,
                icon: action.icon,
                tooltip: action.semanticLabel,
                onPressed: action.onPressed,
              )
            else
              _button(
                context,
                action,
                tooltip: true,
                style: _style(
                  context,
                  action,
                  minimumSize: const Size(0, ProfileActionBar.buttonHeight),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: action.busy
                          ? _spinner(18)
                          : Icon(action.icon, size: 18),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      action.busy
                          ? (action.busyLabel ?? action.label)
                          : action.label,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
        ],
      ),
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
