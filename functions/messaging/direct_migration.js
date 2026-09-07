const {
  SAFE_ID,
  canonicalPair,
  canonicalPublicProfile,
  digest,
  fail,
  isValidOpaqueUid,
  requireId,
  requireSafeInteger,
  timestampMillis,
} = require("../integrity/guards");
const {
  ALLOWED_DIRECT_REACTIONS,
  canonicalConversationId,
  canonicalPairKey,
} = require("./direct_integrity");

function samePair(value, participants) {
  if (!Array.isArray(value) || value.length !== 2 ||
      value.some((uid) => !isValidOpaqueUid(uid))) {
    return false;
  }
  try {
    const pair = canonicalPair(...value);
    return pair.every((uid, index) => uid === participants[index]);
  } catch (_) {
    return false;
  }
}

function boundedString(value, maxLength, fallback = "") {
  return typeof value === "string" && value.length <= maxLength
    ? value
    : fallback;
}

function timestampOr(value, fallback) {
  return timestampMillis(value) === null ? fallback : value;
}

// Carries `deletedBy`/`deletedSequences` through canonicalization, or omits
// both when the root never had them. Omitting is what keeps this pass a
// no-op for the roots that predate the feature: adding empty keys would make
// every already-migrated conversation look like it needed migrating again.
function canonicalDeletionState(rootData, participants, lastMessageSequence) {
  const hasDeletedBy = Array.isArray(rootData.deletedBy);
  const sequences = rootData.deletedSequences;
  const hasSequences = sequences !== null && typeof sequences === "object" &&
    !Array.isArray(sequences);
  if (!hasDeletedBy && !hasSequences) return {};
  const cutFor = (uid) => {
    const value = hasSequences ? sequences[uid] : 0;
    if (!Number.isSafeInteger(value) || value < 0) return 0;
    return Math.min(value, lastMessageSequence);
  };
  return {
    deletedBy: hasDeletedBy
      ? [...new Set(
        rootData.deletedBy.filter((uid) => participants.includes(uid)),
      )].sort()
      : [],
    deletedSequences: Object.fromEntries(
      participants.map((uid) => [uid, cutFor(uid)]),
    ),
  };
}

function valuesEqual(left, right) {
  if (left === right) return true;
  const leftMs = timestampMillis(left);
  const rightMs = timestampMillis(right);
  if (leftMs !== null || rightMs !== null) return leftMs === rightMs;
  if (Array.isArray(left) || Array.isArray(right)) {
    return Array.isArray(left) && Array.isArray(right) &&
      left.length === right.length &&
      left.every((value, index) => valuesEqual(value, right[index]));
  }
  if (left && right && typeof left === "object" && typeof right === "object") {
    const leftKeys = Object.keys(left).sort();
    const rightKeys = Object.keys(right).sort();
    return leftKeys.length === rightKeys.length &&
      leftKeys.every((key, index) => key === rightKeys[index] &&
        valuesEqual(left[key], right[key]));
  }
  return false;
}

function sameUpdateTime(snapshot, expected) {
  if (!snapshot?.exists || !expected) return false;
  return typeof snapshot.updateTime?.isEqual === "function"
    ? snapshot.updateTime.isEqual(expected)
    : timestampMillis(snapshot.updateTime) === timestampMillis(expected);
}

