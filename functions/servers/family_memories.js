// Private Family Memories for Servers V1.
//
// One memory is an immutable photo paired with a short voice note. Clients
// receive only a server-issued, time-bounded upload reservation. Finalization
// verifies the exact object generations, byte sizes, MIME signatures and
// audio timeline before writing the canonical clubs/{serverId}/moments row.
// Published rows contain object descriptors, never permanent download URLs.

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
  requireUid,
  timestampMillis,
  transactionGetAll,
} = require("../integrity/guards");
const {
  MODERATOR_ROLES,
  denied,
  readChannelAccess,
  validRevision,
} = require("./authority");
const { text } = require("./contract");
const { canonicalDisplayName } = require("./documents");
const { createServerOperations } = require("./operations");

const FAMILY_MEMORY_SCHEMA_VERSION = 1;
const FAMILY_MEMORY_RESERVATION_TTL_MS = 10 * 60_000;
const FAMILY_MEMORY_ACCESS_TTL_MS = 90_000;
const FAMILY_MEMORY_DAILY_BYTES = 64 * 1024 * 1024;
const MIN_PHOTO_BYTES = 128;
const MAX_PHOTO_BYTES = 8 * 1024 * 1024;
const MIN_VOICE_BYTES = 1024;
const MAX_VOICE_BYTES = 8 * 1024 * 1024;
const MIN_VOICE_DURATION_MS = 1000;
const MAX_VOICE_DURATION_MS = 30_000;
const VOICE_DURATION_TOLERANCE_MS = 2000;
const ACCESS_LIMIT = Object.freeze({ maxEvents: 120, windowMs: 60_000 });
const GENERATION_PATTERN = /^[0-9]{1,30}$/u;
const PHOTO_TYPES = Object.freeze({
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
});
// iOS and Android both upload the MPEG-4 audio container under audio/mp4.
// Accepting MIME aliases would make the trusted probe and extension contract
// ambiguous, so V1 deliberately has one canonical voice type.
const VOICE_TYPES = Object.freeze({ "audio/mp4": "m4a" });

function exactStoredObject(value, keys, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    fail("data-loss", `${label} is malformed.`);
  }
  const actual = Object.keys(value).sort();
  const expected = [...keys].sort();
  if (actual.length !== expected.length ||
      actual.some((key, index) => key !== expected[index])) {
    fail("data-loss", `${label} is malformed.`);
  }
  return value;
}

function customMetadataOf(metadata) {
  const custom = metadata?.metadata ?? metadata?.customMetadata ?? {};
  return custom && typeof custom === "object" && !Array.isArray(custom)
    ? custom
    : {};
}

function requireGeneration(value, label) {
  if (typeof value !== "string" || !GENERATION_PATTERN.test(value)) {
    fail("invalid-argument", `${label} is invalid.`);
  }
  return value;
}

function storedGeneration(value, label) {
  const generation = String(value ?? "");
  if (!GENERATION_PATTERN.test(generation)) {
    fail("data-loss", `${label} is malformed.`);
  }
  return generation;
}

function canonicalFamilyMemoryId(uid, serverId, requestId) {
  requireUid(uid);
  requireId(serverId, "serverId");
  requireRequestId(requestId);
  return `fm_${digest("server.family.memory.v1", serverId, uid, requestId).slice(0, 40)}`;
}

function familyMemoryStoragePath({ serverId, ownerId, memoryId, assetKind, contentType }) {
  requireId(serverId, "serverId");
  requireUid(ownerId, "ownerId");
  requireId(memoryId, "memoryId");
  const types = assetKind === "photo" ? PHOTO_TYPES :
    assetKind === "voice" ? VOICE_TYPES : null;
  if (!types || typeof contentType !== "string" || !types[contentType]) {
    fail("invalid-argument", "The Family Memory media type is invalid.");
  }
  return `family_moments/${serverId}/${ownerId}/${memoryId}_${assetKind}.${types[contentType]}`;
}

function familyMemoryUploadMetadata({ serverId, channelId, ownerId, memoryId, assetKind }) {
  return Object.freeze({
    yovoiceServerId: serverId,
    yovoiceChannelId: channelId,
    yovoiceOwnerUid: ownerId,
    yovoiceMemoryId: memoryId,
    yovoiceAssetKind: assetKind,
  });
}

function requireMemoryChannel(access, capability = "read") {
  if (access.server.serverType !== "family" || access.channel.kind !== "memories" ||
      access.capabilities[capability] !== true) denied();
  return access;
}

function reservationReference(db, memoryId) {
  return db.doc(`serverFamilyMemoryUploadReservations/${memoryId}`);
}

function leaseReference(db, uid) {
  return db.doc(`serverFamilyMemoryUploadLeases/${uid}`);
}

function deletionJobId(serverId, memoryId) {
  return `fmd_${digest("server.family.memory.delete.v1", serverId, memoryId).slice(0, 40)}`;
}

function deletionJobReference(db, serverId, memoryId) {
  return db.doc(`serverFamilyMemoryDeletionJobs/${deletionJobId(serverId, memoryId)}`);
}

function photoInput(data) {
  if (typeof data.photoContentType !== "string" || !PHOTO_TYPES[data.photoContentType]) {
    fail("invalid-argument", "photoContentType is invalid.");
  }
  return {
    contentType: data.photoContentType,
    size: requireSafeInteger(data.photoSize, "photoSize", {
      min: MIN_PHOTO_BYTES,
      max: MAX_PHOTO_BYTES,
    }),
  };
}

function voiceInput(data) {
  if (typeof data.voiceContentType !== "string" || !VOICE_TYPES[data.voiceContentType]) {
    fail("invalid-argument", "voiceContentType is invalid.");
  }
  return {
    contentType: data.voiceContentType,
    size: requireSafeInteger(data.voiceSize, "voiceSize", {
      min: MIN_VOICE_BYTES,
      max: MAX_VOICE_BYTES,
    }),
    durationMs: requireSafeInteger(data.voiceDurationMs, "voiceDurationMs", {
      min: MIN_VOICE_DURATION_MS,
      max: MAX_VOICE_DURATION_MS,
    }),
  };
}

