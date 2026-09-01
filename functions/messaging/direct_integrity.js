const {
  SAFE_ID,
  activeProfile,
  assertLedgerReplay,
  assertNotBlocked,
  assertNotRestricted,
  canonicalPair,
  canonicalPublicProfile,
  consumeRateLimit,
  digest,
  fail,
  incrementCanonicalCount,
  isValidOpaqueUid,
  ledgerData,
  nonNegativeCount,
  normalizeText,
  operationIdentity,
  rateLimitReference,
  requireActor,
  requireBoolean,
  requireExactInput,
  requireId,
  requireRequestId,
  requireSafeInteger,
  requireUid,
  timestampMillis,
  transactionGetAll,
} = require("../integrity/guards");

const DEFAULT_LIMITS = Object.freeze({
  open: { maxEvents: 12, windowMs: 60_000 },
  send: { maxEvents: 30, windowMs: 60_000 },
  uploadReserve: { maxEvents: 12, windowMs: 10 * 60_000 },
  finalize: { maxEvents: 20, windowMs: 10 * 60_000 },
  edit: { maxEvents: 20, windowMs: 60_000 },
  delete: { maxEvents: 20, windowMs: 60_000 },
  preference: { maxEvents: 60, windowMs: 60_000 },
  reaction: { maxEvents: 60, windowMs: 60_000 },
  read: { maxEvents: 120, windowMs: 60_000 },
  typing: { maxEvents: 120, windowMs: 60_000 },
});
const DIRECT_UPLOAD_TTL_MS = 15 * 60_000;
const DIRECT_MEDIA_TYPES = Object.freeze({
  image: Object.freeze({
    contentTypes: Object.freeze(["image/jpeg", "image/png", "image/webp"]),
    maxBytes: 8 * 1024 * 1024,
    minBytes: 128,
  }),
  voice: Object.freeze({
    contentTypes: Object.freeze(["audio/mp4", "audio/m4a", "audio/x-m4a"]),
    maxBytes: 12 * 1024 * 1024,
    minBytes: 1024,
  }),
});
const ALLOWED_DIRECT_REACTIONS = Object.freeze([
  "❤️",
  "😂",
  "🔥",
  "😮",
  "😢",
  "👍",
]);
const DIRECT_MESSAGE_PRIVACY = Object.freeze({
  everyone: "everyone",
  peopleYouFollow: "peopleYouFollow",
  friends: "friends",
  nobody: "nobody",
});

function directMessagePrivacy(profileSnapshot) {
  const profile = profileSnapshot?.data?.() ?? {};
  if (!("messagePrivacy" in profile)) return DIRECT_MESSAGE_PRIVACY.everyone;
  const value = profile.messagePrivacy;
  if (!Object.values(DIRECT_MESSAGE_PRIVACY).includes(value)) {
    fail("data-loss", "The recipient's message privacy setting is invalid.");
  }
  return value;
}

function exactFollowingEdge(snapshot, targetId) {
  if (!snapshot?.exists) return false;
  const data = snapshot.data() ?? {};
  const keys = Object.keys(data).sort();
  const allowed = new Set(["followedAt", "notificationId", "uid"]);
  const pointerIsValid = !("notificationId" in data) ||
    (typeof data.notificationId === "string" &&
      data.notificationId.length > 0 && data.notificationId.length <= 320);
  return keys.length >= 2 && keys.every((key) => allowed.has(key)) &&
    keys.includes("followedAt") && keys.includes("uid") &&
    pointerIsValid && data.uid === targetId &&
    timestampMillis(data.followedAt) !== null;
}

function exactFriendshipGuard(snapshot, ownerId, friendId) {
  if (!snapshot?.exists) return false;
  const data = snapshot.data() ?? {};
  const keys = Object.keys(data).sort();
  const expected = ["establishedAt", "friendId", "ownerId", "schemaVersion"];
  return keys.length === expected.length &&
    keys.every((key, index) => key === expected[index]) &&
    data.ownerId === ownerId && data.friendId === friendId &&
    data.schemaVersion === 1 && timestampMillis(data.establishedAt) !== null;
}

function assertDirectMessagePrivacy({
  actorId,
  recipientId,
  recipientProfile,
  recipientFollowsActor,
  actorFriendGuard,
  recipientFriendGuard,
}) {
  const privacy = directMessagePrivacy(recipientProfile);
  const allowed = privacy === DIRECT_MESSAGE_PRIVACY.everyone ||
    (privacy === DIRECT_MESSAGE_PRIVACY.peopleYouFollow &&
      exactFollowingEdge(recipientFollowsActor, actorId)) ||
    (privacy === DIRECT_MESSAGE_PRIVACY.friends &&
      exactFriendshipGuard(actorFriendGuard, actorId, recipientId) &&
      exactFriendshipGuard(recipientFriendGuard, recipientId, actorId));
  if (!allowed) {
    fail(
      "permission-denied",
      "This person is not accepting direct messages from you.",
    );
  }
  return { actorId, recipientId, privacy };
}

function directMessagePrivacyReferences(db, actorId, recipientId) {
  return [
    db.doc(`users/${recipientId}/following/${actorId}`),
    db.doc(`friendshipGuards/${actorId}/friends/${recipientId}`),
    db.doc(`friendshipGuards/${recipientId}/friends/${actorId}`),
  ];
}

function assertDirectMessagePrivacyFromRelated({
  actorId,
  recipientId,
  recipientProfile,
  related,
  offset,
}) {
  return assertDirectMessagePrivacy({
    actorId,
    recipientId,
    recipientProfile,
    recipientFollowsActor: related[offset],
    actorFriendGuard: related[offset + 1],
    recipientFriendGuard: related[offset + 2],
  });
}

function canonicalConversationId(firstId, secondId) {
  const pair = canonicalPair(firstId, secondId);
  return `dm_${digest("direct-conversation", pair).slice(0, 40)}`;
}

function canonicalPairKey(firstId, secondId) {
  return digest("direct-pair", canonicalPair(firstId, secondId));
}

function directMediaMessageId(uid, conversationId, requestId) {
  return `m_${digest(
    "direct-media",
    conversationId,
    uid,
    requestId,
  ).slice(0, 40)}`;
}

function extensionForDirectMedia(type, contentType) {
  if (type === "voice") return "m4a";
  return contentType === "image/png"
    ? "png"
    : contentType === "image/webp" ? "webp" : "jpg";
}

function directMediaStoragePath(uid, conversationId, messageId, type, contentType) {
  return `message_attachments/${uid}/${conversationId}/${messageId}.${
    extensionForDirectMedia(type, contentType)
  }`;
}

function directMediaPathFromReference(reference, uid, conversationId, messageId) {
  if (typeof reference !== "string" || !reference.startsWith("gs://")) return null;
  const firstPathSlash = reference.indexOf("/", 5);
  if (firstPathSlash < 0) return null;
  const path = reference.slice(firstPathSlash + 1);
  const expected = `message_attachments/${uid}/${conversationId}/${messageId}.`;
  if (!path.startsWith(expected) ||
      !/\.(jpg|png|webp|m4a)$/u.test(path) ||
      path.slice(expected.length).includes("/")) {
    return null;
  }
  return path;
}

function customMetadataOf(metadata) {
  const custom = metadata?.metadata ?? metadata?.customMetadata ?? {};
  return isPlainObject(custom) ? custom : {};
}

