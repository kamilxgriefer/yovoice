// Servers V1 registration and durable dispatch (ADR-176).
//
// This is the only module that turns the reviewed, frozen factories under
// functions/servers/* into Cloud Functions endpoints. functions/index.js
// requires it solely inside its `YOVOICE_SERVERS_V1=enabled` block, so the
// production default (the variable absent from functions/.env) keeps every
// module in this directory off the cold-start graph and exports none of the
// names below — the registration shape of `STRIPE_BILLING_EXPORTS` and
// `GIF_PROVIDER` in functions/index.js, for the same reason: the factories
// must be deployable as one reviewed unit, on a separate authorization,
// without changing the export map installed clients depend on today.
//
// What this module does NOT do, on purpose:
//   - it never writes to Firestore itself. Every mutation is a reviewed
//     factory method; the dispatcher only reads `serverControlOutbox/{id}` to
//     decide whether asking a worker is worthwhile, and every worker takes
//     its own lease and revalidates the job inside its own transaction;
//   - it never completes uncertain work. A worker outcome of pending,
//     recoveryRequired or contentCleanupPending is reported, not repaired;
//   - it has no activation writer. `serverActivationState: held` stays held
//     (docs/Servers.md, "Sessions"); activation is a separate reviewed slice.

const { FieldPath, Timestamp, getFirestore } = require("firebase-admin/firestore");
const { randomBytes } = require("node:crypto");
const { logger } = require("firebase-functions/v2");
const { defineSecret, defineString } = require("firebase-functions/params");
const { HttpsError, onCall } = require("firebase-functions/v2/https");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");

const { requireActor, requireId, requireSafeInteger } = require("../integrity/guards");
const { createServerCreationService } = require("./creation");
const { createServerChannelService } = require("./channels");
const { createServerInviteService } = require("./invites");
const { createServerMembershipService } = require("./memberships");
const { createServerSessionService } = require("./sessions");
const { createServerSessionParticipationService } = require("./session_participation");
const { createServerSessionStalenessService } = require("./session_staleness");
const { createServerConvergenceService } = require("./convergence");
const { createServerConvergenceRuntimeService } = require("./convergence_runtime");
const { createServerSessionControlService } = require("./session_control");
const { createServerLiveKitAdapter } = require("./session_livekit");

const REGION = "europe-west1";
const OUTBOX_COLLECTION = "serverControlOutbox";

// The twenty-one V1 callables of docs/Servers.md "Callable contract", in that
// order, each bound to the reviewed factory that implements it. The export
// name and the factory method name are deliberately identical, so a typo in
// this table is a TypeError at deploy discovery, never a NOT_FOUND in a client.
// test/servers_registration_independent_qa.test.js parses the documented
// table and asserts this map lists exactly those names in that order.
const SERVER_CALLABLE_METHODS = Object.freeze({
  createServerV1: "creation",
  updateServerV1: "channels",
  createServerChannelV1: "channels",
  updateServerChannelV1: "channels",
  reorderServerChannelsV1: "channels",
  setServerChannelAccessV1: "channels",
  archiveServerChannelV1: "channels",
  deleteServerChannelV1: "channels",
  joinServerV1: "memberships",
  createServerInviteV1: "invites",
  revokeServerInviteV1: "invites",
  respondToServerInviteV1: "memberships",
  leaveServerV1: "memberships",
  setServerMemberRoleV1: "memberships",
  transferServerOwnershipV1: "memberships",
  startServerChannelSessionV1: "sessions",
  createServerChannelTokenV1: "sessions",
  endServerChannelSessionV1: "sessions",
  setServerSessionParticipantRoleV1: "participation",
  setServerSessionHandV1: "participation",
  setServerSessionMuteV1: "participation",
});

