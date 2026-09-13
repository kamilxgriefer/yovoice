// Private Company Files for Servers V1.
//
// Uploads are capability based: a callable reserves one immutable object,
// Storage Rules accept only that exact path/size/type/metadata, and finalize
// verifies the generation and the bytes before publishing a descriptor. Reads
// use short-lived generation-bound signed URLs. Deletion is revision fenced
// and leaves a durable cleanup job until the private object is gone.

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

const COMPANY_FILE_SCHEMA_VERSION = 1;
const COMPANY_FILE_RESERVATION_TTL_MS = 10 * 60_000;
const COMPANY_FILE_ACCESS_TTL_MS = 90_000;
const COMPANY_FILE_DAILY_BYTES = 256 * 1024 * 1024;
const MIN_COMPANY_FILE_BYTES = 1;
const MAX_COMPANY_FILE_BYTES = 25 * 1024 * 1024;
const ACCESS_LIMIT = Object.freeze({ maxEvents: 180, windowMs: 60_000 });
const GENERATION_PATTERN = /^[0-9]{1,30}$/u;
const DISPLAY_NAME_CONTROL_PATTERN = /[\u0000-\u001f\u007f/\\]/u;
const COMPANY_FILE_TYPES = Object.freeze({
  "application/pdf": "pdf",
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
  "text/plain": "txt",
});

function exactObject(value, keys, label, code = "data-loss") {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    fail(code, `${label} is malformed.`);
  }
  const actual = Object.keys(value).sort();
  const expected = [...keys].sort();
  if (actual.length !== expected.length ||
      actual.some((key, index) => key !== expected[index])) {
    fail(code, `${label} is malformed.`);
  }
  return value;
}

function customMetadataOf(metadata) {
  const custom = metadata?.metadata ?? metadata?.customMetadata ?? {};
  return custom && typeof custom === "object" && !Array.isArray(custom) ? custom : {};
}

function requireGeneration(value, label = "generation") {
  if (typeof value !== "string" || !GENERATION_PATTERN.test(value)) {
    fail("invalid-argument", `${label} is invalid.`);
  }
  return value;
}

function storedGeneration(value) {
  const generation = String(value ?? "");
  if (!GENERATION_PATTERN.test(generation)) {
    fail("data-loss", "The Company File generation is malformed.");
  }
  return generation;
}

function companyFileDisplayName(value) {
  const result = text(value, 180, "displayName");
  if (!result || DISPLAY_NAME_CONTROL_PATTERN.test(result)) {
    fail("invalid-argument", "displayName is invalid.");
  }
  return result;
}

function companyFileId(uid, serverId, channelId, requestId) {
  requireUid(uid);
  requireId(serverId, "serverId");
  requireId(channelId, "channelId");
  requireRequestId(requestId);
  return `cf_${digest("server.company.file.v1", serverId, channelId, uid, requestId).slice(0, 40)}`;
}

function companyFileStoragePath({ serverId, channelId, ownerId, fileId, contentType }) {
  requireId(serverId, "serverId");
  requireId(channelId, "channelId");
  requireUid(ownerId, "ownerId");
  requireId(fileId, "fileId");
  if (typeof contentType !== "string" || !COMPANY_FILE_TYPES[contentType]) {
    fail("invalid-argument", "contentType is invalid.");
  }
  return `server_company_files/${serverId}/${channelId}/${ownerId}/${fileId}.${COMPANY_FILE_TYPES[contentType]}`;
}

function companyFileUploadMetadata({ serverId, channelId, ownerId, fileId }) {
  return Object.freeze({
    yovoiceServerId: serverId,
    yovoiceChannelId: channelId,
    yovoiceOwnerUid: ownerId,
    yovoiceFileId: fileId,
    yovoiceAssetKind: "companyFile",
  });
}

function reservationReference(db, fileId) {
  return db.doc(`serverCompanyFileUploadReservations/${fileId}`);
}

function leaseReference(db, uid) {
  return db.doc(`serverCompanyFileUploadLeases/${uid}`);
}

function deletionJobId(serverId, channelId, fileId) {
  return `cfd_${digest("server.company.file.delete.v1", serverId, channelId, fileId).slice(0, 40)}`;
}

function deletionJobReference(db, serverId, channelId, fileId) {
  return db.doc(`serverCompanyFileDeletionJobs/${deletionJobId(serverId, channelId, fileId)}`);
}

