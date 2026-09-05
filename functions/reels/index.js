const { FieldPath, getFirestore, Timestamp } = require("firebase-admin/firestore");
const { getStorage } = require("firebase-admin/storage");
const { logger } = require("firebase-functions/v2");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onCall } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");

const { requireActor, requireId } = require("../integrity/guards");
const { createReelMediaProbe } = require("./probe");
const { createReelService } = require("./service");
const { createReelStorageAdapter } = require("./storage");

const REGION = "europe-west1";
const REEL_EXPIRY_BATCH_SIZE = 200;
const REEL_CLEANUP_BATCH_SIZE = 50;
const REEL_CLEANUP_MAX_BATCHES = 4;
const REEL_CALLABLE_METHODS = Object.freeze({
  reserveReelDraft: "reserveReelDraft",
  reserveReelDraftV2: "reserveReelDraftV2",
  finalizeReelDraft: "finalizeReelDraft",
  finalizeReelDraftV2: "finalizeReelDraftV2",
  listReels: "listReels",
  listReelsV2: "listReelsV2",
  getReelMediaAccess: "getReelMediaAccess",
  getReelMediaAccessV2: "getReelMediaAccessV2",
  deleteReel: "deleteReel",
  createReelReport: "createReelReport",
});

function createReelRuntime({
  db = null,
  bucket = null,
  storage = null,
  probeMedia = undefined,
  clock = () => Date.now(),
  serviceOptions = {},
} = {}) {
  const database = db ?? getFirestore();
  const resolvedBucket = bucket ?? getStorage().bucket();
  const objectStorage = storage ?? createReelStorageAdapter(resolvedBucket);
  const resolvedProbe = probeMedia === undefined
    ? createReelMediaProbe(resolvedBucket)
    : probeMedia;
  const service = createReelService({
    db: database,
    FieldPath,
    Timestamp,
    storage: objectStorage,
    probeMedia: resolvedProbe,
    clock,
    ...serviceOptions,
  });
  return Object.freeze({
    db: database,
    FieldPath,
    service,
  });
}

function defaultRegistrars() {
  return { onCall, onDocumentCreated, onSchedule };
}

function authBoundRequest(request) {
  const auth = requireActor(request, { verified: false });
  return {
    auth: {
      uid: auth.uid,
      token: { ...(auth.token ?? {}) },
    },
    data: request.data,
  };
}

function safeCleanupResultCode(result) {
  const code = typeof result?.code === "string" ? result.code : "internal";
  return /^[a-z0-9-]{1,64}$/u.test(code) ? code : "internal";
}