function validateStoredDirectMedia(metadata, reservation, requestedGeneration) {
  const config = DIRECT_MEDIA_TYPES[reservation.type];
  if (!config || !metadata || typeof metadata !== "object") {
    fail("failed-precondition", "The uploaded attachment is missing.");
  }
  const size = Number(metadata.size);
  if (!Number.isSafeInteger(size) || size < config.minBytes ||
      size > config.maxBytes ||
      !config.contentTypes.includes(metadata.contentType) ||
      metadata.contentType !== reservation.contentType) {
    fail("failed-precondition", "The uploaded attachment payload is invalid.");
  }
  const generation = String(metadata.generation ?? "");
  if (!generation || generation !== String(requestedGeneration)) {
    fail("failed-precondition", "The uploaded object generation does not match.");
  }
  const expected = {
    yovoiceConversationId: reservation.conversationId,
    yovoiceMessageId: reservation.messageId,
    yovoiceMessagePath:
      `conversations/${reservation.conversationId}/messages/${reservation.messageId}`,
    yovoiceMediaType: reservation.type,
    yovoiceOwnerUid: reservation.ownerId,
  };
  const custom = customMetadataOf(metadata);
  const allowed = new Set([...Object.keys(expected), "firebaseStorageDownloadTokens"]);
  if (Object.keys(custom).some((key) => !allowed.has(key)) ||
      Object.entries(expected).some(([key, value]) => custom[key] !== value)) {
    fail("failed-precondition", "The uploaded attachment identity is invalid.");
  }
  return { contentType: metadata.contentType, generation, size };
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function requireParticipantMap(value, participants, label) {
  if (!isPlainObject(value)) {
    fail("data-loss", `${label} is malformed.`);
  }
  const keys = Object.keys(value).sort();
  if (keys.length !== participants.length ||
      keys.some((key, index) => key !== participants[index])) {
    fail("data-loss", `${label} is not bound to the canonical participants.`);
  }
  return value;
}

function requireParticipantList(value, participants, label) {
  if (!Array.isArray(value) || new Set(value).size !== value.length ||
      value.some((uid) => !participants.includes(uid))) {
    fail("data-loss", `${label} is malformed.`);
  }
  return value;
}

function conversationParticipants(snapshot, actorId) {
  if (!snapshot.exists) {
    fail("not-found", "The direct conversation does not exist.");
  }
  const data = snapshot.data() ?? {};
  if (!Array.isArray(data.participantIds) || data.participantIds.length !== 2 ||
      data.participantIds.some((uid) => typeof uid !== "string")) {
    fail("data-loss", "The conversation participants are malformed.");
  }
  const participants = canonicalPair(...data.participantIds);
  if (!participants.includes(actorId) ||
      data.participantIds.some((uid, index) => uid !== participants[index])) {
    fail("permission-denied", "The conversation participants are not canonical.");
  }
  return { data, participants };
}

function validatePairGuard(snapshot, conversationId, participants) {
  if (!snapshot?.exists) {
    fail("data-loss", "The direct-conversation pair guard is missing.");
  }
  const guard = snapshot.data() ?? {};
  const expectedKeys = [
    "conversationId",
    "createdAt",
    "pairKey",
    "participantIds",
    "schemaVersion",
  ];
  const keys = Object.keys(guard).sort();
  if (keys.length !== expectedKeys.length ||
      keys.some((key, index) => key !== expectedKeys[index]) ||
      guard.schemaVersion !== 1 ||
      guard.pairKey !== canonicalPairKey(...participants) ||
      guard.conversationId !== conversationId ||
      !Array.isArray(guard.participantIds) ||
      guard.participantIds.length !== participants.length ||
      guard.participantIds.some((uid, index) => uid !== participants[index]) ||
      timestampMillis(guard.createdAt) === null) {
    fail("data-loss", "The direct-conversation pair guard conflicts.");
  }
  return guard;
}

function validateConversation(snapshot, conversationId, actorId, pairGuard) {
  const { data, participants } = conversationParticipants(snapshot, actorId);
  const expectedKeys = [
    "archivedBy",
    "createdAt",
    "lastMessage",
    "lastMessageId",
    "lastMessageSenderId",
    "lastMessageSequence",
    "lastMessageType",
    "mutedBy",
    "pairKey",
    "participantEmails",
    "participantIds",
    "participantNames",
    "participantPhotoUrls",
    "readSequences",
    "schemaVersion",
    "typing",
    "unreadCounts",
    "updatedAt",
  ];
  const keys = Object.keys(data).sort();
  if (keys.length !== expectedKeys.length ||
      keys.some((key, index) => key !== expectedKeys[index]) ||
      data.pairKey !== canonicalPairKey(...participants) ||
      data.schemaVersion !== 2) {
    fail("permission-denied", "The conversation is not canonically bound.");
  }
  validatePairGuard(pairGuard, conversationId, participants);
  requireParticipantMap(data.participantNames, participants, "participantNames");
  requireParticipantMap(data.participantEmails, participants, "participantEmails");
  requireParticipantMap(
    data.participantPhotoUrls,
    participants,
    "participantPhotoUrls",
  );
  for (const uid of participants) {
    if (typeof data.participantNames[uid] !== "string" ||
        !data.participantNames[uid].trim() ||
        data.participantNames[uid].length > 80 ||
        data.participantEmails[uid] !== "" ||
        typeof data.participantPhotoUrls[uid] !== "string" ||
        data.participantPhotoUrls[uid].length > 2048) {
      fail("data-loss", "The canonical participant identity is malformed.");
    }
  }
  const unreadCounts = requireParticipantMap(
    data.unreadCounts,
    participants,
    "unreadCounts",
  );
  for (const uid of participants) {
    nonNegativeCount(unreadCounts[uid], `Unread count for ${uid}`);
  }
  const readSequences = requireParticipantMap(
    data.readSequences,
    participants,
    "readSequences",
  );
  for (const uid of participants) {
    nonNegativeCount(readSequences[uid], `Read sequence for ${uid}`);
  }
  nonNegativeCount(data.lastMessageSequence, "lastMessageSequence");
  requireParticipantList(data.archivedBy, participants, "archivedBy");
  requireParticipantList(data.mutedBy, participants, "mutedBy");
  if (!isPlainObject(data.typing) ||
      Object.keys(data.typing).some((uid) => !participants.includes(uid))) {
    fail("data-loss", "typing is malformed.");
  }
  for (const state of Object.values(data.typing)) {
    const stateKeys = isPlainObject(state) ? Object.keys(state).sort() : [];
    if (stateKeys.length !== 2 || stateKeys[0] !== "isTyping" ||
        stateKeys[1] !== "updatedAt" || typeof state.isTyping !== "boolean" ||
        timestampMillis(state.updatedAt) === null) {
      fail("data-loss", "typing is malformed.");
    }
  }
  if (typeof data.lastMessage !== "string" || data.lastMessage.length > 2000 ||
      (data.lastMessageId !== null && !SAFE_ID.test(data.lastMessageId)) ||
      !["text", "voice", "image"].includes(data.lastMessageType) ||
      (data.lastMessageSenderId !== "" &&
        !participants.includes(data.lastMessageSenderId)) ||
      timestampMillis(data.createdAt) === null ||
      timestampMillis(data.updatedAt) === null) {
    fail("data-loss", "The conversation preview is malformed.");
  }
  if ((data.lastMessageSequence === 0 &&
        (data.lastMessageId !== null || data.lastMessageSenderId !== "" ||
          data.lastMessage !== "")) ||
      (data.lastMessageSequence > 0 &&
        (data.lastMessageId === null || data.lastMessageSenderId === ""))) {
    fail("data-loss", "The conversation preview sequence is malformed.");
  }
  return { data, participants };
}

function validateMessage(snapshot, conversationId) {
  if (!snapshot.exists) fail("not-found", "The direct message does not exist.");
  const data = snapshot.data() ?? {};
  const exactKeys = [
    "content",
    "conversationId",
    "durationSeconds",
    "editedAt",
    "isDeleted",
    "mediaUrl",
    "reactions",
    "readBy",
    "replyToContent",
    "replyToMessageId",
    "replyToSenderId",
    "schemaVersion",
    "senderId",
    "sentAt",
    "sequence",
    "type",
  ];
  const keys = Object.keys(data).sort();
  if (keys.length !== exactKeys.length ||
      keys.some((key, index) => key !== exactKeys[index]) ||
      data.schemaVersion !== 2 || data.conversationId !== conversationId ||
      typeof data.senderId !== "string" ||
      !Number.isSafeInteger(data.sequence) || data.sequence < 1 ||
      !["text", "voice", "image"].includes(data.type) ||
      typeof data.isDeleted !== "boolean" || !Array.isArray(data.readBy) ||
      !isPlainObject(data.reactions)) {
    fail("data-loss", "The direct message schema is not canonical.");
  }
  if (typeof data.content !== "string" || data.content.length > 2000 ||
      timestampMillis(data.sentAt) === null ||
      (data.editedAt !== null && timestampMillis(data.editedAt) === null) ||
      (data.mediaUrl !== null &&
        (typeof data.mediaUrl !== "string" || data.mediaUrl.length > 4096)) ||
      (data.durationSeconds !== null &&
        (!Number.isSafeInteger(data.durationSeconds) ||
          data.durationSeconds < 1 || data.durationSeconds > 300)) ||
      (data.type === "text" &&
        (data.mediaUrl !== null || data.durationSeconds !== null)) ||
      (data.type === "image" &&
        (data.content !== "" || typeof data.mediaUrl !== "string" ||
          !/^(gs:\/\/|https:\/\/)/u.test(data.mediaUrl) ||
          data.durationSeconds !== null)) ||
      (data.type === "voice" &&
        (data.content !== "" || typeof data.mediaUrl !== "string" ||
          !/^(gs:\/\/|https:\/\/)/u.test(data.mediaUrl) ||
          !Number.isSafeInteger(data.durationSeconds) ||
          data.durationSeconds < 1 || data.durationSeconds > 60)) ||
      (data.isDeleted &&
        (data.content !== "" || data.mediaUrl !== null ||
          data.durationSeconds !== null || Object.keys(data.reactions).length !== 0))) {
    fail("data-loss", "The direct message content is not canonical.");
  }
  const hasReply = data.replyToMessageId !== null;
  if (hasReply !== (data.replyToSenderId !== null) ||
      hasReply !== (data.replyToContent !== null) ||
      (hasReply &&
        (!SAFE_ID.test(data.replyToMessageId) ||
          !isValidOpaqueUid(data.replyToSenderId) ||
          typeof data.replyToContent !== "string" ||
          data.replyToContent.length > 240))) {
    fail("data-loss", "The direct-message reply linkage is malformed.");
  }
  return data;
}

function setMembership(list, uid, enabled) {
  const result = new Set(list);
  if (enabled) result.add(uid);
  else result.delete(uid);
  return [...result].sort();
}

function createDirectMessagingService({
  db,
  Timestamp,
  storage = null,
  clock = () => Date.now(),
  readPageSize = 100,
  limits = DEFAULT_LIMITS,
}) {
  if (!db || !Timestamp?.fromMillis) {
    throw new TypeError("db and Timestamp are required.");
  }
  if (!Number.isSafeInteger(readPageSize) || readPageSize < 1 ||
      readPageSize > 200) {
    throw new TypeError("readPageSize must be between 1 and 200.");
  }

  function time() {
    const nowMs = clock();
    if (!Number.isSafeInteger(nowMs) || nowMs < 0) {
      throw new TypeError("clock must return epoch milliseconds.");
    }
    return { nowMs, now: Timestamp.fromMillis(nowMs) };
  }

  function ledgerReference(identity) {
    return db.doc(`integrityOperationLedgers/${identity.id}`);
  }

  function limitReference(scope, uid) {
    return rateLimitReference(db, `direct.${scope}`, uid);
  }

  function attemptLimitReference(scope, uid) {
    return rateLimitReference(db, `direct.attempt.${scope}`, uid);
  }

  function consume(transaction, snapshot, reference, scope, uid, timing) {
    const config = limits[scope];
    if (!config) throw new TypeError(`Missing direct.${scope} rate limit.`);
    consumeRateLimit(transaction, snapshot, {
      reference,
      scope: `direct.${scope}`,
      uid,
      ...timing,
      ...config,
    });
  }

  // This transaction is intentionally target-independent and commits before
  // any caller-selected uid, conversation, message or Storage object is read.
  // A denied target transaction would otherwise roll its rate-limit write
  // back, letting random IDs turn every request into free database reads.
  async function beginAttemptPreflight({
    identity,
    kind,
    uid,
    requestId,
    scope,
    timing,
  }) {
    return db.runTransaction(async (transaction) => {
      const ledgerRef = ledgerReference(identity);
      const preflightRef = db.doc(`integrityPreflightLedgers/${identity.id}`);
      const rateRef = attemptLimitReference(scope, uid);
      const [ledger, preflight, rate] = await transactionGetAll(
        transaction,
        ledgerRef,
        preflightRef,
        rateRef,
      );
      const replay = assertLedgerReplay(ledger, {
        kind,
        uid,
        inputHash: identity.inputHash,
      });
      if (replay) return { replay };
      if (preflight.exists) {
        const existing = preflight.data() ?? {};
        if (existing.kind !== kind || existing.ownerId !== uid ||
            existing.inputHash !== identity.inputHash ||
            existing.scope !== scope) {
          fail("already-exists", "requestId was reused for another operation.");
        }
      }
      const config = limits[scope];
      if (!config) throw new TypeError(`Missing direct.${scope} rate limit.`);
      consumeRateLimit(transaction, rate, {
        reference: rateRef,
        scope: `direct.attempt.${scope}`,
        uid,
        ...timing,
        ...config,
      });
      if (!preflight.exists) {
        transaction.create(preflightRef, {
          schemaVersion: 1,
          kind,
          ownerId: uid,
          requestId,
          scope,
          inputHash: identity.inputHash,
          createdAt: timing.now,
        });
      }
      return { replay: null };
    });
  }

  async function openDirectConversation(request) {
    const auth = requireActor(request);
    const data = requireExactInput(
      request.data,
      ["requestId", "targetUserId"],
      ["requestId", "targetUserId"],
    );
    const requestId = requireRequestId(data.requestId);
    const targetUserId = requireUid(data.targetUserId, "targetUserId");
    const participants = canonicalPair(auth.uid, targetUserId);
    const pairKey = canonicalPairKey(...participants);
    const defaultConversationId = canonicalConversationId(...participants);
    const input = { targetUserId };
    const identity = operationIdentity("direct.open", auth.uid, requestId, input);
    const timing = time();
    const preflight = await beginAttemptPreflight({
      identity,
      kind: "direct.open",
      uid: auth.uid,
      requestId,
      scope: "open",
      timing,
    });
    if (preflight.replay) return preflight.replay;

    return db.runTransaction(async (transaction) => {
      const ledgerRef = ledgerReference(identity);
      const rateRef = limitReference("open", auth.uid);
      const pairRef = db.doc(`directConversationPairs/${pairKey}`);
      const actorRef = db.doc(`users/${auth.uid}`);
      const targetRef = db.doc(`users/${targetUserId}`);
      const actorPublicRef = db.doc(`publicProfiles/${auth.uid}`);
      const targetPublicRef = db.doc(`publicProfiles/${targetUserId}`);
      const actorRestrictionRef = db.doc(`restrictions/${auth.uid}`);
      const targetRestrictionRef = db.doc(`restrictions/${targetUserId}`);
      const actorBlockRef = db.doc(`users/${auth.uid}/blocked/${targetUserId}`);
      const targetBlockRef = db.doc(`users/${targetUserId}/blocked/${auth.uid}`);
      const privacyRefs = directMessagePrivacyReferences(
        db,
        auth.uid,
        targetUserId,
      );
      const [
        ledger,
        rate,
        pairGuard,
        actorProfileSnapshot,
        targetProfileSnapshot,
        actorPublic,
        targetPublic,
        actorRestriction,
        targetRestriction,
        actorBlock,
        targetBlock,
        targetFollowsActor,
        actorFriendGuard,
        targetFriendGuard,
      ] = await transactionGetAll(
        transaction,
        ledgerRef,
        rateRef,
        pairRef,
        actorRef,
        targetRef,
        actorPublicRef,
        targetPublicRef,
        actorRestrictionRef,
        targetRestrictionRef,
        actorBlockRef,
        targetBlockRef,
        ...privacyRefs,
      );

      const replay = assertLedgerReplay(ledger, {
        kind: "direct.open",
        uid: auth.uid,
        inputHash: identity.inputHash,
      });
      if (replay) return replay;

      activeProfile(actorProfileSnapshot, "Your");
      activeProfile(targetProfileSnapshot, "The selected");
      assertNotRestricted(actorRestriction, "Your", timing.nowMs);
      assertNotRestricted(targetRestriction, "The selected", timing.nowMs);
      assertNotBlocked(actorBlock, targetBlock);
      assertDirectMessagePrivacy({
        actorId: auth.uid,
        recipientId: targetUserId,
        recipientProfile: targetProfileSnapshot,
        recipientFollowsActor: targetFollowsActor,
        actorFriendGuard,
        recipientFriendGuard: targetFriendGuard,
      });
      let conversationId = defaultConversationId;
      if (pairGuard.exists) {
        const guard = pairGuard.data() ?? {};
        conversationId = requireId(guard.conversationId, "guard conversationId");
      }
      const conversationRef = db.doc(`conversations/${conversationId}`);
      const conversation = await transaction.get(conversationRef);
      consume(transaction, rate, rateRef, "open", auth.uid, timing);

      let created = false;
      if (conversation.exists) {
        validateConversation(conversation, conversationId, auth.uid, pairGuard);
      } else {
        if (pairGuard.exists) {
          fail("data-loss", "The canonical conversation is missing.");
        }
        const actorIdentity = canonicalPublicProfile(actorPublic, auth.uid);
        const targetIdentity = canonicalPublicProfile(targetPublic, targetUserId);
        const identities = {
          [auth.uid]: actorIdentity,
          [targetUserId]: targetIdentity,
        };
        transaction.create(conversationRef, {
          schemaVersion: 2,
          pairKey,
          participantIds: participants,
          participantNames: Object.fromEntries(
            participants.map((uid) => [uid, identities[uid].displayName]),
          ),
          participantEmails: Object.fromEntries(
            participants.map((uid) => [uid, ""]),
          ),
          participantPhotoUrls: Object.fromEntries(
            participants.map((uid) => [uid, identities[uid].photoUrl ?? ""]),
          ),
          unreadCounts: Object.fromEntries(participants.map((uid) => [uid, 0])),
          readSequences: Object.fromEntries(participants.map((uid) => [uid, 0])),
          typing: {},
          archivedBy: [],
          mutedBy: [],
          lastMessage: "",
          lastMessageId: null,
          lastMessageSequence: 0,
          lastMessageType: "text",
          lastMessageSenderId: "",
          createdAt: timing.now,
          updatedAt: timing.now,
        });
        transaction.create(pairRef, {
          schemaVersion: 1,
          pairKey,
          conversationId,
          participantIds: participants,
          createdAt: timing.now,
        });
        created = true;
      }

      const result = { conversationId, created };
      transaction.create(ledgerRef, ledgerData({
        kind: "direct.open",
        uid: auth.uid,
        requestId,
        inputHash: identity.inputHash,
        result,
        now: timing.now,
      }));
      return result;
    });
  }

  async function sendDirectMessage(request) {
    const auth = requireActor(request);
    const data = requireExactInput(
      request.data,
      ["conversationId", "replyToMessageId", "requestId", "text"],
      ["conversationId", "requestId", "text"],
    );
    const conversationId = requireId(data.conversationId, "conversationId");
    const requestId = requireRequestId(data.requestId);
    const text = normalizeText(data.text, 2000, "text");
    const replyToMessageId = data.replyToMessageId === undefined ||
      data.replyToMessageId === null
      ? null
      : requireId(data.replyToMessageId, "replyToMessageId");
    const input = { conversationId, replyToMessageId, text };
    const identity = operationIdentity("direct.send", auth.uid, requestId, input);
    const messageId = `m_${digest(
      "direct-message",
      conversationId,
      auth.uid,
      requestId,
    ).slice(0, 40)}`;
    const timing = time();
    const preflight = await beginAttemptPreflight({
      identity,
      kind: "direct.send",
      uid: auth.uid,
      requestId,
      scope: "send",
      timing,
    });
    if (preflight.replay) return preflight.replay;

    return db.runTransaction(async (transaction) => {
      const ledgerRef = ledgerReference(identity);
      const rateRef = limitReference("send", auth.uid);
      const conversationRef = db.doc(`conversations/${conversationId}`);
      const messageRef = conversationRef.collection("messages").doc(messageId);
      const initial = await transactionGetAll(
        transaction,
        ledgerRef,
        rateRef,
        conversationRef,
        messageRef,
      );
      const [ledger, rate, conversation, existingMessage] = initial;
      const replay = assertLedgerReplay(ledger, {
        kind: "direct.send",
        uid: auth.uid,
        inputHash: identity.inputHash,
      });
      if (replay) return replay;

      const preliminary = conversationParticipants(conversation, auth.uid);
      const recipientId = preliminary.participants.find((uid) => uid !== auth.uid);
      const refs = [
        db.doc(`users/${auth.uid}`),
        db.doc(`users/${recipientId}`),
        db.doc(`restrictions/${auth.uid}`),
        db.doc(`restrictions/${recipientId}`),
        db.doc(`users/${auth.uid}/blocked/${recipientId}`),
        db.doc(`users/${recipientId}/blocked/${auth.uid}`),
        db.doc(`directConversationPairs/${canonicalPairKey(
          ...preliminary.participants,
        )}`),
        ...directMessagePrivacyReferences(db, auth.uid, recipientId),
      ];
      if (replyToMessageId) {
        refs.push(conversationRef.collection("messages").doc(replyToMessageId));
      }
      const related = await transactionGetAll(transaction, ...refs);
      const [actorProfile, recipientProfile, actorRestriction,
        recipientRestriction, actorBlock, recipientBlock, pairGuard,
        recipientFollowsActor, actorFriendGuard, recipientFriendGuard,
        replySnapshot] = related;
      const context = validateConversation(
        conversation,
        conversationId,
        auth.uid,
        pairGuard,
      );
      activeProfile(actorProfile, "Your");
      activeProfile(recipientProfile, "The recipient");
      assertNotRestricted(actorRestriction, "Your", timing.nowMs);
      assertNotRestricted(recipientRestriction, "The recipient", timing.nowMs);
      assertNotBlocked(actorBlock, recipientBlock);
      assertDirectMessagePrivacy({
        actorId: auth.uid,
        recipientId,
        recipientProfile,
        recipientFollowsActor,
        actorFriendGuard,
        recipientFriendGuard,
      });
      consume(transaction, rate, rateRef, "send", auth.uid, timing);

      if (existingMessage.exists) {
        fail("data-loss", "A message exists without its idempotency ledger.");
      }

      let reply = {
        replyToMessageId: null,
        replyToSenderId: null,
        replyToContent: null,
      };
      if (replyToMessageId) {
        const replyData = validateMessage(replySnapshot, conversationId);
        if (!context.participants.includes(replyData.senderId)) {
          fail("data-loss", "The reply target has an invalid sender.");
        }
        reply = {
          replyToMessageId,
          replyToSenderId: replyData.senderId,
          replyToContent: replyData.isDeleted
            ? "Message deleted"
            : String(replyData.content || replyData.type).slice(0, 240),
        };
      }

      const sequence = incrementCanonicalCount(
        context.data.lastMessageSequence,
        "lastMessageSequence",
      );

      transaction.create(messageRef, {
        schemaVersion: 2,
        sequence,
        conversationId,
        senderId: auth.uid,
        type: "text",
        content: text,
        mediaUrl: null,
        durationSeconds: null,
        sentAt: timing.now,
        readBy: [auth.uid],
        reactions: {},
        isDeleted: false,
        editedAt: null,
        ...reply,
      });
      const unreadCounts = { ...context.data.unreadCounts };
      unreadCounts[auth.uid] = 0;
      unreadCounts[recipientId] = incrementCanonicalCount(
        unreadCounts[recipientId],
        "Recipient unread count",
      );
      const typing = { ...context.data.typing };
      typing[auth.uid] = { isTyping: false, updatedAt: timing.now };
      transaction.update(conversationRef, {
        lastMessage: text,
        lastMessageId: messageId,
        lastMessageSequence: sequence,
        lastMessageType: "text",
        lastMessageSenderId: auth.uid,
        updatedAt: timing.now,
        archivedBy: [],
        unreadCounts,
        typing,
      });
      const result = { conversationId, messageId, recipientId, created: true };
      transaction.create(ledgerRef, ledgerData({
        kind: "direct.send",
        uid: auth.uid,
        requestId,
        inputHash: identity.inputHash,
        result,
        now: timing.now,
      }));
      return result;
    });
  }

  async function reserveDirectMessageAttachment(request) {
    const auth = requireActor(request);
    const data = requireExactInput(
      request.data,
      ["contentType", "conversationId", "durationSeconds", "requestId", "type"],
      ["contentType", "conversationId", "requestId", "type"],
    );
    const conversationId = requireId(data.conversationId, "conversationId");
    const requestId = requireRequestId(data.requestId);
    const type = String(data.type ?? "");
    const config = DIRECT_MEDIA_TYPES[type];
    if (!config) fail("invalid-argument", "type must be image or voice.");
    const contentType = String(data.contentType ?? "").toLowerCase();
    if (!config.contentTypes.includes(contentType)) {
      fail("invalid-argument", "contentType is not supported for this attachment.");
    }
    const durationSeconds = type === "voice"
      ? requireSafeInteger(data.durationSeconds, "durationSeconds", { min: 1, max: 60 })
      : null;
    if (type === "image" && data.durationSeconds !== undefined &&
        data.durationSeconds !== null) {
      fail("invalid-argument", "Images cannot carry a duration.");
    }
    const messageId = directMediaMessageId(auth.uid, conversationId, requestId);
    const storagePath = directMediaStoragePath(
      auth.uid,
      conversationId,
      messageId,
      type,
      contentType,
    );
    const input = { contentType, conversationId, durationSeconds, type };
    const identity = operationIdentity(
      "direct.attachment.reserve",
      auth.uid,
      requestId,
      input,
    );
    const timing = time();
    const preflight = await beginAttemptPreflight({
      identity,
      kind: "direct.attachment.reserve",
      uid: auth.uid,
      requestId,
      scope: "uploadReserve",
      timing,
    });
    if (preflight.replay) return preflight.replay;

    return db.runTransaction(async (transaction) => {
      const ledgerRef = ledgerReference(identity);
      const rateRef = limitReference("uploadReserve", auth.uid);
      const conversationRef = db.doc(`conversations/${conversationId}`);
      const reservationRef = db.doc(`directMessageUploadReservations/${messageId}`);
      const [ledger, rate, conversation, existing] = await transactionGetAll(
        transaction,
        ledgerRef,
        rateRef,
        conversationRef,
        reservationRef,
      );
      const replay = assertLedgerReplay(ledger, {
        kind: "direct.attachment.reserve",
        uid: auth.uid,
        inputHash: identity.inputHash,
      });
      if (replay) return replay;
      const preliminary = conversationParticipants(conversation, auth.uid);
      const recipientId = preliminary.participants.find((uid) => uid !== auth.uid);
      const related = await transactionGetAll(
        transaction,
        db.doc(`users/${auth.uid}`),
        db.doc(`users/${recipientId}`),
        db.doc(`restrictions/${auth.uid}`),
        db.doc(`restrictions/${recipientId}`),
        db.doc(`users/${auth.uid}/blocked/${recipientId}`),
        db.doc(`users/${recipientId}/blocked/${auth.uid}`),
        db.doc(`directConversationPairs/${canonicalPairKey(
          ...preliminary.participants,
        )}`),
        ...directMessagePrivacyReferences(db, auth.uid, recipientId),
      );
      validateConversation(conversation, conversationId, auth.uid, related[6]);
      activeProfile(related[0], "Your");
      activeProfile(related[1], "The recipient");
      assertNotRestricted(related[2], "Your", timing.nowMs);
      assertNotRestricted(related[3], "The recipient", timing.nowMs);
      assertNotBlocked(related[4], related[5]);
      assertDirectMessagePrivacyFromRelated({
        actorId: auth.uid,
        recipientId,
        recipientProfile: related[1],
        related,
        offset: 7,
      });
      consume(transaction, rate, rateRef, "uploadReserve", auth.uid, timing);
      if (existing.exists) {
        fail("data-loss", "An attachment reservation exists without its ledger.");
      }
      const expiresAt = Timestamp.fromMillis(timing.nowMs + DIRECT_UPLOAD_TTL_MS);
      transaction.create(reservationRef, {
        schemaVersion: 1,
        ownerId: auth.uid,
        conversationId,
        messageId,
        recipientId,
        type,
        contentType,
        durationSeconds,
        storagePath,
        status: "uploading",
        createdAt: timing.now,
        expiresAt,
      });
      const result = {
        conversationId,
        messageId,
        storagePath,
        type,
        expiresAtMillis: timing.nowMs + DIRECT_UPLOAD_TTL_MS,
        maxBytes: config.maxBytes,
        created: true,
      };
      transaction.create(ledgerRef, ledgerData({
        kind: "direct.attachment.reserve",
        uid: auth.uid,
        requestId,
        inputHash: identity.inputHash,
        result,
        now: timing.now,
      }));
      return result;
    });
  }

  async function finalizeDirectMessageAttachment(request) {
    const auth = requireActor(request);
    const data = requireExactInput(
      request.data,
      ["conversationId", "messageId", "objectGeneration", "requestId"],
      ["conversationId", "messageId", "objectGeneration", "requestId"],
    );
    const conversationId = requireId(data.conversationId, "conversationId");
    const messageId = requireId(data.messageId, "messageId");
    const requestId = requireRequestId(data.requestId);
    const objectGeneration = String(data.objectGeneration ?? "");
    if (!/^[0-9]{1,30}$/u.test(objectGeneration)) {
      fail("invalid-argument", "objectGeneration is invalid.");
    }
    const input = { conversationId, messageId, objectGeneration };
    const identity = operationIdentity(
      "direct.attachment.finalize",
      auth.uid,
      requestId,
      input,
    );
    const timing = time();
    const preflight = await beginAttemptPreflight({
      identity,
      kind: "direct.attachment.finalize",
      uid: auth.uid,
      requestId,
      scope: "finalize",
      timing,
    });
    if (preflight.replay) return preflight.replay;
    if (!storage?.getMetadata || !storage?.getObjectReference) {
      fail("failed-precondition", "Attachment storage is unavailable.");
    }
    const reservationRef = db.doc(`directMessageUploadReservations/${messageId}`);
    const reservationSnapshot = await reservationRef.get();
    if (!reservationSnapshot.exists) {
      fail("not-found", "The attachment reservation does not exist.");
    }
    const reservation = reservationSnapshot.data() ?? {};
    const expectedKeys = [
      "contentType", "conversationId", "createdAt", "durationSeconds",
      "expiresAt", "messageId", "ownerId", "recipientId", "schemaVersion",
      "status", "storagePath", "type",
    ];
    const keys = Object.keys(reservation).sort();
    if (keys.length !== expectedKeys.length ||
        keys.some((key, index) => key !== expectedKeys[index]) ||
        reservation.schemaVersion !== 1 || reservation.ownerId !== auth.uid ||
        reservation.conversationId !== conversationId ||
        reservation.messageId !== messageId || reservation.status !== "uploading" ||
        timestampMillis(reservation.expiresAt) === null ||
        timestampMillis(reservation.expiresAt) <= timing.nowMs ||
        reservation.storagePath !== directMediaStoragePath(
          auth.uid,
          conversationId,
          messageId,
          reservation.type,
          reservation.contentType,
        )) {
      fail("failed-precondition", "The attachment reservation is invalid.");
    }
    const metadata = await storage.getMetadata(reservation.storagePath);
    const media = validateStoredDirectMedia(
      metadata,
      reservation,
      objectGeneration,
    );
    const mediaReference = storage.getObjectReference(reservation.storagePath);
    if (typeof mediaReference !== "string" || !mediaReference.startsWith("gs://") ||
        mediaReference.length > 4096) {
      fail("failed-precondition", "The attachment reference is invalid.");
    }

    return db.runTransaction(async (transaction) => {
      const ledgerRef = ledgerReference(identity);
      const preflightRef = db.doc(`integrityPreflightLedgers/${identity.id}`);
      const conversationRef = db.doc(`conversations/${conversationId}`);
      const messageRef = conversationRef.collection("messages").doc(messageId);
      const [ledger, preflightLedger, conversation, currentReservation, existing] =
        await transactionGetAll(
          transaction,
          ledgerRef,
          preflightRef,
          conversationRef,
          reservationRef,
          messageRef,
        );
      const replay = assertLedgerReplay(ledger, {
        kind: "direct.attachment.finalize",
        uid: auth.uid,
        inputHash: identity.inputHash,
      });
      if (replay) return replay;
      const preflightData = preflightLedger.exists
        ? preflightLedger.data() ?? {}
        : {};
      if (preflightData.ownerId !== auth.uid ||
          preflightData.kind !== "direct.attachment.finalize" ||
          preflightData.inputHash !== identity.inputHash) {
        fail("failed-precondition", "The upload preflight is not canonical.");
      }
      if (!currentReservation.exists ||
          currentReservation.data()?.ownerId !== auth.uid ||
          currentReservation.data()?.storagePath !== reservation.storagePath) {
        fail("failed-precondition", "The attachment reservation changed.");
      }
      if (existing.exists) {
        fail("data-loss", "An attachment message exists without its ledger.");
      }
      const preliminary = conversationParticipants(conversation, auth.uid);
      const recipientId = preliminary.participants.find((uid) => uid !== auth.uid);
      const related = await transactionGetAll(
        transaction,
        db.doc(`users/${auth.uid}`),
        db.doc(`users/${recipientId}`),
        db.doc(`restrictions/${auth.uid}`),
        db.doc(`restrictions/${recipientId}`),
        db.doc(`users/${auth.uid}/blocked/${recipientId}`),
        db.doc(`users/${recipientId}/blocked/${auth.uid}`),
        db.doc(`directConversationPairs/${canonicalPairKey(
          ...preliminary.participants,
        )}`),
        ...directMessagePrivacyReferences(db, auth.uid, recipientId),
      );
      const context = validateConversation(
        conversation,
        conversationId,
        auth.uid,
        related[6],
      );
      activeProfile(related[0], "Your");
      activeProfile(related[1], "The recipient");
      assertNotRestricted(related[2], "Your", timing.nowMs);
      assertNotRestricted(related[3], "The recipient", timing.nowMs);
      assertNotBlocked(related[4], related[5]);
      assertDirectMessagePrivacyFromRelated({
        actorId: auth.uid,
        recipientId,
        recipientProfile: related[1],
        related,
        offset: 7,
      });
      const sequence = incrementCanonicalCount(
        context.data.lastMessageSequence,
        "lastMessageSequence",
      );
      const preview = reservation.type === "image" ? "Photo" : "Voice message";
      transaction.create(messageRef, {
        schemaVersion: 2,
        sequence,
        conversationId,
        senderId: auth.uid,
        type: reservation.type,
        content: "",
        mediaUrl: mediaReference,
        durationSeconds: reservation.durationSeconds,
        sentAt: timing.now,
        readBy: [auth.uid],
        reactions: {},
        isDeleted: false,
        editedAt: null,
        replyToMessageId: null,
        replyToSenderId: null,
        replyToContent: null,
      });
      const unreadCounts = { ...context.data.unreadCounts };
      unreadCounts[auth.uid] = 0;
      unreadCounts[recipientId] = incrementCanonicalCount(
        unreadCounts[recipientId],
        "Recipient unread count",
      );
      transaction.update(conversationRef, {
        lastMessage: preview,
        lastMessageId: messageId,
        lastMessageSequence: sequence,
        lastMessageType: reservation.type,
        lastMessageSenderId: auth.uid,
        updatedAt: timing.now,
        archivedBy: [],
        unreadCounts,
      });
      transaction.delete(reservationRef);
      const result = {
        conversationId,
        messageId,
        recipientId,
        type: reservation.type,
        mediaSize: media.size,
        created: true,
      };
      transaction.create(ledgerRef, ledgerData({
        kind: "direct.attachment.finalize",
        uid: auth.uid,
        requestId,
        inputHash: identity.inputHash,
        result,
        now: timing.now,
      }));
      return result;
    });
  }

  async function mutateMessage(request, action) {
    const auth = requireActor(request);
    const isEdit = action === "edit";
    const allowed = isEdit
      ? ["conversationId", "messageId", "requestId", "text"]
      : ["conversationId", "messageId", "requestId"];
    const data = requireExactInput(
      request.data,
      allowed,
      allowed,
    );
    const conversationId = requireId(data.conversationId, "conversationId");
    const messageId = requireId(data.messageId, "messageId");
    const requestId = requireRequestId(data.requestId);
    const text = isEdit ? normalizeText(data.text, 2000, "text") : undefined;
    const kind = `direct.${action}`;
    const input = { conversationId, messageId, ...(isEdit ? { text } : {}) };
    const identity = operationIdentity(kind, auth.uid, requestId, input);
    const timing = time();
    const preflight = await beginAttemptPreflight({
      identity,
      kind,
      uid: auth.uid,
      requestId,
      scope: action,
      timing,
    });
    if (preflight.replay) return preflight.replay;

    return db.runTransaction(async (transaction) => {
      const ledgerRef = ledgerReference(identity);
      const rateRef = limitReference(action, auth.uid);
      const conversationRef = db.doc(`conversations/${conversationId}`);
      const messageRef = conversationRef.collection("messages").doc(messageId);
      const [ledger, rate, conversation, message] = await transactionGetAll(
        transaction,
        ledgerRef,
        rateRef,
        conversationRef,
        messageRef,
      );
      const replay = assertLedgerReplay(ledger, {
        kind,
        uid: auth.uid,
        inputHash: identity.inputHash,
      });
      if (replay) return replay;

      const preliminary = conversationParticipants(conversation, auth.uid);
      const recipientId = preliminary.participants.find((uid) => uid !== auth.uid);
      const related = await transactionGetAll(
        transaction,
        db.doc(`users/${auth.uid}`),
        db.doc(`users/${recipientId}`),
        db.doc(`restrictions/${auth.uid}`),
        db.doc(`restrictions/${recipientId}`),
        db.doc(`users/${auth.uid}/blocked/${recipientId}`),
        db.doc(`users/${recipientId}/blocked/${auth.uid}`),
        db.doc(`directConversationPairs/${canonicalPairKey(
          ...preliminary.participants,
        )}`),
      );
      const context = validateConversation(
        conversation,
        conversationId,
        auth.uid,
        related[6],
      );
      activeProfile(related[0], "Your");
      activeProfile(related[1], "The recipient");
      assertNotRestricted(related[2], "Your", timing.nowMs);
      assertNotRestricted(related[3], "The recipient", timing.nowMs);
      assertNotBlocked(related[4], related[5]);
      consume(transaction, rate, rateRef, action, auth.uid, timing);

      const messageData = validateMessage(message, conversationId);
      if (messageData.senderId !== auth.uid) {
        fail("permission-denied", "You can only change your own message.");
      }
      if (messageData.isDeleted) {
        if (isEdit) fail("failed-precondition", "Deleted messages cannot be edited.");
      } else if (isEdit) {
        if (messageData.type !== "text") {
          fail("failed-precondition", "Only text messages can be edited.");
        }
        transaction.update(messageRef, { content: text, editedAt: timing.now });
        if (context.data.lastMessageId === messageId) {
          transaction.update(conversationRef, {
            lastMessage: text,
            updatedAt: timing.now,
          });
        }
      } else {
        const attachmentPath = directMediaPathFromReference(
          messageData.mediaUrl,
          auth.uid,
          conversationId,
          messageId,
        );
        transaction.update(messageRef, {
          content: "",
          mediaUrl: null,
          durationSeconds: null,
          isDeleted: true,
          editedAt: timing.now,
          reactions: {},
        });
        if (context.data.lastMessageId === messageId) {
          transaction.update(conversationRef, {
            lastMessage: "Message deleted",
            updatedAt: timing.now,
          });
        }
        if (attachmentPath) {
          const outboxId = digest(
            "direct-attachment-cleanup",
            conversationId,
            messageId,
          );
          transaction.set(db.doc(`contentCleanupOutbox/${outboxId}`), {
            schemaVersion: 1,
            kind: "directMessageAttachment",
            rootPath: messageRef.path,
            objectPaths: [attachmentPath],
            status: "pending",
            attemptCount: 0,
            requestedBy: auth.uid,
            requestedReason: "authorDeletedMessage",
            createdAt: timing.now,
            updatedAt: timing.now,
          });
        }
      }

      const result = {
        conversationId,
        messageId,
        changed: !messageData.isDeleted || isEdit,
      };
      transaction.create(ledgerRef, ledgerData({
        kind,
        uid: auth.uid,
        requestId,
        inputHash: identity.inputHash,
        result,
        now: timing.now,
      }));
      return result;
    });
  }

  const editDirectMessage = (request) => mutateMessage(request, "edit");
  const deleteDirectMessage = (request) => mutateMessage(request, "delete");

  async function setDirectConversationPreference(request) {
    const auth = requireActor(request, { verified: false });
    const data = requireExactInput(
      request.data,
      ["conversationId", "enabled", "preference", "requestId"],
      ["conversationId", "enabled", "preference", "requestId"],
    );
    const conversationId = requireId(data.conversationId, "conversationId");
    const requestId = requireRequestId(data.requestId);
    const enabled = requireBoolean(data.enabled, "enabled");
    if (!["archived", "muted"].includes(data.preference)) {
      fail("invalid-argument", "preference must be archived or muted.");
    }
    const input = { conversationId, enabled, preference: data.preference };
    const identity = operationIdentity(
      "direct.preference",
      auth.uid,
      requestId,
      input,
    );
    const timing = time();
    const preflight = await beginAttemptPreflight({
      identity,
      kind: "direct.preference",
      uid: auth.uid,
      requestId,
      scope: "preference",
      timing,
    });
    if (preflight.replay) return preflight.replay;

    return db.runTransaction(async (transaction) => {
      const ledgerRef = ledgerReference(identity);
      const rateRef = limitReference("preference", auth.uid);
      const conversationRef = db.doc(`conversations/${conversationId}`);
      const [ledger, rate, conversation, profile] = await transactionGetAll(
        transaction,
        ledgerRef,
        rateRef,
        conversationRef,
        db.doc(`users/${auth.uid}`),
      );
      const replay = assertLedgerReplay(ledger, {
        kind: "direct.preference",
        uid: auth.uid,
        inputHash: identity.inputHash,
      });
      if (replay) return replay;
      activeProfile(profile, "Your");
      const preliminary = conversationParticipants(conversation, auth.uid);
      const pairGuard = await transaction.get(db.doc(
        `directConversationPairs/${canonicalPairKey(...preliminary.participants)}`,
      ));
      const context = validateConversation(
        conversation,
        conversationId,
        auth.uid,
        pairGuard,
      );
      consume(transaction, rate, rateRef, "preference", auth.uid, timing);
      const field = data.preference === "muted" ? "mutedBy" : "archivedBy";
      const update = {
        [field]: setMembership(context.data[field], auth.uid, enabled),
      };
      if (field === "archivedBy" && enabled) {
        update.unreadCounts = { ...context.data.unreadCounts, [auth.uid]: 0 };
      }
      transaction.update(conversationRef, update);
      const result = { conversationId, preference: data.preference, enabled };
      transaction.create(ledgerRef, ledgerData({
        kind: "direct.preference",
        uid: auth.uid,
        requestId,
        inputHash: identity.inputHash,
        result,
        now: timing.now,
      }));
      return result;
    });
  }

  async function markDirectConversationRead(request) {
    const auth = requireActor(request, { verified: false });
    const data = requireExactInput(
      request.data,
      ["conversationId", "requestId"],
      ["conversationId", "requestId"],
    );
    const conversationId = requireId(data.conversationId, "conversationId");
    const requestId = requireRequestId(data.requestId);
    const input = { conversationId };
    const identity = operationIdentity("direct.read", auth.uid, requestId, input);
    const timing = time();
    const preflight = await beginAttemptPreflight({
      identity,
      kind: "direct.read",
      uid: auth.uid,
      requestId,
      scope: "read",
      timing,
    });
    if (preflight.replay) return preflight.replay;
    return db.runTransaction(async (transaction) => {
      const ledgerRef = ledgerReference(identity);
      const rateRef = limitReference("read", auth.uid);
      const conversationRef = db.doc(`conversations/${conversationId}`);
      const [ledger, rate, conversation, profile] = await transactionGetAll(
        transaction,
        ledgerRef,
        rateRef,
        conversationRef,
        db.doc(`users/${auth.uid}`),
      );
      const replay = assertLedgerReplay(ledger, {
        kind: "direct.read",
        uid: auth.uid,
        inputHash: identity.inputHash,
      });
      if (replay) return replay;
      activeProfile(profile, "Your");
      const preliminary = conversationParticipants(conversation, auth.uid);
      const pairGuard = await transaction.get(db.doc(
        `directConversationPairs/${canonicalPairKey(...preliminary.participants)}`,
      ));
      const context = validateConversation(
        conversation,
        conversationId,
        auth.uid,
        pairGuard,
      );
      const currentSequence = nonNegativeCount(
        context.data.readSequences[auth.uid],
        "Current read sequence",
      );
      const targetSequence = nonNegativeCount(
        context.data.lastMessageSequence,
        "Last message sequence",
      );
      if (currentSequence > targetSequence) {
        fail("data-loss", "The read cursor is ahead of the conversation.");
      }
      const messageQuery = conversationRef
        .collection("messages")
        .where("sequence", ">", currentSequence)
        .orderBy("sequence")
        .limit(readPageSize + 1);
      const messagePage = await transaction.get(messageQuery);
      const page = messagePage.docs.slice(0, readPageSize);
      let markedCount = 0;
      let previousSequence = currentSequence;
      for (const document of page) {
        const message = validateMessage(document, conversationId);
        if (!context.participants.includes(message.senderId) ||
            message.sequence <= previousSequence ||
            message.sequence > targetSequence ||
            new Set(message.readBy).size !== message.readBy.length ||
            message.readBy.some((uid) => !context.participants.includes(uid))) {
          fail("data-loss", "A message read receipt is malformed.");
        }
        previousSequence = message.sequence;
      }
      consume(transaction, rate, rateRef, "read", auth.uid, timing);
      for (const document of page) {
        const message = document.data();
        if (!message.readBy.includes(auth.uid)) {
          transaction.update(document.ref, {
            readBy: [...message.readBy, auth.uid].sort(),
          });
          markedCount += 1;
        }
      }
      const processedSequence = page.at(-1)?.data().sequence ?? targetSequence;
      const completed = messagePage.size <= readPageSize;
      const rootUpdate = {
        readSequences: {
          ...context.data.readSequences,
          [auth.uid]: completed ? targetSequence : processedSequence,
        },
      };
      if (completed) {
        rootUpdate.unreadCounts = {
          ...context.data.unreadCounts,
          [auth.uid]: 0,
        };
      }
      transaction.update(conversationRef, rootUpdate);
      const result = {
        conversationId,
        completed,
        markedCount,
        nextReadSequence: rootUpdate.readSequences[auth.uid],
        unreadCount: completed ? 0 : context.data.unreadCounts[auth.uid],
      };
      transaction.create(ledgerRef, ledgerData({
        kind: "direct.read",
        uid: auth.uid,
        requestId,
        inputHash: identity.inputHash,
        result,
        now: timing.now,
      }));
      return result;
    });
  }

  async function setDirectMessageReaction(request) {
    const auth = requireActor(request);
    const data = requireExactInput(
      request.data,
      ["conversationId", "emoji", "messageId", "requestId"],
      ["conversationId", "emoji", "messageId", "requestId"],
    );
    const conversationId = requireId(data.conversationId, "conversationId");
    const messageId = requireId(data.messageId, "messageId");
    const requestId = requireRequestId(data.requestId);
    const emoji = data.emoji === null ? null : String(data.emoji ?? "");
    if (emoji !== null && !ALLOWED_DIRECT_REACTIONS.includes(emoji)) {
      fail("invalid-argument", "emoji is not an allowed direct-message reaction.");
    }
    const input = { conversationId, emoji, messageId };
    const identity = operationIdentity(
      "direct.reaction",
      auth.uid,
      requestId,
      input,
    );
    const timing = time();
    const preflight = await beginAttemptPreflight({
      identity,
      kind: "direct.reaction",
      uid: auth.uid,
      requestId,
      scope: "reaction",
      timing,
    });
    if (preflight.replay) return preflight.replay;
    return db.runTransaction(async (transaction) => {
      const ledgerRef = ledgerReference(identity);
      const rateRef = limitReference("reaction", auth.uid);
      const conversationRef = db.doc(`conversations/${conversationId}`);
      const messageRef = conversationRef.collection("messages").doc(messageId);
      const [ledger, rate, conversation, message] = await transactionGetAll(
        transaction,
        ledgerRef,
        rateRef,
        conversationRef,
        messageRef,
      );
      const replay = assertLedgerReplay(ledger, {
        kind: "direct.reaction",
        uid: auth.uid,
        inputHash: identity.inputHash,
      });
      if (replay) return replay;
      const preliminary = conversationParticipants(conversation, auth.uid);
      const recipientId = preliminary.participants.find((uid) => uid !== auth.uid);
      const related = await transactionGetAll(
        transaction,
        db.doc(`users/${auth.uid}`),
        db.doc(`users/${recipientId}`),
        db.doc(`restrictions/${auth.uid}`),
        db.doc(`restrictions/${recipientId}`),
        db.doc(`users/${auth.uid}/blocked/${recipientId}`),
        db.doc(`users/${recipientId}/blocked/${auth.uid}`),
        db.doc(`directConversationPairs/${canonicalPairKey(
          ...preliminary.participants,
        )}`),
      );
      const context = validateConversation(
        conversation,
        conversationId,
        auth.uid,
        related[6],
      );
      activeProfile(related[0], "Your");
      activeProfile(related[1], "The recipient");
      assertNotRestricted(related[2], "Your", timing.nowMs);
      assertNotRestricted(related[3], "The recipient", timing.nowMs);
      assertNotBlocked(related[4], related[5]);
      const messageData = validateMessage(message, conversationId);
      if (!context.participants.includes(messageData.senderId) ||
          messageData.isDeleted) {
        fail("failed-precondition", "This message cannot be reacted to.");
      }
      const reactions = messageData.reactions;
      if (Object.keys(reactions).some((uid) =>
        !context.participants.includes(uid) ||
        !ALLOWED_DIRECT_REACTIONS.includes(reactions[uid]))) {
        fail("data-loss", "The direct-message reactions are malformed.");
      }
      consume(transaction, rate, rateRef, "reaction", auth.uid, timing);
      const previous = reactions[auth.uid] ?? null;
      const changed = previous !== emoji;
      if (changed) {
        const next = { ...reactions };
        if (emoji === null) delete next[auth.uid];
        else next[auth.uid] = emoji;
        transaction.update(messageRef, { reactions: next });
        if (emoji !== null) {
          transaction.create(db.doc(`directReactionEvents/${identity.id}`), {
            schemaVersion: 1,
            actorId: auth.uid,
            authorId: messageData.senderId,
            recipientId,
            conversationId,
            messageId,
            emoji,
            sourceKey: `conversations/${conversationId}/messages/${messageId}`,
            createdAt: timing.now,
          });
        }
      }
      const result = { conversationId, messageId, emoji, changed };
      transaction.create(ledgerRef, ledgerData({
        kind: "direct.reaction",
        uid: auth.uid,
        requestId,
        inputHash: identity.inputHash,
        result,
        now: timing.now,
      }));
      return result;
    });
  }

  async function setDirectTyping(request) {
    const auth = requireActor(request);
    const data = requireExactInput(
      request.data,
      ["conversationId", "isTyping", "requestId"],
      ["conversationId", "isTyping", "requestId"],
    );
    const conversationId = requireId(data.conversationId, "conversationId");
    const requestId = requireRequestId(data.requestId);
    const isTyping = requireBoolean(data.isTyping, "isTyping");
    const input = { conversationId, isTyping };
    const identity = operationIdentity("direct.typing", auth.uid, requestId, input);
    const timing = time();
    const preflight = await beginAttemptPreflight({
      identity,
      kind: "direct.typing",
      uid: auth.uid,
      requestId,
      scope: "typing",
      timing,
    });
    if (preflight.replay) return preflight.replay;
    return db.runTransaction(async (transaction) => {
      const ledgerRef = ledgerReference(identity);
      const rateRef = limitReference("typing", auth.uid);
      const conversationRef = db.doc(`conversations/${conversationId}`);
      const [ledger, rate, conversation] = await transactionGetAll(
        transaction,
        ledgerRef,
        rateRef,
        conversationRef,
      );
      const replay = assertLedgerReplay(ledger, {
        kind: "direct.typing",
        uid: auth.uid,
        inputHash: identity.inputHash,
      });
      if (replay) return replay;
      const preliminary = conversationParticipants(conversation, auth.uid);
      const recipientId = preliminary.participants.find((uid) => uid !== auth.uid);
      const related = await transactionGetAll(
        transaction,
        db.doc(`users/${auth.uid}`),
        db.doc(`users/${recipientId}`),
        db.doc(`restrictions/${auth.uid}`),
        db.doc(`restrictions/${recipientId}`),
        db.doc(`users/${auth.uid}/blocked/${recipientId}`),
        db.doc(`users/${recipientId}/blocked/${auth.uid}`),
        db.doc(`directConversationPairs/${canonicalPairKey(
          ...preliminary.participants,
        )}`),
      );
      const context = validateConversation(
        conversation,
        conversationId,
        auth.uid,
        related[6],
      );
      activeProfile(related[0], "Your");
      activeProfile(related[1], "The recipient");
      assertNotRestricted(related[2], "Your", timing.nowMs);
      assertNotRestricted(related[3], "The recipient", timing.nowMs);
      assertNotBlocked(related[4], related[5]);
      consume(transaction, rate, rateRef, "typing", auth.uid, timing);
      transaction.update(conversationRef, {
        typing: {
          ...context.data.typing,
          [auth.uid]: { isTyping, updatedAt: timing.now },
        },
      });
      const result = { conversationId, isTyping };
      transaction.create(ledgerRef, ledgerData({
        kind: "direct.typing",
        uid: auth.uid,
        requestId,
        inputHash: identity.inputHash,
        result,
        now: timing.now,
      }));
      return result;
    });
  }

  async function expireAbandonedAttachmentReservations({ limit = 100 } = {}) {
    requireSafeInteger(limit, "limit", { min: 1, max: 100 });
    const timing = time();
    const snapshot = await db.collection("directMessageUploadReservations")
      .where("expiresAt", "<=", timing.now)
      .limit(limit)
      .get();
    const expired = [];
    const malformed = [];
    for (const document of snapshot.docs) {
      const outcome = await db.runTransaction(async (transaction) => {
        const current = await transaction.get(document.ref);
        if (!current.exists) return "gone";
        const data = current.data() ?? {};
        const expiresAt = timestampMillis(data.expiresAt);
        if (data.status !== "uploading" || expiresAt === null ||
            expiresAt > timing.nowMs) return "unchanged";
        const config = DIRECT_MEDIA_TYPES[data.type];
        const canonical = config && isValidOpaqueUid(data.ownerId) &&
          typeof data.conversationId === "string" && SAFE_ID.test(data.conversationId) &&
          data.messageId === current.id && /^m_[a-f0-9]{40}$/u.test(current.id) &&
          config.contentTypes.includes(data.contentType) &&
          data.storagePath === directMediaStoragePath(
            data.ownerId,
            data.conversationId,
            current.id,
            data.type,
            data.contentType,
          );
        transaction.delete(current.ref);
        if (!canonical) {
          transaction.set(db.doc(`contentCleanupQuarantine/${digest(
            "direct-reservation-quarantine",
            current.id,
          )}`), {
            schemaVersion: 1,
            rootPath: current.ref.path,
            reason: "nonCanonicalExpiredDirectAttachmentReservation",
            createdAt: timing.now,
          });
          return "malformed";
        }
        const outboxId = digest("direct-reservation-cleanup", current.id);
        transaction.set(db.doc(`contentCleanupOutbox/${outboxId}`), {
          schemaVersion: 1,
          kind: "directMessageAttachmentReservation",
          rootPath: current.ref.path,
          objectPaths: [data.storagePath],
          status: "pending",
          attemptCount: 0,
          requestedBy: data.ownerId,
          requestedReason: "expiredUploadReservation",
          createdAt: timing.now,
          updatedAt: timing.now,
        });
        return "expired";
      });
      if (outcome === "expired") expired.push(document.id);
      if (outcome === "malformed") malformed.push(document.id);
    }
    return { expired, malformed, hasMore: snapshot.size === limit };
  }

  return {
    deleteDirectMessage,
    editDirectMessage,
    expireAbandonedAttachmentReservations,
    finalizeDirectMessageAttachment,
    markDirectConversationRead,
    openDirectConversation,
    reserveDirectMessageAttachment,
    sendDirectMessage,
    setDirectConversationPreference,
    setDirectMessageReaction,
    setDirectTyping,
  };
}

module.exports = {
  ALLOWED_DIRECT_REACTIONS,
  DEFAULT_LIMITS,
  canonicalConversationId,
  canonicalPairKey,
  createDirectMessagingService,
  directMediaMessageId,
  directMediaStoragePath,
  validateStoredDirectMedia,
  validateConversation,
  validateMessage,
};