function canonicalDeletionJob(snapshot, expected = {}) {
  if (!snapshot?.exists) fail("not-found", "The Company File deletion job is unavailable.");
  const value = snapshot.data() ?? {};
  exactObject(value, [
    "schemaVersion", "kind", "jobId", "serverId", "channelId", "fileId",
    "ownerId", "requestedBy", "deletionOperationId", "deletionRevision", "file",
    "status", "createdAt", "updatedAt",
  ], "The Company File deletion job");
  try {
    requireId(value.serverId, "serverId");
    requireId(value.channelId, "channelId");
    requireId(value.fileId, "fileId");
    requireUid(value.ownerId, "ownerId");
    requireUid(value.requestedBy, "requestedBy");
  } catch (_) {
    fail("data-loss", "The Company File deletion job needs reconciliation.");
  }
  const descriptor = fileDescriptor(value.file);
  let canonicalPath;
  try {
    canonicalPath = companyFileStoragePath({
      serverId: value.serverId,
      channelId: value.channelId,
      ownerId: value.ownerId,
      fileId: value.fileId,
      contentType: descriptor.contentType,
    });
  } catch (_) {
    fail("data-loss", "The Company File deletion job needs reconciliation.");
  }
  if (value.schemaVersion !== COMPANY_FILE_SCHEMA_VERSION ||
      value.kind !== "serverCompanyFileDelete" || value.status !== "pending" ||
      value.jobId !== snapshot.id ||
      value.jobId !== deletionJobId(value.serverId, value.channelId, value.fileId) ||
      !validRevision(value.deletionRevision) ||
      typeof value.deletionOperationId !== "string" ||
      timestampMillis(value.createdAt) === null || timestampMillis(value.updatedAt) === null ||
      descriptor.storagePath !== canonicalPath ||
      (expected.serverId !== undefined && value.serverId !== expected.serverId) ||
      (expected.channelId !== undefined && value.channelId !== expected.channelId) ||
      (expected.fileId !== undefined && value.fileId !== expected.fileId)) {
    fail("data-loss", "The Company File deletion job needs reconciliation.");
  }
  return value;
}

function requireFilesChannel(access, capability) {
  if (access.server.serverType !== "company" || access.channel.kind !== "files" ||
      access.capabilities[capability] !== true) denied();
  return access;
}

function reserveInput(data) {
  const fields = [
    "serverId", "channelId", "requestId", "displayName", "contentType", "size",
  ];
  requireExactInput(data, fields, fields);
  if (typeof data.contentType !== "string" || !COMPANY_FILE_TYPES[data.contentType]) {
    fail("invalid-argument", "contentType is invalid.");
  }
  return {
    serverId: requireId(data.serverId, "serverId"),
    channelId: requireId(data.channelId, "channelId"),
    requestId: requireRequestId(data.requestId),
    displayName: companyFileDisplayName(data.displayName),
    contentType: data.contentType,
    size: requireSafeInteger(data.size, "size", {
      min: MIN_COMPANY_FILE_BYTES,
      max: MAX_COMPANY_FILE_BYTES,
    }),
  };
}

function canonicalReservation(snapshot, expected, nowMs, { allowExpiring = false } = {}) {
  if (!snapshot?.exists) fail("failed-precondition", "The Company File upload reservation is missing.");
  const value = snapshot.data() ?? {};
  const expiring = value.status === "expiring";
  exactObject(value, [
    "schemaVersion", "kind", "serverId", "channelId", "fileId", "ownerId",
    "requestId", "displayName", "storagePath", "contentType", "size", "status",
    "createdAt", "expiresAt", ...(expiring ? ["updatedAt"] : []),
  ], "The Company File upload reservation");
  let canonicalId;
  let canonicalPath;
  try {
    canonicalId = companyFileId(value.ownerId, value.serverId, value.channelId, value.requestId);
    canonicalPath = companyFileStoragePath(value);
  } catch (_) {
    fail("failed-precondition", "The Company File upload reservation is invalid.");
  }
  const expiresAtMillis = timestampMillis(value.expiresAt);
  const statuses = allowExpiring ? ["uploading", "expiring"] : ["uploading"];
  if (value.schemaVersion !== COMPANY_FILE_SCHEMA_VERSION ||
      value.kind !== "serverCompanyFile" || value.serverId !== expected.serverId ||
      value.channelId !== expected.channelId || value.fileId !== expected.fileId ||
      value.fileId !== snapshot.id || value.fileId !== canonicalId ||
      value.ownerId !== expected.ownerId || value.requestId !== expected.reserveRequestId ||
      typeof value.displayName !== "string" || !value.displayName ||
      value.displayName !== value.displayName.trim() || value.displayName.length > 180 ||
      DISPLAY_NAME_CONTROL_PATTERN.test(value.displayName) ||
      !COMPANY_FILE_TYPES[value.contentType] ||
      !Number.isSafeInteger(value.size) || value.size < MIN_COMPANY_FILE_BYTES ||
      value.size > MAX_COMPANY_FILE_BYTES || value.storagePath !== canonicalPath ||
      !statuses.includes(value.status) || timestampMillis(value.createdAt) === null ||
      !Number.isSafeInteger(expiresAtMillis) || (!allowExpiring && expiresAtMillis <= nowMs)) {
    fail("failed-precondition", "The Company File upload reservation is invalid.");
  }
  return { ...value, expiresAtMillis };
}

function fileDescriptor(value) {
  exactObject(value, ["storagePath", "generation", "contentType", "size"],
    "The Company File descriptor");
  if (typeof value.storagePath !== "string" || !GENERATION_PATTERN.test(value.generation) ||
      !COMPANY_FILE_TYPES[value.contentType] || !Number.isSafeInteger(value.size) ||
      value.size < MIN_COMPANY_FILE_BYTES || value.size > MAX_COMPANY_FILE_BYTES) {
    fail("data-loss", "The Company File descriptor is malformed.");
  }
  return value;
}

