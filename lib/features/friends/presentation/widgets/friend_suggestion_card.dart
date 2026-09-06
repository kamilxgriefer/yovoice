import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/social_graph_service.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/shared/widgets/identity/official_role_badge.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/profile/profile_photo_viewer.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// How much room the hosting surface gives one suggestion.
enum FriendSuggestionCardLayout {
  /// Full-width row: avatar and identity on the left, the add action on the
  /// right (stacking under it on a narrow surface or at large text). Used by
  /// the Add friends search screen.
  list,

  /// Compact vertical card sized for a horizontally scrollable rail. Used by
  /// the Friends screen's "People you may know" section.
  rail,
}

/// The one rendering of a friend suggestion.
///
/// Both surfaces that offer a server-computed suggestion — the Add friends
/// screen's "Suggested for you" list and the Friends screen's "People you may
/// know" rail — draw this widget, so the two can never drift in chrome,
/// mutual-friend wording or add-button states.
///
/// The card is display + one action only. It never computes a relationship
/// itself: [relationshipStatus] is whatever the caller learned from
/// [FriendService.sendFriendRequest], and null means "not acted on yet".
class FriendSuggestionCard extends StatelessWidget {
  const FriendSuggestionCard({
    required this.suggestion,
    required this.isProcessing,
    required this.relationshipStatus,
    required this.onPressed,
    this.profileMediaService,
    this.layout = FriendSuggestionCardLayout.list,
    super.key,
  });

  final SuggestedFriend suggestion;
  final ProfileMediaService? profileMediaService;

  /// True while this suggestion's request is in flight: the action shows a
  /// spinner and stops accepting taps.
  final bool isProcessing;

  /// Null until the caller has sent a request for this person. `requestSent`
  /// renders "Sent"; `friends` renders "Friends" (the server can accept a
  /// reciprocal pending request instead of creating a new one).
  final FriendRelationshipStatus? relationshipStatus;
  final VoidCallback onPressed;
  final FriendSuggestionCardLayout layout;

  bool get _isFriend => relationshipStatus == FriendRelationshipStatus.friends;
  bool get _isSent =>
      relationshipStatus == FriendRelationshipStatus.requestSent;
  bool get _isComplete => _isFriend || _isSent;

  /// "3 mutual friends" — the one place this sentence is built, so the
  /// singular case and the Polish genitive plural stay identical on both
  /// surfaces.
  static String mutualFriendsLabel(AppLocalizations copy, int mutualCount) {
    return mutualCount == 1
        ? copy.text('1 mutual friend', '1 wspólny znajomy')
        : copy.template(
            '{count} mutual friends',
            '{count} wspólnych znajomych',
            values: {'count': mutualCount},
          );
  }

  /// The add action, identical on both layouts.
  ///
  /// The fixed 44 px height is the established tap target on this card and
  /// keeps the rail's intrinsic height deterministic; the label is capped to
  /// one ellipsized line so no text scale can overflow it.
  Widget _action(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final copy = AppLocalizations.of(context);
    final button = FilledButton.icon(
      onPressed: isProcessing || _isComplete ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: _isFriend
            ? palette.successSurface
            : _isSent
            ? palette.warningSurface
            : colors.primary,
        disabledBackgroundColor: _isFriend
            ? palette.successSurface
            : _isSent
            ? palette.warningSurface
            : palette.surfaceMuted,
        foregroundColor: _isFriend
            ? palette.successForeground
            : _isSent
            ? palette.warningForeground
            : colors.onPrimary,
        disabledForegroundColor: _isFriend
            ? palette.successForeground
            : _isSent
            ? palette.warningForeground
            : palette.textTertiary,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      ),
      icon: isProcessing
          ? SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.onPrimary,
              ),
            )
          : Icon(
              _isComplete
                  ? Icons.check_rounded
                  : Icons.person_add_alt_1_rounded,
              size: 18,
            ),
      label: Text(
        _isFriend
            ? copy.text('Friends', 'Znajomi')
            : (_isSent
                  ? copy.text('Sent', 'Wysłano')
                  : copy.text('Add', 'Dodaj')),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
      ),
    );

    return SizedBox(height: 44, child: button);
  }

  @override
  Widget build(BuildContext context) {
    return layout == FriendSuggestionCardLayout.rail
        ? _buildRail(context)
        : _buildList(context);
  }

  Widget _buildList(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final identity = Row(
      children: [
        Container(
          width: 52,
          height: 52,
          padding: const EdgeInsets.all(2),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [Color(0xFFC32BFF), Color(0xFF6D25FF)],
            ),
          ),
          child: ProfilePhotoButton(
            userId: suggestion.uid,
            displayName: suggestion.displayName,
            mediaRevision: suggestion.profileUpdatedAt,
            mediaService: profileMediaService,
            minimumSize: const Size(48, 48),
            child: ClipOval(
              child: UserAvatar(
                radius: 24,
                userId: suggestion.uid,
                mediaRevision: suggestion.profileUpdatedAt,
                mediaService: profileMediaService,
                displayName: suggestion.displayName,
                backgroundColor: palette.surfaceSunken,
              ),
            ),
          ),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    suggestion.displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  UserIdentityBadges(uid: suggestion.uid),
                ],
              ),
              if (suggestion.mutualCount > 0) ...[
                const SizedBox(height: 4),
                Text(
                  mutualFriendsLabel(copy, suggestion.mutualCount),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.textSecondary, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ],
    );

    return Container(
      key: ValueKey('friend-suggestion-${suggestion.uid}'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: palette.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stack =
              constraints.maxWidth < 360 ||
              MediaQuery.textScalerOf(context).scale(1) >= 1.5;
          if (stack) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                identity,
                const SizedBox(height: 12),
                _action(context),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: identity),
              const SizedBox(width: 10),
              _action(context),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRail(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    return Container(
      key: ValueKey('friend-suggestion-rail-${suggestion.uid}'),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 60,
              height: 60,
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Color(0xFFC32BFF), Color(0xFF6D25FF)],
                ),
              ),
              child: ProfilePhotoButton(
                userId: suggestion.uid,
                displayName: suggestion.displayName,
                mediaRevision: suggestion.profileUpdatedAt,
                mediaService: profileMediaService,
                minimumSize: const Size(56, 56),
                child: ClipOval(
                  child: UserAvatar(
                    radius: 28,
                    userId: suggestion.uid,
                    mediaRevision: suggestion.profileUpdatedAt,
                    mediaService: profileMediaService,
                    displayName: suggestion.displayName,
                    backgroundColor: palette.surfaceSunken,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            suggestion.displayName,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 14,
              height: 1.2,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          // The icon variant keeps the official role visible (with its label
          // in a tooltip) without a pill that would clip in a dense rail.
          Center(
            child: UserIdentityBadges(
              uid: suggestion.uid,
              variant: IdentityBadgeVariant.icon,
            ),
          ),
          if (suggestion.mutualCount > 0) ...[
            const SizedBox(height: 6),
            Text(
              mutualFriendsLabel(copy, suggestion.mutualCount),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 12,
                height: 1.25,
              ),
            ),
          ],
          const SizedBox(height: 12),
          // Pushes every card's action to the same baseline once the rail's
          // IntrinsicHeight has equalised the column heights.
          const Spacer(),
          _action(context),
        ],
      ),
    );
  }
}