// Only the two callables that reach the media provider bind the LiveKit
// secrets: token issuance signs a JWT, and a session end eagerly runs one
// revocation page (sessions.js). `startServerChannelSessionV1` validates the
// public LIVEKIT_URL only, and the three participation callables
// (session_participation.js) never touch the provider themselves: a role or
// mute change revokes through the outbox worker, which binds the secrets
// below. Binding a secret to a function that never reads it is what
// functions/media/gif/catalog.js deliberately avoids.
const SECRET_BOUND_CALLABLES = Object.freeze([
  "createServerChannelTokenV1",
  "endServerChannelSessionV1",
]);

const DISPATCHER_EXPORTS = Object.freeze([
  "onServerControlOutboxCreated",
  "processPendingServerControlOutboxSchedule",
]);

// The stale-generation bound (session_staleness.js, ADR-180): not a
// dispatcher, because it does not read the outbox — it WRITES to it, through
// the same reviewed end writer every authorized lifecycle operation uses,
// and the dispatcher above then drains what it staged.
const SWEEP_EXPORTS = Object.freeze([
  "sweepStaleServerChannelSessionsSchedule",
]);

const SERVERS_V1_EXPORT_NAMES = Object.freeze([
  ...Object.keys(SERVER_CALLABLE_METHODS),
  ...DISPATCHER_EXPORTS,
  ...SWEEP_EXPORTS,
]);

// Outbox job kinds and the reviewed worker that owns each of them. The three
// workers validate their own job shape under their own transaction; this
// table only decides which of them is asked.
const CONVERGENCE_KINDS = Object.freeze([
  "memberJoined", "memberLeft", "memberRoleChanged", "sessionParticipantChanged", "channelAccess",
  "channelArchive", "channelDelete", "ownershipTransferred",
]);
const OUTBOX_KINDS = Object.freeze([...CONVERGENCE_KINDS, "sessionEnd", "serverMetadata"]);

// A failure the platform may redeliver: the moment was wrong, not the job.
// Everything else — a structured refusal describing the job, a programming
// fault, a malformed document — returns normally and is retried only by the
// schedule, once per sweep, so a permanently broken job costs one worker call
// per sweep and one error line, never an Eventarc retry storm.
const TRANSIENT_CODES = Object.freeze(new Set([
  "aborted", "cancelled", "deadline-exceeded", "resource-exhausted", "unavailable", "unknown",
]));
// The same classes as gRPC status numbers, which is how the Firestore SDK
// reports an aborted or unavailable transaction.
const TRANSIENT_GRPC_CODES = Object.freeze(new Set([1, 2, 4, 8, 10, 14]));

// Fields whose change between two reads means a worker made durable progress
// on a job. Identical fingerprints after a worker call mean the job was busy,
// settled without writing, or is waiting on something the dispatcher must
// not complete on its own.
const PROGRESS_FIELDS = Object.freeze([
  "status", "grantStatus", "grantCursor", "rtcStatus", "rtcTargetIndex",
  "rtcRecipientCursor", "cursor", "lastErrorCode", "retryAfterMillis",
]);

const DEFAULT_DISPATCH_LIMITS = Object.freeze({
  // Pages one Firestore create event may drive before yielding to the
  // schedule. Each convergence page is at most 20 recipients (four concurrent
  // provider calls); each session-end page is at most 20 SDK requests.
  triggerMaxPages: 6,
  scheduleMaxPagesPerJob: 4,
  // Pending jobs one schedule run may visit, read in pages of this size.
  scheduleScanLimit: 100,
  scheduleScanPageSize: 25,
  // No new page starts after this much wall clock, so a loop ends with a
  // written summary line and a released lease instead of a platform kill at
  // the 300 s worker timeout (a page's provider work is itself bounded).
  timeBudgetMs: 180_000,
});

// Redeclared here exactly as calls/direct_calls.js redeclares the token.js
// parameters: the params registry keeps one declaration per name, and the
// secrets are read inside a request, never at module load.
const livekitApiKey = defineSecret("LIVEKIT_API_KEY");
const livekitApiSecret = defineSecret("LIVEKIT_API_SECRET");
const livekitUrl = defineString("LIVEKIT_URL");
const LIVEKIT_SECRET_PARAMS = Object.freeze([livekitApiKey, livekitApiSecret]);