function reserveInput(data) {
  const fields = [
    "serverId", "channelId", "requestId", "caption",
    "photoContentType", "photoSize",
    "voiceContentType", "voiceSize", "voiceDurationMs",
  ];
  requireExactInput(data, fields, fields);
  return {
    serverId: requireId(data.serverId, "serverId"),
    channelId: requireId(data.channelId, "channelId"),
    requestId: requireRequestId(data.requestId),
    caption: text(data.caption, 500, "caption"),
    photo: photoInput(data),
    voice: voiceInput(data),
  };
}

function canonicalReservation(snapshot, expected, nowMs, { allowExpiring = false } = {}) {
  if (!snapshot?.exists) {
    fail("failed-precondition", "The Family Memory upload reservation is missing.");
  }
  const value = snapshot.data() ?? {};
  const allowedKeys = [
    "schemaVersion", "kind", "serverId", "channelId", "memoryId", "ownerId",
    "requestId", "caption", "photoStoragePath", "photoContentType", "photoSize",
    "voiceStoragePath", "voiceContentType", "voiceSize", "voiceDurationMs",
    "status", "createdAt", "expiresAt",
    ...(value.status === "expiring" ? ["updatedAt"] : []),
  ];
  exactStoredObject(value, allowedKeys, "The Family Memory upload reservation");
  const expiresAtMillis = timestampMillis(value.expiresAt);
  const statuses = allowExpiring ? ["uploading", "expiring"] : ["uploading"];
  let canonicalId = null;
  let expectedPhotoPath = null;
  let expectedVoicePath = null;
  try {
    requireId(value.channelId, "channelId");
    requireUid(value.ownerId, "ownerId");
    requireRequestId(value.requestId);
    canonicalId = canonicalFamilyMemoryId(
      value.ownerId,
      value.serverId,
      value.requestId,
    );
    expectedPhotoPath = familyMemoryStoragePath({
      serverId: value.serverId,
      ownerId: value.ownerId,
      memoryId: value.memoryId,
      assetKind: "photo",
      contentType: value.photoContentType,
    });
    expectedVoicePath = familyMemoryStoragePath({
      serverId: value.serverId,
      ownerId: value.ownerId,
      memoryId: value.memoryId,
      assetKind: "voice",
      contentType: value.voiceContentType,
    });
  } catch (_) {
    fail("failed-precondition", "The Family Memory upload reservation is invalid.");
  }
  if (value.schemaVersion !== FAMILY_MEMORY_SCHEMA_VERSION ||
      value.kind !== "serverFamilyMemory" ||
      value.serverId !== expected.serverId || value.channelId !== expected.channelId ||
      value.memoryId !== expected.memoryId || value.memoryId !== snapshot.id ||
      value.memoryId !== canonicalId || value.ownerId !== expected.ownerId ||
      value.requestId !== expected.reserveRequestId ||
      typeof value.caption !== "string" || value.caption !== value.caption.trim() ||
      value.caption.length > 500 || !statuses.includes(value.status) ||
      !PHOTO_TYPES[value.photoContentType] || !VOICE_TYPES[value.voiceContentType] ||
      !Number.isSafeInteger(value.photoSize) || value.photoSize < MIN_PHOTO_BYTES ||
      value.photoSize > MAX_PHOTO_BYTES ||
      !Number.isSafeInteger(value.voiceSize) || value.voiceSize < MIN_VOICE_BYTES ||
      value.voiceSize > MAX_VOICE_BYTES ||
      !Number.isSafeInteger(value.voiceDurationMs) ||
      value.voiceDurationMs < MIN_VOICE_DURATION_MS ||
      value.voiceDurationMs > MAX_VOICE_DURATION_MS ||
      value.photoStoragePath !== expectedPhotoPath ||
      value.voiceStoragePath !== expectedVoicePath ||
      timestampMillis(value.createdAt) === null ||
      !Number.isSafeInteger(expiresAtMillis) ||
      (!allowExpiring && expiresAtMillis <= nowMs)) {
    fail("failed-precondition", "The Family Memory upload reservation is invalid.");
  }
  return { ...value, expiresAtMillis };
}

function mediaDescriptor(value, kind) {
  exactStoredObject(value, ["storagePath", "generation", "contentType", "size",
    ...(kind === "voice" ? ["durationMs"] : [])], `The Family Memory ${kind}`);
  const types = kind === "photo" ? PHOTO_TYPES : VOICE_TYPES;
  const minimum = kind === "photo" ? MIN_PHOTO_BYTES : MIN_VOICE_BYTES;
  const maximum = kind === "photo" ? MAX_PHOTO_BYTES : MAX_VOICE_BYTES;
  if (typeof value.storagePath !== "string" || !GENERATION_PATTERN.test(value.generation) ||
      !types[value.contentType] || !Number.isSafeInteger(value.size) ||
      value.size < minimum || value.size > maximum ||
      (kind === "voice" && (!Number.isSafeInteger(value.durationMs) ||
        value.durationMs < MIN_VOICE_DURATION_MS ||
        value.durationMs > MAX_VOICE_DURATION_MS))) {
    fail("data-loss", `The Family Memory ${kind} is malformed.`);
  }
  return value;
}

