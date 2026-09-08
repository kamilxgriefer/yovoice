import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/presence/presence_service.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/shared/widgets/profile/availability_picker.dart';
import 'package:yovoice/shared/widgets/profile/people_status_ring.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';
import 'package:yovoice/shared/widgets/states/yo_error_state.dart';

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
    this.expandedLabels = false,
    this.avatarRadius = 26,
    this.horizontalPadding = 12,
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

  /// Desktop widens the name column (`radius * 3.2` instead of `2.4`) so
  /// full names ellipsise less.
  final bool expandedLabels;
  final double avatarRadius;
  final double horizontalPadding;

  double get _labelWidth => avatarRadius * (expandedLabels ? 3.2 : 2.4);

  /// Outer disc: avatar + 2 px inner padding + 1.5 px ring on each side.
  double get _discSize => avatarRadius * 2 + 7;

  @override
  Widget build(BuildContext context) {
    final friendStream = friends;
    final profileStream = profile;
    if (friendStream == null && profileStream == null) {
      return const SizedBox.shrink();
    }
    return StreamBuilder<UserProfile>(
      stream: profileStream,
      builder: (context, profileSnapshot) => StreamBuilder<List<FriendUser>>(
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
    final palette = context.appPalette;
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
    final empty = hasFriendStream && friends.hasData && people.isEmpty;

    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding + 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    copy.text('Your people', 'Twoi znajomi'),
                    // Wraps rather than truncating, the way every other
                    // mobile section heading does at enlarged text.
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                TextButton(
                  key: const ValueKey('home-people-see-all'),
                  onPressed: onSeeAll,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(44, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: Text(copy.text('See all', 'Zobacz wszystkie')),
                ),
              ],
            ),
          ),
          // Intrinsic height, not a guessed one: the tile is an avatar
          // plus two text lines that both scale, and any fixed height
          // clips the status label at 200 % text. Friends are bounded
          // (tens), so building them all costs nothing.
          SingleChildScrollView(
            key: const ValueKey('home-people-strip'),
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasProfileStream)
                  profile == null
                      ? _PendingOwnTile(discSize: _discSize)
                      : _ownTile(context, profile, copy),
                if (loading)
                  _LoadingSlot(discSize: _discSize)
                else if (!failed)
                  for (final friend in people)
                    PeopleStatusAvatar(
                      key: ValueKey('home-person-${friend.id}'),
                      displayName: friend.displayName,
                      userId: friend.id,
                      photoUrl: friend.photoUrl,
                      radius: avatarRadius,
                      labelWidth: _labelWidth,
                      status: PeopleStatus.fromPresence(
                        isOnline: friend.isOnline,
                        availability: friend.availability,
                      ),
                      onTap: () => showProfilePreview(
                        context,
                        userId: friend.id,
                        displayName: friend.displayName,
                        photoUrl: friend.photoUrl,
                      ),
                    ),
                if (empty)
                  _AddFriendsTile(
                    discSize: _discSize,
                    labelWidth: _labelWidth,
                    onTap: onSeeAll,
                  ),
              ],
            ),
          ),
          if (failed)
            Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding + 6,
                6,
                horizontalPadding + 6,
                0,
              ),
              child: YoErrorState(
                compact: true,
                message: copy.text(
                  'Friends could not be loaded.',
                  'Nie udało się wczytać znajomych.',
                ),
                onRetry: onRetry,
              ),
            ),
        ],
      ),
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
    return PeopleStatusAvatar(
      key: const ValueKey('home-people-me'),
      displayName: copy.homeYou,
      userId: profile.uid,
      photoUrl: profile.photoUrl,
      mediaRevision: profile.profileUpdatedAt,
      radius: avatarRadius,
      labelWidth: _labelWidth,
      status: PeopleStatus.fromOwnAvailability(profile.availability),
      statusLabel: label,
      // The visible name leads, then the chip's exact phrase: the tile
      // prints "You" under the avatar, so the accessible name has to contain
      // it (WCAG 2.5.3 Label in Name — "tap You" must work), and a reader
      // moving along the rail needs to hear which tile is their own before
      // the status. The action wording stays byte-identical to
      // AvailabilityChip's, in every locale.
      semanticLabel: '${copy.homeYou}. $action',
      showChangeBadge: true,
      // No optimistic state: `watchCurrentProfile` replays the merged write
      // from the local cache, and the picker already reports a failure.
      onTap: () => showAvailabilityPicker(
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: SizedBox(
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
    final label = copy.text('Add friends', 'Dodaj znajomych');
    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      label: label,
      onTap: onTap,
      child: PeopleTileInk(
        key: const ValueKey('home-people-add'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: discSize,
                height: discSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: palette.surfaceRaised,
                  border: Border.all(color: palette.borderStrong, width: 1.5),
                ),
                child: Icon(
                  Icons.person_add_alt_1_rounded,
                  size: 22,
                  color: palette.interactiveForeground,
                ),
              ),
              const SizedBox(height: 7),
              SizedBox(
                width: labelWidth,
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
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
      ),
    );
  }
}
