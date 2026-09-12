import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_sizing.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/core/theme/join_action_identity.dart';
import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_home.dart'
    show RoomVisual;
import 'package:yovoice/features/home/presentation/widgets/shared/home_places_section.dart'
    show HomePlace;
import 'package:yovoice/features/home/presentation/widgets/shared/home_roster_cache.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_room_board.dart'
    show rankRoomsForHome;
import 'package:yovoice/features/home/presentation/widgets/shared/home_static_waveform.dart';
import 'package:yovoice/features/rooms/data/models/room_participant.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// Where a live room came from. The hero prefers the places the account
/// actually belongs to before anything public, so "Tu i teraz" is about the
/// reader's own world rather than the busiest room on the service.
enum HomeHereNowTier { place, owned, public }

/// One live room the hero may feature, with the place it belongs to.
@immutable
class HomeLiveCandidate {
  const HomeLiveCandidate({required this.room, required this.tier, this.club});

  final VoiceRoom room;
  final HomeHereNowTier tier;

  /// Set only for a club lounge: entering one goes through
  /// `prepareClubLounge` (a membership check, no roster write) rather than
  /// straight to the room.
  final Club? club;

  String get roomId => room.id;
}

/// Picks the room "Tu i teraz" features.
///
/// The rule is deterministic and bounded, in this order:
///
///  1. the first candidate whose ALREADY-LOADED roster contains a friend —
///     the only way the headline may say "Twoi ludzie";
///  2. otherwise the first candidate in tier order (my places, my rooms,
///     public), which is the order the caller builds the list in.
///
/// Rosters that have not arrived, or that the caller may not read, simply do
/// not participate: a room is never promoted on a guess, and while the reads
/// are in flight the hero shows the tier-first room with no friend claim.
HomeLiveCandidate? selectHereNowCandidate({
  required List<HomeLiveCandidate> candidates,
  required HomeRosterCache rosters,
  required Set<String> friendIds,
}) {
  if (candidates.isEmpty) return null;
  if (friendIds.isNotEmpty) {
    for (final candidate in candidates) {
      final entry = rosters.entryFor(candidate.roomId);
      final participants = entry?.participants;
      if (participants == null) continue;
      final hasFriend = participants.any(
        (participant) => friendIds.contains(participant.userId),
      );
      if (hasFriend) return candidate;
    }
  }
  return candidates.first;
}

/// The hero's candidate list, in the one order both Home compositions use:
/// my places first, then my own live rooms, then the ranked public board.
///
/// Every entry is a room that is live RIGHT NOW; nothing is promoted on a
/// guess and nothing is de-duplicated away silently. The phone and the
/// desktop arrange the result very differently but must never disagree about
/// which room "Tu i teraz" is about, which is why the rule lives here rather
/// than in either surface.
List<HomeLiveCandidate> homeLiveCandidates({
  required List<HomePlace> places,
  required List<VoiceRoom> owned,
  required List<VoiceRoom> live,
  required Set<String> followedIds,
  required Set<String> friendIds,
}) {
  final seen = <String>{};
  final candidates = <HomeLiveCandidate>[];
  void add(VoiceRoom room, HomeHereNowTier tier, {Club? club}) {
    if (!room.isLive || !room.isActive || room.deletionInProgress) return;
    if (!seen.add(room.id)) return;
    candidates.add(HomeLiveCandidate(room: room, tier: tier, club: club));
  }

  for (final place in places) {
    if (place.isLive) {
      add(place.lounge!, HomeHereNowTier.place, club: place.club);
    }
  }
  for (final room in owned) {
    add(room, HomeHereNowTier.owned);
  }
  for (final room in rankRoomsForHome(
    live: live,
    recommended: live,
    followedHostIds: followedIds,
    friendHostIds: friendIds,
  )) {
    add(room, HomeHereNowTier.public);
  }
  return candidates;
}

/// Friends present in a roster, in roster order.
List<RoomParticipant> hereNowFriendsInRoom({
  required List<RoomParticipant> participants,
  required Set<String> friendIds,
}) => participants
    .where((participant) => friendIds.contains(participant.userId))
    .toList(growable: false);

