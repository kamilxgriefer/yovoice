const { onDocumentCreated, onDocumentWritten } = require(
  "firebase-functions/v2/firestore",
);
const { logger } = require("firebase-functions/v2");
const { FieldPath, FieldValue } = require("firebase-admin/firestore");

const { db } = require("../utils/firestore");
const { digest } = require("../integrity/guards");
const { createNotificationForEvent } = require("./canonical");
const {
  documentGeneration,
  notificationSourceIsCurrent,
} = require("./social_source");

const REGION = "europe-west1";
const MAX_LABEL = 120;
const ROOM_LIVE_FANOUT_CONCURRENCY = 16;
const ROOM_LIVE_FOLLOWER_PAGE_SIZE = 200;

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

async function mapWithConcurrency(items, concurrency, operation) {
  const outcomes = new Array(items.length);
  let next = 0;
  const workers = Array.from(
    { length: Math.min(concurrency, items.length) },
    async () => {
      while (next < items.length) {
        const index = next;
        next += 1;
        outcomes[index] = await operation(items[index], index);
      }
    },
  );
  await Promise.all(workers);
  return outcomes;
}

async function listFollowerPage({
  afterId,
  firestore,
  hostId,
  pageSize,
}) {
  let query = firestore.collection(`users/${hostId}/followers`)
    .orderBy(FieldPath.documentId())
    .limit(pageSize);
  if (afterId !== null) query = query.startAfter(afterId);
  const snapshot = await query.get();
  return snapshot.docs.map((document) => document.id);
}

async function fanOutRoomLiveFollowers({
  afterId: initialAfterId = null,
  concurrency = ROOM_LIVE_FANOUT_CONCURRENCY,
  firestore = db,
  hostId,
  notify,
  pageLoader = listFollowerPage,
  pageSize = ROOM_LIVE_FOLLOWER_PAGE_SIZE,
  maxPages = 1,
}) {
  if (!Number.isSafeInteger(concurrency) || concurrency < 1 || concurrency > 32) {
    throw new TypeError("fanout concurrency must be between 1 and 32.");
  }
  if (!Number.isSafeInteger(pageSize) || pageSize < 1 || pageSize > 500) {
    throw new TypeError("fanout page size must be between 1 and 500.");
  }
  if (!Number.isSafeInteger(maxPages) || maxPages < 1 || maxPages > 5) {
    throw new TypeError("fanout maxPages must be between 1 and 5.");
  }
  let afterId = initialAfterId;
  let followers = 0;
  let pages = 0;
  let written = 0;
  while (pages < maxPages) {
    const ids = await pageLoader({
      afterId,
      firestore,
      hostId,
      pageSize,
    });
    if (!Array.isArray(ids) || ids.length > pageSize) {
      throw new TypeError("follower page is malformed.");
    }
    if (ids.length === 0) {
      return { afterId, complete: true, followers, pages, written };
    }
    if (
      ids.some((id) => typeof id !== "string" || id.length < 1) ||
      new Set(ids).size !== ids.length ||
      ids[ids.length - 1] === afterId
    ) {
      throw new TypeError("follower page cursor is malformed.");
    }
    const outcomes = await mapWithConcurrency(ids, concurrency, notify);
    followers += ids.length;
    pages += 1;
    written += outcomes.filter((outcome) => outcome === "written").length;
    afterId = ids[ids.length - 1];
    if (ids.length < pageSize) {
      return { afterId, complete: true, followers, pages, written };
    }
  }
  return { afterId, complete: false, followers, pages, written };
}

function roomLiveFanoutOutboxReference(roomId, session, firestore = db) {
  const id = `room_live_${digest("room-live-fanout", roomId, session)
    .slice(0, 48)}`;
  return firestore.doc(`roomLiveFanoutOutbox/${id}`);
}

function validOutbox(data) {
  return data?.schemaVersion === 1 &&
    typeof data.roomId === "string" &&
    typeof data.hostId === "string" &&
    typeof data.session === "string" &&
    typeof data.sourcePath === "string" &&
    typeof data.sourceGeneration === "string" &&
    typeof data.targetLabel === "string" &&
    (data.afterId === null || typeof data.afterId === "string") &&
    ["pending", "complete"].includes(data.status) &&
    Number.isSafeInteger(data.followers) && data.followers >= 0 &&
    Number.isSafeInteger(data.pages) && data.pages >= 0 &&
    Number.isSafeInteger(data.written) && data.written >= 0;
}

