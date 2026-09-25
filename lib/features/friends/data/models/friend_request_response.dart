import 'friend_user.dart';

/// What an explicit Accept or Decline actually did.
///
/// A friend request is a consent decision, so the answer the user sees must
/// be the one the server gave. The stale outcomes exist so a request that was
/// cancelled, declined elsewhere, accepted on another device or cut off by a
/// block is described honestly instead of surfacing as a generic failure.
enum FriendRequestResponseOutcome {
  /// This tap made the two people friends.
  accepted,

  /// This tap declined the request. The sender is not told.
  declined,

  /// The request was already accepted (another device, an earlier tap).
  alreadyFriends,

  /// The request was already gone when Decline arrived.
  alreadyResolved,

  /// The request no longer exists: the sender cancelled it, it was declined
  /// elsewhere, or a block removed it.
  noLongerAvailable,

  /// One of the accounts blocked the other or is no longer active. Never
  /// says which side, on purpose.
  unavailable;

  bool get isStale => switch (this) {
    accepted || declined => false,
    alreadyFriends ||
    alreadyResolved ||
    noLongerAvailable ||
    unavailable => true,
  };
}

/// The result of an "Add friend" tap.
///
/// [status] is always the truthful relationship after the call.
/// [incomingPending] means the other person had already sent a request and
/// nothing was changed: the caller must show an explicit Accept / Decline
/// prompt. [acceptedWithoutPrompt] means the server turned the send into an
/// acceptance even though this client asked it not to — which only an older
/// Functions deployment that ignores `acceptIncoming` can do. The friendship
/// exists, so it is not an error, but it must never be presented as a plain
/// "request sent" success either.
class FriendRequestSendResult {
  const FriendRequestSendResult({
    required this.status,
    this.incomingPending = false,
    this.acceptedWithoutPrompt = false,
  });

  final FriendRelationshipStatus status;
  final bool incomingPending;
  final bool acceptedWithoutPrompt;
}