function defaultRegistrars() {
  return { onCall, onDocumentCreated, onSchedule };
}

/**
 * The reviewed factories over one Firestore handle and one revocation-capable
 * LiveKit adapter. No I/O, no SDK load and no secret read happens here: the
 * adapter reads its accessors on first use, inside a request that bound them.
 */
function createServersV1Runtime({
  db = null,
  Timestamp: TimestampClass = Timestamp,
  FieldPath: FieldPathClass = FieldPath,
  clock = Date.now,
  livekit = null,
} = {}) {
  if (typeof clock !== "function") throw new TypeError("clock must be a function.");
  if (typeof FieldPathClass?.documentId !== "function") throw new TypeError("FieldPath is required.");
  const database = db ?? getFirestore();
  const adapter = livekit ?? createServerLiveKitAdapter({
    apiKey: () => livekitApiKey.value(),
    apiSecret: () => livekitApiSecret.value(),
    serverUrl: () => livekitUrl.value(),
    clock,
  });
  const dependencies = { db: database, Timestamp: TimestampClass, livekit: adapter, clock };
  return Object.freeze({
    db: database,
    FieldPath: FieldPathClass,
    clock,
    creation: createServerCreationService(dependencies),
    channels: createServerChannelService(dependencies),
    invites: createServerInviteService(dependencies),
    memberships: createServerMembershipService(dependencies),
    sessions: createServerSessionService(dependencies),
    participation: createServerSessionParticipationService(dependencies),
    projection: createServerConvergenceService(dependencies),
    convergence: createServerConvergenceRuntimeService(dependencies),
    sessionControl: createServerSessionControlService(dependencies),
    staleness: createServerSessionStalenessService(dependencies),
  });
}

/**
 * Exactly the Stage B binding (integrity/stage_b_handlers.js): keep the Auth
 * uid and token, discard every other transport property, and hand the payload
 * through unchanged. Each factory validates its exact input allowlist and
 * derives every identity from `auth.uid`, so a client-supplied ownerId,
 * memberId-as-self or forged header cannot cross this boundary.
 */
function authBoundRequest(request) {
  const auth = requireActor(request, { verified: false });
  return {
    auth: { uid: auth.uid, token: { ...(auth.token ?? {}) } },
    data: request.data,
  };
}

function safeErrorCode(error) {
  const code = error?.code;
  if (typeof code === "string" && /^[a-z0-9-]{1,64}$/u.test(code)) return code;
  if (Number.isSafeInteger(code)) return String(code);
  return "internal";
}

function callableHandler(name, method, log) {
  return async (request) => {
    const bound = authBoundRequest(request);
    try {
      return await method(bound);
    } catch (error) {
      // Factory failures are already structured HttpsErrors (integrity/guards
      // `fail`) and reach the client unchanged. Anything else is an
      // infrastructure or programming fault: log its code and class, never
      // its message (which may quote document paths), and answer `internal`.
      if (error instanceof HttpsError) throw error;
      log.error("servers.callable_failed", {
        callable: name, code: safeErrorCode(error), name: error?.name ?? "Error",
      });
      throw new HttpsError("internal", "The server operation could not be completed.");
    }
  };
}

/**
 * Read-only classification of an outbox document. `eligible` means a worker
 * invocation is worthwhile now; every other reason is a state the dispatcher
 * must leave alone: another lease holder, a retry hint that has not elapsed,
 * a finished job, or a shape no reviewed worker accepts.
 */
