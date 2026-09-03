const {
  SAFE_ID,
  canonicalPair,
  fail,
  isValidOpaqueUid,
  operationIdentity,
  requireRequestId,
  requireSafeInteger,
  timestampMillis,
} = require("../integrity/guards");
const {
  canonicalPairKey,
  directMediaStoragePath,
  validateConversation,
  validateDirectMediaProbe,
  validateMessage,
  validateStoredDirectMedia,
} = require("./direct_integrity");

const DEFAULT_PAGE_SIZE = 25;
const MAX_PAGE_SIZE = 100;
const FINALIZED_METADATA_KEY = "yovoiceFinalized";
const FINALIZED_METADATA_VALUE = "true";

function customMetadataOf(metadata) {
  const custom = metadata?.metadata ?? metadata?.customMetadata;
  return custom && typeof custom === "object" && !Array.isArray(custom)
    ? custom
    : {};
}

function hasFirebaseDownloadToken(metadata) {
  const token = customMetadataOf(metadata).firebaseStorageDownloadTokens;
  return typeof token === "string" && token.length > 0;
}

function missingObject(error) {
  return (
    error?.code === 404 ||
    error?.code === "404" ||
    error?.code === "storage/object-not-found" ||
    /(?:missing fake object|no such object|not found)/iu.test(
      String(error?.message ?? ""),
    )
  );
}

function parseDirectAttachmentPath(path) {
  if (typeof path !== "string" || path.length > 1024) return null;
  const segments = path.split("/");
  if (
    segments.length !== 4 ||
    segments[0] !== "message_attachments" ||
    !isValidOpaqueUid(segments[1]) ||
    !SAFE_ID.test(segments[2])
  ) {
    return null;
  }
  const match = /^(m_[a-f0-9]{40})[.](jpg|png|webp|m4a|mp4|mov|webm)$/u.exec(
    segments[3],
  );
  if (match === null) return null;
  return {
    ownerId: segments[1],
    conversationId: segments[2],
    messageId: match[1],
  };
}

function sameStoredObject(left, right) {
  return (
    String(left?.generation ?? "") === String(right?.generation ?? "") &&
    String(left?.size ?? "") === String(right?.size ?? "") &&
    left?.contentType === right?.contentType
  );
}

function expectedValidationError(error) {
  return new Set([
    "data-loss",
    "failed-precondition",
    "not-found",
    "permission-denied",
  ]).has(error?.code);
}

