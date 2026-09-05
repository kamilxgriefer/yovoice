const {
  fail,
  requireActor,
  requireId,
  requireSafeInteger,
} = require("./guards");

const USER_CALLABLE_METHODS = Object.freeze({
  openDirectConversation: ["direct", "openDirectConversation"],
  sendDirectMessage: ["direct", "sendDirectMessage"],
  reserveDirectMessageAttachment: ["direct", "reserveDirectMessageAttachment"],
  finalizeDirectMessageAttachment: [
    "direct",
    "finalizeDirectMessageAttachment",
  ],
  editDirectMessage: ["direct", "editDirectMessage"],
  deleteDirectMessage: ["direct", "deleteDirectMessage"],
  setDirectConversationPreference: [
    "direct",
    "setDirectConversationPreference",
  ],
  markDirectConversationRead: ["direct", "markDirectConversationRead"],
  setDirectMessageReaction: ["direct", "setDirectMessageReaction"],
  setDirectTyping: ["direct", "setDirectTyping"],
  sendRoomMessage: ["community", "sendRoomMessage"],
  sendClubMessage: ["community", "sendClubMessage"],
  createRoom: ["roomCreation", "createRoom"],
  startRoomVoice: ["roomCreation", "startRoomVoice"],
  reserveMomentDraft: ["moments", "reserveMomentDraft"],
  finalizeMomentDraft: ["moments", "finalizeMomentDraft"],
  getVoiceMomentsFeedV2: ["moments", "getVoiceMomentsFeedV2"],
  getVoiceMomentViewV2: ["moments", "getVoiceMomentViewV2"],
  getVoiceMomentMediaAccess: ["moments", "getVoiceMomentMediaAccess"],
  setMomentLike: ["moments", "setMomentLike"],
  createMomentComment: ["moments", "createMomentComment"],
  reserveVoiceCommentDraft: ["moments", "reserveVoiceCommentDraft"],
  finalizeVoiceCommentDraft: ["moments", "finalizeVoiceCommentDraft"],
  deleteMomentComment: ["moments", "deleteMomentComment"],
  deleteMoment: ["moments", "deleteMoment"],
  createContentReport: ["moments", "createContentReport"],
  finalizeRoomCoverUpload: ["roomCovers", "finalizeRoomCoverUpload"],
  getRoomCoverMediaAccess: ["roomCovers", "getRoomCoverMediaAccess"],
  reserveRoomCoverUpload: ["roomCovers", "reserveRoomCoverUpload"],
  setRoomVisibilitySelf: ["roomCovers", "setRoomVisibilitySelf"],
});

function authBoundRequest(request) {
  const auth = requireActor(request, { verified: false });
  // Deliberately discard every transport property except Auth and data. The
  // services derive all identities from this Auth uid and reject unknown
  // input fields, so a client-supplied uid/authorId/senderId cannot cross the
  // binding boundary.
  return {
    auth: {
      uid: auth.uid,
      token: { ...(auth.token ?? {}) },
    },
    data: request.data,
  };
}

function createUserCallableHandlers(runtime) {
  if (
    !runtime?.community ||
    !runtime?.direct ||
    !runtime?.moments ||
    !runtime?.roomCovers ||
    !runtime?.roomCreation
  ) {
    throw new TypeError("A Stage B integrity runtime is required.");
  }
  const handlers = {};
  for (const [name, [serviceName, methodName]] of Object.entries(
    USER_CALLABLE_METHODS,
  )) {
    const method = runtime[serviceName]?.[methodName];
    if (typeof method !== "function") {
      throw new TypeError(
        `Missing runtime method ${serviceName}.${methodName}.`,
      );
    }
    handlers[name] = async (request) => method(authBoundRequest(request));
  }
  return Object.freeze(handlers);
}

function createMaintenanceHandlers({
  db,
  direct,
  FieldPath,
  moments,
  roomCovers,
  logger = console,
  cleanupBatchSize = 12,
  expiryBatchSize = 100,
} = {}) {
  if (!db || !FieldPath?.documentId || !direct || !moments || !roomCovers) {
    throw new TypeError(
      "db, direct, FieldPath, moments and roomCovers are required.",
    );
  }
  requireSafeInteger(cleanupBatchSize, "cleanupBatchSize", { min: 1, max: 25 });
  requireSafeInteger(expiryBatchSize, "expiryBatchSize", { min: 1, max: 100 });

  async function processOne(outboxId) {
    try {
      return await moments.processCleanupOutbox(outboxId);
    } catch (error) {
      logger.error?.("content cleanup failed", {
        outboxId,
        code: error?.code ?? "internal",
      });
      return { outboxId, failed: true, code: error?.code ?? "internal" };
    }
  }

  async function onContentCleanupOutboxCreated(event) {
    const outboxId = requireId(event?.params?.outboxId, "outboxId");
    if (!event.data?.exists) return { outboxId, skipped: true };
    return processOne(outboxId);
  }

  async function processPendingContentCleanup() {
    const snapshot = await db
      .collection("contentCleanupOutbox")
      .where("status", "==", "pending")
      .orderBy(FieldPath.documentId())
      .limit(cleanupBatchSize)
      .get();
    const results = await Promise.all(
      snapshot.docs.map((document) => processOne(document.id)),
    );
    return {
      processed: results.length,
      completed: results.filter((result) => result.completed === true).length,
      remaining: results.filter((result) => result.completed === false).length,
      failed: results.filter((result) => result.failed === true).length,
      hasMore: snapshot.size === cleanupBatchSize,
    };
  }

  async function expireAbandonedMomentDrafts() {
    return moments.expireAbandonedMomentDrafts({ limit: expiryBatchSize });
  }

  async function expireAbandonedVoiceCommentDrafts() {
    return moments.expireAbandonedVoiceCommentDrafts({
      limit: expiryBatchSize,
    });
  }

  async function expireAbandonedDirectMessageAttachments() {
    return direct.expireAbandonedAttachmentReservations({
      limit: expiryBatchSize,
    });
  }

  async function expireRoomCoverUploadReservations() {
    return roomCovers.expireRoomCoverUploadReservations({
      limit: expiryBatchSize,
    });
  }

  async function rejectExternalMaintenanceInvocation() {
    fail(
      "permission-denied",
      "Maintenance handlers are not callable endpoints.",
    );
  }

  return Object.freeze({
    expireAbandonedMomentDrafts,
    expireAbandonedDirectMessageAttachments,
    expireAbandonedVoiceCommentDrafts,
    expireRoomCoverUploadReservations,
    onContentCleanupOutboxCreated,
    processPendingContentCleanup,
    // Exported only so binding tests can prove these handlers are registered
    // as schedules/events, never accidentally as public callables.
    rejectExternalMaintenanceInvocation,
  });
}

module.exports = {
  USER_CALLABLE_METHODS,
  authBoundRequest,
  createMaintenanceHandlers,
  createUserCallableHandlers,
};