function describeOutboxJob(data, nowMs) {
  if (!data || typeof data !== "object" || data.schemaVersion !== 1 || !OUTBOX_KINDS.includes(data.kind)) {
    return { route: null, reason: "unsupported" };
  }
  if (data.status === "completed") return { route: null, reason: "completed" };
  if (data.status !== "pending") return { route: null, reason: "unsupported" };
  if (data.kind === "sessionEnd") {
    const leased = typeof data.leaseId === "string" && data.leaseId !== "" &&
      Number.isSafeInteger(data.leaseExpiresAtMillis) && data.leaseExpiresAtMillis > nowMs;
    return { route: "sessionEnd", reason: leased ? "leased" : "eligible" };
  }
  if (data.kind === "serverMetadata") return { route: "projection", reason: "eligible" };
  if (data.convergenceVersion !== 1) return { route: null, reason: "unsupported" };
  if (typeof data.bridgeLeaseId === "string" && data.bridgeLeaseId !== "" &&
      Number.isSafeInteger(data.bridgeLeaseExpiresAtMillis) && data.bridgeLeaseExpiresAtMillis > nowMs) {
    return { route: "convergence", reason: "leased" };
  }
  if (Number.isSafeInteger(data.retryAfterMillis) && data.retryAfterMillis > nowMs) {
    return { route: "convergence", reason: "backoff" };
  }
  return { route: "convergence", reason: "eligible" };
}

function progressFingerprint(data) {
  return JSON.stringify([
    ...PROGRESS_FIELDS.map((field) => data[field] ?? null),
    Object.hasOwn(data, "terminalDelete"),
  ]);
}

/**
 * Whether a worker's page left work behind, as a three-state answer:
 * `true` (more to do), `false` (this job is finished) and `null` (the result
 * carries no boolean signal at all). The projection worker reports completion
 * positively (`propagationComplete`); the convergence and session-end workers
 * report remaining work positively (`cleanupPending`).
 *
 * Only an explicit `false` may complete a job. A result that never stated its
 * page — a renamed field, a partial stub, a worker that returned nothing —
 * is `null` and is refused, never read as completion: inferring "done" from a
 * missing field is exactly the uncertain work this dispatcher must not settle.
 */
function workRemains(route, result) {
  const field = route === "projection" ? "propagationComplete" : "cleanupPending";
  const value = result?.[field];
  if (typeof value !== "boolean") return null;
  return field === "propagationComplete" ? !value : value;
}

function isTransientFailure(error) {
  if (error instanceof HttpsError) return TRANSIENT_CODES.has(error.code);
  return Number.isSafeInteger(error?.code) && TRANSIENT_GRPC_CODES.has(error.code);
}

/**
 * The trigger and schedule handlers. Both drive the same bounded loop: read
 * the job, stop unless it is eligible, ask its reviewed worker for one page,
 * then continue only while the worker reports remaining work AND the job
 * document visibly advanced AND it is still eligible AND the page and time
 * budgets allow. A page that ends busy, backed off, recovery-required or
 * content-cleanup-pending stops the loop with that outcome; the schedule
 * revisits the job later under the same rules. Two outcomes exist so that a
 * page is never reported as work it did not do: `busy`, when another lease
 * holder settled the job during this invocation, and `rejected` with
 * `invalid-worker-result`, when a worker returned no work-remaining boolean.
 */
