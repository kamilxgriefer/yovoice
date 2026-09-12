import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/presence/presence_service.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_add_affordance.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_friend_tile.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_section_header.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_section_status.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/shared/widgets/profile/availability_picker.dart';
import 'package:yovoice/shared/widgets/profile/people_status_ring.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';

/// "Your people" — the signed-in account first, with its own availability
/// ring, then every friend, online first, with the shared status ring.
///
/// The live-first Home shipped without it: both Home variants took a
/// `friendService` and never used it, so the only people on the screen came
/// from the follow graph, capped at two rows. An account with a dozen friends
/// therefore saw one person. This strip is the friends list itself, so the
/// count on Home matches the Friends tab.
///
/// The first tile is the account itself. Its ring is exactly what friends
/// see (`PeopleStatus.fromOwnAvailability`, ADR-150) and tapping it opens the
/// one shared availability picker — the same picker the header chip, the
/// More sheet and the desktop sidebar open.
///
/// Loading, empty and error are three different renders on purpose: a blank
/// top of Home on a cold start or a permission denial used to read as "no
/// friends", which is a claim the data never made.
class HomePeopleStrip extends StatelessWidget {
  const HomePeopleStrip({
    required this.friends,
    required this.onSeeAll,
    this.profile,
    this.presenceService,
    this.onRetry,
    this.friendsSnapshot,
    this.voiceByFriendId = const <String, HomeFriendVoice>{},
    this.onOpenVoice,
    this.expandedLabels = false,
    this.avatarRadius = 26,
    this.horizontalPadding = AppRhythm.title,
    super.key,
  });

  /// Null when no session or no Firebase — with no profile stream either,
  /// the strip then renders nothing rather than an error box on the first
  /// screen of the app.
  final Stream<List<FriendUser>>? friends;
  final VoidCallback onSeeAll;

  /// The shared `watchCurrentProfile()` stream the parent already holds.
  /// The strip never opens a second listener; null (a harness, or a session
  /// without a profile) simply means no own tile.
  final Stream<UserProfile>? profile;

  /// Test seam only. Production passes null and the picker constructs a
  /// service when a choice is made, exactly as the chip does.
  final PresenceService? presenceService;

  /// Re-subscribes the friends stream after a failed read. `watchFriends()`
  /// is process-shared, so the parent's `setState` is cheap.
  final VoidCallback? onRetry;

  /// An already-resolved friends read from the surrounding surface. Non-null
  /// stops this strip from opening a listener of its own — Home resolves the
  /// list once because the "Tu i teraz" hero needs the same ids, and one
  /// screen must never subscribe to the same query twice.
  final AsyncSnapshot<List<FriendUser>>? friendsSnapshot;

  /// Unheard Voice Moment chains, keyed by friend id, resolved by the parent
  /// from the page it already loaded. An entry here is the ONLY reason a tile
  /// draws a ring or a badge; an empty map renders presence only, which is
  /// exactly what a failed Moments read must look like.
  final Map<String, HomeFriendVoice> voiceByFriendId;

  /// Opens one friend's chain in the existing story viewer.
  final ValueChanged<List<VoiceMoment>>? onOpenVoice;

  /// Desktop widens the name column (`radius * 3.2` instead of `2.4`) so
  /// full names ellipsise less.
  final bool expandedLabels;
  final double avatarRadius;

  /// The page gutter. The strip is full-bleed: the heading takes this as
  /// padding and the rail takes it INSIDE its scroll view, so the first
  /// tile's COLUMN starts exactly at the gutter and the tiles scroll under
  /// the frame edge instead of past it. Every tile centres its disc in an
  /// identical column, so every disc — the own tile included — carries the
  /// same small inset; the own tile used to add the caret's width to its
  /// column alone and sat 9 px further in than its neighbours.
  final double horizontalPadding;

  /// The name/status column. It scales with the reader's text preference the
  /// way the two "add" and own-tile columns already did — a fixed 67 px broke
  /// "Dostępny" mid-word at 200 %.
  double _labelWidth(BuildContext context) => MediaQuery.textScalerOf(
    context,
  ).scale(avatarRadius * (expandedLabels ? 3.2 : 2.4));

  /// Outer disc: avatar + a 2 px gap + the 2 px ring slot on each side —
  /// the same box [HomeFriendTile] lays out whether or not a ring is painted,
  /// so the rail's pitch never changes when a Voice Moment arrives.
  double get _discSize => avatarRadius * 2 + 8;

