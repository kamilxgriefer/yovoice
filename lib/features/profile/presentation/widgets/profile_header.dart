import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_finish.dart';
import 'package:yovoice/core/theme/app_gradients.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/achievements/data/models/achievement_definition.dart';
import 'package:yovoice/features/achievements/presentation/widgets/title_badge.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/features/profile/presentation/widgets/profile_layout.dart';
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
/// identity block (avatar + name + username + badges) standing on the photo,
/// which continues behind it as a blurred copy under a veil that keeps the
/// text legible. See [ProfileHeroLayout] and
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

  /// The upper part of [bannerSafeBandFraction] that stays above the hero's
  /// bottom melt at every width — where faces and text belong. Below it the
  /// band is still on screen but fades into the page on wide layouts.
  static final double bannerClearBandFraction =
      ProfileHeroGeometry.alwaysClearFraction;

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
        // luminance is unknown, drawn on the visible photo only — below the
        // status bar, above the text line, on the content column.
        borderRadius: 0,
        focusContrastColor: palette.scrim,
        focusRingInsets: frame.bannerFocusInsets,
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
            nameOffset: frame.geometry.nameOffset,
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
                  // readable measure instead of stretching to 1040 px; the
                  // body sections below join the same measure.
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: ProfileLayout.wideMeasure,
                    ),
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
    double nameOffset = 0,
  }) {
    final palette = context.appPalette;
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
                // Slim: a flat canvas-coloured cut-out separates the avatar
                // from the photo it stands on. Its 1 px hairline is
                // `borderStrong`, ≥ 3:1 against that cut-out in both
                // themes, so the ring reads over a white, a black or no
                // photo alike. It stays free of decorative gradients (it is
                // not a Moment ring).
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: palette.background,
                  border: Border.all(color: palette.borderStrong),
                ),
                // Refine-look R10: the one letter-avatar gradient, a calm
                // w700 initial and a hairline ring on a photo. The cut-out
                // ring above stays the only ring (no decorative one).
                child: UserAvatar(
                  radius: avatarRadius,
                  userId: profile.uid,
                  photoUrl: profile.photoUrl,
                  mediaRevision: profile.profileUpdatedAt,
                  mediaService: mediaService,
                  displayName: profile.displayName,
                  premium: profile.premiumIdentity,
                  finish: UserAvatarFinish.brand,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                // The avatar rises into the photo; the text starts lower, on
                // the hero's name line, where the veil keeps it legible.
                padding: EdgeInsets.only(top: nameOffset),
                alignment: Alignment.centerLeft,
                // The name block starts on the hero's name line, on the
                // photo, where the veil has already taken it down to at most
                // 45% (15% from the handle down) over the page canvas, so it
                // needs no plate of its own (the former raised plate was a
                // card-in-card whose only job was legibility over the old
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
                              fontWeight: FontWeight.w700,
                              letterSpacing: isWide ? -.6 : -.45,
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
/// profile (Slim redesign, phase 5; refine-look §10 handoff): one band with
/// the R2 block finish — the top-lit fill, a `hairline` edge, radius 20 and
/// Pearl's soft lift (flat `surface` + `borderStrong` under high contrast) —
/// the same finish as the profile sections below it, so 12 and 20 never sit
/// together. Values are 17 w700 in tabular figures over 12 w600 labels that
/// are never scaled down. Counters sit side by side, each as wide as its own
/// words plus [cellPadding] of air on either side (at least [minCellWidth]),
/// spaced evenly across the band, so a long label ("Obserwowani") never
/// crowds its neighbour. When they no longer fit on one line, four or more
/// counters fold into two per line; if even that does not fit, or body text
/// reaches 21 px (≈150 % text), the band stacks one counter per line. Labels
/// are never squeezed or truncated and every tappable counter keeps a 44 px
/// target.
class ProfileStatsRow extends StatelessWidget {
  const ProfileStatsRow({required this.stats, this.containerKey, super.key});

  final List<ProfileStat> stats;

  /// Rides the decorated band itself, so a finder can read its decoration.
  final Key? containerKey;

  /// The narrowest counter cell (its tap target included).
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

  /// A counter's label: 12 w600, never scaled down to fit (its tracking is
  /// pinned so the theme's body tracking never widens it).
  static TextStyle labelStyle(AppPalette palette) => TextStyle(
    color: palette.textSecondary,
    fontSize: 12,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
  );

  /// The air each counter keeps on either side of its words.
  static const double cellPadding = 8;

  /// A counter's value: 17 w700 in tabular figures, so "148" and "111"
  /// share a width.
  static TextStyle valueStyle(AppPalette palette) => TextStyle(
    color: palette.textPrimary,
    fontSize: 17,
    height: 1.2,
    fontWeight: FontWeight.w700,
    letterSpacing: -.2,
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
  );

  /// Each counter's natural width at the reader's text size: its wider line
  /// (value or label) plus [cellPadding] on either side, at least
  /// [minCellWidth].
  static List<double> _naturalWidths(
    BuildContext context,
    AppPalette palette,
    List<ProfileStat> stats,
  ) {
    final base = DefaultTextStyle.of(context).style;
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    double measure(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: base.merge(style)),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    return [
      for (final stat in stats)
        math.max(
          minCellWidth,
          math.max(
                measure(stat.label, labelStyle(palette)),
                measure(compact(stat.value), valueStyle(palette)),
              ) +
              cellPadding * 2,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final palette = context.appPalette;
        final highContrast = MediaQuery.highContrastOf(context);
        final largeText =
            MediaQuery.textScalerOf(context).scale(14) >=
            ProfileLayout.largeTextBody;
        final decoration = AppFinish.block(palette, highContrast: highContrast);
        // The band's 1 px edge insets its content (a decoration's border is
        // layout padding), so the counters get the band's width minus that
        // edge. Measuring against the outer width let a total within 2 px
        // of the band pick one line and overflow, and a widest counter
        // within 1 px of half the band pick two per line and ellipsize.
        final inner = math.max(
          0.0,
          constraints.maxWidth - decoration.padding.horizontal,
        );
        final widths = _naturalWidths(context, palette, stats);
        final widest = widths.fold<double>(0, math.max);
        final total = widths.fold<double>(0, (sum, width) => sum + width);
        // Counters per line: all of them while their natural widths fit the
        // band, two for four or more counters once they no longer do, and
        // one at large text or when even half the band is too narrow.
        final count = stats.length.clamp(1, 99);
        final int perLine;
        if (largeText) {
          perLine = 1;
        } else if (total <= inner) {
          perLine = count;
        } else if (count >= 4 && widest <= inner / 2) {
          perLine = 2;
        } else {
          perLine = 1;
        }
        final divider = Divider(
          height: 1,
          indent: 16,
          endIndent: 16,
          color: highContrast ? palette.borderStrong : palette.hairline,
        );
        final cells = [for (final stat in stats) _ProfileStatCell(stat: stat)];
        final Widget body;
        if (perLine == 1) {
          body = Column(
            children: [
              for (var index = 0; index < cells.length; index++) ...[
                cells[index],
                if (index < cells.length - 1) divider,
              ],
            ],
          );
        } else if (perLine == count) {
          body = Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (var index = 0; index < cells.length; index++)
                SizedBox(width: widths[index], child: cells[index]),
            ],
          );
        } else {
          final lines = [
            for (var start = 0; start < cells.length; start += perLine)
              cells.sublist(start, (start + perLine).clamp(0, cells.length)),
          ];
          body = Column(
            children: [
              for (var index = 0; index < lines.length; index++) ...[
                Row(
                  children: [
                    for (final cell in lines[index]) Expanded(child: cell),
                    // A short last line keeps its cells the same width.
                    for (var i = lines[index].length; i < perLine; i++)
                      const Expanded(child: SizedBox.shrink()),
                  ],
                ),
                if (index < lines.length - 1) divider,
              ],
            ],
          );
        }
        return Container(
          key: containerKey,
          padding: EdgeInsets.symmetric(vertical: perLine == count ? 6 : 4),
          decoration: decoration,
          child: body,
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
            padding: const EdgeInsets.symmetric(
              horizontal: ProfileStatsRow.cellPadding,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  ProfileStatsRow.compact(stat.value),
                  maxLines: 1,
                  style: ProfileStatsRow.valueStyle(palette),
                ),
                // Every label is the same 12 w600: a label that would not
                // fit its cell stacks the row (ProfileStatsRow) instead of
                // shrinking this one word.
                Text(
                  stat.label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: ProfileStatsRow.labelStyle(palette),
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
      // Concentric with the band's 20 px block radius, inset by its 6 px.
      borderRadius: 14,
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

  /// The CTAs' shape: [radius] 12 on every profile action.
  static const OutlinedBorder shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(radius)),
  );

  /// The R7 neutral tonal finish of every secondary profile action (glass
  /// fill, control hairline, `textPrimary` ink, `borderStrong` under high
  /// contrast), for `OutlinedButton`, `FilledButton`, `TextButton` or
  /// `IconButton` alike: callers keep their widget types and keys.
  static ButtonStyle neutralStyle(BuildContext context) =>
      AppFinish.tonalNeutral(
        context.appPalette,
        foreground: context.appPalette.textPrimary,
        shape: shape,
        highContrast: MediaQuery.highContrastOf(context),
      );

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

/// The icon action of a [ProfileActionBar]: a 44 px square in the R7
/// neutral tonal finish — glass fill, control hairline, `textPrimary` glyph —
/// the same finish as the secondary action beside it.
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
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      constraints: const BoxConstraints(
        minWidth: ProfileActionBar.buttonHeight,
        minHeight: ProfileActionBar.buttonHeight,
      ),
      style: ProfileActionBar.neutralStyle(context),
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
        if (constraints.maxWidth < gridBelowWidth) {
          return _grid(context, constraints.maxWidth);
        }
        // Equal-height tiles even when one label is busy.
        return IntrinsicHeight(
          child: _tileRow(
            context,
            actions,
            labelSize: _tileLabelSize(context, actions, constraints.maxWidth),
          ),
        );
      },
    );
  }

  /// The tile label's natural size.
  static const double tileLabelSize = 12;

  /// The smallest shared tile label size before a label is left to its own
  /// [FittedBox] guard (only on a row far narrower than any phone).
  static const double minTileLabelSize = 10;

  static const double _tileGap = 8;
  static const double _tilePadding = 8;

  static TextStyle _tileLabelStyle(double size) =>
      TextStyle(fontSize: size, height: 16 / 12, fontWeight: FontWeight.w600);

  /// One label size for every tile in a row of [rowWidth]: the natural 12 px
  /// when every label (and every busy label) fits its tile, otherwise the
  /// size at which the widest one does. A single long word ("Wiadomość")
  /// no longer shrinks alone beside three full-size labels.
  static double _tileLabelSize(
    BuildContext context,
    List<ProfileQuickAction> slots,
    double rowWidth, {
    int? perRow,
  }) {
    if (slots.isEmpty || !rowWidth.isFinite) return tileLabelSize;
    final tiles = perRow ?? slots.length;
    final tileWidth = (rowWidth - _tileGap * (tiles - 1)) / tiles;
    final room = tileWidth - _tilePadding * 2;
    final base = Theme.of(
      context,
    ).textTheme.labelLarge?.merge(_tileLabelStyle(tileLabelSize));
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    var widest = 0.0;
    for (final slot in slots) {
      for (final text in [slot.label, ?slot.busyLabel]) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: base),
          textDirection: direction,
          textScaler: scaler,
          maxLines: 1,
        )..layout();
        widest = math.max(widest, painter.width);
        painter.dispose();
      }
    }
    if (widest <= room || room <= 0) return tileLabelSize;
    // Rounded down to a quarter pixel so the widest label fits with room.
    final fitted = (tileLabelSize * room / widest * 4).floorToDouble() / 4;
    return fitted.clamp(minTileLabelSize, tileLabelSize);
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
    // A busy slot is disabled but keeps its own colours, so the spinner
    // reads as progress rather than as "unavailable".
    final busy = action.busy;
    Set<WidgetState> shown(Set<WidgetState> states) =>
        busy ? (states.toSet()..remove(WidgetState.disabled)) : states;
    final geometry = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(minimumSize),
      padding: WidgetStatePropertyAll(padding),
      alignment: alignment,
      shape: const WidgetStatePropertyAll(ProfileActionBar.shape),
      elevation: const WidgetStatePropertyAll(0),
      // The primary's painted shape IS its target (never under 44 px), so
      // the lift outside it hugs the gradient exactly.
      tapTargetSize: primary
          ? MaterialTapTargetSize.shrinkWrap
          : MaterialTapTargetSize.padded,
    );
    if (!primary) {
      // R7 neutral: glass fill, control hairline, `textPrimary` ink.
      final tonal = ProfileActionBar.neutralStyle(context);
      WidgetStateProperty<T?> keep<T>(WidgetStateProperty<T?>? property) =>
          WidgetStateProperty.resolveWith(
            (states) => property?.resolve(shown(states)),
          );
      return tonal
          .copyWith(
            backgroundColor: keep(tonal.backgroundColor),
            foregroundColor: keep(tonal.foregroundColor),
            iconColor: keep(tonal.iconColor),
            side: keep(tonal.side),
            // The same label base as the primary slot (the theme's
            // labelLarge); each layout sets its own size and weight.
            textStyle: WidgetStatePropertyAll(
              Theme.of(context).textTheme.labelLarge,
            ),
          )
          .merge(geometry);
    }
    // R5: the screen's one CTA paints `primaryAction` (the theme's primary
    // into its AA-safe secondary) over its primary base colour; the lift is
    // added around the button by [_button]. A disabled slot is a flat
    // sunken fill.
    final gradient = AppGradients.primaryAction(colors);
    bool flat(Set<WidgetState> states) =>
        shown(states).contains(WidgetState.disabled);
    return ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => flat(states) ? palette.surfaceMuted : colors.primary,
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => flat(states) ? palette.textTertiary : colors.onPrimary,
      ),
      iconColor: WidgetStateProperty.resolveWith(
        (states) => flat(states) ? palette.textTertiary : colors.onPrimary,
      ),
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return AppColors.white.withValues(alpha: .10);
        }
        if (states.contains(WidgetState.hovered)) {
          return AppColors.white.withValues(alpha: .06);
        }
        return null;
      }),
      side: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.focused)
            ? BorderSide(color: colors.onPrimary, width: 2)
            : BorderSide.none,
      ),
      backgroundBuilder: (context, states, child) => flat(states)
          ? child ?? const SizedBox.shrink()
          : Ink(
              decoration: BoxDecoration(gradient: gradient),
              child: child,
            ),
    ).merge(geometry);
  }

  /// A white (or tertiary, when disabled) spinner in the slot's own ink.
  Widget _spinner(double size) => SizedBox(
    width: size,
    height: size,
    child: Builder(
      builder: (context) => CircularProgressIndicator(
        strokeWidth: 2,
        color: IconTheme.of(context).color,
        backgroundColor: Colors.transparent,
      ),
    ),
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
      // Keeps the primary's gradient inside the rounded shape.
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        label: label,
        hint: hint,
        liveRegion: action.busy,
        child: ExcludeSemantics(child: child),
      ),
    );
    final primary = action.emphasis == ProfileQuickActionEmphasis.primary;
    if (primary) {
      // The gradient is ink laid above the button's shape border, so the
      // style's 2 px `onPrimary` focus side never shows: draw it on top.
      button = ProfileFocusRing(
        color: Theme.of(context).colorScheme.onPrimary,
        borderRadius: const BorderRadius.all(
          Radius.circular(ProfileActionBar.radius),
        ),
        child: button,
      );
    }
    final lifted =
        primary &&
        (action.onPressed != null || action.busy) &&
        !MediaQuery.highContrastOf(context);
    if (lifted) {
      // The screen's one CTA lift (R5, the rail's values; half while busy),
      // on an outer box so the button's clip never cuts it.
      button = DecoratedBox(
        decoration: ShapeDecoration(
          shape: ProfileActionBar.shape,
          shadows: AppFinish.actionLift(
            AppColors.primary,
            strength: action.busy ? .5 : 1,
          ),
        ),
        child: button,
      );
    }
    if (tooltip) {
      button = Tooltip(
        message: action.semanticLabel,
        excludeFromSemantics: true,
        child: button,
      );
    }
    return button;
  }

  Widget _tile(
    BuildContext context,
    ProfileQuickAction action, {
    double labelSize = tileLabelSize,
  }) {
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
        padding: const EdgeInsets.symmetric(
          horizontal: _tilePadding,
          vertical: 10,
        ),
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
          // Every tile of the row shares [labelSize] (see _tileLabelSize);
          // larger text switches to the list layout instead. The FittedBox
          // is only a guard for a row narrower than any phone.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(text, maxLines: 1, style: _tileLabelStyle(labelSize)),
          ),
        ],
      ),
    );
  }

  Widget _tileRow(
    BuildContext context,
    List<ProfileQuickAction> slots, {
    required double labelSize,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < slots.length; i++) ...[
          if (i > 0) const SizedBox(width: _tileGap),
          Expanded(child: _tile(context, slots[i], labelSize: labelSize)),
        ],
      ],
    );
  }

  Widget _grid(BuildContext context, double width) {
    final rows = <List<ProfileQuickAction>>[
      for (var i = 0; i < actions.length; i += 2)
        actions.sublist(i, i + 2 > actions.length ? actions.length : i + 2),
    ];
    // One size across the whole grid, measured on its two-tile rows.
    final labelSize = _tileLabelSize(context, actions, width, perRow: 2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          IntrinsicHeight(
            child: _tileRow(context, rows[i], labelSize: labelSize),
          ),
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
            // The logo's own gradient with a white rim. No glow: on Profile
            // emitted light belongs to the pinned Moment while it plays
            // (the refine-look light budget).
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppGradients.primary,
              border: Border.all(color: AppColors.white.withValues(alpha: .28)),
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
///
/// Refine-look §10 proposes one 24 px glass pill family for this badge and
/// the role pill. The role pill (`IdentityBadgePill`, which the desktop rail
/// also renders) and `TitleBadge` cannot move in this batch, so this badge
/// keeps the tinted, bold, compact finish it shares with them until the
/// whole family moves together — a lone glass pill made the header's badge
/// rail mix three styles.
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
