// Photo and video messages in Servers V1 text channels, and the author's own
// message retraction. Modelled on Company Files (company_files.js):
//
//   reserve  -> a server-issued, 15-minute reservation for ONE immutable object
//   upload   -> the client writes exactly that object; storage.rules checks the
//               live reservation, the exact metadata and the direct-message
//               size/MIME/extension bounds
//   finalize -> metadata, trusted byte probe, metadata re-read, download token
//               revoked, then ONE transaction re-authorizes and creates the
//               message with a gs:// reference and a generation-bound
//               descriptor
//   access   -> a batched (<= 20) callable re-runs the channel ACL and issues
//               90-second, generation-bound V4 read URLs; bytes are never
//               readable through Storage rules
//   delete   -> the author tombstones their own message; the object is removed
//               by a durable, generation-guarded deletion job
//
// Authority: reserve/finalize need the channel's `write` capability (so only
// moderators and above in announcements/rules; never guests), a verified
// email, an active profile and no communication mute — exactly sendClubMessage.
// Access needs `read` (restricted grant included) and no mute. Retraction needs
// `read` and authorship, and is allowed while muted and unverified, like the
// legacy author branch of the club-chat rule.

const { FieldValue } = require("firebase-admin/firestore");

const {
  assertLedgerReplay,
  assertNotRestricted,
  consumeRateLimit,
  digest,
  fail,
  operationIdentity,
  rateLimitReference,
  requireActor,
  requireExactInput,
  requireId,
  requireRequestId,
  requireSafeInteger,
  timestampMillis,
  transactionGetAll,
} = require("../integrity/guards");
const { validateDirectMediaProbe } = require("../messaging/direct_integrity");
const { DEFAULT_COMMUNITY_LIMITS } = require("../messaging/community_integrity");
const { denied, readChannelAccess } = require("./authority");
const { canonicalDisplayName } = require("./documents");
const {
  BUDGETS,
  CONTENT_FALLBACK,
  DELETION_JOBS,
  EXTENSIONS,
  GENERATION_PATTERN,
  LEASES,
  MESSAGE_ID_PATTERN,
  OBJECTS,
  RESERVATIONS,
  SERVER_MESSAGE_MEDIA_ACCESS_TTL_MS,
  SERVER_MESSAGE_MEDIA_DAILY_BYTES,
  SERVER_MESSAGE_MEDIA_MAX_ACCESS_IDS,
  SERVER_MESSAGE_MEDIA_PREFIX,
  SERVER_MESSAGE_MEDIA_RESERVATION_TTL_MS,
  SERVER_MESSAGE_MEDIA_SCHEMA_VERSION,
  canonicalServerMessageMedia,
  channelMediaPrefix,
  objectDeletionJob,
  objectDeletionJobId,
  parseServerMessageMediaObjectName,
  prefixDeletionJobId,
  requireGeneration,
  requireMediaShape,
  serverMessageMediaMessageId,
  serverMessageMediaStoragePath,
  serverMessageMediaUploadMetadata,
  serverMessagePath,
} = require("./message_media_contract");
const { createServerOperations } = require("./operations");

const CHAT_CHANNEL_KINDS = Object.freeze(["text", "announcements", "rules"]);
const ACCESS_SCOPE = "server.channel.message.media.access";
const ACCESS_LIMIT = Object.freeze({ maxEvents: 120, windowMs: 60_000 });
const MAX_WORKER_PAGE = 20;

function customMetadataOf(metadata) {
  const custom = metadata?.metadata ?? metadata?.customMetadata ?? {};
  return custom && typeof custom === "object" && !Array.isArray(custom) ? custom : {};
}

function hasDownloadToken(metadata) {
  const token = customMetadataOf(metadata).firebaseStorageDownloadTokens;
  return typeof token === "string" && token.length > 0;
}

function safeGrantUrl(value) {
  if (typeof value !== "string" || value.length < 1 || value.length > 4096) return false;
  try {
    const url = new URL(value);
    return url.protocol === "https:" && url.hostname === "storage.googleapis.com" &&
      url.username === "" && url.password === "" && url.port === "";
  } catch (_) {
    return false;
  }
}

function isMissingObject(error) {
  return error?.code === 404 || error?.code === "404" || error?.code === "storage/object-not-found";
}

function requireChatChannel(access) {
  if (!CHAT_CHANNEL_KINDS.includes(access.channel.kind)) denied();
  return access;
}