  @override
  Widget build(BuildContext context) {
    final friendStream = friends;
    final profileStream = profile;
    final resolved = friendsSnapshot;
    if (friendStream == null && profileStream == null && resolved == null) {
      return const SizedBox.shrink();
    }
    return StreamBuilder<UserProfile>(
      stream: profileStream,
      builder: (context, profileSnapshot) => resolved != null
          ? _buildStrip(
              context,
              profile: profileSnapshot.data,
              hasProfileStream: profileStream != null,
              friends: resolved,
              hasFriendStream: true,
            )
          : StreamBuilder<List<FriendUser>>(
              stream: friendStream,
              builder: (context, friendSnapshot) => _buildStrip(
                context,
                profile: profileSnapshot.data,
                hasProfileStream: profileStream != null,
                friends: friendSnapshot,
                hasFriendStream: friendStream != null,
              ),
            ),
    );
  }

  Widget _buildStrip(
    BuildContext context, {
    required UserProfile? profile,
    required bool hasProfileStream,
    required AsyncSnapshot<List<FriendUser>> friends,
    required bool hasFriendStream,
  }) {
    final copy = AppLocalizations.of(context);
    final people = [...(friends.data ?? const <FriendUser>[])]
      ..sort((a, b) {
        if (a.isOnline != b.isOnline) return a.isOnline ? -1 : 1;
        return a.displayName.toLowerCase().compareTo(
          b.displayName.toLowerCase(),
        );
      });
    // A missing friend stream (no session for friends) is neither loading
    // nor an error: the row simply holds the own tile.
    final failed = hasFriendStream && friends.hasError;
    final loading =
        hasFriendStream &&
        !failed &&
        !friends.hasData &&
        friends.connectionState == ConnectionState.waiting;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The SAME heading every other Home section draws — one type ramp,
        // one label, one right edge, and the section rhythm (24 above,
        // 16 below) owned in one place rather than by a bespoke row that
        // sat 18 px inboard of every neighbour.
        Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: HomeSectionHeader(
            title: copy.homeYourPeople,
            seeAllKey: const ValueKey('home-people-see-all'),
            seeAllLabel: copy.homeSeeAllPeople,
            scale: expandedLabels
                ? HomeSectionHeaderScale.expanded
                : HomeSectionHeaderScale.compact,
            onSeeAll: onSeeAll,
          ),
        ),
        // Intrinsic height, not a guessed one: the tile is an avatar
        // plus two text lines that both scale, and any fixed height
        // clips the status label at 200 % text. Friends are bounded
        // (tens), so building them all costs nothing.
        SingleChildScrollView(
          key: const ValueKey('home-people-strip'),
          scrollDirection: Axis.horizontal,
          // Full-bleed: the gutter is the scroll view's own padding, so the
          // first tile starts at the page margin and the rest scroll under
          // the frame edge rather than painting past the layout (the rail
          // used to reach x = 391.9 on a 390 px screen).
          clipBehavior: Clip.hardEdge,
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasProfileStream)
                profile == null
                    ? _PendingOwnTile(discSize: _discSize)
                    : _ownTile(context, profile, copy),
              if (loading) ...[
                if (hasProfileStream) const SizedBox(width: AppRhythm.item),
                _LoadingSlot(discSize: _discSize),
              ] else if (!failed)
                for (final friend in people) ...[
                  if (friend != people.first || hasProfileStream)
                    const SizedBox(width: AppRhythm.item),
                  HomeFriendTile(
                    key: ValueKey('home-person-${friend.id}'),
                    displayName: friend.displayName,
                    userId: friend.id,
                    photoUrl: friend.photoUrl,
                    mediaRevision: friend.profileUpdatedAt,
                    avatarRadius: avatarRadius,
                    labelWidth: _labelWidth(context),
                    status: PeopleStatus.fromPresence(
                      isOnline: friend.isOnline,
                      availability: friend.availability,
                    ),
                    voice: voiceByFriendId[friend.id],
                    onOpenVoice: onOpenVoice,
                    onOpenProfile: () => showProfilePreview(
                      context,
                      userId: friend.id,
                      displayName: friend.displayName,
                      photoUrl: friend.photoUrl,
                    ),
                  ),
                ],
              // ALWAYS last — not only when the list is empty, and not only
              // when the read succeeded: growing the circle is a standing
              // action, and a failed friends read is precisely the state in
              // which the reader is most likely to want it. The error card
              // below the rail explains the failure; it does not have to
              // cost the reader an unrelated door.
              if (hasProfileStream || people.isNotEmpty || loading || failed)
                const SizedBox(width: AppRhythm.item),
              _AddFriendsTile(
                discSize: _discSize,
                // A primary action is not a person-name preview: keep its
                // complete localized verb visible.
                labelWidth: MediaQuery.textScalerOf(context).scale(84),
                onTap: onSeeAll,
              ),
            ],
          ),
        ),
        if (failed)
          Padding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              AppRhythm.item,
              horizontalPadding,
              0,
            ),
            child: HomeSectionError(
              key: const ValueKey('home-people-error'),
              error: friends.error,
              message: copy.text(
                'Friends could not be loaded.',
                'Nie udało się wczytać znajomych.',
              ),
              onRetry: onRetry,
            ),
          ),
      ],
    );
  }

  Widget _ownTile(
    BuildContext context,
    UserProfile profile,
    AppLocalizations copy,
  ) {
    final label = profile.availability.localizedLabel(copy);
    final action = copy.template(
      'Availability: {status}. Change',
      'Dostępność: {status}. Zmień',
      values: <String, Object>{'status': label},
    );
    // Deliberately NOT `PeopleStatusAvatar`: its RING means presence, and two
    // discs along this rail a ring means "new Voice Moment" (the join
    // identity). One rail may not carry one mark with two meanings — in Pearl
    // the two colours are near neighbours — so the own tile uses the rail's
    // own tile with presence as the dot plus the word, and leaves the ring
    // slot laid out but neutral.
    return HomeFriendTile(
      key: const ValueKey('home-people-me'),
      displayName: copy.homeYou,
      userId: profile.uid,
      photoUrl: profile.photoUrl,
      mediaRevision: profile.profileUpdatedAt,
      avatarRadius: avatarRadius,
      // The caret rides the status line, so the column only widens when the
      // chosen availability actually needs the room ("Nie przeszkadzać"):
      // for every ordinary label the own tile's column is its siblings', and
      // the first disc stops sitting 9 px inboard of the page margin.
      labelWidth: math.max(
        _labelWidth(context),
        HomeFriendTile.statusColumnMinimumWidth(
          context,
          label,
          showCaret: true,
        ),
      ),
      status: PeopleStatus.fromOwnAvailability(profile.availability),
      statusLabel: label,
      showChangeCaret: true,
      // The visible name leads, then the chip's exact phrase: the tile
      // prints "You" under the avatar, so the accessible name has to contain
      // it (WCAG 2.5.3 Label in Name — "tap You" must work), and a reader
      // moving along the rail needs to hear which tile is their own before
      // the status. The action wording stays byte-identical to
      // AvailabilityChip's, in every locale.
      semanticLabel: '${copy.homeYou}. $action',
      // No optimistic state: `watchCurrentProfile` replays the merged write
      // from the local cache, and the picker already reports a failure.
      onOpenProfile: () => showAvailabilityPicker(
        context,
        current: profile.availability,
        presenceService: presenceService,
      ),
    );
  }
}