/// The Polish plural bucket shared by every count phrase on Home.
///
/// Polish needs three forms and the boundary is not "1 vs many": 2–4 take the
/// nominative plural, 12–14 do not, and everything else takes the genitive.
/// Keeping the decision in one place is what stops "22 osób" appearing on one
/// row and "22 osoby" on the next.
enum HomeCountForm { one, few, many }

HomeCountForm homeCountForm(int count) {
  if (count == 1) return HomeCountForm.one;
  final lastTwo = count % 100;
  final last = count % 10;
  if (last >= 2 && last <= 4 && (lastTwo < 12 || lastTwo > 14)) {
    return HomeCountForm.few;
  }
  return HomeCountForm.many;
}

/// "1 osoba rozmawia" / "4 osoby rozmawiają" / "22 osoby rozmawiają" /
/// "7 osób rozmawia" — used when no readable speaker name exists.
String homeTalkingCount(AppLocalizations copy, int count) {
  final values = <String, Object>{'count': '$count'};
  return switch (homeCountForm(count)) {
    HomeCountForm.one => copy.template(
      '{count} person is talking',
      '{count} osoba rozmawia',
      values: values,
    ),
    HomeCountForm.few => copy.template(
      '{count} people are talking',
      '{count} osoby rozmawiają',
      values: values,
    ),
    HomeCountForm.many => copy.template(
      '{count} people are talking',
      '{count} osób rozmawia',
      values: values,
    ),
  };
}

/// "1 osoba słucha" / "4 osoby słuchają" / "9 osób słucha".
String homeListeningCount(AppLocalizations copy, int count) {
  final values = <String, Object>{'count': '$count'};
  return switch (homeCountForm(count)) {
    HomeCountForm.one => copy.template(
      '{count} person is listening',
      '{count} osoba słucha',
      values: values,
    ),
    HomeCountForm.few => copy.template(
      '{count} people are listening',
      '{count} osoby słuchają',
      values: values,
    ),
    HomeCountForm.many => copy.template(
      '{count} people are listening',
      '{count} osób słucha',
      values: values,
    ),
  };
}

/// The names of the people talking, or an honest count when no name is
/// readable. Never a mixture of a name and an invented one.
String? homeActivitySummary({
  required AppLocalizations copy,
  required List<RoomParticipant> participants,
}) {
  if (participants.isEmpty) return null;
  final speakers = participants
      .where((participant) => participant.isSpeaker)
      .toList(growable: false);
  final listeners = participants.length - speakers.length;
  if (speakers.isEmpty) {
    return listeners == 0 ? null : homeListeningCount(copy, listeners);
  }
  final names = speakers
      .map((participant) => participant.displayName.trim())
      .where((name) => name.isNotEmpty)
      .toList(growable: false);
  if (names.isEmpty) return homeTalkingCount(copy, speakers.length);
  if (names.length == 1) {
    return copy.template(
      '{a} is talking',
      '{a} rozmawia',
      values: <String, Object>{'a': names.first},
    );
  }
  if (names.length == 2) {
    return copy.template(
      '{a} and {b} are talking',
      '{a} i {b} rozmawiają',
      values: <String, Object>{'a': names[0], 'b': names[1]},
    );
  }
  if (names.length == 3) {
    return copy.template(
      '{a}, {b} and {c} are talking',
      '{a}, {b} i {c} rozmawiają',
      values: <String, Object>{'a': names[0], 'b': names[1], 'c': names[2]},
    );
  }
  final remaining = names.length - 3;
  return copy.template(
    '{a}, {b}, {c} and {more}',
    '{a}, {b} i {c} oraz {more}',
    values: <String, Object>{
      'a': names[0],
      'b': names[1],
      'c': names[2],
      'more': homeExtraPeople(copy, remaining),
    },
  );
}

/// The tail of a names list: "oraz 2 osoby" / "and 2 more".
String homeExtraPeople(AppLocalizations copy, int count) {
  final values = <String, Object>{'count': '$count'};
  return switch (homeCountForm(count)) {
    HomeCountForm.one => copy.template(
      '{count} more',
      '{count} osoba',
      values: values,
    ),
    HomeCountForm.few => copy.template(
      '{count} more',
      '{count} osoby',
      values: values,
    ),
    HomeCountForm.many => copy.template(
      '{count} more',
      '{count} osób',
      values: values,
    ),
  };
}