function createReelFunctions({
  runtime = null,
  registrars = defaultRegistrars(),
  enforceAppCheck = false,
  log = logger,
  cleanupBatchSize = REEL_CLEANUP_BATCH_SIZE,
  cleanupMaxBatches = REEL_CLEANUP_MAX_BATCHES,
} = {}) {
  for (const name of ["onCall", "onDocumentCreated", "onSchedule"]) {
    if (typeof registrars?.[name] !== "function") {
      throw new TypeError(`Missing Cloud Functions registrar: ${name}.`);
    }
  }
  if (!Number.isSafeInteger(cleanupBatchSize) || cleanupBatchSize < 1 || cleanupBatchSize > 50) {
    throw new TypeError("cleanupBatchSize must be an integer from 1 to 50.");
  }
  if (!Number.isSafeInteger(cleanupMaxBatches) ||
      cleanupMaxBatches < 1 || cleanupMaxBatches > 10) {
    throw new TypeError("cleanupMaxBatches must be an integer from 1 to 10.");
  }
  const resolved = runtime ?? createReelRuntime();
  if (!resolved?.db || !resolved?.FieldPath?.documentId || !resolved?.service) {
    throw new TypeError("A Reel runtime is required.");
  }
  const callableOptions = {
    region: REGION,
    memory: "512MiB",
    timeoutSeconds: 120,
    maxInstances: 50,
    enforceAppCheck: enforceAppCheck === true,
    consumeAppCheckToken: enforceAppCheck === true,
  };
  const exportsMap = {};
  for (const [name, method] of Object.entries(REEL_CALLABLE_METHODS)) {
    exportsMap[name] = registrars.onCall(callableOptions, async (request) =>
      resolved.service[method](authBoundRequest(request)));
  }
  const scheduleOptions = {
    region: REGION,
    timeZone: "Etc/UTC",
    memory: "512MiB",
    timeoutSeconds: 300,
    maxInstances: 1,
  };
  exportsMap.expireAbandonedReelDraftsSchedule = registrars.onSchedule(
    { ...scheduleOptions, schedule: "every 10 minutes" },
    () => resolved.service.expireAbandonedReelDrafts({ limit: 100 }),
  );
  exportsMap.expirePublishedReelsSchedule = registrars.onSchedule(
    { ...scheduleOptions, schedule: "every 10 minutes" },
    async () => {
      const result = await resolved.service.expirePublishedReels({
        limit: REEL_EXPIRY_BATCH_SIZE,
      });
      for (const failure of result.failed ?? []) {
        log.error?.("Reel availability expiry failed", failure);
      }
      if (result.hasMore === true) {
        log.warn?.("Reel availability expiry reached its scan bound", {
          expired: result.expired?.length ?? 0,
          failed: result.failed?.length ?? 0,
        });
      }
      return result;
    },
  );
  exportsMap.processPendingReelCleanupSchedule = registrars.onSchedule(
    { ...scheduleOptions, schedule: "every 5 minutes" },
    async () => {
      const aggregate = {
        processed: 0,
        completed: 0,
        failed: [],
        hasMore: false,
        batches: 0,
        batchSize: cleanupBatchSize,
      };
      for (let batch = 0; batch < cleanupMaxBatches; batch += 1) {
        const page = await resolved.service.processReadyCleanupOutbox({
          limit: cleanupBatchSize,
        });
        aggregate.batches += 1;
        aggregate.processed += page.processed ?? 0;
        aggregate.completed += page.completed ?? 0;
        aggregate.failed.push(...(page.failed ?? []));
        aggregate.hasMore = page.hasMore === true;
        // `hasMore` can be true while a legacy compatibility page contains
        // only future-dated modern rows. Its durable scan cursor still made
        // progress, so keep draining within the explicit batch cap.
        if (page.hasMore !== true) break;
      }
      for (const failure of aggregate.failed) {
        log.error?.("Reel cleanup failed", failure);
      }
      if (aggregate.hasMore === true) {
        log.warn?.("Reel cleanup reached its scan bound", {
          processed: aggregate.processed,
          completed: aggregate.completed,
          failed: aggregate.failed.length,
          batches: aggregate.batches,
          capacity: cleanupBatchSize * cleanupMaxBatches,
        });
      }
      return aggregate;
    },
  );
  exportsMap.onReelCleanupOutboxCreated = registrars.onDocumentCreated(
    {
      region: REGION,
      memory: "256MiB",
      timeoutSeconds: 120,
      maxInstances: 50,
      retry: true,
      document: "reelCleanupOutbox/{outboxId}",
    },
    async (event) => {
      if (!event.data?.exists) return { skipped: true };
      const outboxId = requireId(event.params?.outboxId, "outboxId");
      const result = await resolved.service.processCleanupOutbox(outboxId);
      if (result?.deadLetter === true) {
        log.error?.("Reel cleanup trigger reached dead letter", {
          outboxId,
          deadLetter: true,
          code: safeCleanupResultCode(result),
        });
      }
      return result;
    },
  );
  return Object.freeze(exportsMap);
}

module.exports = {
  REGION,
  REEL_CLEANUP_BATCH_SIZE,
  REEL_CLEANUP_MAX_BATCHES,
  REEL_CALLABLE_METHODS,
  REEL_EXPIRY_BATCH_SIZE,
  authBoundRequest,
  createReelFunctions,
  createReelRuntime,
};
