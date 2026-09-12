import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_sizing.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/core/theme/place_identity.dart';
import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_add_affordance.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_here_now_hero.dart'
    show homeActivitySummary;
import 'package:yovoice/features/home/presentation/widgets/shared/home_participant_stack.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_roster_cache.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_section_header.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// One membership, with whatever the client knows about its voice room.
///
/// The three lounge states are kept apart on purpose: a lounge that has not
/// loaded is not a quiet lounge, and a lounge the reader may not read is not
/// a quiet one either. `Club.onlineCount` is never consulted — it is a
/// membership counter written by Cloud Functions, not presence, and printing
/// it as activity would be the exact fiction this product refuses.
@immutable
class HomePlace {
  const HomePlace({
    required this.club,
    this.lounge,
    this.loungeFailed = false,
    this.loungeLoading = false,
  });

  final Club club;
  final VoiceRoom? lounge;
  final bool loungeFailed;
  final bool loungeLoading;

  bool get isLive {
    final room = lounge;
    return room != null &&
        room.isLive &&
        room.isActive &&
        !room.deletionInProgress;
  }

  PlaceIdentity get identity =>
      PlaceIdentity.of(PlaceKind.fromClubTypeName(club.type.name));
}

/// "W Twoich serwerach" — the places the reader belongs to that have a live
/// conversation right now, at most three, newest membership first.
///
/// A heading is a promise about content, so this section draws nothing at all
/// when the account has no memberships: the "Twoje miejsca" section below
/// owns that empty state, and Home never prints two empty messages about the
/// same fact.
class HomeServerActivitySection extends StatelessWidget {
  const HomeServerActivitySection({
    required this.places,
    required this.rosters,
    required this.onSeeAll,
    required this.onOpenPlace,
    required this.onEnterLounge,
    this.onRetryPlace,
    this.uncheckedPlaces = 0,
    this.maxRows = 3,
    super.key,
  });

  /// Only the memberships whose lounge Home actually subscribed to. A place
  /// that was never read may not appear here, because appearing here — or
  /// being counted as silent below — is an activity claim.
  final List<HomePlace> places;

  /// How many further memberships exist that Home did NOT check, because the
  /// listener budget stops at [HomeLoungeWatcher.budget]. It never becomes a
  /// row; it only stops the quiet card from speaking for places nobody
  /// looked at.
  final int uncheckedPlaces;
  final HomeRosterCache rosters;
  final VoidCallback onSeeAll;
  final ValueChanged<Club> onOpenPlace;
  final ValueChanged<HomePlace> onEnterLounge;

  /// Re-subscribes ONE place's lounge after a failed read.
  final ValueChanged<HomePlace>? onRetryPlace;
  final int maxRows;

  @override
  Widget build(BuildContext context) {
    if (places.isEmpty) return const SizedBox.shrink();
    final copy = AppLocalizations.of(context);
    final rows = <HomePlace>[
      ...places.where((place) => place.isLive),
      // A place whose lounge could not be read still gets a row, because
      // hiding it would quietly claim it is silent.
      ...places.where((place) => place.loungeFailed),
    ].take(maxRows).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeSectionHeader(
          title: copy.homeInYourServers,
          seeAllKey: const ValueKey('home-servers-see-all'),
          seeAllLabel: copy.homeSeeAll,
          onSeeAll: onSeeAll,
        ),
        if (rows.isEmpty)
          // "Quiet" is a statement about places Home LOOKED AT. With more
          // memberships than the listener budget, the unchecked remainder is
          // not silent — it is unknown — so the sentence narrows and the
          // Serwery destination is named as the way to see the rest.
          _QuietCard(
            message: uncheckedPlaces == 0
                ? copy.text(
                    "It's quiet in your places right now.",
                    'Teraz cicho w Twoich miejscach.',
                  )
                : copy.text(
                    "It's quiet in the places Home could check. "
                        'The rest are in Servers.',
                    'Teraz cicho w miejscach, które udało się sprawdzić. '
                        'Resztę znajdziesz w Serwerach.',
                  ),
          )
        else
          for (var index = 0; index < rows.length; index++) ...[
            if (index > 0) const SizedBox(height: AppRhythm.item),
            HomeServerActivityCard(
              key: ValueKey('home-club-activity-${rows[index].club.id}'),
              place: rows[index],
              roster: rosters.entryFor(rows[index].lounge?.id ?? ''),
              onOpenPlace: () => onOpenPlace(rows[index].club),
              onEnterLounge: () => onEnterLounge(rows[index]),
              onRetry: onRetryPlace == null
                  ? null
                  : () => onRetryPlace!(rows[index]),
            ),
          ],
      ],
    );
  }
}

