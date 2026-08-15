const { onDocumentCreated, onDocumentWritten } = require(
  "firebase-functions/v2/firestore",
);
const { FieldValue } = require("firebase-admin/firestore");
const { logger } = require("firebase-functions/v2");

const { db } = require("../utils/firestore");

const REGION = "europe-west1";
const MAX_NAME = 80;
const MAX_LABEL = 120;

function cleanText(value, fallback, maxLength) {
  if (typeof value !== "string") return fallback;
  const valueTrimmed = value.trim();
  return valueTrimmed ? valueTrimmed.slice(0, maxLength) : fallback;
}

async function blockedEitherWay(firstId, secondId) {
  const [first, second] = await Promise.all([
    db.doc(`users/${firstId}/blocked/${secondId}`).get(),
    db.doc(`users/${secondId}/blocked/${firstId}`).get(),
  ]);
  return first.exists || second.exists;
}

async function writeActivityNotification({
  recipientId,
  actorId,
  type,
  entryId,
  targetId,
  targetLabel = null,
  bellSuppressed = false,
}) {
  if (!recipientId || !actorId || recipientId === actorId) return "skipped:self";

  const [actor, recipient, blocked] = await Promise.all([
    db.doc(`users/${actorId}`).get(),
    db.doc(`users/${recipientId}`).get(),
    blockedEitherWay(actorId, recipientId),
  ]);
  if (!actor.exists || !recipient.exists) return "skipped:missing-user";
  if (actor.data()?.banned === true || recipient.data()?.banned === true) {
    return "skipped:banned";
  }
  if (blocked) return "skipped:blocked";

  await db.doc(`users/${recipientId}/notifications/${entryId}`).set({
    type,
    actorId,
    actorName: cleanText(actor.data()?.displayName, "YO Voice user", MAX_NAME),
    actorPhotoUrl:
      typeof actor.data()?.photoUrl === "string" ? actor.data().photoUrl : null,
    targetId: targetId || null,
    targetLabel: targetLabel
      ? cleanText(targetLabel, null, MAX_LABEL)
      : null,
    isRead: false,
    createdAt: FieldValue.serverTimestamp(),
    dedupeKey: entryId,
    bellSuppressed,
  });
  return "written";
}

// A message notification is derived from the committed message, not from a
// second best-effort client write. This guarantees that a delivered message
// and its push cannot drift apart when the sender closes the app or loses
// connectivity immediately after sending.
const onDirectMessageCreated = onDocumentCreated(
  {
    document: "conversations/{conversationId}/messages/{messageId}",
    region: REGION,
  },
  async (event) => {
    const message = event.data?.data();
    if (!message || message.isDeleted === true) return;
    const { conversationId, messageId } = event.params;
    const senderId = message.senderId;
    if (typeof senderId !== "string" || !senderId) return;

    const conversation = await db.doc(`conversations/${conversationId}`).get();
    const participantIds = conversation.data()?.participantIds;
    if (!conversation.exists || !Array.isArray(participantIds)) return;
    if (!participantIds.includes(senderId)) {
      logger.warn("Ignoring message whose sender is not a participant", {
        conversationId,
        messageId,
        senderId,
      });
      return;
    }
    const recipientId = participantIds.find((id) => id !== senderId);
    if (!recipientId) return;

    const [friendship, muted] = await Promise.all([
      db.doc(`users/${recipientId}/friends/${senderId}`).get(),
      Promise.resolve(
        Array.isArray(conversation.data()?.mutedBy) &&
          conversation.data().mutedBy.includes(recipientId),
      ),
    ]);
    if (muted) return;

    const isReply = message.replyToSenderId === recipientId;
    const outcome = await writeActivityNotification({
      recipientId,
      actorId: senderId,
      type: isReply ? "reply" : "directMessage",
      entryId: `message_${messageId}`,
      targetId: conversationId,
      bellSuppressed: friendship.exists,
    });
    logger.info("direct message notification", {
      conversationId,
      messageId,
      recipientId,
      outcome,
    });
  },
);

// Followers are notified when a public room becomes live. Creation with
// isLive=true and a later false->true transition are both covered. The
// source document's update time makes retries idempotent while still allowing
// a new notification for the host's next live session.
const onRoomLiveChanged = onDocumentWritten(
  { document: "rooms/{roomId}", region: REGION },
  async (event) => {
    const before = event.data?.before;
    const after = event.data?.after;
    if (!after?.exists) return;
    const room = after.data();
    if (room?.isLive !== true || before?.data()?.isLive === true) return;
    if (room.visibility !== "public") return;

    const hostId = room.hostId;
    if (typeof hostId !== "string" || !hostId) return;
    const followers = await db.collection(`users/${hostId}/followers`).get();
    const session = after.updateTime?.toMillis?.() || Date.now();
    const outcomes = await Promise.all(
      followers.docs.map((follower) =>
        writeActivityNotification({
          recipientId: follower.id,
          actorId: hostId,
          type: "liveStarted",
          entryId: `live_${event.params.roomId}_${session}`,
          targetId: event.params.roomId,
          targetLabel: cleanText(room.name, "Live room", MAX_LABEL),
        }),
      ),
    );
    logger.info("live room notifications", {
      roomId: event.params.roomId,
      followers: followers.size,
      written: outcomes.filter((outcome) => outcome === "written").length,
    });
  },
);

module.exports = {
  onDirectMessageCreated,
  onRoomLiveChanged,
  writeActivityNotification,
};
