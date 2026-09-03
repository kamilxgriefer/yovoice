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
const REEL_CALLABLE_METHODS = Object.freeze({
  reserveReelDraft: "reserveReelDraft",
  finalizeReelDraft: "finalizeReelDraft",
  listReels: "listReels",
  getReelMediaAccess: "getReelMediaAccess",
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

function createReelFunctions({
  runtime = null,
  registrars = defaultRegistrars(),
  enforceAppCheck = false,
  log = logger,
  cleanupBatchSize = 20,
} = {}) {
  for (const name of ["onCall", "onDocumentCreated", "onSchedule"]) {
    if (typeof registrars?.[name] !== "function") {
      throw new TypeError(`Missing Cloud Functions registrar: ${name}.`);
    }
  }
  if (!Number.isSafeInteger(cleanupBatchSize) || cleanupBatchSize < 1 || cleanupBatchSize > 50) {
    throw new TypeError("cleanupBatchSize must be an integer from 1 to 50.");
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
  exportsMap.processPendingReelCleanupSchedule = registrars.onSchedule(
    { ...scheduleOptions, schedule: "every 5 minutes" },
    async () => {
      const snapshot = await resolved.db
        .collection("reelCleanupOutbox")
        .where("status", "==", "pending")
        .limit(cleanupBatchSize)
        .get();
      const results = await Promise.all(
        snapshot.docs.map(async (document) => {
          try {
            return await resolved.service.processCleanupOutbox(document.id);
          } catch (error) {
            log.error?.("Reel cleanup failed", {
              outboxId: document.id,
              code: error?.code ?? "internal",
            });
            return { outboxId: document.id, completed: false };
          }
        }),
      );
      return {
        processed: results.length,
        completed: results.filter(({ completed }) => completed === true).length,
        hasMore: snapshot.size === cleanupBatchSize,
      };
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
      return resolved.service.processCleanupOutbox(outboxId);
    },
  );
  return Object.freeze(exportsMap);
}

module.exports = {
  REGION,
  REEL_CALLABLE_METHODS,
  authBoundRequest,
  createReelFunctions,
  createReelRuntime,
};
