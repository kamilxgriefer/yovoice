import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_finish.dart';
import 'package:yovoice/core/theme/app_icons.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/shared/widgets/badges/yo_count_badge.dart';
import 'package:yovoice/shared/widgets/branding/yo_logo.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';
import 'package:yovoice/shared/widgets/profile/availability_dot.dart';
import 'package:yovoice/shared/widgets/profile/people_status_ring.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// Home's greeting: who you are, what is waiting, and the way to your
/// profile.
///
/// The name is the first whitespace token of the account's own display name —
/// never the email local part, which the retired Home used as a fallback and
/// which is personal data the account did not choose to show itself as. With
/// no name at all the greeting is simply "Cześć!"; a screen that invents a
/// name is worse than one that does not use it.
class HomeGreetingHeader extends StatelessWidget {
  const HomeGreetingHeader({
    required this.profile,
    required this.onOpenNotifications,
    required this.onOpenProfile,
    this.unreadNotificationCount = 0,
    this.expanded = false,
    bool? showBrand,
    super.key,
  }) : showBrand = showBrand ?? !expanded;

  /// The shared `watchCurrentProfile()` stream the parent already holds.
  final Stream<UserProfile>? profile;
  final VoidCallback onOpenNotifications;
  final VoidCallback onOpenProfile;
  final int unreadNotificationCount;

  /// Desktop ramp (`greetingWide`, 30 px) rather than the phone's
  /// `screenTitle` (22 px).
  final bool expanded;

  /// The YO Voice lockup (mark + wordmark) above the greeting. Start on a
  /// phone or tablet has no app bar and no rail, so this line is where the
  /// brand stays visible (Slim brief, 2026-09-19). The desktop rail already
  /// carries the mark at its top, so the expanded header leaves it out by
  /// default rather than printing the brand twice on one screen.
  final bool showBrand;

  /// The bare brand mark's box on a phone (refine-look W1): 32 px, about
  /// 26 px of ink, no tile.
  static const double brandMarkSize = 32;

  /// The mark's box from 600 px up to the desktop shell (which leaves the
  /// brand to its rail).
  static const double brandMarkSizeMedium = 36;

  /// The control row's height: the 46 px discs are its tallest members, so
  /// the header is exactly as tall before the profile arrives as after.
  static const double controlHeight = 46;

  /// The greeting's visible name: the first whitespace token of the display
  /// name, trimmed. Empty when the profile has no usable name.
  static String firstName(UserProfile? profile) {
    final full = profile?.displayName.trim() ?? '';
    if (full.isEmpty) return '';
    final token = full.split(RegExp(r'\s+')).first.trim();
    return token;
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    return StreamBuilder<UserProfile>(
      stream: profile,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final scaler = MediaQuery.textScalerOf(context);
        final enlargedText = scaler.scale(1) >= 1.6;
        final name = firstName(data);
        final greeting = name.isEmpty
            ? copy.homeGreetingNoName
            : copy.homeGreeting(name);

        final heading = LayoutBuilder(
          builder: (context, constraints) => Text.rich(
            TextSpan(
              children: [
                TextSpan(text: greeting),
                // Decorative: the wave is not part of what a reader needs
                // to hear, and it must not break the name out of its line.
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: ExcludeSemantics(
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(start: 6),
                      child: Text(
                        '👋',
                        style: TextStyle(
                          fontSize: expanded ? 26 : 19,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            semanticsLabel: greeting,
            maxLines: 2,
            // The refine-look title roles (w700, tight tracking): 22 px on
            // a phone. The words share their row with two 46 px controls, so
            // the column is ~250 px on a 390 px phone; only a column under
            // 240 px (a 320 px phone) steps down to 20 px so a long Polish
            // name still keeps to two lines.
            style: expanded
                ? AppTypography.greetingWide.copyWith(
                    color: palette.textPrimary,
                  )
                : AppTypography.screenTitle.copyWith(
                    color: palette.textPrimary,
                    fontSize: constraints.maxWidth < 240 ? 20 : null,
                  ),
          ),
        );

        final subtitle = Text(
          copy.homeGreetingSubtitle,
          maxLines: 2,
          style: AppTypography.bodyMedium.copyWith(
            color: palette.textSecondary,
          ),
        );

        final bell = HomeHeaderDisc(
          icon: AppIcons.notifications,
          onTap: onOpenNotifications,
          tooltip: unreadNotificationCount > 0
              ? copy.template(
                  'Notifications, {count} unread',
                  'Powiadomienia: {count} nieprzeczytanych',
                  values: <String, Object>{'count': '$unreadNotificationCount'},
                )
              : copy.notifications,
          badgeCount: unreadNotificationCount,
        );

        final avatar = AccessibleTapRegion(
          onTap: onOpenProfile,
          semanticLabel: copy.text('Open your profile', 'Otwórz swój profil'),
          tooltip: copy.profile,
          circular: true,
          child: ExcludeSemantics(
            child: SizedBox(
              width: controlHeight,
              height: controlHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // A hairline ring (refine-look §8.1), not an outline: the
                  // same brand-finished avatar the friends row shows for "Ty".
                  Container(
                    width: controlHeight,
                    height: controlHeight,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: palette.hairline),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(1),
                      child: UserAvatar(
                        radius: 21,
                        userId: data?.uid,
                        photoUrl: data?.photoUrl,
                        mediaRevision: data?.profileUpdatedAt,
                        displayName: data?.displayName,
                        fallbackIcon: Icons.person_rounded,
                        finish: UserAvatarFinish.brand,
                      ),
                    ),
                  ),
                  // The same availability the friends rail's own tile shows,
                  // and the same one friends see — never a guessed state, so
                  // it appears only once the profile has emitted.
                  if (data != null)
                    PositionedDirectional(
                      start: controlHeight - 12,
                      top: controlHeight - 12,
                      child: AvailabilityDot(
                        status: PeopleStatus.fromOwnAvailability(
                          data.availability,
                        ),
                        size: 12,
                        borderColor: palette.background,
                        borderWidth: 2,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );

        final controls = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            bell,
            const SizedBox(width: AppRhythm.tight),
            avatar,
          ],
        );

        final text = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showBrand) ...[
              const HomeBrandLockup(),
              const SizedBox(height: AppRhythm.tight),
            ],
            heading,
            const SizedBox(height: AppRhythm.hairline),
            subtitle,
          ],
        );

        // At enlarged text a 320 px phone cannot hold two 46 px discs beside
        // a wrapped Polish greeting, so the controls drop under the words
        // rather than squeezing the name into one character per line.
        if (enlargedText) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              text,
              const SizedBox(height: AppRhythm.item),
              Align(alignment: AlignmentDirectional.centerEnd, child: controls),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: text),
            const SizedBox(width: AppRhythm.tight),
            controls,
          ],
        );
      },
    );
  }
}