/// The hero headline.
///
/// NEVER embeds a room or place name: Polish would have to inflect it
/// ("w Salonie", not "w Salon") and no app can decline a name its users typed.
/// The place and room live in the eyebrow, in the nominative, where they are
/// correct for every name. A friend's own first name is only ever used in the
/// nominative subject position, which is the one place it is always right.
String homeHeroHeadline({
  required AppLocalizations copy,
  required List<RoomParticipant> friendsInRoom,
  required bool isBroadcast,
}) {
  if (friendsInRoom.length >= 2) {
    return copy.text(
      'Your people are already talking.',
      'Twoi ludzie już rozmawiają.',
    );
  }
  if (friendsInRoom.length == 1) {
    final name = friendsInRoom.first.displayName.trim();
    if (name.isNotEmpty) {
      return copy.template(
        '{name} is already talking.',
        '{name} już rozmawia.',
        values: <String, Object>{'name': name},
      );
    }
  }
  return isBroadcast
      ? copy.text('A broadcast is on right now.', 'Transmisja właśnie trwa.')
      : copy.text('A conversation is on right now.', 'Rozmowa właśnie trwa.');
}

/// "{place} • {room}" for a club lounge, "{category} • {name}" otherwise,
/// with the category omitted when the room carries none. A lounge's stored
/// name is machine-written ("Nasz dom Lounge"), so it is never printed.
String homeHeroEyebrow({
  required AppLocalizations copy,
  required VoiceRoom room,
  Club? club,
}) {
  final parts = <String>[];
  if (club != null) {
    parts.add(club.name.trim());
    parts.add(copy.text('Club room', 'Pokój klubu'));
  } else {
    final category = room.category.trim();
    if (category.isNotEmpty) parts.add(category);
    final name = room.name.trim();
    if (name.isNotEmpty) parts.add(name);
  }
  if (room.isBroadcast) parts.add(copy.text('Broadcast', 'Transmisja'));
  return parts.where((part) => part.isNotEmpty).join(' • ');
}

/// "Tu i teraz" — one live room the reader can actually walk into.
///
/// The card is a browsing surface, not a connection: the CTA opens the
/// existing pre-join screen, which remains the single consent boundary for
/// the microphone and for joining audio. Nothing here subscribes to audio,
/// and the waveform is a static motif for exactly that reason.
class HomeHereNowHero extends StatelessWidget {
  const HomeHereNowHero({
    required this.candidate,
    required this.roster,
    required this.friendIds,
    required this.onJoin,
    this.onOpenRoster,
    this.trailing,
    this.compact = true,
    this.expanded = false,
    super.key,
  });

  final HomeLiveCandidate candidate;

  /// The bounded roster read for this room. Loading and denied are distinct
  /// and neither is "nobody is here".
  final HomeRosterEntry? roster;
  final Set<String> friendIds;

  /// Null disables the CTA — the single-flight guard while a pre-join screen
  /// is already opening.
  final VoidCallback? onJoin;

  /// Opens the existing roster sheet. The portrait cluster is the one
  /// secondary control on the card.
  final VoidCallback? onOpenRoster;

  /// Owner and staff controls, when the reader has them.
  final Widget? trailing;

  final bool compact;

  /// The desktop type ramp: a 30 px headline, 16 px summary, 24 px padding
  /// and a CTA that takes its own width instead of the whole copy column.
  ///
  /// Deliberately separate from [compact]: a 768 px slate already gets the
  /// horizontal composition, but at the PHONE ramp — a wide card is not a
  /// reason to print desktop type on a tablet held in two hands.
  final bool expanded;

  /// The card's inner padding. The desktop hero is a 788 px card in a
  /// workbench, so it breathes; the phone card is 16 px from a 360 px edge.
  double get _padding => expanded ? AppRhythm.section : AppRhythm.title;