/** The private-object adapter over a (lazy) Cloud Storage bucket. */
function createServerMessageMediaStorageAdapter(bucket) {
  if (!bucket?.file || !bucket?.getFiles) throw new TypeError("A Storage bucket is required.");
  return Object.freeze({
    objectReference(path) {
      return `gs://${bucket.name}/${path}`;
    },
    async getMetadata(path) {
      const [metadata] = await bucket.file(path).getMetadata();
      return metadata;
    },
    async hardenObject(path, metadata, requiredMetadata) {
      const generation = String(metadata?.generation ?? "");
      if (!GENERATION_PATTERN.test(generation)) {
        fail("data-loss", "The server message media generation is malformed.");
      }
      const custom = customMetadataOf(metadata);
      const canonical = Object.entries(requiredMetadata)
        .every(([key, value]) => custom[key] === value);
      if (canonical && !hasDownloadToken(metadata)) return metadata;
      const [updated] = await bucket.file(path).setMetadata({
        metadata: { ...custom, ...requiredMetadata, firebaseStorageDownloadTokens: null },
      }, { ifGenerationMatch: generation });
      return updated;
    },
    async getSignedReadUrl(path, { expiresAtMs, generation }) {
      if (!Number.isSafeInteger(expiresAtMs) || expiresAtMs <= 0 ||
          typeof generation !== "string" || !GENERATION_PATTERN.test(generation)) {
        fail("failed-precondition", "The server message media grant is malformed.");
      }
      const [url] = await bucket.file(path).getSignedUrl({
        version: "v4", action: "read", expires: expiresAtMs, queryParams: { generation },
      });
      return url;
    },
    async deleteObject(path, { generation = null } = {}) {
      if (generation !== null && !GENERATION_PATTERN.test(generation)) {
        fail("data-loss", "The server message media cleanup generation is malformed.");
      }
      await bucket.file(path, generation === null ? undefined : { generation }).delete({
        ignoreNotFound: true,
        ...(generation === null ? {} : { ifGenerationMatch: generation }),
      });
    },
    async listObjects(prefix, { maxResults = MAX_WORKER_PAGE } = {}) {
      if (typeof prefix !== "string" || !prefix.startsWith(`${SERVER_MESSAGE_MEDIA_PREFIX}/`) ||
          prefix.length > 1024 || !Number.isSafeInteger(maxResults) ||
          maxResults < 1 || maxResults > MAX_WORKER_PAGE) {
        throw new TypeError("A bounded server message media prefix is required.");
      }
      const [files] = await bucket.getFiles({ prefix, maxResults, autoPaginate: false });
      return files.map((file) => ({
        name: file.name,
        generation: String(file.generation ?? file.metadata?.generation ?? ""),
      }));
    },
  });
}

function reserveInput(data) {
  const fields = [
    "serverId", "channelId", "type", "contentType", "size", "durationSeconds", "requestId",
  ];
  requireExactInput(data, fields, fields);
  const shape = requireMediaShape({
    type: data.type,
    contentType: data.contentType,
    size: data.size,
    durationSeconds: data.durationSeconds,
  });
  return {
    serverId: requireId(data.serverId, "serverId"),
    channelId: requireId(data.channelId, "channelId"),
    ...shape,
    requestId: requireRequestId(data.requestId),
  };
}

const RESERVATION_KEYS = Object.freeze([
  "schemaVersion", "kind", "serverId", "channelId", "messageId", "ownerId", "requestId",
  "type", "contentType", "size", "durationSeconds", "storagePath", "status",
  "createdAt", "expiresAt",
]);

/** A reservation read back exactly; `expected` pins what the caller knows. */
function canonicalReservation(snapshot, expected, nowMs, { allowExpiring = false } = {}) {
  if (!snapshot?.exists) fail("failed-precondition", "The media upload reservation is missing.");
  const value = snapshot.data() ?? {};
  const expiring = value.status === "expiring";
  const keys = Object.keys(value).sort();
  const wanted = [...RESERVATION_KEYS, ...(expiring ? ["updatedAt"] : [])].sort();
  if (keys.length !== wanted.length || keys.some((key, index) => key !== wanted[index])) {
    fail("failed-precondition", "The media upload reservation is invalid.");
  }
  let canonicalId;
  let canonicalPath;
  try {
    requireMediaShape(value, "failed-precondition");
    canonicalId = serverMessageMediaMessageId(value.serverId, value.channelId, value.ownerId, value.requestId);
    canonicalPath = serverMessageMediaStoragePath(value);
  } catch (_) {
    fail("failed-precondition", "The media upload reservation is invalid.");
  }
  const expiresAtMillis = timestampMillis(value.expiresAt);
  const statuses = allowExpiring ? ["uploading", "expiring"] : ["uploading"];
  if (value.schemaVersion !== SERVER_MESSAGE_MEDIA_SCHEMA_VERSION ||
      value.kind !== "serverChannelMessageMedia" ||
      value.messageId !== snapshot.id || value.messageId !== canonicalId ||
      value.storagePath !== canonicalPath || !statuses.includes(value.status) ||
      timestampMillis(value.createdAt) === null || !Number.isSafeInteger(expiresAtMillis) ||
      (expected.serverId !== undefined && value.serverId !== expected.serverId) ||
      (expected.channelId !== undefined && value.channelId !== expected.channelId) ||
      (expected.ownerId !== undefined && value.ownerId !== expected.ownerId) ||
      (expected.requestId !== undefined && value.requestId !== expected.requestId)) {
    fail("failed-precondition", "The media upload reservation is invalid.");
  }
  if (!allowExpiring && expiresAtMillis <= nowMs) {
    fail("deadline-exceeded", "The media upload reservation expired.");
  }
  return { ...value, expiresAtMillis };
}