function createDirectAttachmentMigrationService({
  db,
  storage,
  mediaProbe,
  beforeFinalize = null,
}) {
  if (
    !db?.doc ||
    !db?.collection ||
    !storage?.getMetadata ||
    !storage?.getObjectReference ||
    !storage?.listObjects ||
    !storage?.revokeDownloadTokens ||
    typeof mediaProbe !== "function"
  ) {
    throw new TypeError(
      "db, direct-attachment storage and a trusted media probe are required.",
    );
  }
  if (beforeFinalize !== null && typeof beforeFinalize !== "function") {
    throw new TypeError("beforeFinalize must be a function.");
  }

  async function canonicalBinding(path, parsed, metadata) {
    const conversationRef = db.doc(`conversations/${parsed.conversationId}`);
    const conversation = await conversationRef.get();
    if (!conversation.exists) return null;
    const root = conversation.data() ?? {};
    if (
      !Array.isArray(root.participantIds) ||
      root.participantIds.length !== 2 ||
      root.participantIds.some((uid) => !isValidOpaqueUid(uid))
    ) {
      return null;
    }
    let participants;
    try {
      participants = canonicalPair(...root.participantIds);
    } catch (_) {
      return null;
    }
    const pairGuard = await db.doc(
      `directConversationPairs/${canonicalPairKey(...participants)}`,
    ).get();
    const message = await conversationRef
      .collection("messages")
      .doc(parsed.messageId)
      .get();
    if (!message.exists) return null;

    let conversationData;
    let messageData;
    try {
      conversationData = validateConversation(
        conversation,
        parsed.conversationId,
        parsed.ownerId,
        pairGuard,
      );
      messageData = validateMessage(message, parsed.conversationId);
    } catch (error) {
      if (expectedValidationError(error)) return null;
      throw error;
    }
    const recipientId = conversationData.participants.find(
      (uid) => uid !== parsed.ownerId,
    );
    if (
      recipientId === undefined ||
      messageData.senderId !== parsed.ownerId ||
      messageData.isDeleted ||
      !["image", "voice", "video"].includes(messageData.type) ||
      messageData.mediaUrl !== storage.getObjectReference(path)
    ) {
      return null;
    }
    const reservation = {
      contentType: metadata?.contentType,
      conversationId: parsed.conversationId,
      durationSeconds: messageData.durationSeconds,
      messageId: parsed.messageId,
      ownerId: parsed.ownerId,
      recipientId,
      storagePath: path,
      type: messageData.type,
    };
    if (
      directMediaStoragePath(
        parsed.ownerId,
        parsed.conversationId,
        parsed.messageId,
        reservation.type,
        reservation.contentType,
      ) !== path
    ) {
      return null;
    }
    let media;
    try {
      media = validateStoredDirectMedia(
        metadata,
        reservation,
        String(metadata?.generation ?? ""),
      );
    } catch (error) {
      if (expectedValidationError(error)) return null;
      throw error;
    }
    const ledgers = await db
      .collection("integrityOperationLedgers")
      // A normal Build 18 attachment has both reserve and finalize ledgers
      // carrying result.messageId. Filter by kind at the datastore rather
      // than applying a limit before the trusted operation is selected.
      // Both predicates are equality filters and are served by Firestore's
      // automatic single-field index merging.
      .where("kind", "==", "direct.attachment.finalize")
      .where("result.messageId", "==", parsed.messageId)
      .limit(2)
      .get();
    if (ledgers.size !== 1) return null;
    const ledgerDocument = ledgers.docs[0];
    const ledger = ledgerDocument.data() ?? {};
    const ledgerKeys = [
      "createdAt",
      "inputHash",
      "kind",
      "ownerId",
      "requestId",
      "result",
      "schemaVersion",
    ];
    const resultKeys = [
      "conversationId",
      "created",
      "mediaSize",
      "messageId",
      "recipientId",
      "type",
    ];
    let canonicalRequestId;
    try {
      canonicalRequestId = requireRequestId(ledger.requestId);
    } catch (error) {
      if (expectedValidationError(error) || error?.code === "invalid-argument") {
        return null;
      }
      throw error;
    }
    const expectedIdentity = operationIdentity(
      "direct.attachment.finalize",
      parsed.ownerId,
      canonicalRequestId,
      {
        conversationId: parsed.conversationId,
        messageId: parsed.messageId,
        objectGeneration: media.generation,
      },
    );
    if (
      Object.keys(ledger).sort().some(
        (key, index) => key !== ledgerKeys[index],
      ) ||
      Object.keys(ledger).length !== ledgerKeys.length ||
      ledger.schemaVersion !== 1 ||
      ledger.kind !== "direct.attachment.finalize" ||
      ledger.ownerId !== parsed.ownerId ||
      !/^[a-f0-9]{64}$/u.test(ledger.inputHash) ||
      timestampMillis(ledger.createdAt) === null ||
      !ledger.result ||
      typeof ledger.result !== "object" ||
      Array.isArray(ledger.result) ||
      Object.keys(ledger.result).length !== resultKeys.length ||
      Object.keys(ledger.result).sort().some(
        (key, index) => key !== resultKeys[index],
      ) ||
      ledger.result.conversationId !== parsed.conversationId ||
      ledger.result.messageId !== parsed.messageId ||
      ledger.result.recipientId !== recipientId ||
      ledger.result.type !== messageData.type ||
      ledger.result.mediaSize !== media.size ||
      ledger.result.created !== true ||
      ledger.inputHash !== expectedIdentity.inputHash ||
      expectedIdentity.id !== ledgerDocument.id
    ) {
      return null;
    }
    return { media, reservation };
  }

  async function inspectObject(path, { dryRun }) {
    let metadata;
    try {
      metadata = await storage.getMetadata(path);
    } catch (error) {
      if (missingObject(error)) {
        return { status: "missing", tokenFound: false, tokenRevoked: false };
      }
      throw error;
    }
    const tokenFound = hasFirebaseDownloadToken(metadata);
    let tokenRevoked = false;

    // The marker is a server-owned attestation. Never rewrite or attempt to
    // "repair" an object that already carries it; only remove a stray durable
    // bearer capability with the observed immutable generation.
    if (customMetadataOf(metadata)[FINALIZED_METADATA_KEY] ===
        FINALIZED_METADATA_VALUE) {
      if (!dryRun && tokenFound) {
        metadata = await storage.revokeDownloadTokens(path, metadata);
        tokenRevoked = true;
      }
      return { status: "already-finalized", tokenFound, tokenRevoked };
    }

    const parsed = parseDirectAttachmentPath(path);
    let binding = parsed === null
      ? null
      : await canonicalBinding(path, parsed, metadata);
    let probe = null;
    if (binding !== null) {
      try {
        probe = await mediaProbe({
          storagePath: path,
          generation: binding.media.generation,
          contentType: binding.media.contentType,
          size: binding.media.size,
          kind: binding.reservation.type,
        });
        validateDirectMediaProbe(
          probe,
          binding.reservation,
          binding.media,
        );
      } catch (error) {
        if (!expectedValidationError(error)) throw error;
        binding = null;
      }
    }

    if (dryRun) {
      return {
        status: binding === null ? "invalid" : "eligible",
        tokenFound,
        tokenRevoked: false,
      };
    }

    // Build 18 uploads contain Firebase's durable bearer token. Revoke it for
    // every inventoried object before deciding whether the object is eligible
    // for authenticated playback. Invalid/orphan bytes remain fail-closed.
    if (tokenFound) {
      metadata = await storage.revokeDownloadTokens(path, metadata);
      tokenRevoked = true;
    }
    if (binding === null || parsed === null) {
      return { status: "invalid", tokenFound, tokenRevoked };
    }

    if (beforeFinalize !== null) {
      await beforeFinalize({ path, parsed, metadata });
    }
    const currentMetadata = await storage.getMetadata(path);
    if (!sameStoredObject(metadata, currentMetadata)) {
      // A privileged replacement cannot inherit the validation of the prior
      // generation. Strip any new bearer token but leave the marker absent so
      // a later, complete run has to probe that generation from scratch.
      const replacementHasToken = hasFirebaseDownloadToken(currentMetadata);
      if (replacementHasToken) {
        await storage.revokeDownloadTokens(path, currentMetadata);
        tokenRevoked = true;
      }
      return {
        status: "raced",
        tokenFound: tokenFound || replacementHasToken,
        tokenRevoked,
      };
    }
    const currentBinding = await canonicalBinding(path, parsed, currentMetadata);
    if (currentBinding === null ||
        currentBinding.media.generation !== binding.media.generation ||
        currentBinding.media.size !== binding.media.size ||
        currentBinding.media.contentType !== binding.media.contentType) {
      return { status: "raced", tokenFound, tokenRevoked };
    }
    try {
      validateDirectMediaProbe(
        probe,
        currentBinding.reservation,
        currentBinding.media,
      );
    } catch (error) {
      if (expectedValidationError(error)) {
        return { status: "raced", tokenFound, tokenRevoked };
      }
      throw error;
    }

    const finalized = await storage.revokeDownloadTokens(
      path,
      currentMetadata,
      {
        requiredMetadata: {
          [FINALIZED_METADATA_KEY]: FINALIZED_METADATA_VALUE,
        },
      },
    );
    if (
      hasFirebaseDownloadToken(finalized) ||
      customMetadataOf(finalized)[FINALIZED_METADATA_KEY] !==
        FINALIZED_METADATA_VALUE
    ) {
      fail("aborted", "The legacy direct attachment could not be secured.");
    }
    const finalizedMedia = validateStoredDirectMedia(
      finalized,
      currentBinding.reservation,
      currentBinding.media.generation,
      { requireFinalized: true },
    );
    if (
      finalizedMedia.size !== currentBinding.media.size ||
      finalizedMedia.contentType !== currentBinding.media.contentType
    ) {
      fail("aborted", "The legacy direct attachment changed during migration.");
    }
    const postMarkerBinding = await canonicalBinding(path, parsed, finalized);
    if (postMarkerBinding === null ||
        postMarkerBinding.media.generation !== currentBinding.media.generation) {
      fail(
        "aborted",
        "The direct message changed after marker migration. Keep rules held.",
      );
    }
    return { status: "finalized", tokenFound, tokenRevoked };
  }

  async function migrateDirectAttachmentPage({
    pageToken = null,
    maxResults = DEFAULT_PAGE_SIZE,
    dryRun = true,
  } = {}) {
    requireSafeInteger(maxResults, "maxResults", {
      min: 1,
      max: MAX_PAGE_SIZE,
    });
    if (typeof dryRun !== "boolean") {
      fail("invalid-argument", "dryRun must be a boolean.");
    }
    if (
      pageToken !== null &&
      (typeof pageToken !== "string" || pageToken.length > 4096)
    ) {
      fail("invalid-argument", "pageToken is invalid.");
    }
    const page = await storage.listObjects({
      prefix: "message_attachments/",
      pageToken,
      maxResults,
    });
    if (
      !page ||
      !Array.isArray(page.names) ||
      page.names.length > maxResults ||
      page.names.some((name) => typeof name !== "string") ||
      (page.nextPageToken !== null &&
        typeof page.nextPageToken !== "string")
    ) {
      fail("data-loss", "The direct attachment inventory response is malformed.");
    }
    const counts = {
      alreadyFinalized: 0,
      eligible: 0,
      finalized: 0,
      invalid: 0,
      missing: 0,
      raced: 0,
      tokensFound: 0,
      tokensRevoked: 0,
    };
    for (const path of page.names) {
      const outcome = await inspectObject(path, { dryRun });
      const counter = outcome.status.replace(
        "already-finalized",
        "alreadyFinalized",
      );
      counts[counter] += 1;
      if (outcome.tokenFound) counts.tokensFound += 1;
      if (outcome.tokenRevoked) counts.tokensRevoked += 1;
    }
    return {
      dryRun,
      objectsScanned: page.names.length,
      ...counts,
      hasMore: page.nextPageToken !== null,
      nextPageToken: page.nextPageToken,
    };
  }

  return Object.freeze({ migrateDirectAttachmentPage });
}

module.exports = {
  DEFAULT_PAGE_SIZE,
  FINALIZED_METADATA_KEY,
  FINALIZED_METADATA_VALUE,
  MAX_PAGE_SIZE,
  createDirectAttachmentMigrationService,
  hasFirebaseDownloadToken,
  parseDirectAttachmentPath,
};