function canonicalMemory(snapshot, expected, { allowDeleting = false } = {}) {
  if (!snapshot?.exists) fail("not-found", "The selected Family Memory is unavailable.");
  const value = snapshot.data() ?? {};
  const deleting = value.status === "deleting";
  exactStoredObject(value, [
    "schemaVersion", "memoryKind", "serverId", "clubId", "channelId", "memoryId",
    "authorId", "authorDisplayName", "authorPhotoUrl", "caption", "status",
    "photo", "voice", "revision", "createdAt", "updatedAt",
    ...(deleting ? ["deletionOperationId", "deletionRequestedBy"] : []),
  ], "The Family Memory");
  const photo = mediaDescriptor(value.photo, "photo");
  const voice = mediaDescriptor(value.voice, "voice");
  if (value.schemaVersion !== FAMILY_MEMORY_SCHEMA_VERSION ||
      value.memoryKind !== "familyMemory" || value.serverId !== expected.serverId ||
      value.clubId !== expected.serverId || value.channelId !== expected.channelId ||
      value.memoryId !== expected.memoryId || typeof value.authorId !== "string" ||
      typeof value.authorDisplayName !== "string" || value.authorDisplayName.length < 1 ||
      value.authorDisplayName.length > 120 || value.authorPhotoUrl !== null ||
      typeof value.caption !== "string" || value.caption !== value.caption.trim() ||
      value.caption.length > 500 || !["published", ...(allowDeleting ? ["deleting"] : [])].includes(value.status) ||
      !validRevision(value.revision) || timestampMillis(value.createdAt) === null ||
      timestampMillis(value.updatedAt) === null ||
      photo.storagePath !== familyMemoryStoragePath({
        serverId: value.serverId, ownerId: value.authorId, memoryId: value.memoryId,
        assetKind: "photo", contentType: photo.contentType,
      }) || voice.storagePath !== familyMemoryStoragePath({
        serverId: value.serverId, ownerId: value.authorId, memoryId: value.memoryId,
        assetKind: "voice", contentType: voice.contentType,
      }) || (deleting && (typeof value.deletionOperationId !== "string" ||
        typeof value.deletionRequestedBy !== "string"))) {
    fail("data-loss", "The Family Memory needs reconciliation.");
  }
  return value;
}

function expectedUploadMetadata({ serverId, channelId, ownerId, memoryId, assetKind }) {
  return familyMemoryUploadMetadata({ serverId, channelId, ownerId, memoryId, assetKind });
}

function validateStoredAsset(metadata, expected) {
  if (!metadata || typeof metadata !== "object") {
    fail("failed-precondition", "The uploaded Family Memory media is missing.");
  }
  const generation = String(metadata.generation ?? "");
  const size = Number(metadata.size);
  const minimum = expected.assetKind === "photo" ? MIN_PHOTO_BYTES : MIN_VOICE_BYTES;
  const maximum = expected.assetKind === "photo" ? MAX_PHOTO_BYTES : MAX_VOICE_BYTES;
  const types = expected.assetKind === "photo" ? PHOTO_TYPES : VOICE_TYPES;
  const custom = customMetadataOf(metadata);
  const allowed = new Set([
    "firebaseStorageDownloadTokens",
    "yovoiceServerId", "yovoiceChannelId", "yovoiceOwnerUid",
    "yovoiceMemoryId", "yovoiceAssetKind",
  ]);
  const required = expectedUploadMetadata(expected);
  if (!GENERATION_PATTERN.test(generation) || generation !== expected.generation ||
      !Number.isSafeInteger(size) || size !== expected.size || size < minimum || size > maximum ||
      metadata.contentType !== expected.contentType || !types[metadata.contentType] ||
      Object.keys(custom).some((key) => !allowed.has(key)) ||
      Object.entries(required).some(([key, value]) => custom[key] !== value)) {
    fail("failed-precondition", "The uploaded Family Memory media is invalid.");
  }
  return { generation, size, contentType: metadata.contentType };
}