function canonicalFile(snapshot, expected, { allowDeleting = false } = {}) {
  if (!snapshot?.exists) fail("not-found", "The selected Company File is unavailable.");
  const value = snapshot.data() ?? {};
  const deleting = value.status === "deleting";
  exactObject(value, [
    "schemaVersion", "fileKind", "serverId", "clubId", "channelId", "fileId",
    "ownerId", "ownerDisplayName", "ownerPhotoUrl", "displayName", "status",
    "file", "revision", "createdAt", "updatedAt",
    ...(deleting ? ["deletionOperationId", "deletionRequestedBy"] : []),
  ], "The Company File");
  const descriptor = fileDescriptor(value.file);
  let canonicalPath;
  try {
    canonicalPath = companyFileStoragePath({
      serverId: value.serverId, channelId: value.channelId, ownerId: value.ownerId,
      fileId: value.fileId, contentType: descriptor.contentType,
    });
    requireUid(value.ownerId, "ownerId");
  } catch (_) {
    fail("data-loss", "The Company File needs reconciliation.");
  }
  if (value.schemaVersion !== COMPANY_FILE_SCHEMA_VERSION || value.fileKind !== "companyFile" ||
      value.serverId !== expected.serverId || value.clubId !== expected.serverId ||
      value.channelId !== expected.channelId || value.fileId !== expected.fileId ||
      typeof value.ownerDisplayName !== "string" || !value.ownerDisplayName ||
      value.ownerDisplayName.length > 120 || value.ownerPhotoUrl !== null ||
      typeof value.displayName !== "string" || !value.displayName ||
      value.displayName !== value.displayName.trim() || value.displayName.length > 180 ||
      DISPLAY_NAME_CONTROL_PATTERN.test(value.displayName) ||
      !["published", ...(allowDeleting ? ["deleting"] : [])].includes(value.status) ||
      !validRevision(value.revision) || timestampMillis(value.createdAt) === null ||
      timestampMillis(value.updatedAt) === null || descriptor.storagePath !== canonicalPath ||
      (deleting && (typeof value.deletionOperationId !== "string" ||
        typeof value.deletionRequestedBy !== "string"))) {
    fail("data-loss", "The Company File needs reconciliation.");
  }
  return value;
}

function validateStoredFile(metadata, expected) {
  if (!metadata || typeof metadata !== "object" || Array.isArray(metadata)) {
    fail("failed-precondition", "The uploaded Company File is missing.");
  }
  const generation = String(metadata.generation ?? "");
  const size = Number(metadata.size);
  const custom = customMetadataOf(metadata);
  const allowed = new Set([
    "firebaseStorageDownloadTokens", "yovoiceServerId", "yovoiceChannelId",
    "yovoiceOwnerUid", "yovoiceFileId", "yovoiceAssetKind",
  ]);
  const required = companyFileUploadMetadata(expected);
  if (!GENERATION_PATTERN.test(generation) || generation !== expected.generation ||
      !Number.isSafeInteger(size) || size !== expected.size ||
      size < MIN_COMPANY_FILE_BYTES || size > MAX_COMPANY_FILE_BYTES ||
      metadata.contentType !== expected.contentType || !COMPANY_FILE_TYPES[metadata.contentType] ||
      Object.keys(custom).some((key) => !allowed.has(key)) ||
      Object.entries(required).some(([key, expectedValue]) => custom[key] !== expectedValue)) {
    fail("failed-precondition", "The uploaded Company File is invalid.");
  }
  return { generation, size, contentType: metadata.contentType };
}