function createServersV1Dispatcher({
  runtime,
  log = logger,
  random = () => randomBytes(32).toString("hex"),
  ...limits
} = {}) {
  if (!runtime?.db?.collection || typeof runtime?.FieldPath?.documentId !== "function" ||
      typeof runtime?.clock !== "function" ||
      typeof runtime?.convergence?.processServerConvergencePage !== "function" ||
      typeof runtime?.sessionControl?.processServerSessionEndPage !== "function" ||
      typeof runtime?.projection?.processServerControlOutboxPage !== "function") {
    throw new TypeError("A Servers V1 runtime with its three reviewed workers is required.");
  }
  if (typeof random !== "function") throw new TypeError("random must be a function.");
  const bounds = { ...DEFAULT_DISPATCH_LIMITS, ...limits };
  requireSafeInteger(bounds.triggerMaxPages, "triggerMaxPages", { min: 1, max: 50 });
  requireSafeInteger(bounds.scheduleMaxPagesPerJob, "scheduleMaxPagesPerJob", { min: 1, max: 50 });
  requireSafeInteger(bounds.scheduleScanLimit, "scheduleScanLimit", { min: 1, max: 1000 });
  requireSafeInteger(bounds.scheduleScanPageSize, "scheduleScanPageSize", { min: 1, max: 100 });
  requireSafeInteger(bounds.timeBudgetMs, "timeBudgetMs", { min: 1_000, max: 290_000 });
  const { db, FieldPath: FieldPathClass, clock } = runtime;
  const outbox = db.collection(OUTBOX_COLLECTION);
  const workers = Object.freeze({
    convergence: (operationId) => runtime.convergence.processServerConvergencePage({ operationId }),
    sessionEnd: (operationId) => runtime.sessionControl.processServerSessionEndPage({ operationId }),
    projection: (operationId) => runtime.projection.processServerControlOutboxPage({ operationId }),
  });

  async function dispatchOutboxJob(operationId, { source, maxPages, deadlineMs }) {
    const reference = outbox.doc(operationId);
    const report = {
      source, operationId, kind: null, outcome: null, pages: 0, processed: 0, code: null, error: null,
    };
    let previous = null;
    while (report.outcome === null) {
      const snapshot = await reference.get();
      if (!snapshot.exists) { report.outcome = "missing"; break; }
      const data = snapshot.data();
      if (OUTBOX_KINDS.includes(data?.kind)) report.kind = data.kind;
      const described = describeOutboxJob(data, clock());
      if (described.reason !== "eligible") {
        // A job that another lease holder settled between this invocation's
        // page and this read was not completed by this invocation. Crediting
        // the race with `completed` would report work this dispatcher never
        // did (and, for a session end, hide a lost lease behind a success
        // line), so the race is reported as `busy` — a deferred outcome that
        // tallies with the other deferrals and leaves the document untouched.
        report.outcome = described.reason === "completed" && report.pages > 0
          ? "busy"
          : described.reason;
        break;
      }
      const fingerprint = progressFingerprint(data);
      if (previous !== null && previous === fingerprint) { report.outcome = "stalled"; break; }
      if (report.pages >= maxPages || clock() >= deadlineMs) { report.outcome = "exhausted"; break; }
      let result;
      try {
        result = await workers[described.route](operationId);
      } catch (error) {
        report.outcome = isTransientFailure(error) ? "failed" : "rejected";
        report.code = safeErrorCode(error);
        report.error = error;
        break;
      }
      report.pages += 1;
      if (Number.isSafeInteger(result?.processed) && result.processed > 0) report.processed += result.processed;
      previous = fingerprint;
      const remaining = workRemains(described.route, result);
      if (remaining === null) {
        // Every reviewed worker states its page. A result without the boolean
        // is a contract break, not a completion: refuse the job with an error
        // line so the schedule revisits it and the break is visible.
        report.outcome = "rejected";
        report.code = "invalid-worker-result";
        break;
      }
      if (remaining === false) { report.outcome = "completed"; break; }
      if (result?.recoveryRequired === true) { report.outcome = "recoveryRequired"; break; }
      if (result?.contentCleanupPending === true && result?.rtcCleanupPending === false) {
        report.outcome = "contentCleanupPending";
        break;
      }
    }
    return report;
  }

  function emit(report) {
    const line = {
      source: report.source, operationId: report.operationId, kind: report.kind,
      outcome: report.outcome, pages: report.pages, processed: report.processed, code: report.code,
    };
    if (report.outcome === "failed" || report.outcome === "rejected") log.error("servers.dispatch", line);
    else log.info("servers.dispatch", line);
    return line;
  }

  async function onServerControlOutboxCreated(event) {
    let operationId;
    try {
      operationId = requireId(event?.params?.operationId, "operationId");
    } catch {
      // A document id outside the operation-id grammar was not written by a
      // reviewed factory. Redelivering the event cannot change that.
      const line = { source: "trigger", operationId: null, kind: null, outcome: "unsupported", pages: 0, processed: 0, code: null };
      log.warn("servers.dispatch", line);
      return line;
    }
    // The event snapshot is not consulted: by delivery time the reviewed
    // worker may already hold a lease or have finished, so the loop reads
    // the live document instead.
    const report = await dispatchOutboxJob(operationId, {
      source: "trigger", maxPages: bounds.triggerMaxPages, deadlineMs: clock() + bounds.timeBudgetMs,
    });
    const line = emit(report);
    // Only a transient failure rethrows, so the event is redelivered with
    // backoff (`retry: true`). Rejections and every deferred outcome return
    // normally and wait for the schedule. Either way the document is exactly
    // what the reviewed worker left behind.
    if (report.outcome === "failed") throw report.error;
    return line;
  }

  function tally(counts, outcome) {
    if (outcome === "completed") counts.completed += 1;
    else if (outcome === "rejected") counts.rejected += 1;
    else if (outcome === "failed") counts.failed += 1;
    else if (outcome === "unsupported" || outcome === "missing") counts.unsupported += 1;
    else counts.deferred += 1;
  }

  async function processPendingServerControlOutbox() {
    const deadlineMs = clock() + bounds.timeBudgetMs;
    const counts = {
      scanned: 0, completed: 0, deferred: 0, rejected: 0, failed: 0, unsupported: 0, hasMore: false,
    };
    // Operation ids are uniformly distributed SHA-256 hex digests, so a random
    // start cursor with one wrap-around visits every pending job with equal
    // probability across runs. A permanently deferred prefix (recovery
    // required, content cleanup pending, a rejected job awaiting
    // reconciliation) therefore cannot starve the rest of the queue, and no
    // composite index or persisted cursor is needed: an equality filter
    // ordered by document id is served by the single-field index alone.
    const start = String(random());
    if (!/^[0-9a-f]{64}$/u.test(start)) throw new TypeError("random must return 64 hex characters.");
    let remaining = bounds.scheduleScanLimit;
    let cursor = start;
    let wrapped = false;
    scan: while (remaining > 0) {
      let query = outbox.where("status", "==", "pending").orderBy(FieldPathClass.documentId());
      if (cursor !== null) query = query.startAfter(cursor);
      const limit = Math.min(bounds.scheduleScanPageSize, remaining);
      const page = await query.limit(limit).get();
      for (const document of page.docs) {
        // After the wrap-around, ids above the start were visited already.
        if (wrapped && document.id > start) break scan;
        if (clock() >= deadlineMs) { counts.hasMore = true; break scan; }
        counts.scanned += 1;
        remaining -= 1;
        const report = await dispatchOutboxJob(document.id, {
          source: "schedule", maxPages: bounds.scheduleMaxPagesPerJob, deadlineMs,
        });
        emit(report);
        tally(counts, report.outcome);
      }
      if (page.size < limit) {
        if (wrapped) break;
        wrapped = true;
        cursor = null;
      } else {
        cursor = page.docs.at(-1).id;
        if (remaining === 0) counts.hasMore = true;
      }
    }
    log.info("servers.dispatch_sweep", counts);
    return counts;
  }

  return Object.freeze({
    describeOutboxJob,
    dispatchOutboxJob,
    onServerControlOutboxCreated,
    processPendingServerControlOutbox,
  });
}

