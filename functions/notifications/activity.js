const { onDocumentCreated, onDocumentWritten } = require(
  "firebase-functions/v2/firestore",
);
const { logger } = require("firebase-functions/v2");

const { db } = require("../utils/firestore");
const { createNotificationForEvent } = require("./canonical");
const {
  documentGeneration,
  notificationSourceIsCurrent,
} = require("./social_source");

const REGION = "europe-west1";
const MAX_LABEL = 120;

function cleanText(value, fallback, maxLength) {
  if (typeof value !== "string") return fallback;
  const valueTrimmed = value.trim();
  return valueTrimmed ? valueTrimmed.slice(0, maxLength) : fallback;
}

async function writeActivityNotification({
  recipientId,
  actorId,
  type,
  entryId,
  targetId,
  targetLabel = null,
  bellSuppressed = false,
  eventId = null,
  sourcePath = null,
  sourceGeneration = null,
  validate = null,
}) {
  if (!recipientId || !actorId || recipientId === actorId) return "skipped:self";
  const canonicalEventId = eventId ||
    `activity:${type}:${recipientId}:${entryId}`;
  return createNotificationForEvent({
    eventId: canonicalEventId,
    recipientId,
    actorId,
    type,
    notificationId: entryId,
    targetId,
    targetLabel,
    bellSuppressed,
    sourcePath,
    sourceGeneration,
    validate,
  });
}

// A message notification is derived from the committed message, not from a
// second best-effort client write. This guarantees that a delivered message
// and its push cannot drift apart when the sender closes the app or loses
// connectivity immediately after sending.
async function handleDirectMessageCreated(event) {
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

  const friendship = await db.doc(
    `users/${recipientId}/friends/${senderId}`,
  ).get();

  const isReply = message.replyToSenderId === recipientId;
  const notificationId = `message_${messageId}`;
  const sourcePath = `conversations/${conversationId}/messages/${messageId}`;
  const sourceGeneration = documentGeneration(event.data, "createTime");
  const notificationShape = {
    type: isReply ? "reply" : "directMessage",
    actorId: senderId,
    targetId: conversationId,
    sourcePath,
    sourceGeneration,
  };
  const outcome = await writeActivityNotification({
    recipientId,
    actorId: senderId,
    type: notificationShape.type,
    entryId: notificationId,
    targetId: conversationId,
    bellSuppressed: friendship.exists,
    // Derive this from the immutable source identity, not from the transport
    // event id. It stays stable even if the platform redelivers the same
    // document generation under a different CloudEvent envelope.
    eventId: `direct-message:${conversationId}:${messageId}:${recipientId}`,
    sourcePath,
    sourceGeneration,
    validate: (transaction) => notificationSourceIsCurrent({
      recipientId,
      notificationId,
      notification: notificationShape,
      firestore: db,
      reader: transaction,
    }),
  });
  logger.info("direct message notification", {
    conversationId,
    messageId,
    recipientId,
    outcome,
  });
}

const onDirectMessageCreated = onDocumentCreated(
  {
    document: "conversations/{conversationId}/messages/{messageId}",
    region: REGION,
  },
  handleDirectMessageCreated,
);

// Followers are notified when a public room becomes live. Creation with
// isLive=true and a later false->true transition are both covered. The
// source document's update time makes retries idempotent while still allowing
// a new notification for the host's next live session.
async function handleRoomLiveChanged(event) {
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
  const sourcePath = `rooms/${event.params.roomId}`;
  const sourceGeneration = documentGeneration(after, "updateTime");
  const outcomes = await Promise.all(
    followers.docs.map((follower) => {
      const notificationId = `live_${event.params.roomId}_${session}`;
      const notificationShape = {
        type: "liveStarted",
        actorId: hostId,
        targetId: event.params.roomId,
        sourcePath,
        sourceGeneration,
      };
      return writeActivityNotification({
        recipientId: follower.id,
        actorId: hostId,
        type: "liveStarted",
        entryId: notificationId,
        targetId: event.params.roomId,
        targetLabel: cleanText(room.name, "Live room", MAX_LABEL),
        eventId: `room-live:${event.params.roomId}:${session}:${follower.id}`,
        sourcePath,
        sourceGeneration,
        validate: (transaction) => notificationSourceIsCurrent({
          recipientId: follower.id,
          notificationId,
          notification: notificationShape,
          firestore: db,
          reader: transaction,
        }),
      });
    }),
  );
  logger.info("live room notifications", {
    roomId: event.params.roomId,
    followers: followers.size,
    written: outcomes.filter((outcome) => outcome === "written").length,
  });
}

const onRoomLiveChanged = onDocumentWritten(
  { document: "rooms/{roomId}", region: REGION },
  handleRoomLiveChanged,
);

module.exports = {
  handleDirectMessageCreated,
  handleRoomLiveChanged,
  onDirectMessageCreated,
  onRoomLiveChanged,
  writeActivityNotification,
};
