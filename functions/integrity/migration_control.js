const {
  consumeRateLimit,
  fail,
  isValidOpaqueUid,
  operationIdentity,
  rateLimitReference,
  requireBoolean,
  requireExactInput,
  requireId,
  requireRequestId,
  requireSafeInteger,
  timestampMillis,
  transactionGetAll,
} = require("./guards");

const DEFAULT_MIGRATION_LIMITS = Object.freeze({
  scan: { maxEvents: 2, windowMs: 60_000 },
  apply: { maxEvents: 30, windowMs: 60 * 60_000 },
});
const LEDGER_KEYS = Object.freeze([
  "attemptCount",
  "errorCode",
  "inputHash",
  "kind",
  "leaseExpiresAt",
  "ownerId",
  "requestId",
  "result",
  "schemaVersion",
  "startedAt",
  "status",
  "updatedAt",
]);

function exactMigrationLedger(snapshot, identity) {
  if (!snapshot.exists) return null;
  const data = snapshot.data() ?? {};
  const keys = Object.keys(data).sort();
  if (keys.length !== LEDGER_KEYS.length ||
      keys.some((key, index) => key !== LEDGER_KEYS[index]) ||
      data.schemaVersion !== 1 || data.kind !== identity.kind ||
      data.ownerId !== identity.uid || data.requestId !== identity.requestId ||
      !["running", "failed", "completed"].includes(data.status) ||
      !Number.isSafeInteger(data.attemptCount) || data.attemptCount < 1 ||
      timestampMillis(data.startedAt) === null ||
      timestampMillis(data.updatedAt) === null ||
      timestampMillis(data.leaseExpiresAt) === null ||
      (data.status === "completed" &&
        (!data.result || typeof data.result !== "object" ||
          Array.isArray(data.result))) ||
      (data.status !== "completed" && data.result !== null) ||
      (data.errorCode !== null && typeof data.errorCode !== "string")) {
    fail("data-loss", "The migration operation ledger is malformed.");
  }
  if (data.inputHash !== identity.inputHash) {
    fail("already-exists", "requestId was reused for another migration input.");
  }
  return data;
}

function normalizeActor(request, actor) {
  if (!isValidOpaqueUid(actor?.uid) || actor.uid !== request?.auth?.uid) {
    fail("permission-denied", "Migration authorization is not bound to Auth.");
  }
  return actor;
}