/// The own slot before the profile has emitted. Never a guessed ring and
/// never an interactive tile — opening the picker with a guessed `current`
/// could write a state the account did not choose.
class _PendingOwnTile extends StatelessWidget {
  const _PendingOwnTile({required this.discSize});

  final double discSize;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return ExcludeSemantics(
      child: Container(
        key: const ValueKey('home-people-me-pending'),
        width: discSize,
        height: discSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: palette.surfaceRaised,
          border: Border.all(color: palette.border, width: 1.5),
        ),
      ),
    );
  }
}

/// One disc-sized slot with a spinner: the friends read is in flight. No
/// fake names, no shimmer rows.
class _LoadingSlot extends StatelessWidget {
  const _LoadingSlot({required this.discSize});

  final double discSize;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('home-people-loading'),
      width: discSize,
      height: discSize,
      child: const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

/// The loaded-and-empty state: one tile that leads to the Friends tab,
/// which owns Add friend and "People you may know".
class _AddFriendsTile extends StatelessWidget {
  const _AddFriendsTile({
    required this.discSize,
    required this.labelWidth,
    required this.onTap,
  });

  final double discSize;
  final double labelWidth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final label = copy.homeAddFriends;
    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      label: label,
      onTap: onTap,
      child: PeopleTileInk(
        key: const ValueKey('home-people-add'),
        onTap: onTap,
        // No padding of its own: the rail owns the pitch, so this tile's
        // layout box is its ink box like every other tile in the row.
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Dashed, with a "+": the one mark on Home that says "this is a
            // slot you can fill". A solid ring reads as a disabled avatar.
            HomeDashedOutline(
              size: discSize,
              color: palette.borderStrong,
              child: Icon(
                Icons.add_rounded,
                size: 22,
                color: palette.interactiveForeground,
              ),
            ),
            const SizedBox(height: AppRhythm.tight),
            SizedBox(
              width: labelWidth,
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