function validateTrustedFileProbe(probe, descriptor) {
  if (!probe || typeof probe !== "object" || Array.isArray(probe) ||
      probe.generation !== descriptor.generation || probe.size !== descriptor.size ||
      probe.detectedContentType !== descriptor.contentType) {
    fail("failed-precondition", "The uploaded Company File bytes do not match.");
  }
  return descriptor;
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

function detectCompanyFileType(bytes) {
  if (!Buffer.isBuffer(bytes)) bytes = Buffer.from(bytes ?? []);
  if (bytes.length >= 12 && /^%PDF-1[.][0-9]/u.test(bytes.subarray(0, 8).toString("ascii")) &&
      bytes.subarray(Math.max(0, bytes.length - 1024)).includes(Buffer.from("%%EOF"))) {
    return "application/pdf";
  }
  if (bytes.length >= 5 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff &&
      bytes[bytes.length - 2] === 0xff && bytes[bytes.length - 1] === 0xd9) {
    return "image/jpeg";
  }
  if (bytes.length >= 20 && bytes.subarray(0, 8).equals(
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
  ) && bytes.subarray(bytes.length - 8).equals(
    Buffer.from([0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82]),
  )) return "image/png";
  if (bytes.length >= 12 && bytes.subarray(0, 4).toString("ascii") === "RIFF" &&
      bytes.readUInt32LE(4) + 8 === bytes.length &&
      bytes.subarray(8, 12).toString("ascii") === "WEBP" &&
      ["VP8 ", "VP8L", "VP8X"].includes(bytes.subarray(12, 16).toString("ascii"))) {
    return "image/webp";
  }
  if (bytes.length > 0 && !bytes.includes(0)) {
    try {
      new TextDecoder("utf-8", { fatal: true }).decode(bytes);
      return "text/plain";
    } catch (_) {
      // Fall through to the closed unsupported result.
    }
  }
  return null;
}

function createCompanyFileStorageAdapter(bucket) {
  if (!bucket?.file) throw new TypeError("A Storage bucket is required.");
  return Object.freeze({
    async getMetadata(path) {
      const [metadata] = await bucket.file(path).getMetadata();
      return metadata;
    },
    async probeFile(path, { generation, size }) {
      requireGeneration(generation);
      requireSafeInteger(size, "size", {
        min: MIN_COMPANY_FILE_BYTES,
        max: MAX_COMPANY_FILE_BYTES,
      });
      const chunks = [];
      let seen = 0;
      const stream = bucket.file(path, { generation }).createReadStream({ validation: true });
      for await (const chunk of stream) {
        seen += chunk.length;
        if (seen > size || seen > MAX_COMPANY_FILE_BYTES) {
          stream.destroy();
          fail("failed-precondition", "The uploaded Company File is too large.");
        }
        chunks.push(chunk);
      }
      if (seen !== size) fail("failed-precondition", "The uploaded Company File size changed.");
      return {
        generation,
        size,
        detectedContentType: detectCompanyFileType(Buffer.concat(chunks, seen)),
      };
    },
    async hardenObject(path, metadata, requiredMetadata) {
      const generation = storedGeneration(metadata?.generation);
      const custom = customMetadataOf(metadata);
      const canonical = Object.entries(requiredMetadata)
        .every(([key, expectedValue]) => custom[key] === expectedValue);
      const hasToken = typeof custom.firebaseStorageDownloadTokens === "string" &&
        custom.firebaseStorageDownloadTokens.length > 0;
      if (canonical && !hasToken) return metadata;
      const [updated] = await bucket.file(path).setMetadata({
        metadata: { ...custom, ...requiredMetadata, firebaseStorageDownloadTokens: null },
      }, { ifGenerationMatch: generation });
      return updated;
    },
    async getSignedReadUrl(path, { expiresAtMs, generation }) {
      if (!Number.isSafeInteger(expiresAtMs) || expiresAtMs <= 0 ||
          typeof generation !== "string" || !GENERATION_PATTERN.test(generation)) {
        fail("failed-precondition", "The Company File access grant is malformed.");
      }
      const [url] = await bucket.file(path).getSignedUrl({
        version: "v4", action: "read", expires: expiresAtMs,
        queryParams: { generation },
      });
      return url;
    },
    async deleteObject(path, { generation = null } = {}) {
      if (generation !== null && !GENERATION_PATTERN.test(generation)) {
        fail("data-loss", "The Company File cleanup generation is malformed.");
      }
      await bucket.file(path, generation === null ? undefined : { generation }).delete({
        ignoreNotFound: true,
        ...(generation === null ? {} : { ifGenerationMatch: generation }),
      });
    },
  });
}

function createServerCompanyFileService(dependencies) {
  const { db, Timestamp, storage, clock = Date.now } = dependencies;
  if (!db?.runTransaction || !Timestamp?.fromMillis || typeof clock !== "function" ||
      !storage?.getMetadata || !storage?.probeFile || !storage?.hardenObject ||
      !storage?.getSignedReadUrl || !storage?.deleteObject) {
    throw new TypeError("db, Timestamp, storage and clock are required.");
  }
  const operations = createServerOperations(dependencies);

  async function channelAccess(transaction, uid, input, capability = "read") {
    return requireFilesChannel(await readChannelAccess({
      db,
      transaction,
      uid,
      serverId: input.serverId,
      channelId: input.channelId,
      capability,
    }), capability);
  }

  async function reserveServerCompanyFileV1(request) {
    const input = reserveInput(request.data);
    return operations.execute(request, "server.company.file.reserve.v1", input,
      async ({ transaction, auth, prior, now, nowMs }) => {
        const access = await channelAccess(transaction, auth.uid, input, "write");
        const fileId = companyFileId(auth.uid, input.serverId, input.channelId, input.requestId);
        const fileRef = access.channelReference.collection("files").doc(fileId);
        const reservationRef = reservationReference(db, fileId);
        const leaseRef = leaseReference(db, auth.uid);
        const day = new Date(nowMs).toISOString().slice(0, 10);
        const budgetRef = db.doc(`serverCompanyFileUploadBudgets/${digest(
          "server.company.file.budget.v1", auth.uid, day,
        )}`);
        const [fileSnapshot, reservationSnapshot, leaseSnapshot, budgetSnapshot] =
          await transactionGetAll(transaction, fileRef, reservationRef, leaseRef, budgetRef);
        if (prior) {
          if (!reservationSnapshot.exists) {
            if (fileSnapshot.exists) {
              const stored = canonicalFile(
                fileSnapshot,
                { ...input, fileId },
                { allowDeleting: true },
              );
              if (stored.ownerId !== auth.uid) {
                fail("aborted", "The Company File changed after the original request.");
              }
            }
            fail(
              "failed-precondition",
              "The original Company File upload reservation is no longer active.",
            );
          }
          canonicalReservation(reservationSnapshot, {
            ...input,
            fileId,
            ownerId: auth.uid,
            reserveRequestId: input.requestId,
          }, nowMs);
          return prior;
        }
        if (fileSnapshot.exists || reservationSnapshot.exists) {
          fail("data-loss", "A Company File exists without its reservation receipt.");
        }
        if (leaseSnapshot.exists) {
          const lease = leaseSnapshot.data() ?? {};
          if (lease.ownerId !== auth.uid || typeof lease.fileId !== "string" ||
              timestampMillis(lease.expiresAt) === null) {
            fail("data-loss", "The Company File upload lease needs reconciliation.");
          }
          if (lease.status === "uploading" && lease.expiresAt.toMillis() > nowMs) {
            fail("resource-exhausted", "Finish the current Company File upload first.");
          }
        }
        const budget = budgetSnapshot.exists ? budgetSnapshot.data() ?? {} : {};
        const usedBytes = budgetSnapshot.exists ? budget.bytes : 0;
        const reservations = budgetSnapshot.exists ? budget.reservations : 0;
        if (budgetSnapshot.exists && (budget.schemaVersion !== 1 ||
            budget.ownerId !== auth.uid || budget.day !== day)) {
          fail("data-loss", "The Company File upload budget needs reconciliation.");
        }
        if (!Number.isSafeInteger(usedBytes) || usedBytes < 0 ||
            !Number.isSafeInteger(reservations) || reservations < 0 ||
            usedBytes + input.size > COMPANY_FILE_DAILY_BYTES) {
          fail("resource-exhausted", "The daily Company File upload limit is reached.");
        }
        const expiresAtMillis = nowMs + COMPANY_FILE_RESERVATION_TTL_MS;
        const storagePath = companyFileStoragePath({
          serverId: input.serverId,
          channelId: input.channelId,
          ownerId: auth.uid,
          fileId,
          contentType: input.contentType,
        });
        const reservation = {
          schemaVersion: COMPANY_FILE_SCHEMA_VERSION,
          kind: "serverCompanyFile",
          serverId: input.serverId,
          channelId: input.channelId,
          fileId,
          ownerId: auth.uid,
          requestId: input.requestId,
          displayName: input.displayName,
          storagePath,
          contentType: input.contentType,
          size: input.size,
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
          schemaVersion: COMPANY_FILE_SCHEMA_VERSION,
          serverId: input.serverId,
          channelId: input.channelId,
          fileId,
          displayName: input.displayName,
          expiresAtMillis,
          file: {
            storagePath,
            contentType: input.contentType,
            size: input.size,
            uploadMetadata: companyFileUploadMetadata({
              serverId: input.serverId,
              channelId: input.channelId,
              ownerId: auth.uid,
              fileId,
            }),
          },
        };
      });
  }

  function finalizeInput(data) {
    const fields = ["serverId", "channelId", "fileId", "generation", "requestId"];
    requireExactInput(data, fields, fields);
    return {
      serverId: requireId(data.serverId, "serverId"),
      channelId: requireId(data.channelId, "channelId"),
      fileId: requireId(data.fileId, "fileId"),
      generation: requireGeneration(data.generation),
      requestId: requireRequestId(data.requestId),
    };
  }

  function finalizeIdentity(uid, input) {
    const { requestId, ...operationInput } = input;
    return operationIdentity("server.company.file.finalize.v1", uid, requestId, operationInput);
  }

  async function readFinalizePlan(auth, input) {
    const identity = finalizeIdentity(auth.uid, input);
    return db.runTransaction(async (transaction) => {
      const access = await channelAccess(transaction, auth.uid, input, "write");
      const fileRef = access.channelReference.collection("files").doc(input.fileId);
      const [ledger, fileSnapshot, reservationSnapshot] = await transactionGetAll(
        transaction,
        db.doc(`integrityOperationLedgers/${identity.id}`),
        fileRef,
        reservationReference(db, input.fileId),
      );
      const prior = assertLedgerReplay(ledger, {
        kind: "server.company.file.finalize.v1",
        uid: auth.uid,
        inputHash: identity.inputHash,
      });
      if (prior) {
        if (!fileSnapshot.exists) {
          fail("not-found", "The finalized Company File is no longer available.");
        }
        const stored = canonicalFile(fileSnapshot, input, { allowDeleting: true });
        if (stored.status !== "published") {
          fail("failed-precondition", "The finalized Company File is being deleted.");
        }
        if (stored.ownerId !== auth.uid || stored.file.generation !== input.generation) {
          fail("aborted", "The Company File changed after finalization.");
        }
        return { prior };
      }
      if (fileSnapshot.exists) {
        fail("data-loss", "A Company File exists without its finalization receipt.");
      }
      const raw = reservationSnapshot.data() ?? {};
      const reservation = canonicalReservation(reservationSnapshot, {
        ...input,
        ownerId: auth.uid,
        reserveRequestId: raw.requestId,
      }, clock());
      return { reservation };
    });
  }

  async function verifyReservationFile(reservation, input) {
    const expected = {
      serverId: reservation.serverId,
      channelId: reservation.channelId,
      ownerId: reservation.ownerId,
      fileId: reservation.fileId,
      generation: input.generation,
      contentType: reservation.contentType,
      size: reservation.size,
    };
    const metadata = await storage.getMetadata(reservation.storagePath);
    const descriptor = {
      storagePath: reservation.storagePath,
      ...validateStoredFile(metadata, expected),
    };
    validateTrustedFileProbe(await storage.probeFile(reservation.storagePath, {
      generation: descriptor.generation,
      size: descriptor.size,
      contentType: descriptor.contentType,
    }), descriptor);
    const finalMetadata = await storage.getMetadata(reservation.storagePath);
    const finalDescriptor = {
      storagePath: reservation.storagePath,
      ...validateStoredFile(finalMetadata, expected),
    };
    if (JSON.stringify(finalDescriptor) !== JSON.stringify(descriptor)) {
      fail("aborted", "The Company File changed during verification.");
    }
    await storage.hardenObject(reservation.storagePath, finalMetadata,
      companyFileUploadMetadata(expected));
    return finalDescriptor;
  }

  async function finalizeServerCompanyFileV1(request) {
    const auth = requireActor(request);
    const input = finalizeInput(request.data);
    const plan = await readFinalizePlan(auth, input);
    const verified = plan.prior ? null : await verifyReservationFile(plan.reservation, input);
    return operations.execute(request, "server.company.file.finalize.v1", input,
      async ({ transaction, auth: currentAuth, profile, prior, now, nowMs }) => {
        const access = await channelAccess(transaction, currentAuth.uid, input, "write");
        const fileRef = access.channelReference.collection("files").doc(input.fileId);
        const reservationRef = reservationReference(db, input.fileId);
        const leaseRef = leaseReference(db, currentAuth.uid);
        const [fileSnapshot, reservationSnapshot, leaseSnapshot] = await transactionGetAll(
          transaction, fileRef, reservationRef, leaseRef,
        );
        if (prior) {
          if (!fileSnapshot.exists) {
            fail("not-found", "The finalized Company File is no longer available.");
          }
          const stored = canonicalFile(fileSnapshot, input, { allowDeleting: true });
          if (stored.status !== "published") {
            fail("failed-precondition", "The finalized Company File is being deleted.");
          }
          if (stored.ownerId !== currentAuth.uid || stored.file.generation !== input.generation) {
            fail("aborted", "The Company File changed after finalization.");
          }
          return prior;
        }
        if (!verified || fileSnapshot.exists) {
          fail("data-loss", "The Company File finalization needs reconciliation.");
        }
        const reservation = canonicalReservation(reservationSnapshot, {
          ...input,
          ownerId: currentAuth.uid,
          reserveRequestId: plan.reservation.requestId,
        }, nowMs);
        const lease = leaseSnapshot.exists ? leaseSnapshot.data() ?? {} : {};
        if (!leaseSnapshot.exists || lease.fileId !== input.fileId ||
            lease.ownerId !== currentAuth.uid || lease.status !== "uploading") {
          fail("failed-precondition", "The Company File upload lease is invalid.");
        }
        if (reservation.storagePath !== verified.storagePath) {
          fail("aborted", "The Company File reservation changed. Try again.");
        }
        const result = {
          schemaVersion: COMPANY_FILE_SCHEMA_VERSION,
          serverId: input.serverId,
          channelId: input.channelId,
          fileId: input.fileId,
          revision: 1,
          status: "published",
        };
        transaction.create(fileRef, {
          schemaVersion: COMPANY_FILE_SCHEMA_VERSION,
          fileKind: "companyFile",
          serverId: input.serverId,
          clubId: input.serverId,
          channelId: input.channelId,
          fileId: input.fileId,
          ownerId: currentAuth.uid,
          ownerDisplayName: canonicalDisplayName(profile),
          ownerPhotoUrl: null,
          displayName: reservation.displayName,
          status: "published",
          file: verified,
          revision: 1,
          createdAt: now,
          updatedAt: now,
        });
        transaction.delete(reservationRef);
        transaction.delete(leaseRef);
        return result;
      });
  }

  async function authorizeFileAccess(auth, input, { consume = false } = {}) {
    const nowMs = clock();
    const now = Timestamp.fromMillis(nowMs);
    return db.runTransaction(async (transaction) => {
      const access = await channelAccess(transaction, auth.uid, input, "read");
      const fileRef = access.channelReference.collection("files").doc(input.fileId);
      const restrictionRef = db.doc(`restrictions/${auth.uid}`);
      const rateRef = rateLimitReference(db, "server.company.file.access", auth.uid);
      const reads = consume
        ? await transactionGetAll(transaction, fileRef, restrictionRef, rateRef)
        : await transactionGetAll(transaction, fileRef, restrictionRef);
      assertNotRestricted(reads[1], "Your", nowMs);
      const file = canonicalFile(reads[0], input);
      if (consume) {
        consumeRateLimit(transaction, reads[2], {
          reference: rateRef,
          scope: "server.company.file.access",
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
        file,
      };
    });
  }

  function sameAccess(first, second) {
    return first.serverRevision === second.serverRevision &&
      first.channelRevision === second.channelRevision &&
      first.channelAclRevision === second.channelAclRevision &&
      first.membershipRevision === second.membershipRevision &&
      first.file.revision === second.file.revision &&
      first.file.status === second.file.status &&
      JSON.stringify(first.file.file) === JSON.stringify(second.file.file);
  }

  async function getServerCompanyFileAccessV1(request) {
    const auth = requireActor(request, { verified: false });
    const fields = ["serverId", "channelId", "fileId"];
    requireExactInput(request.data, fields, fields);
    const input = {
      serverId: requireId(request.data.serverId, "serverId"),
      channelId: requireId(request.data.channelId, "channelId"),
      fileId: requireId(request.data.fileId, "fileId"),
    };
    const access = await authorizeFileAccess(auth, input, { consume: true });
    const descriptor = access.file.file;
    const metadata = await storage.getMetadata(descriptor.storagePath);
    const verified = validateStoredFile(metadata, {
      serverId: input.serverId,
      channelId: input.channelId,
      ownerId: access.file.ownerId,
      fileId: input.fileId,
      generation: descriptor.generation,
      contentType: descriptor.contentType,
      size: descriptor.size,
    });
    await storage.hardenObject(descriptor.storagePath, metadata,
      companyFileUploadMetadata({
        serverId: input.serverId,
        channelId: input.channelId,
        ownerId: access.file.ownerId,
        fileId: input.fileId,
      }));
    const expiresAtMillis = access.checkedAtMs + COMPANY_FILE_ACCESS_TTL_MS;
    const url = await storage.getSignedReadUrl(descriptor.storagePath, {
      expiresAtMs: expiresAtMillis,
      generation: verified.generation,
    });
    if (!safeGrantUrl(url)) {
      fail("failed-precondition", "A private Company File access grant is unavailable.");
    }
    const finalAccess = await authorizeFileAccess(auth, input);
    if (finalAccess.checkedAtMs >= expiresAtMillis || !sameAccess(access, finalAccess)) {
      fail("aborted", "Company File authorization changed. Try again.");
    }
    return {
      schemaVersion: COMPANY_FILE_SCHEMA_VERSION,
      serverId: input.serverId,
      channelId: input.channelId,
      fileId: input.fileId,
      displayName: access.file.displayName,
      expiresAtMillis,
      file: { url, ...verified },
    };
  }

  function deleteInput(data) {
    const fields = ["serverId", "channelId", "fileId", "expectedRevision", "requestId"];
    requireExactInput(data, fields, fields);
    return {
      serverId: requireId(data.serverId, "serverId"),
      channelId: requireId(data.channelId, "channelId"),
      fileId: requireId(data.fileId, "fileId"),
      expectedRevision: requireSafeInteger(data.expectedRevision, "expectedRevision", {
        min: 1,
        max: Number.MAX_SAFE_INTEGER - 1,
      }),
      requestId: requireRequestId(data.requestId),
    };
  }

  async function processCompanyFileDeletionJob(jobId, expected = {}) {
    requireId(jobId, "deletion job id");
    const jobRef = db.doc(`serverCompanyFileDeletionJobs/${jobId}`);
    const initial = await jobRef.get();
    if (!initial.exists) return { deleted: true, cleanupPending: false };
    const job = canonicalDeletionJob(initial, expected);
    const fileRef = db.doc(`clubs/${job.serverId}/channels/${job.channelId}/files/${job.fileId}`);
    const initialFile = await fileRef.get();
    if (initialFile.exists) {
      const file = canonicalFile(initialFile, job, { allowDeleting: true });
      if (file.status !== "deleting" || file.deletionOperationId !== job.deletionOperationId ||
          file.revision !== job.deletionRevision || file.ownerId !== job.ownerId ||
          JSON.stringify(file.file) !== JSON.stringify(job.file)) {
        fail("data-loss", "The Company File deletion fence changed.");
      }
    }
    await storage.deleteObject(job.file.storagePath, { generation: job.file.generation });
    await db.runTransaction(async (transaction) => {
      const [currentJob, currentFile] = await transactionGetAll(transaction, jobRef, fileRef);
      if (!currentJob.exists) {
        if (currentFile.exists) fail("data-loss", "The Company File deletion job disappeared early.");
        return;
      }
      const checkedJob = canonicalDeletionJob(currentJob, job);
      if (currentFile.exists) {
        const checkedFile = canonicalFile(currentFile, checkedJob, { allowDeleting: true });
        if (checkedFile.status !== "deleting" ||
            checkedFile.deletionOperationId !== checkedJob.deletionOperationId ||
            checkedFile.revision !== checkedJob.deletionRevision ||
            checkedFile.ownerId !== checkedJob.ownerId ||
            JSON.stringify(checkedFile.file) !== JSON.stringify(checkedJob.file)) {
          fail("data-loss", "The Company File deletion fence changed.");
        }
        transaction.delete(fileRef);
      }
      transaction.delete(jobRef);
    });
    return { deleted: true, cleanupPending: false };
  }

  async function deleteServerCompanyFileV1(request) {
    const input = deleteInput(request.data);
    let operationId = null;
    const staged = await operations.execute(request, "server.company.file.delete.v1", input,
      async ({ transaction, auth, prior, now, identity }) => {
        operationId = identity.id;
        const access = await channelAccess(transaction, auth.uid, input, "write");
        const fileRef = access.channelReference.collection("files").doc(input.fileId);
        const snapshot = await transaction.get(fileRef);
        if (prior) {
          if (snapshot.exists) {
            const stored = canonicalFile(snapshot, input, { allowDeleting: true });
            if (stored.status !== "deleting" || stored.deletionOperationId !== identity.id) {
              fail("aborted", "The Company File changed after the deletion request.");
            }
          }
          return prior;
        }
        const file = canonicalFile(snapshot, input);
        if (file.revision !== input.expectedRevision) {
          fail("aborted", "The Company File changed. Refresh before deleting it.");
        }
        if (file.ownerId !== auth.uid && !MODERATOR_ROLES.includes(access.member.role)) denied();
        const deletionRevision = file.revision + 1;
        if (!validRevision(deletionRevision)) fail("data-loss", "The Company File revision is exhausted.");
        const jobRef = deletionJobReference(db, input.serverId, input.channelId, input.fileId);
        if ((await transaction.get(jobRef)).exists) {
          fail("data-loss", "A Company File deletion job already exists.");
        }
        transaction.update(fileRef, {
          status: "deleting",
          deletionOperationId: identity.id,
          deletionRequestedBy: auth.uid,
          revision: deletionRevision,
          updatedAt: now,
        });
        transaction.create(jobRef, {
          schemaVersion: COMPANY_FILE_SCHEMA_VERSION,
          kind: "serverCompanyFileDelete",
          jobId: jobRef.id,
          serverId: input.serverId,
          channelId: input.channelId,
          fileId: input.fileId,
          ownerId: file.ownerId,
          requestedBy: auth.uid,
          deletionOperationId: identity.id,
          deletionRevision,
          file: file.file,
          status: "pending",
          createdAt: now,
          updatedAt: now,
        });
        return {
          serverId: input.serverId,
          channelId: input.channelId,
          fileId: input.fileId,
          deletionRevision,
          deleted: false,
          cleanupPending: true,
        };
      });
    await processCompanyFileDeletionJob(
      deletionJobId(input.serverId, input.channelId, input.fileId), input,
    );
    return { ...staged, deletionOperationId: operationId, deleted: true, cleanupPending: false };
  }

  async function expireServerCompanyFileUploadReservations({ limit = 20 } = {}) {
    requireSafeInteger(limit, "limit", { min: 1, max: 20 });
    const nowMs = clock();
    const now = Timestamp.fromMillis(nowMs);
    const page = await db.collection("serverCompanyFileUploadReservations")
      .where("expiresAt", "<=", now)
      .limit(limit)
      .get();
    const expired = [];
    for (const document of page.docs) {
      const raw = document.data() ?? {};
      const expected = {
        serverId: raw.serverId,
        channelId: raw.channelId,
        fileId: document.id,
        ownerId: raw.ownerId,
        reserveRequestId: raw.requestId,
      };
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
        const leaseRef = leaseReference(db, claimed.ownerId);
        const [current, lease] = await transactionGetAll(transaction, document.ref, leaseRef);
        if (current.exists) {
          const value = canonicalReservation(current, expected, nowMs, { allowExpiring: true });
          if (value.status !== "expiring") {
            fail("data-loss", "The Company File reservation cleanup fence changed.");
          }
          transaction.delete(document.ref);
        }
        if (lease.exists && lease.data()?.fileId === document.id &&
            lease.data()?.ownerId === claimed.ownerId) transaction.delete(leaseRef);
      });
      expired.push(document.id);
    }
    return { expired, processed: page.size, hasMore: page.size === limit };
  }

  async function processPendingCompanyFileDeletionJobs({ limit = 20 } = {}) {
    requireSafeInteger(limit, "limit", { min: 1, max: 20 });
    const page = await db.collection("serverCompanyFileDeletionJobs")
      .where("status", "==", "pending")
      .limit(limit)
      .get();
    const completed = [];
    for (const document of page.docs) {
      canonicalDeletionJob(document);
      await processCompanyFileDeletionJob(document.id);
      completed.push(document.id);
    }
    return { completed, processed: page.size, hasMore: page.size === limit };
  }

  return Object.freeze({
    deleteServerCompanyFileV1,
    expireServerCompanyFileUploadReservations,
    finalizeServerCompanyFileV1,
    getServerCompanyFileAccessV1,
    processCompanyFileDeletionJob,
    processPendingCompanyFileDeletionJobs,
    reserveServerCompanyFileV1,
  });
}

module.exports = {
  COMPANY_FILE_ACCESS_TTL_MS,
  COMPANY_FILE_DAILY_BYTES,
  COMPANY_FILE_RESERVATION_TTL_MS,
  COMPANY_FILE_SCHEMA_VERSION,
  COMPANY_FILE_TYPES,
  MAX_COMPANY_FILE_BYTES,
  MIN_COMPANY_FILE_BYTES,
  canonicalCompanyFile: canonicalFile,
  canonicalCompanyFileDeletionJob: canonicalDeletionJob,
  canonicalCompanyFileReservation: canonicalReservation,
  companyFileId,
  companyFileStoragePath,
  companyFileUploadMetadata,
  createCompanyFileStorageAdapter,
  createServerCompanyFileService,
  deletionJobId,
  detectCompanyFileType,
  validateStoredFile,
  validateTrustedFileProbe,
};