async function ensureRoomLiveFanoutOutbox({
  hostId,
  roomId,
  session,
  sourceGeneration,
  sourcePath,
  targetLabel,
}) {
  const reference = roomLiveFanoutOutboxReference(roomId, session);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    if (snapshot.exists) {
      const existing = snapshot.data();
      if (
        !validOutbox(existing) ||
        existing.roomId !== roomId ||
        existing.hostId !== hostId ||
        existing.session !== session ||
        existing.sourceGeneration !== sourceGeneration ||
        existing.sourcePath !== sourcePath ||
        existing.targetLabel !== targetLabel
      ) {
        throw new Error("room-live fanout outbox identity conflict");
      }
      return;
    }
    transaction.create(reference, {
      schemaVersion: 1,
      roomId,
      hostId,
      session,
      sourcePath,
      sourceGeneration,
      targetLabel,
      afterId: null,
      status: "pending",
      followers: 0,
      pages: 0,
      written: 0,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  return reference;
}

async function processRoomLiveFanoutOutbox(reference, {
  firestore = db,
  pageLoader = listFollowerPage,
  notify = null,
} = {}) {
  const snapshot = await reference.get();
  if (!snapshot.exists) return { state: "missing" };
  const state = snapshot.data();
  if (!validOutbox(state)) throw new Error("malformed room-live fanout outbox");
  if (state.status === "complete") return { state: "complete" };
  const cursor = state.afterId;
  const operation = notify ?? (async (followerId) => {
    const notificationId = `live_${state.roomId}_${state.session}`;
    const notificationShape = {
      type: "liveStarted",
      actorId: state.hostId,
      targetId: state.roomId,
      sourcePath: state.sourcePath,
      sourceGeneration: state.sourceGeneration,
    };
    return writeActivityNotification({
      recipientId: followerId,
      actorId: state.hostId,
      type: "liveStarted",
      entryId: notificationId,
      targetId: state.roomId,
      targetLabel: state.targetLabel,
      eventId: `room-live:${state.roomId}:${state.session}:${followerId}`,
      sourcePath: state.sourcePath,
      sourceGeneration: state.sourceGeneration,
      validate: (transaction) => notificationSourceIsCurrent({
        recipientId: followerId,
        notificationId,
        notification: notificationShape,
        firestore,
        reader: transaction,
      }),
    });
  });
  const page = await fanOutRoomLiveFollowers({
    afterId: cursor,
    firestore,
    hostId: state.hostId,
    maxPages: 1,
    notify: operation,
    pageLoader,
  });
  const commit = await firestore.runTransaction(async (transaction) => {
    const currentSnapshot = await transaction.get(reference);
    const current = currentSnapshot.data();
    if (
      !currentSnapshot.exists ||
      !validOutbox(current) ||
      current.status !== "pending" ||
      current.afterId !== cursor
    ) {
      return "stale";
    }
    transaction.update(reference, {
      afterId: page.afterId,
      status: page.complete ? "complete" : "pending",
      followers: current.followers + page.followers,
      pages: current.pages + page.pages,
      written: current.written + page.written,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return page.complete ? "complete" : "pending";
  });
  return { ...page, state: commit };
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
  const session = typeof room.voiceSessionId === "string" &&
      /^[A-Za-z0-9_-]{8,128}$/u.test(room.voiceSessionId)
    ? room.voiceSessionId
    : after.updateTime?.toMillis?.() || Date.now();
  const sourcePath = `rooms/${event.params.roomId}`;
  const sourceGeneration = documentGeneration(after, "updateTime");
  if (typeof sourceGeneration !== "string") return;
  const reference = await ensureRoomLiveFanoutOutbox({
    hostId,
    roomId: event.params.roomId,
    session: String(session),
    sourceGeneration,
    sourcePath,
    targetLabel: cleanText(room.name, "Live room", MAX_LABEL),
  });
  // Process one bounded page immediately. The outbox update trigger advances
  // every later page; a timeout or retry resumes from the committed cursor.
  const fanout = await processRoomLiveFanoutOutbox(reference);
  logger.info("live room notifications", {
    roomId: event.params.roomId,
    ...fanout,
  });
}

async function handleRoomLiveFanoutOutboxWritten(event) {
  const after = event.data?.after;
  if (!after?.exists || after.data()?.status !== "pending") return;
  return processRoomLiveFanoutOutbox(after.ref);
}

const onRoomLiveChanged = onDocumentWritten(
  {
    document: "rooms/{roomId}",
    region: REGION,
    memory: "512MiB",
    timeoutSeconds: 300,
    maxInstances: 25,
    retry: true,
  },
  handleRoomLiveChanged,
);

const onRoomLiveFanoutOutboxWritten = onDocumentWritten(
  {
    document: "roomLiveFanoutOutbox/{outboxId}",
    region: REGION,
    memory: "512MiB",
    timeoutSeconds: 120,
    maxInstances: 50,
    retry: true,
  },
  handleRoomLiveFanoutOutboxWritten,
);

module.exports = {
  ROOM_LIVE_FANOUT_CONCURRENCY,
  ROOM_LIVE_FOLLOWER_PAGE_SIZE,
  fanOutRoomLiveFollowers,
  handleDirectMessageCreated,
  handleRoomLiveFanoutOutboxWritten,
  handleRoomLiveChanged,
  onRoomLiveFanoutOutboxWritten,
  onDirectMessageCreated,
  onRoomLiveChanged,
  processRoomLiveFanoutOutbox,
  roomLiveFanoutOutboxReference,
  writeActivityNotification,
};