function createMigrationControl({
  db,
  Timestamp,
  directMigration,
  momentMigration,
  roomCoverMigration,
  authorize = null,
  stepUp = null,
  clock = () => Date.now(),
  limits = DEFAULT_MIGRATION_LIMITS,
  leaseMs = 5 * 60_000,
}) {
  if (
    !db ||
    !Timestamp?.fromMillis ||
    !directMigration ||
    !momentMigration ||
    !roomCoverMigration
  ) {
    throw new TypeError(
      "db, Timestamp and every migration service are required.",
    );
  }
  if (authorize !== null && typeof authorize !== "function") {
    throw new TypeError("authorize must be a function.");
  }
  if (stepUp !== null && typeof stepUp !== "function") {
    throw new TypeError("stepUp must be a function.");
  }
  requireSafeInteger(leaseMs, "leaseMs", { min: 30_000, max: 30 * 60_000 });

  const authorizeRequest = authorize ?? (async (request) => {
    const { requireProtectedOwner } = require("../utils/auth");
    return requireProtectedOwner(request);
  });
  const requireApplyStepUp = stepUp ?? ((actor) => {
    const { requirePrivilegedAuthentication } = require("../utils/auth");
    return requirePrivilegedAuthentication(actor);
  });

  function time() {
    const nowMs = clock();
    if (!Number.isSafeInteger(nowMs) || nowMs < 0) {
      throw new TypeError("clock must return epoch milliseconds.");
    }
    return { nowMs, now: Timestamp.fromMillis(nowMs) };
  }

  async function authorizedActor(request) {
    return normalizeActor(request, await authorizeRequest(request));
  }

  async function execute(request, { actor, kind, scope, input, work }) {
    const requestId = requireRequestId(request.data.requestId);
    const operation = operationIdentity(kind, actor.uid, requestId, input);
    const identity = {
      kind,
      uid: actor.uid,
      requestId,
      inputHash: operation.inputHash,
    };
    const ledgerRef = db.doc(`integrityMigrationOperations/${operation.id}`);
    const rateRef = rateLimitReference(db, `migration.${scope}`, actor.uid);
    const timing = time();
    const config = limits[scope];
    if (!config) throw new TypeError(`Missing migration.${scope} rate limit.`);

    const start = await db.runTransaction(async (transaction) => {
      const [ledger, rate] = await transactionGetAll(
        transaction,
        ledgerRef,
        rateRef,
      );
      const prior = exactMigrationLedger(ledger, identity);
      if (prior?.status === "completed") {
        return { replay: prior.result, attemptCount: prior.attemptCount };
      }
      const priorLease = prior ? timestampMillis(prior.leaseExpiresAt) : null;
      if (prior?.status === "running" && priorLease > timing.nowMs) {
        fail("aborted", "This migration request is already running.");
      }
      consumeRateLimit(transaction, rate, {
        reference: rateRef,
        scope: `migration.${scope}`,
        uid: actor.uid,
        nowMs: timing.nowMs,
        now: timing.now,
        ...config,
      });
      const attemptCount = (prior?.attemptCount ?? 0) + 1;
      if (!Number.isSafeInteger(attemptCount) || attemptCount > 1000) {
        fail("data-loss", "The migration attempt counter is invalid.");
      }
      transaction.set(ledgerRef, {
        schemaVersion: 1,
        kind,
        ownerId: actor.uid,
        requestId,
        inputHash: operation.inputHash,
        status: "running",
        attemptCount,
        startedAt: prior?.startedAt ?? timing.now,
        updatedAt: timing.now,
        leaseExpiresAt: Timestamp.fromMillis(timing.nowMs + leaseMs),
        result: null,
        errorCode: null,
      });
      return { replay: null, attemptCount };
    });
    if (start.replay) return start.replay;

    let result;
    try {
      result = await work();
      if (!result || typeof result !== "object" || Array.isArray(result)) {
        throw new TypeError("A migration handler returned an invalid result.");
      }
    } catch (error) {
      try {
        await db.runTransaction(async (transaction) => {
          const ledger = await transaction.get(ledgerRef);
          const current = exactMigrationLedger(ledger, identity);
          if (current.status !== "running" ||
              current.attemptCount !== start.attemptCount) return;
          const failedAt = time();
          transaction.set(ledgerRef, {
            ...current,
            status: "failed",
            updatedAt: failedAt.now,
            leaseExpiresAt: failedAt.now,
            result: null,
            errorCode: typeof error?.code === "string"
              ? error.code.slice(0, 80)
              : "internal",
          });
        });
      } catch (_) {
        // Preserve the original failure. A malformed/conflicting ledger is
        // investigated through server logs rather than leaked to the caller.
      }
      throw error;
    }

    await db.runTransaction(async (transaction) => {
      const ledger = await transaction.get(ledgerRef);
      const current = exactMigrationLedger(ledger, identity);
      if (current.status !== "running" ||
          current.attemptCount !== start.attemptCount) {
        fail("aborted", "The migration lease changed before completion.");
      }
      const completedAt = time();
      transaction.set(ledgerRef, {
        ...current,
        status: "completed",
        updatedAt: completedAt.now,
        leaseExpiresAt: completedAt.now,
        result,
        errorCode: null,
      });
    });
    return result;
  }

  async function scanDirectMigration(request) {
    const actor = await authorizedActor(request);
    const data = requireExactInput(
      request.data,
      ["cursor", "limit", "maxMessages", "requestId"],
      ["requestId"],
    );
    const limit = data.limit === undefined
      ? 25
      : requireSafeInteger(data.limit, "limit", { min: 1, max: 100 });
    const maxMessages = data.maxMessages === undefined
      ? 400
      : requireSafeInteger(data.maxMessages, "maxMessages", { min: 1, max: 400 });
    const cursor = data.cursor === undefined || data.cursor === null
      ? null
      : requireId(data.cursor, "cursor");
    const input = { cursor, limit, maxMessages };
    return execute(request, {
      kind: "migration.direct.scan",
      actor,
      scope: "scan",
      input,
      work: () => directMigration.scanDirectConversationMigration(input),
    });
  }

  async function migrateDirectConversation(request) {
    const actor = await authorizedActor(request);
    const data = requireExactInput(
      request.data,
      ["conversationId", "dryRun", "maxMessages", "requestId"],
      ["conversationId", "dryRun", "requestId"],
    );
    const input = {
      conversationId: requireId(data.conversationId, "conversationId"),
      dryRun: requireBoolean(data.dryRun, "dryRun"),
      maxMessages: data.maxMessages === undefined
        ? 400
        : requireSafeInteger(
          data.maxMessages,
          "maxMessages",
          { min: 1, max: 400 },
        ),
    };
    // Dry-runs remain available under the owner role gate. Applying a
    // migration can rewrite canonical data, so require the shared five-minute
    // reauthentication/MFA policy before the operation ledger or data changes.
    if (!input.dryRun) await requireApplyStepUp(actor);
    return execute(request, {
      kind: input.dryRun
        ? "migration.direct.dryRun"
        : "migration.direct.apply",
      actor,
      scope: input.dryRun ? "scan" : "apply",
      input,
      work: () => directMigration.migrateDirectConversation(input),
    });
  }

  async function scanMomentMigration(request) {
    const actor = await authorizedActor(request);
    const data = requireExactInput(
      request.data,
      ["cursor", "limit", "maxRelated", "requestId"],
      ["requestId"],
    );
    const limit = data.limit === undefined
      ? 25
      : requireSafeInteger(data.limit, "limit", { min: 1, max: 100 });
    const maxRelated = data.maxRelated === undefined
      ? 200
      : requireSafeInteger(data.maxRelated, "maxRelated", { min: 1, max: 200 });
    const cursor = data.cursor === undefined || data.cursor === null
      ? null
      : requireId(data.cursor, "cursor");
    const input = { cursor, limit, maxRelated };
    return execute(request, {
      kind: "migration.moment.scan",
      actor,
      scope: "scan",
      input,
      work: () => momentMigration.scanMomentMigration(input),
    });
  }

  async function migrateMoment(request) {
    const actor = await authorizedActor(request);
    const data = requireExactInput(
      request.data,
      ["dryRun", "maxRelated", "momentId", "requestId"],
      ["dryRun", "momentId", "requestId"],
    );
    const input = {
      momentId: requireId(data.momentId, "momentId"),
      dryRun: requireBoolean(data.dryRun, "dryRun"),
      maxRelated: data.maxRelated === undefined
        ? 200
        : requireSafeInteger(
          data.maxRelated,
          "maxRelated",
          { min: 1, max: 200 },
        ),
    };
    if (!input.dryRun) await requireApplyStepUp(actor);
    return execute(request, {
      kind: input.dryRun
        ? "migration.moment.dryRun"
        : "migration.moment.apply",
      actor,
      scope: input.dryRun ? "scan" : "apply",
      input,
      work: () => momentMigration.migrateMoment(input),
    });
  }

  async function scanRoomCoverMigration(request) {
    const actor = await authorizedActor(request);
    const data = requireExactInput(
      request.data,
      ["cursor", "limit", "requestId"],
      ["requestId"],
    );
    const input = {
      cursor: data.cursor === undefined || data.cursor === null
        ? null
        : requireId(data.cursor, "cursor"),
      limit: data.limit === undefined
        ? 25
        : requireSafeInteger(data.limit, "limit", { min: 1, max: 100 }),
    };
    return execute(request, {
      kind: "migration.roomCover.scan",
      actor,
      scope: "scan",
      input,
      work: () => roomCoverMigration.scanRoomCoverMigration(input),
    });
  }

  async function migrateRoomCover(request) {
    const actor = await authorizedActor(request);
    const data = requireExactInput(
      request.data,
      ["dryRun", "maxObjects", "requestId", "roomId"],
      ["dryRun", "requestId", "roomId"],
    );
    const input = {
      roomId: requireId(data.roomId, "roomId"),
      dryRun: requireBoolean(data.dryRun, "dryRun"),
      maxObjects: data.maxObjects === undefined
        ? 10_000
        : requireSafeInteger(data.maxObjects, "maxObjects", {
          min: 1,
          max: 10_000,
        }),
    };
    if (!input.dryRun) await requireApplyStepUp(actor);
    return execute(request, {
      kind: input.dryRun
        ? "migration.roomCover.dryRun"
        : "migration.roomCover.apply",
      actor,
      scope: input.dryRun ? "scan" : "apply",
      input,
      work: () => roomCoverMigration.migrateRoomCover(input),
    });
  }

  async function scanRoomCoverObjectInventory(request) {
    const actor = await authorizedActor(request);
    const data = requireExactInput(
      request.data,
      ["dryRun", "maxResults", "pageToken", "requestId"],
      ["dryRun", "requestId"],
    );
    const pageToken = data.pageToken === undefined || data.pageToken === null
      ? null
      : data.pageToken;
    if (
      pageToken !== null &&
      (typeof pageToken !== "string" || pageToken.length > 4096)
    ) {
      fail("invalid-argument", "pageToken is invalid.");
    }
    const input = {
      dryRun: requireBoolean(data.dryRun, "dryRun"),
      maxResults: data.maxResults === undefined
        ? 200
        : requireSafeInteger(data.maxResults, "maxResults", {
          min: 1,
          max: 1000,
        }),
      pageToken,
    };
    if (!input.dryRun) await requireApplyStepUp(actor);
    return execute(request, {
      kind: input.dryRun
        ? "migration.roomCoverInventory.dryRun"
        : "migration.roomCoverInventory.apply",
      actor,
      scope: input.dryRun ? "scan" : "apply",
      input,
      work: () => roomCoverMigration.scanRoomCoverObjectInventory(input),
    });
  }

  return Object.freeze({
    migrateDirectConversation,
    migrateMoment,
    migrateRoomCover,
    scanDirectMigration,
    scanMomentMigration,
    scanRoomCoverMigration,
    scanRoomCoverObjectInventory,
  });
}

module.exports = {
  DEFAULT_MIGRATION_LIMITS,
  createMigrationControl,
};
