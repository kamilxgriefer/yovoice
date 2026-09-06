import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/shared/widgets/profile/people_status_ring.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';

/// "Your people" — every friend of the signed-in account, online first, with
/// the shared availability ring.
///
/// The live-first Home shipped without it: both Home variants took a
/// `friendService` and never used it, so the only people on the screen came
/// from the follow graph, capped at two rows. An account with a dozen friends
/// therefore saw one person. This strip is the friends list itself, so the
/// count on Home matches the Friends tab.
class HomePeopleStrip extends StatelessWidget {
  const HomePeopleStrip({
    required this.friends,
    required this.onSeeAll,
    this.avatarRadius = 26,
    this.horizontalPadding = 12,
    super.key,
  });

  /// Null when no session or no Firebase — the strip then renders nothing
  /// rather than an error box on the first screen of the app.
  final Stream<List<FriendUser>>? friends;
  final VoidCallback onSeeAll;
  final double avatarRadius;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final stream = friends;
    if (stream == null) return const SizedBox.shrink();
    return StreamBuilder<List<FriendUser>>(
      stream: stream,
      builder: (context, snapshot) {
        final people = [...(snapshot.data ?? const <FriendUser>[])]
          ..sort((a, b) {
            if (a.isOnline != b.isOnline) return a.isOnline ? -1 : 1;
            return a.displayName.toLowerCase().compareTo(
              b.displayName.toLowerCase(),
            );
          });
        // No friends yet, still loading, or a failed read: Home says nothing.
        // Inventing rows here would be exactly the fake activity the product
        // rules forbid.
        if (people.isEmpty) return const SizedBox.shrink();
        final copy = AppLocalizations.of(context);
        final palette = context.appPalette;
        return Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding + 6,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        copy.text('Your people', 'Twoi znajomi'),
                        maxLines: 1,
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
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final friend in people)
                      PeopleStatusAvatar(
                        key: ValueKey('home-person-${friend.id}'),
                        displayName: friend.displayName,
                        userId: friend.id,
                        photoUrl: friend.photoUrl,
                        radius: avatarRadius,
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
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