/**
 * Builds the complete Servers V1 export map: the twenty-one callables plus the
 * outbox trigger, its bounded retry schedule and the stale-generation sweep.
 * functions/index.js merges the result into `exports` only behind
 * `YOVOICE_SERVERS_V1=enabled`.
 */
function createServersV1Functions({
  runtime = null,
  registrars = defaultRegistrars(),
  enforceAppCheck = false,
  log = logger,
  dispatch = {},
} = {}) {
  for (const name of ["onCall", "onDocumentCreated", "onSchedule"]) {
    if (typeof registrars?.[name] !== "function") {
      throw new TypeError(`Missing Cloud Functions registrar: ${name}.`);
    }
  }
  const resolved = runtime ?? createServersV1Runtime();
  if (typeof resolved?.staleness?.stageStaleServerChannelSessions !== "function") {
    throw new TypeError("Missing Servers V1 worker staleness.stageStaleServerChannelSessions.");
  }
  const callableOptions = {
    region: REGION,
    memory: "256MiB",
    timeoutSeconds: 60,
    maxInstances: 50,
    // Held feature: no always-on instance. test/cold_start_module_graph.test.js
    // pins the complete warm set and this surface must not join it.
    minInstances: 0,
    // Same App Check convention as Stage B and Reels: enforcement and
    // limited-use token consumption flip together, per rollout switch.
    enforceAppCheck: enforceAppCheck === true,
    consumeAppCheckToken: enforceAppCheck === true,
  };
  // One eager teardown page (at most 20 provider requests, four at a time,
  // four-second request timeouts) must fit inside the deadline.
  const securedOptions = { ...callableOptions, timeoutSeconds: 120, secrets: [...LIVEKIT_SECRET_PARAMS] };
  const exportsMap = {};
  for (const [name, serviceName] of Object.entries(SERVER_CALLABLE_METHODS)) {
    const method = resolved?.[serviceName]?.[name];
    if (typeof method !== "function") {
      throw new TypeError(`Missing Servers V1 method ${serviceName}.${name}.`);
    }
    const handler = callableHandler(name, method, log);
    exportsMap[name] = registrars.onCall(
      SECRET_BOUND_CALLABLES.includes(name) ? { ...securedOptions } : { ...callableOptions },
      handler,
    );
  }

  const dispatcher = createServersV1Dispatcher({ runtime: resolved, log, ...dispatch });
  const workerOptions = {
    region: REGION,
    memory: "512MiB",
    timeoutSeconds: 300,
    secrets: [...LIVEKIT_SECRET_PARAMS],
  };
  exportsMap.onServerControlOutboxCreated = registrars.onDocumentCreated(
    {
      ...workerOptions,
      document: `${OUTBOX_COLLECTION}/{operationId}`,
      // Every job is lease-guarded, so concurrent instances are safe; the
      // ceiling bounds provider concurrency, not correctness.
      maxInstances: 10,
      retry: true,
    },
    dispatcher.onServerControlOutboxCreated,
  );
  exportsMap.processPendingServerControlOutboxSchedule = registrars.onSchedule(
    { ...workerOptions, schedule: "every 5 minutes", timeZone: "Etc/UTC", maxInstances: 1 },
    dispatcher.processPendingServerControlOutbox,
  );
  // Same cadence as the legacy sweepStrandedLiveRoomsSchedule: a stale
  // generation stays visibly LIVE for at most one grace period plus one
  // cadence. maxInstances: 1 keeps two runs from racing onto one generation
  // (the staging transaction makes that correct anyway, but not free).
  exportsMap.sweepStaleServerChannelSessionsSchedule = registrars.onSchedule(
    { ...workerOptions, schedule: "every 5 minutes", timeZone: "Etc/UTC", maxInstances: 1 },
    async () => {
      const outcome = await resolved.staleness.stageStaleServerChannelSessions();
      const line = { ...outcome, staged: outcome.staged.length };
      if (outcome.truncated || outcome.providerUnavailable > 0) log.warn("servers.stale_session_sweep", line);
      else log.info("servers.stale_session_sweep", line);
      return line;
    },
  );
  return Object.freeze(exportsMap);
}

module.exports = {
  CONVERGENCE_KINDS,
  DEFAULT_DISPATCH_LIMITS,
  DISPATCHER_EXPORTS,
  OUTBOX_COLLECTION,
  OUTBOX_KINDS,
  REGION,
  SECRET_BOUND_CALLABLES,
  SERVER_CALLABLE_METHODS,
  SERVERS_V1_EXPORT_NAMES,
  SWEEP_EXPORTS,
  authBoundRequest,
  createServersV1Dispatcher,
  createServersV1Functions,
  createServersV1Runtime,
  describeOutboxJob,
  isTransientFailure,
};