  VoiceRoom get room => candidate.room;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final highContrast = MediaQuery.highContrastOf(context);
    final hasCover = (room.imageUrl?.trim().isNotEmpty ?? false);
    // Copy printed over a darkened cover is white in both themes, exactly as
    // the existing room banner does it; without a cover the card is an
    // ordinary surface and uses the theme's own inks.
    final onCover = hasCover && !highContrast;
    final join = JoinAction.resolve(
      onCover ? Brightness.dark : Theme.of(context).brightness,
    );
    final titleInk = onCover ? Colors.white : palette.textPrimary;
    final bodyInk = onCover
        ? Colors.white.withValues(alpha: .82)
        : palette.textSecondary;

    final participants = roster?.orderedSpeakersFirst ?? const [];
    final friendsInRoom = hereNowFriendsInRoom(
      participants: participants,
      friendIds: friendIds,
    );
    final rosterFailed = roster?.failed ?? false;
    final headline = homeHeroHeadline(
      copy: copy,
      friendsInRoom: friendsInRoom,
      isBroadcast: room.isBroadcast,
    );
    final summary = rosterFailed
        ? null
        : homeActivitySummary(copy: copy, participants: participants);

    return Semantics(
      container: true,
      label: [
        homeHeroEyebrow(copy: copy, room: room, club: candidate.club),
        headline,
        if (rosterFailed)
          copy.text(
            "Couldn't check who is talking.",
            'Nie udało się sprawdzić, kto rozmawia.',
          )
        else
          ?summary,
      ].join('. '),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // A card wide enough for two real columns stops being a phone card:
          // copy on one side, portraits on the other. Below that the portraits
          // sit ABOVE the centred headline, as the reference draws the phone.
          final horizontal = constraints.maxWidth >= 560;
          return DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: AppRadius.lg,
              color: palette.surface,
              border: Border.all(color: palette.border),
              boxShadow: [
                BoxShadow(
                  color: palette.shadow.withValues(alpha: .12),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: AppRadius.lg,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ExcludeSemantics(
                      child: _Background(
                        room: room,
                        onCover: onCover,
                        highContrast: highContrast,
                        glow: join.glow,
                        palette: palette,
                      ),
                    ),
                  ),
                  ConstrainedBox(
                    // The desktop card keeps a stage-sized minimum so a room
                    // with no readable roster does not collapse into a strip
                    // beside a 300 px context column. The phone card is
                    // sized purely by its content, as it was.
                    constraints: BoxConstraints(minHeight: expanded ? 240 : 0),
                    child: Padding(
                      padding: EdgeInsets.all(_padding),
                      child: horizontal
                          ? _horizontalBody(
                              context,
                              copy: copy,
                              join: join,
                              titleInk: titleInk,
                              bodyInk: bodyInk,
                              participants: participants,
                              headline: headline,
                              summary: summary,
                              rosterFailed: rosterFailed,
                            )
                          : _verticalBody(
                              context,
                              copy: copy,
                              join: join,
                              titleInk: titleInk,
                              bodyInk: bodyInk,
                              participants: participants,
                              headline: headline,
                              summary: summary,
                              rosterFailed: rosterFailed,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _eyebrowRow(
    BuildContext context, {
    required AppLocalizations copy,
    required JoinActionVisuals join,
  }) {
    // The card's own Semantics container already reads eyebrow, headline and
    // summary as one sentence with no ellipsis, so the painted copy is
    // excluded rather than read a second time in its truncated form.
    final eyebrow = ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.groups_rounded,
            size: expanded ? 20 : 18,
            color: join.ring,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              homeHeroEyebrow(copy: copy, room: room, club: candidate.club),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: join.ring,
                fontSize: expanded ? 14 : 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    final actions = trailing;
    if (actions == null) return eyebrow;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: eyebrow),
        actions,
      ],
    );
  }

  Widget _headline(String text, Color ink, {required TextAlign align}) {
    final style =
        (expanded ? AppTypography.displayMedium : AppTypography.headlineMedium)
            .copyWith(color: ink, fontWeight: FontWeight.w800, height: 1.15);
    // NO line cap. "Max 3 lines" in the contract is an expectation about the
    // length of the copy, not a truncation mechanism: the headline is one of
    // four fixed sentences and never embeds a user-typed name (C19), so
    // letting it wrap costs nothing and the CARD is what grows. A fixed
    // `maxLines: 3` with the default `TextOverflow.clip` cut „Twoi ludzie już
    // rozmawi" in half at 1280 × 200 % — no ellipsis, no cue, content simply
    // gone (WCAG 1.4.4 Resize Text). Whatever the column, the sentence is
    // now complete.
    return ExcludeSemantics(
      child: Text(text, textAlign: align, style: style),
    );
  }

  Widget _summary(
    BuildContext context, {
    required AppLocalizations copy,
    required String? summary,
    required bool rosterFailed,
    required Color ink,
    required TextAlign align,
  }) {
    final text = rosterFailed
        ? copy.text(
            "Couldn't check who is talking.",
            'Nie udało się sprawdzić, kto rozmawia.',
          )
        : summary;
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppRhythm.hairline),
      child: ExcludeSemantics(
        child: Text(
          text,
          key: rosterFailed ? const ValueKey('home-hero-roster-note') : null,
          textAlign: align,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: (expanded ? AppTypography.bodyLarge : AppTypography.bodyMedium)
              .copyWith(color: ink),
        ),
      ),
    );
  }