/// The YO Voice lockup on Start: the real logo, bare, before the wordmark.
///
/// Refine-look W1: the grey 28 px tile is gone. The full-colour mark sits in
/// a 32 px box on phones (36 px from 600 px wide), about 26 px of ink, 10 px
/// before the unchanged w800 wordmark. Dark gives it a static bloom; Pearl a
/// plum contact shadow so the glossy object sits on the paper. Light is
/// paint only — the layout box is exactly the mark — and there is no glint
/// at this size. At ≥ 1.6 × text the mark follows the wordmark (clamped to
/// 48). The wordmark is the product name, not copy, so it is not localized;
/// the line is one semantics node that reads the name once.
class HomeBrandLockup extends StatelessWidget {
  const HomeBrandLockup({super.key});

  @override
  Widget build(BuildContext context) {
    final medium = MediaQuery.sizeOf(context).width >= 600;
    return YoBrandLockup(
      key: const ValueKey('home-brand-lockup'),
      markKey: const ValueKey('home-brand-mark'),
      size: medium
          ? HomeGreetingHeader.brandMarkSizeMedium
          : HomeGreetingHeader.brandMarkSize,
    );
  }
}

/// A 46 px header control with the real unread count on it.
///
/// Refine-look §8.1: a neutral glass disc with a hairline edge (never an
/// outline) and a `textPrimary` glyph. The count is a fact the shell already
/// holds; a bare dot would be a lossy view of the same fact, so the badge
/// prints the number (99+ above that) as the one [YoCountBadge], ringed in
/// the canvas colour so it reads as cut out of the disc.
class HomeHeaderDisc extends StatelessWidget {
  const HomeHeaderDisc({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.badgeCount = 0,
    super.key,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final highContrast = MediaQuery.highContrastOf(context);
    return AccessibleTapRegion(
      onTap: onTap,
      semanticLabel: tooltip,
      tooltip: tooltip,
      circular: true,
      child: ExcludeSemantics(
        child: Container(
          width: HomeGreetingHeader.controlHeight,
          height: HomeGreetingHeader.controlHeight,
          decoration:
              AppFinish.glassDecoration(
                palette,
                shape: BoxShape.circle,
                highContrast: highContrast,
              ).copyWith(
                border: Border.all(
                  color: highContrast ? palette.borderStrong : palette.hairline,
                ),
              ),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Icon(icon, color: palette.textPrimary, size: 21),
              if (badgeCount > 0)
                PositionedDirectional(
                  top: -4,
                  end: -4,
                  child: YoCountBadge(
                    key: const ValueKey('home-bell-count'),
                    count: badgeCount,
                    ring: palette.background,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