/// One live place: who is in the voice room, and one way in.
class HomeServerActivityCard extends StatelessWidget {
  const HomeServerActivityCard({
    required this.place,
    required this.onOpenPlace,
    required this.onEnterLounge,
    this.roster,
    this.onRetry,
    super.key,
  });

  final HomePlace place;
  final HomeRosterEntry? roster;
  final VoidCallback onOpenPlace;
  final VoidCallback onEnterLounge;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final visuals = place.identity.resolve(Theme.of(context).brightness);
    final lounge = place.lounge;
    final participants = roster?.orderedSpeakersFirst ?? const [];
    final activity = place.loungeFailed || (roster?.failed ?? false)
        ? null
        : homeActivitySummary(copy: copy, participants: participants);
    final context0 = copy.text('Club room', 'Pokój klubu');
    final kind = lounge?.isBroadcast ?? false
        ? copy.text('Broadcast', 'Transmisja')
        : copy.homeVoiceConversation;

    final failureNote = Row(
      children: [
        Expanded(
          child: ExcludeSemantics(
            child: Text(
              copy.text(
                "Couldn't check the conversation",
                'Nie udało się sprawdzić rozmowy',
              ),
              style: AppTypography.bodySmall.copyWith(
                color: palette.textSecondary,
              ),
            ),
          ),
        ),
        if (onRetry != null)
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              minimumSize: const Size(
                AppSizing.minimumTouchTarget,
                AppSizing.minimumTouchTarget,
              ),
              foregroundColor: palette.interactiveForeground,
            ),
            child: Text(copy.text('Try again', 'Spróbuj ponownie')),
          ),
      ],
    );

    Widget identityBlock({required double square, required bool wide}) =>
        ExcludeSemantics(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _PlaceSquare(club: place.club, visuals: visuals, size: square),
              const SizedBox(width: AppRhythm.item),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      place.club.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          (wide
                                  ? AppTypography.titleMedium
                                  : AppTypography.titleSmall)
                              .copyWith(
                                color: palette.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                    ),
                    Text(
                      context0,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          (wide
                                  ? AppTypography.bodyMedium
                                  : AppTypography.bodySmall)
                              .copyWith(color: palette.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );

    final voiceKindRow = ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.mic_rounded, size: 16, color: visuals.foreground),
          const SizedBox(width: AppRhythm.hairline),
          Flexible(
            child: Text(
              kind,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: visuals.foreground,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    final pill = _TakeALookPill(
      label: copy.homeTakeALook,
      semanticLabel: copy.template(
        'Take a look: {place}',
        'Zajrzyj: {place}',
        values: <String, Object>{'place': place.club.name},
      ),
      visuals: visuals,
      onTap: onEnterLounge,
    );

    /// The wide anatomy: identity, faces, activity, channel kind and the way
    /// in, all on ONE line. It is not the phone card stretched — the phone
    /// stacks because a Polish activity sentence cannot share 360 px with a
    /// name and a pill, and that reason disappears at 680.
    final wideBody = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(flex: 4, child: identityBlock(square: 48, wide: true)),
        if (place.loungeFailed)
          Expanded(flex: 5, child: failureNote)
        else ...[
          if (participants.isNotEmpty) ...[
            const SizedBox(width: AppRhythm.item),
            HomeParticipantStack(
              participants: participants,
              radius: 18,
              overlap: 14,
            ),
          ],
          if (activity != null) ...[
            const SizedBox(width: AppRhythm.tight),
            Expanded(
              flex: 3,
              child: ExcludeSemantics(
                child: Text(
                  activity,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmall.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(width: AppRhythm.item),
          voiceKindRow,
          const SizedBox(width: AppRhythm.item),
          pill,
        ],
      ],
    );

    final stackedBody = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: identityBlock(square: 44, wide: false)),
            if (participants.isNotEmpty) ...[
              const SizedBox(width: AppRhythm.item),
              HomeParticipantStack(participants: participants),
            ],
          ],
        ),
        if (place.loungeFailed) ...[
          const SizedBox(height: AppRhythm.tight),
          failureNote,
        ] else ...[
          if (activity != null) ...[
            const SizedBox(height: AppRhythm.tight),
            ExcludeSemantics(
              child: Text(
                activity,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodySmall.copyWith(
                  color: palette.textSecondary,
                ),
              ),
            ),
          ],
          const SizedBox(height: AppRhythm.tight),
          Row(
            children: [
              Expanded(child: voiceKindRow),
              const SizedBox(width: AppRhythm.tight),
              pill,
            ],
          ),
        ],
      ],
    );

    // ONE announced control per destination. The card node carries the
    // composed sentence AND the tap that opens the place, so the promise
    // "Otwórz miejsce." is one a screen reader can actually keep (WCAG
    // 4.1.2); the painted copy below is excluded so it is not read a second
    // time as loose fragments. `explicitChildNodes` keeps "Zajrzyj" (and the
    // retry) as their own nodes instead of merging their labels and their
    // taps upward — which is what made a screen-reader tap on this card open
    // the lounge while a sighted tap opened the club.
    return Semantics(
      container: true,
      button: true,
      explicitChildNodes: true,
      onTap: onOpenPlace,
      label: copy.template(
        '{place}, {room}. {kind}: {activity}. Open place.',
        '{place}, {room}. {kind}: {activity}. Otwórz miejsce.',
        values: <String, Object>{
          'place': place.club.name,
          'room': context0,
          'kind': kind,
          'activity':
              activity ??
              copy.text(
                "Couldn't check the conversation",
                'Nie udało się sprawdzić rozmowy',
              ),
        },
      ),
      child: Material(
        color: Color.alphaBlend(visuals.cardWash, palette.surface),
        borderRadius: AppRadius.lg,
        child: InkWell(
          onTap: onOpenPlace,
          excludeFromSemantics: true,
          borderRadius: AppRadius.lg,
          child: Container(
            padding: const EdgeInsets.all(AppRhythm.item),
            decoration: BoxDecoration(
              borderRadius: AppRadius.lg,
              border: Border.all(color: palette.border),
            ),
            // The one-line anatomy needs a card wide enough to hold a
            // Polish activity sentence beside a name, a face stack and a
            // pill. Below that the same facts stack — different shape,
            // identical content and identical semantics.
            child: LayoutBuilder(
              builder: (context, constraints) =>
                  // 680 of CARD, so 656 of content inside the padding — and
                  // the measure is in TYPE, not pixels: at 200 % every word
                  // on this row is twice as wide, so a 700 px card is as
                  // cramped as a 350 px one and takes the stacked anatomy.
                  constraints.maxWidth >=
                      (680 - AppRhythm.item * 2) *
                          MediaQuery.textScalerOf(context).scale(1)
                  ? wideBody
                  : stackedBody,
            ),
          ),
        ),
      ),
    );
  }
}