  Widget _cta(
    BuildContext context, {
    required AppLocalizations copy,
    required JoinActionVisuals join,
  }) => _JoinPill(
    key: const ValueKey('home-hero-join'),
    label: room.isBroadcast
        ? copy.homeJoinBroadcast
        : copy.homeJoinConversation,
    hint: copy.text(
      'Opens the pre-join screen',
      'Otwiera ekran przed dołączeniem',
    ),
    visuals: join,
    onTap: onJoin,
    height: expanded ? 52 : AppSizing.standardControlHeight,
    minWidth: expanded ? 200 : 0,
  );

  Widget _cluster(
    BuildContext context, {
    required AppLocalizations copy,
    required JoinActionVisuals join,
    required List<RoomParticipant> participants,
    required double diameter,
    required double raise,
  }) {
    if (participants.isEmpty) return const SizedBox.shrink();
    final cluster = _PortraitCluster(
      participants: participants.take(3).toList(growable: false),
      diameter: diameter,
      raise: raise,
      ringColor: join.ring,
      idleRing: context.appPalette.borderStrong,
      waveformColor: join.ring.withValues(alpha: .9),
    );
    final open = onOpenRoster;
    if (open == null) return ExcludeSemantics(child: cluster);
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: copy.text('See who is in the room', 'Zobacz, kto jest w pokoju'),
      onTap: open,
      child: Tooltip(
        message: copy.text(
          'See who is in the room',
          'Zobacz, kto jest w pokoju',
        ),
        child: InkWell(
          key: const ValueKey('home-hero-cluster'),
          onTap: open,
          excludeFromSemantics: true,
          borderRadius: AppRadius.lg,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppRhythm.tight,
              vertical: AppRhythm.hairline,
            ),
            child: cluster,
          ),
        ),
      ),
    );
  }

  Widget _verticalBody(
    BuildContext context, {
    required AppLocalizations copy,
    required JoinActionVisuals join,
    required Color titleInk,
    required Color bodyInk,
    required List<RoomParticipant> participants,
    required String headline,
    required String? summary,
    required bool rosterFailed,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      _eyebrowRow(context, copy: copy, join: join),
      const SizedBox(height: AppRhythm.tight),
      if (participants.isNotEmpty) ...[
        Center(
          child: _cluster(
            context,
            copy: copy,
            join: join,
            participants: participants,
            diameter: 96,
            raise: 8,
          ),
        ),
        const SizedBox(height: AppRhythm.item),
      ],
      _headline(headline, titleInk, align: TextAlign.center),
      _summary(
        context,
        copy: copy,
        summary: summary,
        rosterFailed: rosterFailed,
        ink: bodyInk,
        align: TextAlign.center,
      ),
      const SizedBox(height: AppRhythm.title),
      _cta(context, copy: copy, join: join),
    ],
  );

  Widget _horizontalBody(
    BuildContext context, {
    required AppLocalizations copy,
    required JoinActionVisuals join,
    required Color titleInk,
    required Color bodyInk,
    required List<RoomParticipant> participants,
    required String headline,
    required String? summary,
    required bool rosterFailed,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _eyebrowRow(context, copy: copy, join: join),
        const SizedBox(height: AppRhythm.item),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 45,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _headline(headline, titleInk, align: TextAlign.start),
                  _summary(
                    context,
                    copy: copy,
                    summary: summary,
                    rosterFailed: rosterFailed,
                    ink: bodyInk,
                    align: TextAlign.start,
                  ),
                  const SizedBox(height: AppRhythm.section),
                  _cta(context, copy: copy, join: join),
                ],
              ),
            ),
            if (participants.isNotEmpty) ...[
              const SizedBox(width: AppRhythm.section),
              Expanded(
                flex: 55,
                // The cluster is measured against the column it is actually
                // given, not against the card. Three discs overlapping by a
                // sixth span 2.67 diameters, so a diameter picked from the
                // card width overflowed its own column on every card whose
                // copy side was wider than 38 % — which is every one of
                // them. Measuring here is what keeps 768, 1280 and 1440 all
                // free of a horizontal overflow.
                child: LayoutBuilder(
                  builder: (context, columnConstraints) {
                    final span = participants.length.clamp(1, 3);
                    // Cluster width = d + (n-1)·(d − d/6); the roster button
                    // adds its own 8 px of padding on each side.
                    final perDiameter = 1 + (span - 1) * (1 - 16 / 96);
                    final available =
                        columnConstraints.maxWidth -
                        (onOpenRoster == null ? 0 : AppRhythm.tight * 2);
                    final diameter = (available / perDiameter).clamp(
                      56.0,
                      136.0,
                    );
                    return Center(
                      child: _cluster(
                        context,
                        copy: copy,
                        join: join,
                        participants: participants,
                        diameter: diameter,
                        raise: 12,
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Cover, scrim and the one restrained glow — in that order, and never a
/// per-frame blur filter: the cover is decoded small, which IS the softness.
class _Background extends StatelessWidget {
  const _Background({
    required this.room,
    required this.onCover,
    required this.highContrast,
    required this.glow,
    required this.palette,
  });

  final VoiceRoom room;
  final bool onCover;
  final bool highContrast;
  final Color glow;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    if (!onCover) {
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [palette.surfaceRaised, palette.surface],
          ),
        ),
        child: highContrast
            ? const SizedBox.expand()
            : DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -.5),
                    radius: .9,
                    colors: [glow, glow.withValues(alpha: 0)],
                  ),
                ),
                child: const SizedBox.expand(),
              ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        RoomVisual(room: room, expand: true, radius: 0),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              stops: const [0, .55, 1],
              colors: [
                palette.scrim.withValues(alpha: .92),
                palette.scrim.withValues(alpha: .78),
                palette.scrim.withValues(alpha: .62),
              ],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [.7, 1],
              colors: [
                palette.scrim.withValues(alpha: 0),
                palette.scrim.withValues(alpha: .85),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Three overlapping portraits with the static waveform under the middle one.
///
/// The ring is a role, not a guess: a cyan ring means the person holds the
/// microphone (`RoomParticipant.isSpeaker`), a neutral hairline means they are
/// listening. Nothing here claims anyone is speaking right now — Home has no
/// audio signal and never will.
class _PortraitCluster extends StatelessWidget {
  const _PortraitCluster({
    required this.participants,
    required this.diameter,
    required this.raise,
    required this.ringColor,
    required this.idleRing,
    required this.waveformColor,
  });

  final List<RoomParticipant> participants;
  final double diameter;
  final double raise;
  final Color ringColor;
  final Color idleRing;
  final Color waveformColor;

  @override
  Widget build(BuildContext context) {
    final overlap = diameter * (16 / 96);
    final step = diameter - overlap;
    final width = diameter + (participants.length - 1) * step;
    final waveWidth = diameter;
    final waveHeight = diameter / 4;
    final height = diameter + raise + waveHeight / 2;
    final middle = participants.length ~/ 2;
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          PositionedDirectional(
            bottom: 0,
            start: (width - waveWidth) / 2,
            child: HomeStaticWaveform(
              color: waveformColor,
              width: waveWidth,
              height: waveHeight,
            ),
          ),
          for (var index = 0; index < participants.length; index++)
            PositionedDirectional(
              start: index * step,
              top: index == middle ? 0 : raise,
              child: _Portrait(
                participant: participants[index],
                diameter: diameter,
                ringColor: ringColor,
                idleRing: idleRing,
              ),
            ),
        ],
      ),
    );
  }
}

class _Portrait extends StatelessWidget {
  const _Portrait({
    required this.participant,
    required this.diameter,
    required this.ringColor,
    required this.idleRing,
  });

  final RoomParticipant participant;
  final double diameter;
  final Color ringColor;
  final Color idleRing;

  /// What every portrait reserves between its outer edge and its face,
  /// whatever weight the ring is painted at.
  ///
  /// The speaking ring is 3 px and a listener's is a 1.5 px hairline. Letting
  /// the ring eat into the avatar made the one person NOT talking render a
  /// 4.5 px LARGER face than the two who are — contract §7.9 asks for equal
  /// circles, so the slot is constant and a thinner ring simply leaves more
  /// of it as padding.
  static const double _faceInset = 4.5;

  @override
  Widget build(BuildContext context) {
    final speaker = participant.isSpeaker;
    final ringWidth = speaker ? 3.0 : 1.5;
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: context.appPalette.surfaceRaised,
        border: Border.all(
          color: speaker ? ringColor : idleRing,
          width: ringWidth,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(_faceInset - ringWidth),
        child: UserAvatar(
          radius: (diameter - _faceInset * 2) / 2,
          userId: participant.userId,
          photoUrl: participant.photoUrl,
          displayName: participant.displayName,
        ),
      ),
    );
  }
}