/** The uploaded object's metadata against the reservation, exactly. */
function validateStoredMedia(metadata, reservation, generation) {
  if (!metadata || typeof metadata !== "object" || Array.isArray(metadata)) {
    fail("failed-precondition", "The uploaded media is missing.");
  }
  const storedGeneration = String(metadata.generation ?? "");
  const size = Number(metadata.size);
  const custom = customMetadataOf(metadata);
  const required = serverMessageMediaUploadMetadata(reservation);
  const allowed = new Set(["firebaseStorageDownloadTokens", ...Object.keys(required)]);
  if (!GENERATION_PATTERN.test(storedGeneration) || storedGeneration !== generation ||
      !Number.isSafeInteger(size) || size !== reservation.size ||
      metadata.contentType !== reservation.contentType ||
      Object.keys(custom).some((key) => !allowed.has(key)) ||
      Object.entries(required).some(([key, value]) => custom[key] !== value)) {
    fail("failed-precondition", "The uploaded media is invalid.");
  }
  return { generation: storedGeneration, size, contentType: metadata.contentType };
}

function sameStored(first, second) {
  return first.generation === second.generation && first.size === second.size &&
    first.contentType === second.contentType;
}

function publishedMessage(snapshot, { serverId, channelId, messageId }) {
  if (!snapshot?.exists) return null;
  const message = snapshot.data() ?? {};
  if (message.clubId !== serverId || message.channelId !== channelId ||
      typeof message.senderId !== "string" || message.senderId.length < 1) {
    fail("data-loss", "The server message binding is invalid.");
  }
  return message;
}

