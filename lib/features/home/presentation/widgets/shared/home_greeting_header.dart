import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';
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
    super.key,
  });

  /// The shared `watchCurrentProfile()` stream the parent already holds.
  final Stream<UserProfile>? profile;
  final VoidCallback onOpenNotifications;
  final VoidCallback onOpenProfile;
  final int unreadNotificationCount;

  /// Desktop ramp (26 px heading) rather than the phone's 22.
  final bool expanded;

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
                          fontSize: expanded ? 22 : 19,
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
            style:
                (expanded
                        ? AppTypography.headlineLarge
                        : constraints.maxWidth < 320
                        ? AppTypography.headlineSmall
                        : AppTypography.headlineMedium)
                    .copyWith(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w800,
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
          icon: Icons.notifications_none_rounded,
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
                  Container(
                    width: controlHeight,
                    height: controlHeight,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: palette.borderStrong),
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
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: PeopleStatus.fromOwnAvailability(
                            data.availability,
                          ).foreground(palette),
                          border: Border.all(
                            color: palette.background,
                            width: 2,
                          ),
                        ),
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

/// A 46 px header control with the real unread count on it.
///
/// The count is a fact the shell already holds; a bare dot would be a lossy
/// view of the same fact, so the badge prints the number (99+ above that).
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
    return AccessibleTapRegion(
      onTap: onTap,
      semanticLabel: tooltip,
      tooltip: tooltip,
      circular: true,
      child: ExcludeSemantics(
        child: Container(
          width: HomeGreetingHeader.controlHeight,
          height: HomeGreetingHeader.controlHeight,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: palette.surfaceRaised,
            border: Border.all(color: palette.border),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Icon(icon, color: palette.textPrimary, size: 21),
              if (badgeCount > 0)
                Positioned(
                  top: -4,
                  right: -4,
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 20,
                      minHeight: 20,
                    ),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: palette.background, width: 2),
                    ),
                    child: Text(
                      badgeCount > 99 ? '99+' : '$badgeCount',
                      style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
