const { onDocumentCreated, onDocumentDeleted } = require(
  "firebase-functions/v2/firestore",
);
const { FieldValue } = require("firebase-admin/firestore");
const { logger } = require("firebase-functions/v2");

const { db } = require("../utils/firestore");

const REGION = "europe-west1";

// WHY THESE EXIST.
//
// Friend-request, acceptance and follow notifications used to be a
// SECOND client write issued after the source write, from inside a
// `try { ... } catch (_) {}`. Three consequences, all of which bit:
//
//  - the notification was not a consequence of the authoritative event,
//    it was a best-effort follow-up. Anything that stopped the client
//    between the two writes — a denied rule, a dropped connection, a
//    closed tab — lost the notification permanently, with no retry;
//  - every failure was silent. There was no log, no counter, nothing to
//    look at. The outage could only be found by a human noticing;
//  - the recipient, actor, type and routing fields were all chosen by
//    the sender's client, so rules had to spend real complexity making
//    them unforgeable.
//
// Deriving them from the source document instead fixes all three: the
// trigger fires from the committed write, Cloud Functions retries it,
// and every field comes from the server. The client cannot choose a
// recipient, an actor, a type or a timestamp, because the client is no
// longer in the path.
//
// Ids are deterministic, so an at-least-once redelivery overwrites its
// own record instead of appending a second one.

const MAX_NAME = 80;

/// How close a friendship's creation must be to the request deletion for
/// the deletion to count as an acceptance. Acceptance commits both in one
/// transaction, so the real gap is milliseconds; this is slack for clock
/// skew, not a guess.
const ACCEPTANCE_WINDOW_MS = 60 * 1000;

/// Public display fields only. Email, phone, provider data, roles,
/// moderation state and preferences never enter a notification.
async function publicActor(uid) {
  const snapshot = await db.collection("users").doc(uid).get();
  const data = snapshot.data() || {};
  const name = typeof data.displayName === "string" ? data.displayName.trim() : "";
  return {
    exists: snapshot.exists,
    banned: data.banned === true,
    // A deleted or nameless actor renders as the same neutral fallback
    // the client model already uses, rather than an empty row.
    actorName: name ? name.slice(0, MAX_NAME) : "YO Voice user",
    actorPhotoUrl: typeof data.photoUrl === "string" ? data.photoUrl : null,
  };
}

async function isBlockedEitherWay(a, b) {
  const [ab, ba] = await Promise.all([
    db.doc(`users/${a}/blocked/${b}`).get(),
    db.doc(`users/${b}/blocked/${a}`).get(),
  ]);
  return ab.exists || ba.exists;
}

/// The single place a social notification is written.
///
/// `entryId` is deterministic on the authoritative event, so a retry is
/// an overwrite. `bellSuppressed` is always written — the bell's indexed
/// query cannot see a document that lacks the field.
async function writeSocialNotification({
  recipientId,
  actorId,
  type,
  entryId,
  targetId = null,
  targetLabel = null,
}) {
  if (!recipientId || !actorId || recipientId === actorId) return "skipped:self";

  const [actor, recipient, blocked] = await Promise.all([
    publicActor(actorId),
    db.collection("users").doc(recipientId).get(),
    isBlockedEitherWay(actorId, recipientId),
  ]);

  if (!recipient.exists) return "skipped:no-recipient";
  if (!actor.exists) return "skipped:no-actor";
  if (actor.banned) return "skipped:actor-banned";
  if (recipient.data()?.banned === true) return "skipped:recipient-banned";
  if (blocked) return "skipped:blocked";

  await db
    .collection("users")
    .doc(recipientId)
    .collection("notifications")
    .doc(entryId)
    .set({
      type,
      actorId,
      actorName: actor.actorName,
      actorPhotoUrl: actor.actorPhotoUrl,
      targetId,
      targetLabel,
      isRead: false,
      createdAt: FieldValue.serverTimestamp(),
      dedupeKey: entryId,
      // These three are bell events by definition. Chat unread state is
      // a different surface and is never duplicated here.
      bellSuppressed: false,
    });

  return "written";
}