function createServerMessageMediaService(dependencies) {
  const { db, Timestamp, storage, probeMedia, clock = Date.now } = dependencies ?? {};
  if (!db?.runTransaction || !Timestamp?.fromMillis || typeof clock !== "function" ||
      !storage?.getMetadata || !storage?.hardenObject || !storage?.getSignedReadUrl ||
      !storage?.deleteObject || !storage?.listObjects || !storage?.objectReference ||
      typeof probeMedia !== "function") {
    throw new TypeError("db, Timestamp, storage, probeMedia and clock are required.");
  }
  const operations = createServerOperations(dependencies);

  async function chatAccess(transaction, uid, input, capability) {
    return requireChatChannel(await readChannelAccess({
      db, transaction, uid, serverId: input.serverId, channelId: input.channelId, capability,
    }));
  }

  // --------------------------------------------------------------- reserve

  async function reserveServerChannelMessageMediaV1(request) {
    const input = reserveInput(request.data);
    return operations.execute(request, "server.channel.message.media.reserve.v1", input,
      async ({ transaction, auth, prior, now, nowMs }) => {
        await chatAccess(transaction, auth.uid, input, "write");
        const messageId = serverMessageMediaMessageId(
          input.serverId, input.channelId, auth.uid, input.requestId,
        );
        const messageRef = db.doc(serverMessagePath(input.serverId, input.channelId, messageId));
        const reservationRef = db.doc(`${RESERVATIONS}/${messageId}`);
        const leaseRef = db.doc(`${LEASES}/${auth.uid}`);
        const day = new Date(nowMs).toISOString().slice(0, 10);
        const budgetRef = db.doc(`${BUDGETS}/${digest("server.message.media.budget.v1", auth.uid, day)}`);
        const [messageSnapshot, reservationSnapshot, leaseSnapshot, budgetSnapshot] =
          await transactionGetAll(transaction, messageRef, reservationRef, leaseRef, budgetRef);
        if (prior) {
          if (!reservationSnapshot.exists) {
            fail("failed-precondition", "The original media upload reservation is no longer active.");
          }
          canonicalReservation(reservationSnapshot, {
            serverId: input.serverId, channelId: input.channelId,
            ownerId: auth.uid, requestId: input.requestId,
          }, nowMs);
          return prior;
        }
        if (messageSnapshot.exists || reservationSnapshot.exists) {
          fail("data-loss", "A media message exists without its reservation receipt.");
        }
        if (leaseSnapshot.exists) {
          const lease = leaseSnapshot.data() ?? {};
          if (lease.ownerId !== auth.uid || typeof lease.messageId !== "string" ||
              timestampMillis(lease.expiresAt) === null) {
            fail("data-loss", "The media upload lease needs reconciliation.");
          }
          if (lease.status === "uploading" && timestampMillis(lease.expiresAt) > nowMs) {
            fail("resource-exhausted", "Finish the current photo or video upload first.");
          }
        }
        const budget = budgetSnapshot.exists ? budgetSnapshot.data() ?? {} : {};
        const usedBytes = budgetSnapshot.exists ? budget.bytes : 0;
        const reservations = budgetSnapshot.exists ? budget.reservations : 0;
        if (budgetSnapshot.exists && (budget.schemaVersion !== 1 ||
            budget.ownerId !== auth.uid || budget.day !== day)) {
          fail("data-loss", "The media upload budget needs reconciliation.");
        }
        if (!Number.isSafeInteger(usedBytes) || usedBytes < 0 ||
            !Number.isSafeInteger(reservations) || reservations < 0 ||
            usedBytes + input.size > SERVER_MESSAGE_MEDIA_DAILY_BYTES) {
          fail("resource-exhausted", "The daily photo and video upload limit is reached.");
        }
        const expiresAtMillis = nowMs + SERVER_MESSAGE_MEDIA_RESERVATION_TTL_MS;
        const storagePath = serverMessageMediaStoragePath({
          serverId: input.serverId, channelId: input.channelId, ownerId: auth.uid,
          messageId, contentType: input.contentType,
        });
        const reservation = {
          schemaVersion: SERVER_MESSAGE_MEDIA_SCHEMA_VERSION,
          kind: "serverChannelMessageMedia",
          serverId: input.serverId,
          channelId: input.channelId,
          messageId,
          ownerId: auth.uid,
          requestId: input.requestId,
          type: input.type,
          contentType: input.contentType,
          size: input.size,
          durationSeconds: input.durationSeconds,
          storagePath,
          status: "uploading",
          createdAt: now,
          expiresAt: Timestamp.fromMillis(expiresAtMillis),
        };
        transaction.create(reservationRef, reservation);
        transaction.set(leaseRef, reservation);
        transaction.set(budgetRef, {
          schemaVersion: 1,
          ownerId: auth.uid,
          day,
          bytes: usedBytes + input.size,
          reservations: reservations + 1,
          updatedAt: now,
        });
        return {
          schemaVersion: SERVER_MESSAGE_MEDIA_SCHEMA_VERSION,
          serverId: input.serverId,
          channelId: input.channelId,
          messageId,
          expiresAtMillis,
          media: {
            storagePath,
            type: input.type,
            contentType: input.contentType,
            size: input.size,
            durationSeconds: input.durationSeconds,
            uploadMetadata: serverMessageMediaUploadMetadata({
              serverId: input.serverId, channelId: input.channelId, ownerId: auth.uid,
              messageId, type: input.type,
            }),
          },
        };
      });
  }

  // -------------------------------------------------------------- finalize

  function finalizeInput(data) {
    const fields = ["serverId", "channelId", "messageId", "objectGeneration", "requestId"];
    requireExactInput(data, fields, fields);
    const messageId = requireId(data.messageId, "messageId");
    if (!MESSAGE_ID_PATTERN.test(messageId)) fail("invalid-argument", "messageId is invalid.");
    return {
      serverId: requireId(data.serverId, "serverId"),
      channelId: requireId(data.channelId, "channelId"),
      messageId,
      objectGeneration: requireGeneration(data.objectGeneration),
      requestId: requireRequestId(data.requestId),
    };
  }

  function assertFinalizedReplay(snapshot, input, uid) {
    const message = publishedMessage(snapshot, input);
    if (!message) fail("not-found", "The finalized media message is no longer available.");
    if (message.isDeleted === true) {
      fail("failed-precondition", "The finalized media message was removed.");
    }
    const media = canonicalServerMessageMedia(message, input);
    if (message.senderId !== uid || !media || media.generation !== input.objectGeneration) {
      fail("aborted", "The media message changed after finalization.");
    }
  }

  async function readFinalizePlan(auth, input) {
    const { requestId, ...operationInput } = input;
    const identity = operationIdentity("server.channel.message.media.finalize.v1", auth.uid,
      requestId, operationInput);
    return db.runTransaction(async (transaction) => {
      await chatAccess(transaction, auth.uid, input, "write");
      const [ledger, messageSnapshot, reservationSnapshot] = await transactionGetAll(
        transaction,
        db.doc(`integrityOperationLedgers/${identity.id}`),
        db.doc(serverMessagePath(input.serverId, input.channelId, input.messageId)),
        db.doc(`${RESERVATIONS}/${input.messageId}`),
      );
      const prior = assertLedgerReplay(ledger, {
        kind: "server.channel.message.media.finalize.v1",
        uid: auth.uid,
        inputHash: identity.inputHash,
      });
      if (prior) {
        assertFinalizedReplay(messageSnapshot, input, auth.uid);
        return { prior };
      }
      if (messageSnapshot.exists) {
        fail("data-loss", "A media message exists without its finalization receipt.");
      }
      const reservation = canonicalReservation(reservationSnapshot, {
        serverId: input.serverId, channelId: input.channelId, ownerId: auth.uid,
      }, clock());
      if (reservation.messageId !== input.messageId) {
        fail("failed-precondition", "The media upload reservation is invalid.");
      }
      return { reservation };
    });
  }

  async function verifyUploadedMedia(reservation, generation) {
    let metadata;
    try {
      metadata = await storage.getMetadata(reservation.storagePath);
    } catch (error) {
      if (isMissingObject(error)) fail("failed-precondition", "The uploaded media is missing.");
      throw error;
    }
    const stored = validateStoredMedia(metadata, reservation, generation);
    const probe = await probeMedia({
      storagePath: reservation.storagePath,
      generation: stored.generation,
      contentType: stored.contentType,
      size: stored.size,
      kind: reservation.type,
    });
    // The direct-message probe contract: real image/video bytes, track
    // presence, duration within 1-60 s and within 2 s of the declaration.
    const trustedDurationSeconds = validateDirectMediaProbe(probe, reservation, stored);
    // A probe may take seconds: re-read so a replaced object cannot publish.
    const finalMetadata = await storage.getMetadata(reservation.storagePath);
    const final = validateStoredMedia(finalMetadata, reservation, generation);
    if (!sameStored(stored, final)) fail("aborted", "The uploaded media changed. Try again.");
    // Firebase clients mint a durable download token on upload. Remove it,
    // generation-guarded, before the message is published.
    const secured = await storage.hardenObject(reservation.storagePath, finalMetadata,
      serverMessageMediaUploadMetadata(reservation));
    if (hasDownloadToken(secured)) fail("aborted", "The uploaded media could not be secured.");
    const securedStored = validateStoredMedia(secured, reservation, generation);
    if (!sameStored(stored, securedStored)) {
      fail("aborted", "The uploaded media could not be secured.");
    }
    const mediaUrl = storage.objectReference(reservation.storagePath);
    if (typeof mediaUrl !== "string" || mediaUrl.length > 4096 || !mediaUrl.startsWith("gs://") ||
        mediaUrl !== `gs://${mediaUrl.slice(5).split("/")[0]}/${reservation.storagePath}`) {
      fail("failed-precondition", "The media reference is invalid.");
    }
    return {
      mediaUrl,
      media: {
        schemaVersion: SERVER_MESSAGE_MEDIA_SCHEMA_VERSION,
        storagePath: reservation.storagePath,
        generation: stored.generation,
        contentType: stored.contentType,
        size: stored.size,
        durationSeconds: reservation.type === "video" ? trustedDurationSeconds : null,
      },
    };
  }

  async function finalizeServerChannelMessageMediaV1(request) {
    const auth = requireActor(request);
    const input = finalizeInput(request.data);
    const plan = await readFinalizePlan(auth, input);
    const verified = plan.prior ? null : await verifyUploadedMedia(plan.reservation, input.objectGeneration);
    return operations.execute(request, "server.channel.message.media.finalize.v1", input,
      async ({ transaction, auth: current, profile, prior, now, nowMs }) => {
        await chatAccess(transaction, current.uid, input, "write");
        const messageRef = db.doc(serverMessagePath(input.serverId, input.channelId, input.messageId));
        const reservationRef = db.doc(`${RESERVATIONS}/${input.messageId}`);
        const leaseRef = db.doc(`${LEASES}/${current.uid}`);
        const objectRef = db.doc(`${OBJECTS}/${input.messageId}`);
        const scope = `club.message.send.${input.serverId}.${input.channelId}`;
        const rateRef = rateLimitReference(db, scope, current.uid);
        const [messageSnapshot, reservationSnapshot, leaseSnapshot, objectSnapshot, rateSnapshot] =
          await transactionGetAll(transaction, messageRef, reservationRef, leaseRef, objectRef, rateRef);
        if (prior) {
          assertFinalizedReplay(messageSnapshot, input, current.uid);
          return prior;
        }
        if (!verified || messageSnapshot.exists || objectSnapshot.exists) {
          fail("data-loss", "The media message finalization needs reconciliation.");
        }
        const reservation = canonicalReservation(reservationSnapshot, {
          serverId: input.serverId, channelId: input.channelId, ownerId: current.uid,
          requestId: plan.reservation.requestId,
        }, nowMs);
        const lease = leaseSnapshot.exists ? leaseSnapshot.data() ?? {} : {};
        if (!leaseSnapshot.exists || lease.messageId !== input.messageId ||
            lease.ownerId !== current.uid || lease.status !== "uploading") {
          fail("failed-precondition", "The media upload lease is invalid.");
        }
        if (reservation.storagePath !== verified.media.storagePath ||
            reservation.size !== verified.media.size ||
            reservation.contentType !== verified.media.contentType) {
          fail("aborted", "The media upload reservation changed. Try again.");
        }
        // The same per-channel send bucket sendClubMessage consumes, so a
        // photo stream cannot outrun the text slow-down.
        consumeRateLimit(transaction, rateSnapshot, {
          reference: rateRef, scope, uid: current.uid, now, nowMs,
          ...DEFAULT_COMMUNITY_LIMITS.clubScope,
        });
        transaction.create(messageRef, {
          clubId: input.serverId,
          channelId: input.channelId,
          senderId: current.uid,
          senderName: canonicalDisplayName(profile),
          senderPhotoUrl: null,
          content: CONTENT_FALLBACK[reservation.type],
          sentAt: now,
          editedAt: null,
          isDeleted: false,
          type: reservation.type,
          mediaUrl: verified.mediaUrl,
          media: verified.media,
        });
        transaction.create(objectRef, {
          schemaVersion: SERVER_MESSAGE_MEDIA_SCHEMA_VERSION,
          ownerId: current.uid,
          serverId: input.serverId,
          channelId: input.channelId,
          messageId: input.messageId,
          storagePath: verified.media.storagePath,
          generation: verified.media.generation,
          createdAt: now,
        });
        transaction.delete(reservationRef);
        transaction.delete(leaseRef);
        return {
          schemaVersion: SERVER_MESSAGE_MEDIA_SCHEMA_VERSION,
          serverId: input.serverId,
          channelId: input.channelId,
          messageId: input.messageId,
          type: reservation.type,
        };
      });
  }

  // ---------------------------------------------------------------- access

  function accessInput(data) {
    const fields = ["serverId", "channelId", "messageIds"];
    requireExactInput(data, fields, fields);
    if (!Array.isArray(data.messageIds) || data.messageIds.length < 1 ||
        data.messageIds.length > SERVER_MESSAGE_MEDIA_MAX_ACCESS_IDS) {
      fail("invalid-argument", "messageIds must list 1-20 messages.");
    }
    const messageIds = data.messageIds.map((id) => requireId(id, "messageId"));
    if (new Set(messageIds).size !== messageIds.length) {
      fail("invalid-argument", "messageIds must be unique.");
    }
    return {
      serverId: requireId(data.serverId, "serverId"),
      channelId: requireId(data.channelId, "channelId"),
      messageIds,
    };
  }

  async function authorizeAccess(auth, input, { consume }) {
    const nowMs = clock();
    const now = Timestamp.fromMillis(nowMs);
    return db.runTransaction(async (transaction) => {
      const access = await chatAccess(transaction, auth.uid, input, "read");
      const rateRef = rateLimitReference(db, ACCESS_SCOPE, auth.uid);
      const messageRefs = input.messageIds.map((id) =>
        access.channelReference.collection("messages").doc(id));
      const [restriction, rate, ...messages] = await transactionGetAll(
        transaction, db.doc(`restrictions/${auth.uid}`), rateRef, ...messageRefs,
      );
      assertNotRestricted(restriction, "Your", nowMs);
      if (consume) {
        consumeRateLimit(transaction, rate, {
          reference: rateRef, scope: ACCESS_SCOPE, uid: auth.uid, now, nowMs, ...ACCESS_LIMIT,
        });
      }
      const eligible = new Map();
      messages.forEach((snapshot, index) => {
        const messageId = input.messageIds[index];
        const message = publishedMessage(snapshot, { ...input, messageId });
        // Removed, missing and non-media messages never receive a grant.
        if (!message || message.isDeleted === true || !["image", "video"].includes(message.type)) return;
        const media = canonicalServerMessageMedia(message, { ...input, messageId });
        if (media) eligible.set(messageId, media);
      });
      return {
        checkedAtMs: nowMs,
        serverRevision: access.server.revision,
        channelRevision: access.channel.revision,
        channelAclRevision: access.channel.aclRevision,
        membershipRevision: access.member.authorizationRevision,
        eligible,
      };
    });
  }

  function sameAccess(first, second) {
    if (first.serverRevision !== second.serverRevision ||
        first.channelRevision !== second.channelRevision ||
        first.channelAclRevision !== second.channelAclRevision ||
        first.membershipRevision !== second.membershipRevision) return false;
    for (const [messageId, media] of first.eligible) {
      const current = second.eligible.get(messageId);
      if (!current || current.generation !== media.generation ||
          current.storagePath !== media.storagePath) return false;
    }
    return true;
  }

  async function getServerChannelMessageMediaAccessV1(request) {
    const auth = requireActor(request, { verified: false });
    const input = accessInput(request.data);
    // readChannelAccess (inside authorizeAccess) re-checks the active profile.
    const access = await authorizeAccess(auth, input, { consume: true });
    const expiresAtMillis = access.checkedAtMs + SERVER_MESSAGE_MEDIA_ACCESS_TTL_MS;
    const grants = [];
    const unavailable = input.messageIds.filter((id) => !access.eligible.has(id));
    for (const [messageId, media] of access.eligible) {
      let metadata;
      try {
        metadata = await storage.getMetadata(media.storagePath);
      } catch (error) {
        if (!isMissingObject(error)) throw error;
        unavailable.push(messageId);
        continue;
      }
      const custom = customMetadataOf(metadata);
      const binding = serverMessageMediaUploadMetadata({
        serverId: input.serverId, channelId: input.channelId, ownerId: media.ownerId,
        messageId, type: media.type,
      });
      if (String(metadata?.generation ?? "") !== media.generation ||
          Number(metadata?.size) !== media.size || metadata?.contentType !== media.contentType ||
          Object.entries(binding).some(([key, value]) => custom[key] !== value)) {
        // A replaced or rebound object is never served under this message.
        unavailable.push(messageId);
        continue;
      }
      const url = await storage.getSignedReadUrl(media.storagePath, {
        expiresAtMs: expiresAtMillis, generation: media.generation,
      });
      if (!safeGrantUrl(url)) {
        fail("failed-precondition", "A private media access grant is unavailable.");
      }
      grants.push({
        messageId,
        url,
        type: media.type,
        contentType: media.contentType,
        size: media.size,
        durationSeconds: media.durationSeconds,
        generation: media.generation,
      });
    }
    // Re-authorize after signing: a ban, leave, ACL change or removal while
    // the URLs were being minted voids the whole batch.
    const finalAccess = await authorizeAccess(auth, input, { consume: false });
    if (finalAccess.checkedAtMs >= expiresAtMillis || !sameAccess(access, finalAccess)) {
      fail("aborted", "Media authorization changed. Try again.");
    }
    return {
      schemaVersion: SERVER_MESSAGE_MEDIA_SCHEMA_VERSION,
      serverId: input.serverId,
      channelId: input.channelId,
      expiresAtMillis,
      grants,
      unavailable,
    };
  }

  // ---------------------------------------------------------------- delete

  function deleteInput(data) {
    const fields = ["serverId", "channelId", "messageId", "requestId"];
    requireExactInput(data, fields, fields);
    return {
      serverId: requireId(data.serverId, "serverId"),
      channelId: requireId(data.channelId, "channelId"),
      messageId: requireId(data.messageId, "messageId"),
      requestId: requireRequestId(data.requestId),
    };
  }

  async function processObjectDeletionJob(jobId) {
    requireId(jobId, "deletion job id");
    const jobRef = db.doc(`${DELETION_JOBS}/${jobId}`);
    const snapshot = await jobRef.get();
    if (!snapshot.exists) return { deleted: true };
    const job = canonicalDeletionJob(snapshot);
    if (job.target === "object") {
      await storage.deleteObject(job.storagePath, { generation: job.generation });
      await db.runTransaction(async (transaction) => {
        const objectRef = db.doc(`${OBJECTS}/${job.messageId}`);
        const [current, object] = await transactionGetAll(transaction, jobRef, objectRef);
        if (!current.exists) return;
        canonicalDeletionJob(current);
        if (object.exists && object.data()?.storagePath === job.storagePath &&
            object.data()?.generation === job.generation) transaction.delete(objectRef);
        transaction.delete(jobRef);
      });
      return { deleted: true };
    }
    const objects = await storage.listObjects(job.prefix, { maxResults: MAX_WORKER_PAGE });
    if (!Array.isArray(objects) || objects.length > MAX_WORKER_PAGE) {
      fail("data-loss", "The server message media listing is malformed.");
    }
    for (const object of objects) {
      if (typeof object?.name !== "string" || !object.name.startsWith(job.prefix) ||
          !GENERATION_PATTERN.test(object.generation)) {
        fail("data-loss", "The server message media listing is malformed.");
      }
    }
    await Promise.all(objects.map((object) =>
      storage.deleteObject(object.name, { generation: object.generation })));
    await db.runTransaction(async (transaction) => {
      const indexRefs = objects
        .map((object) => parseServerMessageMediaObjectName(object.name))
        .filter(Boolean)
        .map((parsed) => db.doc(`${OBJECTS}/${parsed.messageId}`));
      const [current, ...indexes] = await transactionGetAll(transaction, jobRef, ...indexRefs);
      if (!current.exists) return;
      canonicalDeletionJob(current);
      indexes.forEach((index) => {
        if (index.exists && index.data()?.storagePath?.startsWith(job.prefix)) {
          transaction.delete(index.ref);
        }
      });
      if (objects.length === 0) transaction.delete(jobRef);
      else transaction.update(jobRef, { updatedAt: Timestamp.fromMillis(clock()) });
    });
    return { deleted: objects.length === 0 };
  }

  async function deleteServerChannelMessageV1(request) {
    const input = deleteInput(request.data);
    let jobId = null;
    const result = await operations.execute(request, "server.channel.message.delete.v1", input,
      async ({ transaction, auth, prior, now }) => {
        await chatAccess(transaction, auth.uid, input, "read");
        const messageRef = db.doc(serverMessagePath(input.serverId, input.channelId, input.messageId));
        const snapshot = await transaction.get(messageRef);
        const message = publishedMessage(snapshot, input);
        if (!message) fail("not-found", "This message no longer exists.");
        // Author only. A moderator removes someone else's message through
        // moderateClubMessage, which keeps its rank ordering and owner rule.
        if (message.senderId !== auth.uid) denied();
        if (prior) return prior;
        if (message.isDeleted === true) {
          return {
            serverId: input.serverId, channelId: input.channelId, messageId: input.messageId,
            deleted: true, alreadyRemoved: true,
          };
        }
        const media = canonicalServerMessageMedia(message, input);
        if (media) {
          const job = objectDeletionJob({ ...input, media, reason: "author", now });
          jobId = job.jobId;
          transaction.set(db.doc(`${DELETION_JOBS}/${job.jobId}`), job.document);
        }
        // Exactly ClubChatService.deleteMessage's tombstone, plus every
        // content-bearing field this feature adds.
        transaction.update(messageRef, {
          content: "",
          isDeleted: true,
          editedAt: now,
          deletedBy: auth.uid,
          deletedAt: now,
          gif: FieldValue.delete(),
          mediaUrl: FieldValue.delete(),
          media: FieldValue.delete(),
          reactions: FieldValue.delete(),
        });
        return {
          serverId: input.serverId, channelId: input.channelId, messageId: input.messageId,
          deleted: true, alreadyRemoved: false,
        };
      }, { verified: false, allowRestricted: true });
    let cleanupPending = false;
    if (jobId !== null) {
      // Best effort: the durable job survives a Storage failure and the
      // scheduled worker finishes it.
      try {
        await processObjectDeletionJob(jobId);
      } catch (_) {
        cleanupPending = true;
      }
    }
    return { ...result, cleanupPending };
  }

  // --------------------------------------------------------------- workers

  async function expireServerChannelMessageMediaReservations({ limit = MAX_WORKER_PAGE } = {}) {
    requireSafeInteger(limit, "limit", { min: 1, max: MAX_WORKER_PAGE });
    const nowMs = clock();
    const now = Timestamp.fromMillis(nowMs);
    const page = await db.collection(RESERVATIONS).where("expiresAt", "<=", now).limit(limit).get();
    const expired = [];
    for (const document of page.docs) {
      const raw = document.data() ?? {};
      const expected = { serverId: raw.serverId, channelId: raw.channelId, ownerId: raw.ownerId };
      canonicalReservation(document, expected, nowMs, { allowExpiring: true });
      const claimed = await db.runTransaction(async (transaction) => {
        const current = await transaction.get(document.ref);
        if (!current.exists) return null;
        const value = canonicalReservation(current, expected, nowMs, { allowExpiring: true });
        if (value.expiresAtMillis > nowMs) return null;
        if (value.status === "uploading") {
          transaction.update(document.ref, { status: "expiring", updatedAt: now });
        }
        return value;
      });
      if (!claimed) continue;
      await storage.deleteObject(claimed.storagePath);
      await db.runTransaction(async (transaction) => {
        const leaseRef = db.doc(`${LEASES}/${claimed.ownerId}`);
        const [current, lease] = await transactionGetAll(transaction, document.ref, leaseRef);
        if (current.exists) {
          const value = canonicalReservation(current, expected, nowMs, { allowExpiring: true });
          if (value.status !== "expiring") {
            fail("data-loss", "The media reservation cleanup fence changed.");
          }
          transaction.delete(document.ref);
        }
        if (lease.exists && lease.data()?.messageId === document.id &&
            lease.data()?.ownerId === claimed.ownerId) transaction.delete(leaseRef);
      });
      expired.push(document.id);
    }
    return { expired, processed: page.size, hasMore: page.size === limit };
  }

  async function processServerChannelMessageMediaDeletionJobs({ limit = MAX_WORKER_PAGE } = {}) {
    requireSafeInteger(limit, "limit", { min: 1, max: MAX_WORKER_PAGE });
    const page = await db.collection(DELETION_JOBS).where("status", "==", "pending").limit(limit).get();
    const completed = [];
    for (const document of page.docs) {
      canonicalDeletionJob(document);
      const outcome = await processObjectDeletionJob(document.id);
      if (outcome.deleted) completed.push(document.id);
    }
    return { completed, processed: page.size, hasMore: page.size === limit };
  }

  return Object.freeze({
    deleteServerChannelMessageV1,
    expireServerChannelMessageMediaReservations,
    finalizeServerChannelMessageMediaV1,
    getServerChannelMessageMediaAccessV1,
    processObjectDeletionJob,
    processServerChannelMessageMediaDeletionJobs,
    reserveServerChannelMessageMediaV1,
  });
}