/// "Twoje miejsca" — every membership as one tappable tile, plus the one way
/// to make a new place. Order is the membership order the account already
/// sees in the Serwery destination, so the two never disagree.
class HomePlacesRail extends StatelessWidget {
  const HomePlacesRail({
    required this.places,
    required this.onOpenPlace,
    required this.onCreateServer,
    this.horizontalPadding = AppRhythm.title,
    this.headerScale = HomeSectionHeaderScale.compact,
    super.key,
  });

  final List<HomePlace> places;
  final ValueChanged<Club> onOpenPlace;
  final VoidCallback onCreateServer;
  final double horizontalPadding;

  /// The rail owns its own heading. A desktop single column asks for the
  /// desktop ramp so it sits on the same line as its neighbours.
  final HomeSectionHeaderScale headerScale;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: HomeSectionHeader(
            title: copy.homeYourPlaces,
            scale: headerScale,
          ),
        ),
        SingleChildScrollView(
          key: const ValueKey('home-places-rail'),
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.hardEdge,
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final place in places) ...[
                HomePlaceShortcut(
                  key: ValueKey('home-place-${place.club.id}'),
                  place: place,
                  onTap: () => onOpenPlace(place.club),
                ),
                const SizedBox(width: AppRhythm.item),
              ],
              _CreatePlaceTile(
                key: const ValueKey('home-places-create'),
                label: copy.homeCreateServer,
                onTap: onCreateServer,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One place, as a 44 px identity tile with its full name underneath.
class HomePlaceShortcut extends StatelessWidget {
  const HomePlaceShortcut({
    required this.place,
    required this.onTap,
    this.tileSize = 44,
    this.labelWidth = 64,
    super.key,
  });

  final HomePlace place;
  final VoidCallback onTap;
  final double tileSize;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final visuals = place.identity.resolve(Theme.of(context).brightness);
    // A count only where a count actually exists. `memberCount` is written by
    // Cloud Functions and may never have been written at all; announcing the
    // zero would say "0 osób" about a place the listener is a member of. The
    // desktop list already answers this fact the same way
    // (`home_places_card.dart`), and one fact may not have two answers.
    final members = place.club.memberCount > 0
        ? copy.peopleCount(place.club.memberCount)
        : null;
    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      label: members == null
          ? copy.template(
              '{place}. Open.',
              '{place}. Otwórz.',
              values: <String, Object>{'place': place.club.name},
            )
          : copy.template(
              '{place}, {members}. Open.',
              '{place}, {members}. Otwórz.',
              values: <String, Object>{
                'place': place.club.name,
                'members': members,
              },
            ),
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        excludeFromSemantics: true,
        borderRadius: AppRadius.md,
        child: SizedBox(
          width: MediaQuery.textScalerOf(context).scale(labelWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PlaceSquare(club: place.club, visuals: visuals, size: tileSize),
              const SizedBox(height: 6),
              Text(
                place.club.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppTypography.labelMedium.copyWith(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The honest empty state for an account that belongs to no place yet.
class HomePlacesEmptyCard extends StatelessWidget {
  const HomePlacesEmptyCard({
    required this.onCreateServer,
    required this.onDiscover,
    super.key,
  });

  final VoidCallback onCreateServer;
  final VoidCallback onDiscover;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    return DecoratedBox(
      key: const ValueKey('home-places-empty'),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: AppRadius.lg,
        border: Border.all(color: palette.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppRhythm.title),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              copy.text(
                "You don't have your places yet.",
                'Nie masz jeszcze swoich miejsc.',
              ),
              style: AppTypography.bodyMedium.copyWith(
                color: palette.textSecondary,
              ),
            ),
            const SizedBox(height: AppRhythm.item),
            Wrap(
              spacing: AppRhythm.item,
              runSpacing: AppRhythm.tight,
              children: [
                FilledButton.icon(
                  key: const ValueKey('home-places-empty-create'),
                  onPressed: onCreateServer,
                  style: FilledButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    minimumSize: const Size(0, AppSizing.minimumTouchTarget),
                    shape: const StadiumBorder(),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: Text(copy.homeCreateServer),
                ),
                OutlinedButton(
                  key: const ValueKey('home-places-empty-discover'),
                  onPressed: onDiscover,
                  style: OutlinedButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    minimumSize: const Size(0, AppSizing.minimumTouchTarget),
                    shape: const StadiumBorder(),
                  ),
                  child: Text(copy.homeDiscoverRooms),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The five 44 px squares Home draws while the memberships are in flight.
/// Static shapes, never shimmering names.
class HomePlacesLoading extends StatelessWidget {
  const HomePlacesLoading({
    this.horizontalPadding = AppRhythm.title,
    super.key,
  });

  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return ExcludeSemantics(
      child: Padding(
        key: const ValueKey('home-places-loading'),
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        child: Row(
          children: [
            for (var index = 0; index < 5; index++) ...[
              if (index > 0) const SizedBox(width: AppRhythm.item),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: palette.surfaceRaised,
                  borderRadius: AppRadius.md,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PlaceSquare extends StatelessWidget {
  const _PlaceSquare({
    required this.club,
    required this.visuals,
    required this.size,
  });

  final Club club;
  final PlaceIdentityVisuals visuals;
  final double size;

  @override
  Widget build(BuildContext context) {
    final avatar = club.avatarUrl?.trim();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: visuals.iconSurface,
        borderRadius: AppRadius.md,
        border: Border.all(color: visuals.iconBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: avatar == null || avatar.isEmpty
          ? Icon(visuals.icon, size: size * .5, color: visuals.foreground)
          : UserAvatar(
              radius: size / 2,
              photoUrl: avatar,
              displayName: club.name,
              backgroundColor: visuals.iconSurface,
            ),
    );
  }
}

class _TakeALookPill extends StatelessWidget {
  const _TakeALookPill({
    required this.label,
    required this.semanticLabel,
    required this.visuals,
    required this.onTap,
  });

  final String label;
  final String semanticLabel;
  final PlaceIdentityVisuals visuals;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    // The annotation goes INSIDE the button, never around it: a
    // `ButtonStyleButton` is its own semantics boundary, so a wrapper either
    // becomes a second nameless node or (with `excludeSemantics`) throws away
    // the real control's tap and focus flags. From here it merges into the
    // button's own node, which keeps name, role, tap and focus together.
    return SizedBox(
      height: AppSizing.minimumTouchTarget,
      child: TextButton.icon(
        onPressed: onTap,
        iconAlignment: IconAlignment.end,
        style: TextButton.styleFrom(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.standard,
          minimumSize: const Size(0, AppSizing.minimumTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppRhythm.title),
          backgroundColor: visuals.selectedWash,
          foregroundColor: palette.textPrimary,
          shape: StadiumBorder(side: BorderSide(color: visuals.iconBorder)),
        ),
        icon: const Icon(Icons.chevron_right_rounded, size: 16),
        label: Semantics(
          label: semanticLabel,
          excludeSemantics: true,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

class _CreatePlaceTile extends StatelessWidget {
  const _CreatePlaceTile({required this.label, required this.onTap, super.key});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      label: label,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        excludeFromSemantics: true,
        borderRadius: AppRadius.md,
        child: SizedBox(
          width: MediaQuery.textScalerOf(context).scale(64),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Dashed, like the friends rail's own "add" slot: an empty
              // square with a solid border reads as a place with no avatar.
              HomeDashedOutline(
                size: 44,
                color: palette.borderStrong,
                borderRadius: AppRadius.md,
                child: Icon(
                  Icons.add_rounded,
                  size: 22,
                  color: palette.interactiveForeground,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppTypography.labelMedium.copyWith(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuietCard extends StatelessWidget {
  const _QuietCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return DecoratedBox(
      key: const ValueKey('home-servers-quiet'),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: AppRadius.lg,
        border: Border.all(color: palette.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppRhythm.title),
        child: Text(
          message,
          style: AppTypography.bodyMedium.copyWith(
            color: palette.textSecondary,
          ),
        ),
      ),
    );
  }
}