/// The one primary action on Home.
///
/// It opens the pre-join screen. It does not join, does not start audio and
/// does not ask for the microphone — that consent lives one screen further
/// on, for every room, on every platform.
class _JoinPill extends StatelessWidget {
  const _JoinPill({
    required this.label,
    required this.hint,
    required this.visuals,
    required this.onTap,
    this.height = AppSizing.standardControlHeight,
    this.minWidth = 0,
    super.key,
  });

  final String label;
  final String hint;
  final JoinActionVisuals visuals;
  final VoidCallback? onTap;

  /// 48 on the phone, 52 in the desktop hero.
  final double height;

  /// A floor, never a ceiling: the desktop CTA is a deliberate 200 px
  /// object in a wide card rather than a label-width pill, but a longer
  /// label (or a larger text scale) still grows it.
  final double minWidth;

  @override
  Widget build(BuildContext context) =>
      // ONE node, not two. `ButtonStyleButton` is itself a semantics
      // boundary, so an annotation wrapped AROUND it cannot merge into it and
      // becomes a second, nameless, action-less button on the same rectangle
      // (WCAG 4.1.2). The button's own node is a container that absorbs its
      // descendants, so the hint is attached from the inside instead — that
      // keeps name, role, enabled, tap AND the focus flags the real control
      // reports to a keyboard user on a single node.
      ConstrainedBox(
        constraints: BoxConstraints(minHeight: height, minWidth: minWidth),
        child: FilledButton.icon(
          onPressed: onTap,
          style:
              FilledButton.styleFrom(
                backgroundColor: visuals.fill,
                foregroundColor: visuals.ink,
                disabledBackgroundColor: visuals.fill.withValues(alpha: .55),
                disabledForegroundColor: visuals.ink.withValues(alpha: .7),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.standard,
                minimumSize: Size(minWidth, height),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppRhythm.section,
                ),
                shape: const StadiumBorder(),
                // The filled-control focus rule: the boundary is drawn in the
                // control's own ink, INSIDE the fill, so it stays visible on a
                // saturated surface.
                side: BorderSide.none,
              ).copyWith(
                overlayColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.pressed)) {
                    return visuals.pressed.withValues(alpha: .6);
                  }
                  if (states.contains(WidgetState.hovered)) {
                    return visuals.hover.withValues(alpha: .4);
                  }
                  if (states.contains(WidgetState.focused)) {
                    return visuals.ink.withValues(alpha: .12);
                  }
                  return null;
                }),
              ),
          icon: Icon(Icons.mic_rounded, size: 20, color: visuals.ink),
          label: Semantics(
            hint: hint,
            child: Text(
              label,
              maxLines: 2,
              textAlign: TextAlign.center,
              style: AppTypography.titleMedium.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
}