/** A deletion job read back exactly; the paths are re-derived, not trusted. */
function canonicalDeletionJob(snapshot) {
  const value = snapshot?.data?.() ?? {};
  const common = ["schemaVersion", "kind", "target", "jobId", "serverId", "channelId",
    "reason", "status", "createdAt", "updatedAt"];
  const keys = Object.keys(value).sort();
  const expected = (value.target === "object"
    ? [...common, "messageId", "ownerId", "storagePath", "generation"]
    : [...common, "prefix"]).sort();
  const reject = () => fail("data-loss", "The server message media deletion job needs reconciliation.");
  if (keys.length !== expected.length || keys.some((key, index) => key !== expected[index]) ||
      value.schemaVersion !== SERVER_MESSAGE_MEDIA_SCHEMA_VERSION ||
      value.kind !== "serverChannelMessageMediaDelete" || value.status !== "pending" ||
      value.jobId !== snapshot.id || !["object", "prefix"].includes(value.target) ||
      typeof value.reason !== "string" || timestampMillis(value.createdAt) === null) reject();
  try {
    if (value.target === "object") {
      const contentType = Object.entries(EXTENSIONS)
        .find(([, extension]) => typeof value.storagePath === "string" &&
          value.storagePath.endsWith(`.${extension}`))?.[0];
      const path = serverMessageMediaStoragePath({
        serverId: value.serverId, channelId: value.channelId, ownerId: value.ownerId,
        messageId: value.messageId, contentType,
      });
      if (path !== value.storagePath || !GENERATION_PATTERN.test(value.generation) ||
          value.jobId !== objectDeletionJobId(value.serverId, value.channelId, value.messageId)) reject();
    } else if (value.prefix !== channelMediaPrefix(value.serverId, value.channelId) ||
        value.jobId !== prefixDeletionJobId(value.prefix)) {
      reject();
    }
  } catch (error) {
    if (error?.code === "data-loss") throw error;
    reject();
  }
  return value;
}

module.exports = {
  CHAT_CHANNEL_KINDS,
  canonicalServerMessageMediaDeletionJob: canonicalDeletionJob,
  canonicalServerMessageMediaReservation: canonicalReservation,
  createServerMessageMediaService,
  createServerMessageMediaStorageAdapter,
  validateStoredServerMessageMedia: validateStoredMedia,
};