// users/{userId}/friendRequests/{senderId} — the recipient's copy, so
// the recipient IS userId and the actor IS senderId. Neither is supplied
// by the caller.
const onFriendRequestCreated = onDocumentCreated(
  {
    document: "users/{userId}/friendRequests/{senderId}",
    region: REGION,
  },
  async (event) => {
    const { userId, senderId } = event.params;
    const outcome = await writeSocialNotification({
      recipientId: userId,
      actorId: senderId,
      type: "friendRequest",
      entryId: `friendRequest_${senderId}`,
    });
    logger.info("friendRequest notification", { userId, senderId, outcome });
  },
);

// The request document is removed on accept, decline AND cancel. What
// separates them is whether a friendship now exists: the acceptance
// transaction writes both friends documents and deletes the request in
// one commit, so by the time this runs the friendship is readable.
//
// Direction matters and is unambiguous here. The document lived under
// the RECIPIENT (userId), so userId is the person who accepted and
// senderId is the original requester — the one who gets told.
//
// This also covers the mutual-accept path in sendFriendRequest, where A
// sends a request to B while B's request to A is already pending: A's
// copy is deleted, the friendship exists, and B correctly learns that A
// accepted.
const onFriendRequestResolved = onDocumentDeleted(
  {
    document: "users/{userId}/friendRequests/{senderId}",
    region: REGION,
  },
  async (event) => {
    const { userId, senderId } = event.params;

    const friendship = await db.doc(`users/${userId}/friends/${senderId}`).get();
    if (!friendship.exists) {
      // Declined, cancelled, or removed by blockUser — which deletes the
      // friendship and both request documents in ONE transaction, so by
      // the time this runs there is no friendship to find. Nothing
      // happened that the other side should be told about, and inventing
      // a notification here would be exactly the "invented notification"
      // case.
      logger.info("friendRequest resolved without acceptance", {
        userId,
        senderId,
        reason: "no friendship",
      });
      return;
    }

    // Existence alone is not proof of acceptance. A STALE request
    // document sitting alongside an already-established friendship would
    // otherwise turn any later deletion of it — administrative cleanup,
    // an account teardown, a migration — into "X accepted your friend
    // request", years after the fact.
    //
    // Acceptance writes the friendship in the SAME transaction that
    // deletes the request, so a genuine acceptance has a friendship
    // created at the moment of this event. The comparison is against
    // `event.time` (the commit time of the deletion), not `now`, so it
    // gives the same answer on every retry of the same event.
    const createdAt = friendship.data()?.createdAt;
    const createdMs =
      createdAt && typeof createdAt.toMillis === "function"
        ? createdAt.toMillis()
        : null;
    const eventMs = Date.parse(event.time);

    if (createdMs === null) {
      // A legacy friendship with no timestamp cannot be dated, so it
      // cannot be shown to be new. Failing closed here loses at most one
      // notification for a pre-existing friendship; failing open invents
      // an acceptance that never happened.
      logger.info("friendRequest resolved without acceptance", {
        userId,
        senderId,
        reason: "friendship has no createdAt",
      });
      return;
    }

    if (Math.abs(eventMs - createdMs) > ACCEPTANCE_WINDOW_MS) {
      logger.info("friendRequest resolved without acceptance", {
        userId,
        senderId,
        reason: "friendship predates this deletion",
        ageMs: eventMs - createdMs,
      });
      return;
    }

    const outcome = await writeSocialNotification({
      recipientId: senderId,
      actorId: userId,
      type: "friendAccepted",
      entryId: `friendAccepted_${userId}`,
    });
    logger.info("friendAccepted notification", { userId, senderId, outcome });
  },
);

// users/{userId}/followers/{followerId} — again the recipient is the
// path owner. A repeat follow rewrites the same follower document and
// therefore the same deterministic notification id, so re-following
// cannot produce a second row. Unfollowing deletes the edge and creates
// nothing.
const onFollowerCreated = onDocumentCreated(
  {
    document: "users/{userId}/followers/{followerId}",
    region: REGION,
  },
  async (event) => {
    const { userId, followerId } = event.params;
    const outcome = await writeSocialNotification({
      recipientId: userId,
      actorId: followerId,
      type: "follow",
      entryId: `follow_${followerId}`,
    });
    logger.info("follow notification", { userId, followerId, outcome });
  },
);

module.exports = {
  onFriendRequestCreated,
  onFriendRequestResolved,
  onFollowerCreated,
  // Exported for direct unit tests; the emulator smoke test drives the
  // real triggers.
  writeSocialNotification,
};