function validateTrustedProbe(probe, descriptor, kind) {
  if (!probe || typeof probe !== "object" || Array.isArray(probe) ||
      probe.generation !== descriptor.generation || probe.size !== descriptor.size ||
      probe.detectedContentType !== descriptor.contentType ||
      typeof probe.hasAudio !== "boolean" || typeof probe.hasVideo !== "boolean") {
    fail("failed-precondition", "The uploaded Family Memory bytes do not match.");
  }
  if (kind === "photo") {
    if (probe.durationMs !== null || probe.hasAudio || probe.hasVideo) {
      fail("failed-precondition", "The Family Memory photo is invalid.");
    }
    return null;
  }
  if (!Number.isSafeInteger(probe.durationMs) ||
      probe.durationMs < MIN_VOICE_DURATION_MS ||
      probe.durationMs > MAX_VOICE_DURATION_MS ||
      Math.abs(probe.durationMs - descriptor.durationMs) > VOICE_DURATION_TOLERANCE_MS ||
      !probe.hasAudio || probe.hasVideo) {
    fail("failed-precondition", "The Family Memory voice note is invalid.");
  }
  return probe.durationMs;
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

function createFamilyMemoryStorageAdapter(bucket) {
  if (!bucket?.file || !bucket?.getFiles) throw new TypeError("A Storage bucket is required.");
  return Object.freeze({
    async getMetadata(path) {
      const [metadata] = await bucket.file(path).getMetadata();
      return metadata;
    },
    async hardenObject(path, metadata, requiredMetadata) {
      const generation = storedGeneration(metadata?.generation, "The Family Memory generation");
      const custom = customMetadataOf(metadata);
      const canonical = Object.entries(requiredMetadata)
        .every(([key, value]) => custom[key] === value);
      const hasToken = typeof custom.firebaseStorageDownloadTokens === "string" &&
        custom.firebaseStorageDownloadTokens.length > 0;
      if (canonical && !hasToken) return metadata;
      const [updated] = await bucket.file(path).setMetadata({
        metadata: {
          ...custom,
          ...requiredMetadata,
          firebaseStorageDownloadTokens: null,
        },
      }, { ifGenerationMatch: generation });
      return updated;
    },
    async getSignedReadUrl(path, { expiresAtMs, generation }) {
      if (!Number.isSafeInteger(expiresAtMs) || expiresAtMs <= 0 ||
          typeof generation !== "string" || !GENERATION_PATTERN.test(generation)) {
        fail("failed-precondition", "The Family Memory media grant is malformed.");
      }
      const [url] = await bucket.file(path).getSignedUrl({
        version: "v4",
        action: "read",
        expires: expiresAtMs,
        queryParams: { generation },
      });
      return url;
    },
    async deleteObject(path, { generation = null } = {}) {
      if (generation !== null && !GENERATION_PATTERN.test(generation)) {
        fail("data-loss", "The Family Memory cleanup generation is malformed.");
      }
      await bucket.file(path, generation === null ? undefined : { generation }).delete({
        ignoreNotFound: true,
        ...(generation === null ? {} : { ifGenerationMatch: generation }),
      });
    },
    async listObjects(prefix, { maxResults = 20 } = {}) {
      if (typeof prefix !== "string" || !prefix || prefix.length > 1024 ||
          !Number.isSafeInteger(maxResults) || maxResults < 1 || maxResults > 20) {
        throw new TypeError("A bounded Storage prefix is required.");
      }
      const [files] = await bucket.getFiles({ prefix, maxResults, autoPaginate: false });
      return files.map((file) => ({
        name: file.name,
        generation: String(file.generation ?? file.metadata?.generation ?? ""),
      }));
    },
  });
}

function createServerFamilyMemoryService(dependencies) {
  const { db, Timestamp, storage, probeMedia, clock = Date.now } = dependencies;
  if (!db?.runTransaction || !Timestamp?.fromMillis || typeof clock !== "function" ||
      !storage?.getMetadata || !storage?.hardenObject ||
      !storage?.getSignedReadUrl || !storage?.deleteObject ||
      typeof probeMedia !== "function") {
    throw new TypeError("db, Timestamp, storage, probeMedia and clock are required.");
  }
  const operations = createServerOperations(dependencies);

  async function channelAccess(transaction, uid, input, capability = "read") {
    return requireMemoryChannel(await readChannelAccess({
      db,
      transaction,
      uid,
      serverId: input.serverId,
      channelId: input.channelId,
      capability,
    }), capability);
  }

  async function reserveServerFamilyMemoryV1(request) {
    const input = reserveInput(request.data);
    const operationInput = {
      serverId: input.serverId,
      channelId: input.channelId,
      caption: input.caption,
      photoContentType: input.photo.contentType,
      photoSize: input.photo.size,
      voiceContentType: input.voice.contentType,
      voiceSize: input.voice.size,
      voiceDurationMs: input.voice.durationMs,
      requestId: input.requestId,
    };
    return operations.execute(request, "server.family.memory.reserve.v1", operationInput,
      async ({ transaction, auth, prior, now, nowMs }) => {
        const access = await channelAccess(transaction, auth.uid, input, "write");
        const memoryId = canonicalFamilyMemoryId(auth.uid, input.serverId, input.requestId);
        const memoryReference = access.reference.collection("moments").doc(memoryId);
        const reservationRef = reservationReference(db, memoryId);
        const leaseRef = leaseReference(db, auth.uid);
        const day = new Date(nowMs).toISOString().slice(0, 10);
        const budgetRef = db.doc(`serverFamilyMemoryUploadBudgets/${digest(
          "server.family.memory.budget.v1", auth.uid, day,
        )}`);
        const [memory, reservation, lease, budget] = await transactionGetAll(
          transaction, memoryReference, reservationRef, leaseRef, budgetRef,
        );
        if (prior) {
          if (memory.exists) {
            const stored = canonicalMemory(memory, { ...input, memoryId }, { allowDeleting: true });
            if (stored.authorId !== auth.uid) {
              fail("aborted", "The Family Memory changed after the original request.");
            }
          }
          return prior;
        }
        if (memory.exists || reservation.exists) {
          fail("data-loss", "A Family Memory exists without its reservation receipt.");
        }
        if (lease.exists) {
          const active = lease.data() ?? {};
          if (active.ownerId !== auth.uid || typeof active.memoryId !== "string" ||
              timestampMillis(active.expiresAt) === null) {
            fail("data-loss", "The Family Memory upload lease needs reconciliation.");
          }
          if (active.status === "uploading" && active.expiresAt.toMillis() > nowMs) {
            fail("resource-exhausted", "Finish the current Family Memory upload first.");
          }
        }
        const bytes = input.photo.size + input.voice.size;
        const budgetValue = budget.exists ? budget.data() ?? {} : {};
        const usedBytes = budget.exists ? budgetValue.bytes : 0;
        const reservations = budget.exists ? budgetValue.reservations : 0;
        if (budget.exists && (budgetValue.schemaVersion !== 1 ||
            budgetValue.ownerId !== auth.uid || budgetValue.day !== day)) {
          fail("data-loss", "The Family Memory upload budget needs reconciliation.");
        }
        if (!Number.isSafeInteger(usedBytes) || usedBytes < 0 ||
            !Number.isSafeInteger(reservations) || reservations < 0 ||
            usedBytes + bytes > FAMILY_MEMORY_DAILY_BYTES) {
          fail("resource-exhausted", "The daily Family Memory upload limit is reached.");
        }
        const expiresAtMillis = nowMs + FAMILY_MEMORY_RESERVATION_TTL_MS;
        const photoStoragePath = familyMemoryStoragePath({
          serverId: input.serverId, ownerId: auth.uid, memoryId,
          assetKind: "photo", contentType: input.photo.contentType,
        });
        const voiceStoragePath = familyMemoryStoragePath({
          serverId: input.serverId, ownerId: auth.uid, memoryId,
          assetKind: "voice", contentType: input.voice.contentType,
        });
        const reservationValue = {
          schemaVersion: FAMILY_MEMORY_SCHEMA_VERSION,
          kind: "serverFamilyMemory",
          serverId: input.serverId,
          channelId: input.channelId,
          memoryId,
          ownerId: auth.uid,
          requestId: input.requestId,
          caption: input.caption,
          photoStoragePath,
          photoContentType: input.photo.contentType,
          photoSize: input.photo.size,
          voiceStoragePath,
          voiceContentType: input.voice.contentType,
          voiceSize: input.voice.size,
          voiceDurationMs: input.voice.durationMs,
          status: "uploading",
          createdAt: now,
          expiresAt: Timestamp.fromMillis(expiresAtMillis),
        };
        transaction.create(reservationRef, reservationValue);
        transaction.set(leaseRef, reservationValue);
        transaction.set(budgetRef, {
          schemaVersion: 1,
          ownerId: auth.uid,
          day,
          bytes: usedBytes + bytes,
          reservations: reservations + 1,
          updatedAt: now,
        });
        return {
          schemaVersion: FAMILY_MEMORY_SCHEMA_VERSION,
          serverId: input.serverId,
          channelId: input.channelId,
          memoryId,
          expiresAtMillis,
          photo: {
            storagePath: photoStoragePath,
            contentType: input.photo.contentType,
            size: input.photo.size,
            uploadMetadata: familyMemoryUploadMetadata({
              serverId: input.serverId, channelId: input.channelId,
              ownerId: auth.uid, memoryId, assetKind: "photo",
            }),
          },
          voice: {
            storagePath: voiceStoragePath,
            contentType: input.voice.contentType,
            size: input.voice.size,
            durationMs: input.voice.durationMs,
            uploadMetadata: familyMemoryUploadMetadata({
              serverId: input.serverId, channelId: input.channelId,
              ownerId: auth.uid, memoryId, assetKind: "voice",
            }),
          },
        };
      });
  }

  function finalizeInput(data) {
    const fields = [
      "serverId", "channelId", "memoryId", "requestId",
      "photoGeneration", "voiceGeneration",
    ];
    requireExactInput(data, fields, fields);
    return {
      serverId: requireId(data.serverId, "serverId"),
      channelId: requireId(data.channelId, "channelId"),
      memoryId: requireId(data.memoryId, "memoryId"),
      requestId: requireRequestId(data.requestId),
      photoGeneration: requireGeneration(data.photoGeneration, "photoGeneration"),
      voiceGeneration: requireGeneration(data.voiceGeneration, "voiceGeneration"),
    };
  }

  function finalizeIdentity(uid, input) {
    const { requestId, ...operationInput } = input;
    return operationIdentity("server.family.memory.finalize.v1", uid, requestId, operationInput);
  }

  async function readFinalizePlan(auth, input) {
    const identity = finalizeIdentity(auth.uid, input);
    return db.runTransaction(async (transaction) => {
      const access = await channelAccess(transaction, auth.uid, input, "write");
      const memoryRef = access.reference.collection("moments").doc(input.memoryId);
      const [ledger, memory, reservation] = await transactionGetAll(
        transaction,
        db.doc(`integrityOperationLedgers/${identity.id}`),
        memoryRef,
        reservationReference(db, input.memoryId),
      );
      const prior = assertLedgerReplay(ledger, {
        kind: "server.family.memory.finalize.v1",
        uid: auth.uid,
        inputHash: identity.inputHash,
      });
      if (prior) {
        if (memory.exists) {
          const stored = canonicalMemory(memory, input, { allowDeleting: true });
          if (stored.authorId !== auth.uid ||
              stored.photo.generation !== input.photoGeneration ||
              stored.voice.generation !== input.voiceGeneration) {
            fail("aborted", "The Family Memory changed after finalization.");
          }
        }
        return { prior };
      }
      if (memory.exists) {
        fail("data-loss", "A Family Memory exists without its finalization receipt.");
      }
      const snapshot = canonicalReservation(reservation, {
        ...input,
        ownerId: auth.uid,
        reserveRequestId: reservation.data()?.requestId,
      }, clock());
      return { reservation: snapshot };
    });
  }

  async function verifyReservationAsset(reservation, input, kind) {
    const photo = kind === "photo";
    const storagePath = photo ? reservation.photoStoragePath : reservation.voiceStoragePath;
    const expected = {
      serverId: reservation.serverId,
      channelId: reservation.channelId,
      ownerId: reservation.ownerId,
      memoryId: reservation.memoryId,
      assetKind: kind,
      generation: photo ? input.photoGeneration : input.voiceGeneration,
      contentType: photo ? reservation.photoContentType : reservation.voiceContentType,
      size: photo ? reservation.photoSize : reservation.voiceSize,
      ...(photo ? {} : { durationMs: reservation.voiceDurationMs }),
    };
    const metadata = await storage.getMetadata(storagePath);
    const descriptor = { storagePath, ...validateStoredAsset(metadata, expected),
      ...(photo ? {} : { durationMs: reservation.voiceDurationMs }) };
    const probe = await probeMedia({
      storagePath,
      generation: descriptor.generation,
      contentType: descriptor.contentType,
      size: descriptor.size,
      kind,
    });
    const measuredDuration = validateTrustedProbe(probe, descriptor, kind);
    const finalMetadata = await storage.getMetadata(storagePath);
    const finalDescriptor = {
      storagePath,
      ...validateStoredAsset(finalMetadata, expected),
      ...(photo ? {} : { durationMs: measuredDuration }),
    };
    if (finalDescriptor.generation !== descriptor.generation ||
        finalDescriptor.contentType !== descriptor.contentType ||
        finalDescriptor.size !== descriptor.size) {
      fail("aborted", "The Family Memory media changed during verification.");
    }
    await storage.hardenObject(storagePath, finalMetadata, expectedUploadMetadata(expected));
    return finalDescriptor;
  }

  async function finalizeServerFamilyMemoryV1(request) {
    const auth = requireActor(request);
    const input = finalizeInput(request.data);
    const plan = await readFinalizePlan(auth, input);
    let verified = null;
    if (!plan.prior) {
      const [photo, voice] = await Promise.all([
        verifyReservationAsset(plan.reservation, input, "photo"),
        verifyReservationAsset(plan.reservation, input, "voice"),
      ]);
      verified = { photo, voice, reservation: plan.reservation };
    }
    return operations.execute(request, "server.family.memory.finalize.v1", input,
      async ({ transaction, auth: currentAuth, profile, prior, now, nowMs }) => {
        const access = await channelAccess(transaction, currentAuth.uid, input, "write");
        const memoryRef = access.reference.collection("moments").doc(input.memoryId);
        const reservationRef = reservationReference(db, input.memoryId);
        const leaseRef = leaseReference(db, currentAuth.uid);
        const [memory, reservation, lease] = await transactionGetAll(
          transaction, memoryRef, reservationRef, leaseRef,
        );
        if (prior) {
          if (memory.exists) {
            const stored = canonicalMemory(memory, input, { allowDeleting: true });
            if (stored.authorId !== currentAuth.uid ||
                stored.photo.generation !== input.photoGeneration ||
                stored.voice.generation !== input.voiceGeneration) {
              fail("aborted", "The Family Memory changed after finalization.");
            }
          }
          return prior;
        }
        if (!verified || memory.exists) {
          fail("data-loss", "The Family Memory finalization needs reconciliation.");
        }
        const reserved = canonicalReservation(reservation, {
          ...input,
          ownerId: currentAuth.uid,
          reserveRequestId: verified.reservation.requestId,
        }, nowMs);
        const leaseValue = lease.exists ? lease.data() ?? {} : {};
        if (!lease.exists || leaseValue.memoryId !== input.memoryId ||
            leaseValue.ownerId !== currentAuth.uid || leaseValue.status !== "uploading") {
          fail("failed-precondition", "The Family Memory upload lease is invalid.");
        }
        if (reserved.photoStoragePath !== verified.photo.storagePath ||
            reserved.voiceStoragePath !== verified.voice.storagePath) {
          fail("aborted", "The Family Memory reservation changed. Try again.");
        }
        const result = {
          schemaVersion: FAMILY_MEMORY_SCHEMA_VERSION,
          serverId: input.serverId,
          channelId: input.channelId,
          memoryId: input.memoryId,
          revision: 1,
          status: "published",
        };
        transaction.create(memoryRef, {
          schemaVersion: FAMILY_MEMORY_SCHEMA_VERSION,
          memoryKind: "familyMemory",
          serverId: input.serverId,
          clubId: input.serverId,
          channelId: input.channelId,
          memoryId: input.memoryId,
          authorId: currentAuth.uid,
          authorDisplayName: canonicalDisplayName(profile),
          authorPhotoUrl: null,
          caption: reserved.caption,
          status: "published",
          photo: verified.photo,
          voice: verified.voice,
          revision: 1,
          createdAt: now,
          updatedAt: now,
        });
        transaction.delete(reservationRef);
        transaction.delete(leaseRef);
        return result;
      });
  }

  async function authorizeMemoryAccess(auth, input, { consume = false } = {}) {
    const nowMs = clock();
    const now = Timestamp.fromMillis(nowMs);
    return db.runTransaction(async (transaction) => {
      const access = await channelAccess(transaction, auth.uid, input, "read");
      const memoryRef = access.reference.collection("moments").doc(input.memoryId);
      const restrictionRef = db.doc(`restrictions/${auth.uid}`);
      const rateRef = rateLimitReference(db, "server.family.memory.access", auth.uid);
      const reads = consume
        ? await transactionGetAll(transaction, memoryRef, restrictionRef, rateRef)
        : await transactionGetAll(transaction, memoryRef, restrictionRef);
      assertNotRestricted(reads[1], "Your", nowMs);
      const memory = canonicalMemory(reads[0], input);
      if (consume) {
        consumeRateLimit(transaction, reads[2], {
          reference: rateRef,
          scope: "server.family.memory.access",
          uid: auth.uid,
          now,
          nowMs,
          ...ACCESS_LIMIT,
        });
      }
      return {
        checkedAtMs: nowMs,
        serverRevision: access.server.revision,
        channelRevision: access.channel.revision,
        channelAclRevision: access.channel.aclRevision,
        membershipRevision: access.member.authorizationRevision,
        memory,
      };
    });
  }

  function sameAccess(first, second) {
    return first.serverRevision === second.serverRevision &&
      first.channelRevision === second.channelRevision &&
      first.channelAclRevision === second.channelAclRevision &&
      first.membershipRevision === second.membershipRevision &&
      first.memory.revision === second.memory.revision &&
      first.memory.status === second.memory.status &&
      JSON.stringify(first.memory.photo) === JSON.stringify(second.memory.photo) &&
      JSON.stringify(first.memory.voice) === JSON.stringify(second.memory.voice);
  }

  async function grantForDescriptor(memory, descriptor, kind, expiresAtMillis) {
    const metadata = await storage.getMetadata(descriptor.storagePath);
    const verified = validateStoredAsset(metadata, {
      serverId: memory.serverId,
      channelId: memory.channelId,
      ownerId: memory.authorId,
      memoryId: memory.memoryId,
      assetKind: kind,
      generation: descriptor.generation,
      contentType: descriptor.contentType,
      size: descriptor.size,
    });
    await storage.hardenObject(descriptor.storagePath, metadata,
      expectedUploadMetadata({
        serverId: memory.serverId, channelId: memory.channelId,
        ownerId: memory.authorId, memoryId: memory.memoryId, assetKind: kind,
      }));
    const url = await storage.getSignedReadUrl(descriptor.storagePath, {
      expiresAtMs: expiresAtMillis,
      generation: verified.generation,
    });
    if (!safeGrantUrl(url)) {
      fail("failed-precondition", "A private Family Memory media grant is unavailable.");
    }
    return { url, generation: verified.generation, contentType: verified.contentType,
      size: verified.size, ...(kind === "voice" ? { durationMs: descriptor.durationMs } : {}) };
  }

  async function getServerFamilyMemoryMediaAccessV1(request) {
    const auth = requireActor(request, { verified: false });
    const fields = ["serverId", "channelId", "memoryId"];
    requireExactInput(request.data, fields, fields);
    const input = {
      serverId: requireId(request.data.serverId, "serverId"),
      channelId: requireId(request.data.channelId, "channelId"),
      memoryId: requireId(request.data.memoryId, "memoryId"),
    };
    const access = await authorizeMemoryAccess(auth, input, { consume: true });
    const expiresAtMillis = access.checkedAtMs + FAMILY_MEMORY_ACCESS_TTL_MS;
    const [photo, voice] = await Promise.all([
      grantForDescriptor(access.memory, access.memory.photo, "photo", expiresAtMillis),
      grantForDescriptor(access.memory, access.memory.voice, "voice", expiresAtMillis),
    ]);
    const finalAccess = await authorizeMemoryAccess(auth, input);
    if (finalAccess.checkedAtMs >= expiresAtMillis || !sameAccess(access, finalAccess)) {
      fail("aborted", "Family Memory authorization changed. Try again.");
    }
    return {
      schemaVersion: FAMILY_MEMORY_SCHEMA_VERSION,
      serverId: input.serverId,
      channelId: input.channelId,
      memoryId: input.memoryId,
      expiresAtMillis,
      photo,
      voice,
    };
  }

  function deleteInput(data) {
    const fields = ["serverId", "channelId", "memoryId", "expectedRevision", "requestId"];
    requireExactInput(data, fields, fields);
    return {
      serverId: requireId(data.serverId, "serverId"),
      channelId: requireId(data.channelId, "channelId"),
      memoryId: requireId(data.memoryId, "memoryId"),
      expectedRevision: requireSafeInteger(data.expectedRevision, "expectedRevision", {
        min: 1,
        max: Number.MAX_SAFE_INTEGER - 1,
      }),
      requestId: requireRequestId(data.requestId),
    };
  }

  function canonicalDeletionJob(snapshot, expected = {}) {
    if (!snapshot?.exists) fail("not-found", "The Family Memory deletion job is unavailable.");
    const value = snapshot.data() ?? {};
    exactStoredObject(value, [
      "schemaVersion", "kind", "jobId", "serverId", "channelId", "memoryId",
      "authorId", "requestedBy", "deletionOperationId", "deletionRevision",
      "photo", "voice", "status", "createdAt", "updatedAt",
    ], "The Family Memory deletion job");
    try {
      requireId(value.serverId, "serverId");
      requireId(value.channelId, "channelId");
      requireId(value.memoryId, "memoryId");
      requireUid(value.authorId, "authorId");
      requireUid(value.requestedBy, "requestedBy");
    } catch (_) {
      fail("data-loss", "The Family Memory deletion job needs reconciliation.");
    }
    if (value.schemaVersion !== FAMILY_MEMORY_SCHEMA_VERSION ||
        value.kind !== "serverFamilyMemoryDelete" || value.status !== "pending" ||
        value.jobId !== snapshot.id || value.jobId !== deletionJobId(value.serverId, value.memoryId) ||
        !validRevision(value.deletionRevision) || typeof value.authorId !== "string" ||
        typeof value.requestedBy !== "string" || typeof value.deletionOperationId !== "string" ||
        timestampMillis(value.createdAt) === null || timestampMillis(value.updatedAt) === null ||
        (expected.serverId !== undefined && value.serverId !== expected.serverId) ||
        (expected.channelId !== undefined && value.channelId !== expected.channelId) ||
        (expected.memoryId !== undefined && value.memoryId !== expected.memoryId)) {
      fail("data-loss", "The Family Memory deletion job needs reconciliation.");
    }
    const photo = mediaDescriptor(value.photo, "photo");
    const voice = mediaDescriptor(value.voice, "voice");
    if (photo.storagePath !== familyMemoryStoragePath({
      serverId: value.serverId,
      ownerId: value.authorId,
      memoryId: value.memoryId,
      assetKind: "photo",
      contentType: photo.contentType,
    }) || voice.storagePath !== familyMemoryStoragePath({
      serverId: value.serverId,
      ownerId: value.authorId,
      memoryId: value.memoryId,
      assetKind: "voice",
      contentType: voice.contentType,
    })) {
      fail("data-loss", "The Family Memory deletion job needs reconciliation.");
    }
    return value;
  }

  async function processFamilyMemoryDeletionJob(jobId, expected = {}) {
    requireId(jobId, "deletion job id");
    const jobRef = db.doc(`serverFamilyMemoryDeletionJobs/${jobId}`);
    const initial = await jobRef.get();
    if (!initial.exists) return { deleted: true, cleanupPending: false };
    const job = canonicalDeletionJob(initial, expected);
    const memoryRef = db.doc(`clubs/${job.serverId}/moments/${job.memoryId}`);
    const memorySnapshot = await memoryRef.get();
    if (!memorySnapshot.exists) {
      // The durable job itself carries the canonical, generation-bound
      // descriptors. A concurrent server teardown may already have removed
      // the Firestore row, but that must never turn its private bytes into an
      // orphan. Delete both objects before retiring the job.
      await Promise.all([
        storage.deleteObject(job.photo.storagePath, { generation: job.photo.generation }),
        storage.deleteObject(job.voice.storagePath, { generation: job.voice.generation }),
      ]);
      await db.runTransaction(async (transaction) => {
        const current = await transaction.get(jobRef);
        if (current.exists) canonicalDeletionJob(current, job);
        if (current.exists) transaction.delete(jobRef);
      });
      return { deleted: true, cleanupPending: false };
    }
    const memory = canonicalMemory(memorySnapshot, job, { allowDeleting: true });
    if (memory.status !== "deleting" || memory.deletionOperationId !== job.deletionOperationId ||
        memory.revision !== job.deletionRevision || memory.authorId !== job.authorId ||
        JSON.stringify(memory.photo) !== JSON.stringify(job.photo) ||
        JSON.stringify(memory.voice) !== JSON.stringify(job.voice)) {
      fail("data-loss", "The Family Memory deletion fence changed.");
    }
    await Promise.all([
      storage.deleteObject(job.photo.storagePath, { generation: job.photo.generation }),
      storage.deleteObject(job.voice.storagePath, { generation: job.voice.generation }),
    ]);
    await db.runTransaction(async (transaction) => {
      const [currentJob, currentMemory] = await transactionGetAll(
        transaction, jobRef, memoryRef,
      );
      if (!currentJob.exists) {
        if (currentMemory.exists) {
          fail("data-loss", "The Family Memory deletion job disappeared early.");
        }
        return;
      }
      const checkedJob = canonicalDeletionJob(currentJob, job);
      if (!currentMemory.exists) {
        transaction.delete(jobRef);
        return;
      }
      const checkedMemory = canonicalMemory(currentMemory, checkedJob, { allowDeleting: true });
      if (checkedMemory.status !== "deleting" ||
          checkedMemory.deletionOperationId !== checkedJob.deletionOperationId ||
          checkedMemory.revision !== checkedJob.deletionRevision ||
          JSON.stringify(checkedMemory.photo) !== JSON.stringify(checkedJob.photo) ||
          JSON.stringify(checkedMemory.voice) !== JSON.stringify(checkedJob.voice)) {
        fail("data-loss", "The Family Memory deletion fence changed.");
      }
      transaction.delete(memoryRef);
      transaction.delete(jobRef);
    });
    return { deleted: true, cleanupPending: false };
  }

  async function deleteServerFamilyMemoryV1(request) {
    const input = deleteInput(request.data);
    let operationId = null;
    const staged = await operations.execute(request, "server.family.memory.delete.v1", input,
      async ({ transaction, auth, prior, now, identity }) => {
        operationId = identity.id;
        const access = await channelAccess(transaction, auth.uid, input, "write");
        const memoryRef = access.reference.collection("moments").doc(input.memoryId);
        const memorySnapshot = await transaction.get(memoryRef);
        if (prior) {
          if (memorySnapshot.exists) {
            const stored = canonicalMemory(memorySnapshot, input, { allowDeleting: true });
            if (stored.status !== "deleting" || stored.deletionOperationId !== identity.id) {
              fail("aborted", "The Family Memory changed after the deletion request.");
            }
          }
          return prior;
        }
        const memory = canonicalMemory(memorySnapshot, input);
        if (memory.revision !== input.expectedRevision) {
          fail("aborted", "The Family Memory changed. Refresh before deleting it.");
        }
        if (memory.authorId !== auth.uid && !MODERATOR_ROLES.includes(access.member.role)) denied();
        const deletionRevision = memory.revision + 1;
        if (!validRevision(deletionRevision)) {
          fail("data-loss", "The Family Memory revision is exhausted.");
        }
        const jobRef = deletionJobReference(db, input.serverId, input.memoryId);
        const existingJob = await transaction.get(jobRef);
        if (existingJob.exists) {
          fail("data-loss", "A Family Memory deletion job already exists.");
        }
        const job = {
          schemaVersion: FAMILY_MEMORY_SCHEMA_VERSION,
          kind: "serverFamilyMemoryDelete",
          jobId: jobRef.id,
          serverId: input.serverId,
          channelId: input.channelId,
          memoryId: input.memoryId,
          authorId: memory.authorId,
          requestedBy: auth.uid,
          deletionOperationId: identity.id,
          deletionRevision,
          photo: memory.photo,
          voice: memory.voice,
          status: "pending",
          createdAt: now,
          updatedAt: now,
        };
        transaction.update(memoryRef, {
          status: "deleting",
          deletionOperationId: identity.id,
          deletionRequestedBy: auth.uid,
          revision: deletionRevision,
          updatedAt: now,
        });
        transaction.create(jobRef, job);
        return {
          serverId: input.serverId,
          channelId: input.channelId,
          memoryId: input.memoryId,
          deletionRevision,
          deleted: false,
          cleanupPending: true,
        };
      });
    const jobId = deletionJobId(input.serverId, input.memoryId);
    await processFamilyMemoryDeletionJob(jobId, input);
    return { ...staged, deleted: true, cleanupPending: false,
      deletionOperationId: operationId };
  }

  async function expireServerFamilyMemoryUploadReservations({ limit = 20 } = {}) {
    requireSafeInteger(limit, "limit", { min: 1, max: 20 });
    const nowMs = clock();
    const now = Timestamp.fromMillis(nowMs);
    const page = await db.collection("serverFamilyMemoryUploadReservations")
      .where("expiresAt", "<=", now)
      .limit(limit)
      .get();
    const expired = [];
    for (const document of page.docs) {
      const raw = document.data() ?? {};
      const expected = {
        serverId: raw.serverId,
        channelId: raw.channelId,
        memoryId: document.id,
        ownerId: raw.ownerId,
        reserveRequestId: raw.requestId,
      };
      canonicalReservation(document, expected, nowMs, { allowExpiring: true });
      const claimed = await db.runTransaction(async (transaction) => {
        const current = await transaction.get(document.ref);
        if (!current.exists) return null;
        const value = canonicalReservation(current, expected, nowMs, { allowExpiring: true });
        if (value.status === "uploading") {
          transaction.update(document.ref, { status: "expiring", updatedAt: now });
        }
        return value;
      });
      if (!claimed) continue;
      await Promise.all([
        storage.deleteObject(claimed.photoStoragePath),
        storage.deleteObject(claimed.voiceStoragePath),
      ]);
      await db.runTransaction(async (transaction) => {
        const leaseRef = leaseReference(db, claimed.ownerId);
        const [current, lease] = await transactionGetAll(
          transaction, document.ref, leaseRef,
        );
        if (current.exists) {
          const value = canonicalReservation(current, expected, nowMs, { allowExpiring: true });
          if (value.status !== "expiring") {
            fail("data-loss", "The Family Memory reservation cleanup fence changed.");
          }
          transaction.delete(document.ref);
        }
        if (lease.exists && lease.data()?.memoryId === document.id &&
            lease.data()?.ownerId === claimed.ownerId) {
          transaction.delete(leaseRef);
        }
      });
      expired.push(document.id);
    }
    return { expired, processed: page.size, hasMore: page.size === limit };
  }

  async function processPendingFamilyMemoryDeletionJobs({ limit = 20 } = {}) {
    requireSafeInteger(limit, "limit", { min: 1, max: 20 });
    const page = await db.collection("serverFamilyMemoryDeletionJobs")
      .where("status", "==", "pending")
      .limit(limit)
      .get();
    const completed = [];
    for (const document of page.docs) {
      canonicalDeletionJob(document);
      await processFamilyMemoryDeletionJob(document.id);
      completed.push(document.id);
    }
    return { completed, processed: page.size, hasMore: page.size === limit };
  }

  return Object.freeze({
    deleteServerFamilyMemoryV1,
    expireServerFamilyMemoryUploadReservations,
    finalizeServerFamilyMemoryV1,
    getServerFamilyMemoryMediaAccessV1,
    processFamilyMemoryDeletionJob,
    processPendingFamilyMemoryDeletionJobs,
    reserveServerFamilyMemoryV1,
  });
}

module.exports = {
  FAMILY_MEMORY_ACCESS_TTL_MS,
  FAMILY_MEMORY_DAILY_BYTES,
  FAMILY_MEMORY_RESERVATION_TTL_MS,
  FAMILY_MEMORY_SCHEMA_VERSION,
  MAX_PHOTO_BYTES,
  MAX_VOICE_BYTES,
  MAX_VOICE_DURATION_MS,
  MIN_PHOTO_BYTES,
  MIN_VOICE_BYTES,
  MIN_VOICE_DURATION_MS,
  PHOTO_TYPES,
  VOICE_DURATION_TOLERANCE_MS,
  VOICE_TYPES,
  canonicalFamilyMemoryId,
  createFamilyMemoryStorageAdapter,
  createServerFamilyMemoryService,
  deletionJobId,
  familyMemoryStoragePath,
  familyMemoryUploadMetadata,
  validateStoredAsset,
  validateTrustedProbe,
};
