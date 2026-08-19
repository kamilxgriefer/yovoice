import 'package:yovoice/features/clubs/data/models/club_member.dart';
import 'package:yovoice/features/clubs/data/models/club_message.dart';

/// Who may remove which club chat message — stated once, for both the
/// screen and the service.
///
/// `firestore.rules` accepts a removal on exactly two predicates: the
/// AUTHOR retracting their own message, or a club MODERATOR (and above)
/// removing somebody else's — never the club owner's, whose messages stay
/// with staff tooling (`adminDeleteMessage`). Editing is not expressible
/// by anyone: `content` can only ever become `''`.
///
/// `ClubChatScreen` asks this object whether to OFFER removal and
/// `ClubChatService.deleteMessage` asks the same object whether to
/// ATTEMPT it, so a confirmation dialog can never be shown for a write
/// the rules would refuse. Splitting the two would let the affordance
/// drift away from the rule — which is precisely the failure this
/// feature is fixing.
class ClubChatAuthority {
  const ClubChatAuthority({
    required this.viewerId,
    this.role,
    this.clubOwnerId,
  });

  /// Nobody is signed in, so no message can be removed.
  const ClubChatAuthority.signedOut()
    : viewerId = '',
      role = null,
      clubOwnerId = null;

  /// The signed-in account acting on the chat. Empty when signed out.
  final String viewerId;

  /// The viewer's role in this club, or null while the membership
  /// document has not arrived yet — and also when the viewer is not a
  /// member at all. Both cases withhold moderator power, which is the
  /// safe direction: an affordance that appears a moment late is a much
  /// smaller problem than one that appears and then fails.
  final ClubRole? role;

  /// `clubs/{clubId}.ownerId`, the exact field the moderator rule
  /// compares against. Null while the club document has not arrived, or
  /// when it could not be read — again withholding moderator removal
  /// rather than offering an action whose legality is unknown.
  final String? clubOwnerId;

  bool get canModerate => (role?.power ?? 0) >= ClubRole.moderator.power;

  bool isAuthorOf(ClubMessage message) =>
      viewerId.isNotEmpty && message.senderId == viewerId;

  /// Null when this viewer may remove [message]; otherwise the reason to
  /// show them, already written as product copy.
  ///
  /// Order matters: authorship is decided before ownership, so a club
  /// owner is never blocked from retracting their own message, and
  /// [clubOwnerId] is only ever consulted on the moderator path.
  String? removalRefusal(ClubMessage message) {
    if (viewerId.isEmpty) {
      return 'You must be signed in to use club chat.';
    }
    if (message.isDeleted) {
      return 'This message has already been removed.';
    }
    if (isAuthorOf(message)) return null;
    if (!canModerate) {
      return 'Your role cannot remove this message.';
    }
    if (clubOwnerId == null) {
      return 'We could not confirm who owns this club. Please try again in '
          'a moment.';
    }
    if (message.senderId == clubOwnerId) {
      return 'The club owner’s messages can only be removed by YO Voice '
          'staff. Report it instead.';
    }
    return null;
  }

  bool canRemove(ClubMessage message) => removalRefusal(message) == null;

  /// True when removing [message] is an act of moderation rather than the
  /// author retracting their own words. Drives the confirmation copy, so
  /// a moderator is told plainly that the removal is attributed to them.
  bool isModeratingOthers(ClubMessage message) =>
      !isAuthorOf(message) && canRemove(message);
}