function createDirectMigrationService({
  db,
  FieldPath,
  Timestamp,
  clock = () => Date.now(),
  beforeApply = null,
}) {
  if (!db || !FieldPath?.documentId || !Timestamp?.fromMillis) {
    throw new TypeError("db, FieldPath and Timestamp are required.");
  }
  if (beforeApply !== null && typeof beforeApply !== "function") {
    throw new TypeError("beforeApply must be a function.");
  }

  function now() {
    const value = clock();
    if (!Number.isSafeInteger(value) || value < 0) {
      throw new TypeError("clock must return epoch milliseconds.");
    }
    return Timestamp.fromMillis(value);
  }

  async function legacyPairCandidates(conversationId) {
    const splitIndexes = [];
    for (let index = 0; index < conversationId.length; index += 1) {
      if (conversationId[index] === "_") splitIndexes.push(index);
    }
    if (splitIndexes.length > 64) return { candidates: [], overflow: true };
    const rawPairs = [];
    for (const index of splitIndexes) {
      const first = conversationId.slice(0, index);
      const second = conversationId.slice(index + 1);
      if (!isValidOpaqueUid(first) || !isValidOpaqueUid(second) ||
          first === second) continue;
      const pair = canonicalPair(first, second);
      if (`${pair[0]}_${pair[1]}` === conversationId) rawPairs.push(pair);
    }
    const ids = [...new Set(rawPairs.flat())];
    if (ids.length === 0) return { candidates: [], overflow: false };
    const profiles = await db.getAll(...ids.map((uid) => db.doc(`users/${uid}`)));
    const existing = new Set(profiles.filter((doc) => doc.exists).map((doc) => doc.id));
    const candidates = rawPairs.filter((pair) =>
      existing.has(pair[0]) && existing.has(pair[1]));
    const unique = new Map(candidates.map((pair) => [pair.join("\u0000"), pair]));
    return { candidates: [...unique.values()], overflow: false };
  }

  function canonicalizeMessage(document, conversationId, participants) {
    const data = document.data() ?? {};
    const issues = [];
    if (!participants.includes(data.senderId)) issues.push("invalidMessageSender");
    if (!["text", "voice", "image"].includes(data.type)) {
      issues.push("invalidMessageType");
    }
    if (typeof data.content !== "string" || data.content.length > 2000) {
      issues.push("invalidMessageContent");
    }
    if (data.mediaUrl !== null && data.mediaUrl !== undefined &&
        (typeof data.mediaUrl !== "string" || data.mediaUrl.length > 4096)) {
      issues.push("invalidMessageMediaUrl");
    }
    if (data.durationSeconds !== null && data.durationSeconds !== undefined &&
        (!Number.isSafeInteger(data.durationSeconds) ||
          data.durationSeconds < 1 || data.durationSeconds > 300)) {
      issues.push("invalidMessageDuration");
    }
    if (timestampMillis(data.sentAt) === null) issues.push("invalidMessageTimestamp");
    const readBy = Array.isArray(data.readBy) ? data.readBy : [];
    if (new Set(readBy).size !== readBy.length ||
        readBy.some((uid) => !participants.includes(uid)) ||
        !readBy.includes(data.senderId)) {
      issues.push("invalidMessageReadBy");
    }
    const reactions = data.reactions && typeof data.reactions === "object" &&
      !Array.isArray(data.reactions) ? data.reactions : {};
    if (Object.keys(reactions).some((uid) =>
      !participants.includes(uid) ||
      !ALLOWED_DIRECT_REACTIONS.includes(reactions[uid]))) {
      issues.push("invalidMessageReactions");
    }
    if (typeof (data.isDeleted ?? false) !== "boolean") {
      issues.push("invalidMessageDeletionState");
    }
    const replyToMessageId = data.replyToMessageId ?? null;
    if (replyToMessageId !== null &&
        (typeof replyToMessageId !== "string" || !SAFE_ID.test(replyToMessageId))) {
      issues.push("invalidMessageReplyId");
    }
    return {
      issues,
      sentAtMs: timestampMillis(data.sentAt) ?? 0,
      sourceData: data,
      sourceUpdateTime: document.updateTime,
      data: {
        schemaVersion: 2,
        sequence: 0,
        conversationId,
        senderId: data.senderId,
        type: data.type,
        content: data.isDeleted === true ? "" : data.content,
        mediaUrl: data.isDeleted === true ? null : data.mediaUrl ?? null,
        durationSeconds: data.isDeleted === true
          ? null
          : data.durationSeconds ?? null,
        sentAt: data.sentAt,
        readBy,
        reactions: data.isDeleted === true ? {} : reactions,
        isDeleted: data.isDeleted ?? false,
        editedAt: timestampMillis(data.editedAt) === null ? null : data.editedAt,
        replyToMessageId,
        replyToSenderId: data.replyToSenderId ?? null,
        replyToContent: data.replyToContent === null ||
          data.replyToContent === undefined
          ? null
          : boundedString(data.replyToContent, 240, null),
      },
    };
  }

  async function inspectDirectConversation({
    conversationId,
    maxMessages = 400,
  }) {
    requireId(conversationId, "conversationId");
    requireSafeInteger(maxMessages, "maxMessages", { min: 1, max: 400 });
    const conversationRef = db.doc(`conversations/${conversationId}`);
    const root = await conversationRef.get();
    if (!root.exists) return { conversationId, status: "missing", issues: ["missing"] };
    const rootData = root.data() ?? {};
    const issues = [];
    if (!Array.isArray(rootData.participantIds) ||
        rootData.participantIds.length !== 2 ||
        rootData.participantIds.some((uid) => !isValidOpaqueUid(uid))) {
      return {
        conversationId,
        status: "conflict",
        issues: ["invalidParticipants"],
      };
    }
    const participants = canonicalPair(...rootData.participantIds);
    const pairKey = canonicalPairKey(...participants);
    const legacyId = `${participants[0]}_${participants[1]}`;
    const hashedId = canonicalConversationId(...participants);
    if (![legacyId, hashedId].includes(conversationId)) {
      issues.push("unexpectedConversationId");
    }

    if (conversationId === legacyId) {
      const collision = await legacyPairCandidates(conversationId);
      if (collision.overflow) issues.push("legacyIdSplitLimitExceeded");
      if (collision.candidates.length > 1) issues.push("legacyIdCollision");
      if (collision.candidates.length === 1 &&
          !samePair(collision.candidates[0], participants)) {
        issues.push("legacyIdParticipantMismatch");
      }
    }

    const [guard, duplicateQuery, profiles, messagePage] = await Promise.all([
      db.doc(`directConversationPairs/${pairKey}`).get(),
      db.collection("conversations")
        .where("participantIds", "array-contains", participants[0])
        .limit(21)
        .get(),
      db.getAll(...participants.map((uid) => db.doc(`publicProfiles/${uid}`))),
      conversationRef.collection("messages").limit(maxMessages + 1).get(),
    ]);
    const duplicates = duplicateQuery.docs.filter((doc) =>
      samePair(doc.data()?.participantIds, participants));
    if (duplicates.length > 1) issues.push("duplicatePairRoots");
    if (duplicateQuery.size > 20) issues.push("duplicateScanLimitExceeded");
    if (guard.exists) {
      const guardData = guard.data() ?? {};
      const guardKeys = Object.keys(guardData).sort();
      const expectedGuardKeys = [
        "conversationId",
        "createdAt",
        "pairKey",
        "participantIds",
        "schemaVersion",
      ];
      if (guardKeys.length !== expectedGuardKeys.length ||
          guardKeys.some((key, index) => key !== expectedGuardKeys[index]) ||
          guardData.schemaVersion !== 1 ||
          timestampMillis(guardData.createdAt) === null ||
          guardData.conversationId !== conversationId ||
          !samePair(guardData.participantIds, participants) ||
          guardData.pairKey !== pairKey) {
        issues.push("pairGuardConflict");
      }
    }
    if (messagePage.size > maxMessages) issues.push("messageLimitExceeded");

    const canonicalMessages = messagePage.docs.slice(0, maxMessages).map((doc) => ({
      id: doc.id,
      ref: doc.ref,
      ...canonicalizeMessage(doc, conversationId, participants),
    }));
    const messageIds = new Set(canonicalMessages.map((message) => message.id));
    for (const message of canonicalMessages) {
      issues.push(...message.issues.map((issue) => `${issue}:${message.id}`));
      const replyId = message.data.replyToMessageId;
      if (replyId !== null && !messageIds.has(replyId)) {
        issues.push(`orphanMessageReply:${message.id}`);
      }
    }
    canonicalMessages.sort((first, second) =>
      first.sentAtMs - second.sentAtMs ||
      (first.id < second.id ? -1 : first.id > second.id ? 1 : 0));
    canonicalMessages.forEach((message, index) => {
      message.data.sequence = index + 1;
    });
    const messageById = new Map(canonicalMessages.map((message) => [
      message.id,
      message,
    ]));
    for (const message of canonicalMessages) {
      const replyId = message.data.replyToMessageId;
      if (replyId === null) {
        message.data.replyToSenderId = null;
        message.data.replyToContent = null;
        continue;
      }
      const target = messageById.get(replyId);
      if (!target) continue;
      message.data.replyToSenderId = target.data.senderId;
      message.data.replyToContent = target.data.isDeleted
        ? "Message deleted"
        : String(target.data.content || target.data.type).slice(0, 240);
    }
    const messagesNeedMigration = canonicalMessages.some((message) =>
      !valuesEqual(message.sourceData, message.data));

    const identityById = new Map();
    for (const profile of profiles) {
      try {
        identityById.set(profile.id, canonicalPublicProfile(profile, profile.id));
      } catch (_) {
        issues.push(`invalidPublicProfile:${profile.id}`);
      }
    }
    const unreadCounts = Object.fromEntries(participants.map((uid) => [
      uid,
      canonicalMessages.filter((message) =>
        message.data.senderId !== uid && !message.data.readBy.includes(uid)).length,
    ]));
    const readSequences = Object.fromEntries(participants.map((uid) => {
      let contiguous = 0;
      for (const message of canonicalMessages) {
        if (!message.data.readBy.includes(uid)) break;
        contiguous = message.data.sequence;
      }
      return [uid, contiguous];
    }));
    const last = canonicalMessages.at(-1) ?? null;
    const generatedAt = now();
    const canonicalRoot = {
      schemaVersion: 2,
      pairKey,
      participantIds: participants,
      participantNames: Object.fromEntries(participants.map((uid) => [
        uid,
        identityById.get(uid)?.displayName ?? "YO Voice user",
      ])),
      participantEmails: Object.fromEntries(participants.map((uid) => [uid, ""])),
      participantPhotoUrls: Object.fromEntries(participants.map((uid) => [
        uid,
        identityById.get(uid)?.photoUrl ?? "",
      ])),
      unreadCounts,
      readSequences,
      // Typing is ephemeral and legacy roots allowed one participant to
      // overwrite the peer's state. Never migrate unauthenticated presence.
      typing: {},
      archivedBy: Array.isArray(rootData.archivedBy)
        ? [...new Set(rootData.archivedBy.filter((uid) => participants.includes(uid)))].sort()
        : [],
      mutedBy: Array.isArray(rootData.mutedBy)
        ? [...new Set(rootData.mutedBy.filter((uid) => participants.includes(uid)))].sort()
        : [],
      // Per-user deletion state must SURVIVE canonicalization. Rebuilding the
      // root without it would silently un-delete every thread someone had
      // deleted and resurrect the history behind their cut-off — the exact
      // privacy failure the feature exists to prevent. The cut-off is clamped
      // to the recomputed length because this pass renumbers `sequence`.
      ...canonicalDeletionState(rootData, participants, last?.data.sequence ?? 0),
      lastMessage: last === null
        ? ""
        : last.data.isDeleted
          ? "Message deleted"
          : last.data.type === "text"
            ? last.data.content
            : "",
      lastMessageId: last?.id ?? null,
      lastMessageSequence: last?.data.sequence ?? 0,
      lastMessageType: last?.data.type ?? "text",
      lastMessageSenderId: last?.data.senderId ?? "",
      createdAt: timestampOr(rootData.createdAt, generatedAt),
      updatedAt: timestampOr(rootData.updatedAt, generatedAt),
    };

    const uniqueIssues = [...new Set(issues)].sort();
    const rootNeedsMigration = !valuesEqual(rootData, canonicalRoot);
    return {
      conversationId,
      participants,
      pairKey,
      sourceUpdateTime: root.updateTime,
      sourceGuardExists: guard.exists,
      sourceGuardUpdateTime: guard.updateTime ?? null,
      status: uniqueIssues.length > 0
        ? "conflict"
        : !rootNeedsMigration && !messagesNeedMigration && guard.exists
          ? "alreadyMigrated"
          : "ready",
      issues: uniqueIssues,
      messageCount: canonicalMessages.length,
      canonicalMessages,
      canonicalRoot,
    };
  }

  async function migrateDirectConversation({
    conversationId,
    dryRun = true,
    maxMessages = 400,
  }) {
    const inspection = await inspectDirectConversation({
      conversationId,
      maxMessages,
    });
    const publicResult = {
      conversationId,
      status: inspection.status,
      issues: inspection.issues,
      messageCount: inspection.messageCount ?? 0,
      pairKey: inspection.pairKey ?? null,
      dryRun,
    };
    if (dryRun || inspection.status === "missing" ||
        inspection.status === "alreadyMigrated") {
      return publicResult;
    }
    if (inspection.status === "conflict") {
      const conflictId = digest("direct-migration-conflict", conversationId);
      const conflictRef = db.doc(`directMigrationConflicts/${conflictId}`);
      await db.runTransaction(async (transaction) => {
        const existing = await transaction.get(conflictRef);
        if (existing.exists) {
          const stored = existing.data() ?? {};
          if (stored.conversationId !== conversationId ||
              stored.pairKey !== (inspection.pairKey ?? null) ||
              !valuesEqual(stored.issues, inspection.issues.slice(0, 100))) {
            fail("data-loss", "The migration conflict ledger is inconsistent.");
          }
          return;
        }
        transaction.create(conflictRef, {
          schemaVersion: 1,
          conversationId,
          pairKey: inspection.pairKey ?? null,
          issues: inspection.issues.slice(0, 100),
          status: "open",
          detectedAt: now(),
        });
      });
      return { ...publicResult, conflictId };
    }

    const rootRef = db.doc(`conversations/${conversationId}`);
    const guardRef = db.doc(`directConversationPairs/${inspection.pairKey}`);
    if (beforeApply) await beforeApply({ inspection });
    await db.runTransaction(async (transaction) => {
      const messageQuery = rootRef.collection("messages").limit(maxMessages + 1);
      const [currentRoot, currentGuard, currentMessages] = await Promise.all([
        transaction.get(rootRef),
        transaction.get(guardRef),
        transaction.get(messageQuery),
      ]);
      if (!sameUpdateTime(currentRoot, inspection.sourceUpdateTime)) {
        fail("aborted", "The conversation changed during migration.");
      }
      if (currentGuard.exists !== inspection.sourceGuardExists ||
          (currentGuard.exists && !sameUpdateTime(
            currentGuard,
            inspection.sourceGuardUpdateTime,
          ))) {
        fail("aborted", "The pair guard changed during migration.");
      }
      if (currentGuard.exists) {
        const guard = currentGuard.data() ?? {};
        if (guard.conversationId !== conversationId ||
            !samePair(guard.participantIds, inspection.participants)) {
          fail("data-loss", "The pair guard changed during migration.");
        }
      }
      if (currentMessages.size !== inspection.canonicalMessages.length) {
        fail("aborted", "Messages changed during migration.");
      }
      const expectedMessages = new Map(inspection.canonicalMessages.map(
        (message) => [message.id, message],
      ));
      for (const current of currentMessages.docs) {
        const expected = expectedMessages.get(current.id);
        if (!expected || !sameUpdateTime(current, expected.sourceUpdateTime)) {
          fail("aborted", "Messages changed during migration.");
        }
      }
      for (const message of inspection.canonicalMessages) {
        transaction.set(message.ref, message.data);
      }
      transaction.set(rootRef, inspection.canonicalRoot);
      transaction.set(guardRef, {
        schemaVersion: 1,
        pairKey: inspection.pairKey,
        conversationId,
        participantIds: inspection.participants,
        createdAt: now(),
      });
    });
    return { ...publicResult, status: "migrated" };
  }

  async function scanDirectConversationMigration({
    limit = 50,
    cursor = null,
    maxMessages = 400,
  } = {}) {
    requireSafeInteger(limit, "limit", { min: 1, max: 100 });
    if (cursor !== null) requireId(cursor, "cursor");
    let query = db.collection("conversations")
      .orderBy(FieldPath.documentId())
      .limit(limit);
    if (cursor) query = query.startAfter(cursor);
    const snapshot = await query.get();
    const results = [];
    for (const document of snapshot.docs) {
      const inspected = await inspectDirectConversation({
        conversationId: document.id,
        maxMessages,
      });
      results.push({
        conversationId: document.id,
        status: inspected.status,
        issues: inspected.issues.slice(0, 20),
        issueCount: inspected.issues.length,
        messageCount: inspected.messageCount ?? 0,
      });
    }
    return {
      results,
      nextCursor: snapshot.docs.at(-1)?.id ?? null,
      hasMore: snapshot.size === limit,
    };
  }

  return {
    inspectDirectConversation,
    migrateDirectConversation,
    scanDirectConversationMigration,
  };
}

module.exports = { createDirectMigrationService };
