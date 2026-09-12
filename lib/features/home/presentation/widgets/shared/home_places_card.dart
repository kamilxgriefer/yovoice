import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_sizing.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_places_section.dart';
import 'package:yovoice/shared/widgets/buttons/yo_button.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// "Twoje miejsca" as a LIST, for the desktop context column.
///
/// The phone shows the same memberships as a rail of tiles, because a phone
/// reads top to bottom and a horizontal rail is how it fits nine places in a
/// thumb's reach. A 300 px column beside a 788 px main column is the opposite
/// shape, so the same facts become rows: name, member count, chevron. Neither
/// is the other one stretched, and both open the same place.
///
/// The member count is [Club.memberCount] — a real number written by the
/// backend. A place whose count has never been written reads 0, and a row
/// then prints NO count at all rather than "0 osób", which would be a claim
/// about a place with at least one member in it (the reader).
/// `Club.onlineCount` is never consulted here either; it is not presence.
class HomePlacesCard extends StatelessWidget {
  const HomePlacesCard({
    required this.places,
    required this.onOpenPlace,
    required this.onCreateServer,
    this.onSeeAll,
    this.maxRows = 6,
    super.key,
  });

  final List<HomePlace> places;
  final ValueChanged<Club> onOpenPlace;

  /// The Serwery destination. Creation is gated inside that feature, which
  /// is where its own honest copy lives — Home never states the gate.
  final VoidCallback onCreateServer;

  /// Shown only when the account belongs to more places than the card lists.
  final VoidCallback? onSeeAll;

  final int maxRows;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final rows = places.take(maxRows).toList(growable: false);
    final hasMore = places.length > rows.length;

    return DecoratedBox(
      key: const ValueKey('home-places-card'),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: AppRadius.lg,
        border: Border.all(color: palette.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppRhythm.title),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              copy.homeYourPlaces,
              style: AppTypography.titleMedium.copyWith(
                color: palette.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppRhythm.item),
            for (final place in rows)
              HomePlaceRow(
                key: ValueKey('home-place-${place.club.id}'),
                place: place,
                onTap: () => onOpenPlace(place.club),
              ),
            if (hasMore && onSeeAll != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  key: const ValueKey('home-places-see-all'),
                  onPressed: onSeeAll,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, AppSizing.minimumTouchTarget),
                    foregroundColor: palette.interactiveForeground,
                  ),
                  child: Text(
                    copy.homeSeeAll,
                    style: AppTypography.labelLarge.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: AppRhythm.tight),
            YoButton(
              key: const ValueKey('home-places-create'),
              label: copy.homeCreateServer,
              onPressed: onCreateServer,
              variant: YoButtonVariant.secondary,
              icon: const Icon(Icons.add_rounded, size: 20),
              height: AppSizing.minimumTouchTarget,
            ),
          ],
        ),
      ),
    );
  }
}

/// One membership as a 52 px row: identity, name, real member count, chevron.
class HomePlaceRow extends StatelessWidget {
  const HomePlaceRow({required this.place, required this.onTap, super.key});

  final HomePlace place;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final visuals = place.identity.resolve(Theme.of(context).brightness);
    final club = place.club;
    // A count only where a count actually exists.
    final members = club.memberCount > 0
        ? copy.peopleCount(club.memberCount)
        : null;
    final avatar = club.avatarUrl?.trim();

    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      label: members == null
          ? copy.template(
              '{place}. Open.',
              '{place}. Otwórz.',
              values: <String, Object>{'place': club.name},
            )
          : copy.template(
              '{place}, {members}. Open.',
              '{place}, {members}. Otwórz.',
              values: <String, Object>{'place': club.name, 'members': members},
            ),
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        excludeFromSemantics: true,
        borderRadius: AppRadius.md,
        hoverColor: palette.surfaceMuted,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: visuals.iconSurface,
                  borderRadius: AppRadius.md,
                  border: Border.all(color: visuals.iconBorder),
                ),
                clipBehavior: Clip.antiAlias,
                child: avatar == null || avatar.isEmpty
                    ? Icon(
                        place.identity.icon,
                        size: 22,
                        color: visuals.foreground,
                      )
                    : UserAvatar(
                        radius: 20,
                        userId: club.id,
                        photoUrl: avatar,
                        displayName: club.name,
                      ),
              ),
              const SizedBox(width: AppRhythm.tight),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      club.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.titleSmall.copyWith(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (members != null)
                      Text(
                        members,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySmall.copyWith(
                          color: palette.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppRhythm.hairline),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: palette.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The three 52 px bars the context column draws while the memberships are
/// in flight. Static shapes, never invented place names.
class HomePlacesCardLoading extends StatelessWidget {
  const HomePlacesCardLoading({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return ExcludeSemantics(
      child: DecoratedBox(
        key: const ValueKey('home-places-card-loading'),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: AppRadius.lg,
          border: Border.all(color: palette.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppRhythm.title),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var index = 0; index < 3; index++) ...[
                if (index > 0) const SizedBox(height: AppRhythm.item),
                Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: palette.surfaceRaised,
                    borderRadius: AppRadius.md,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
