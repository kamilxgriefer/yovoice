// Self-service account deletion — ADR-206.
//
// ONE PIPELINE, TWO ENTRY POINTS. The callable below marks intent and returns;
// a leased, staged worker performs the teardown in bounded pages and ends with
// `admin.auth().deleteUser(uid)`. The existing Auth `onDelete` trigger
// (functions/profile/public_profiles.js) is the pipeline's LAST step and its
// SECOND entry point: with a row it deletes `users/{uid}` outright, and without
// one — a Firebase console or staff deletion — it enqueues a row so the same
// teardown runs. That is why the "the trigger keeps the e-mail address forever"
// defect closes on EVERY deletion path, not only on the new button.
//
// The lease/backoff/deadLetter semantics are copied field-for-field from
// `reelCleanupOutbox` (functions/reels/service.js) and the trigger-plus-
// schedule wiring from `contentCleanupOutbox`
// (functions/integrity/stage_b_functions.js). No new architecture is
// introduced; this is a third instance of a shape the repository already runs.

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { logger } = require("firebase-functions/v2");
const { getAuth } = require("firebase-admin/auth");
const {
  FieldPath,
  FieldValue,
  Timestamp,
} = require("firebase-admin/firestore");

const { db } = require("../utils/firestore");
const {
  requireAuthentication,
  requireRecentPrivilegedAuthentication,
} = require("../utils/auth");
const {
  consumeRateLimit,
  rateLimitReference,
} = require("../integrity/guards");
const { isValidOpaqueUid } = require("../achievements/identity");
const { deleteTrustedPrefix } = require("../media/cleanup");
const { createAccountDeletionStages } = require("./stages");
const {
  CONFIG_DOCUMENT,
  LEASE_MS,
  MAX_ABANDONED_ATTEMPTS,
  MAX_ATTEMPTS,
  OUTBOX_COLLECTION,
  STAGE_ORDER,
  accountDeletionMark,
  backoffMs,
  initialOutboxRow,
  isTerminalStatus,
  mayDeleteAuthUser,
  outboxIdForUid,
  stageIndex,
} = require("./outbox");
const { mintReporterTombstone } = require("./retention");

const REGION = "europe-west1";
const RATE_LIMIT_SCOPE = "deleteAccountSelfV1";
const RATE_LIMIT_MAX_EVENTS = 5;
const RATE_LIMIT_WINDOW_MS = 60 * 60 * 1000;

// One leased attempt walks as far as it can inside these two budgets and then
// hands the row back. Both are well inside the 540s function timeout, so an
// attempt always gets to persist its cursor rather than being killed mid-page.
//
// MAX_ATTEMPT_MILLIS must stay COMFORTABLY UNDER `LEASE_MS` (outbox.js, 300s).
// The loop admits one more stage step whenever the elapsed time is still under
// the budget, so with the two equal the final step routinely STARTED at the
// lease boundary and finished after it — long enough for the 2-minute sweep to
// re-claim the row legitimately while the first worker was still writing. The
// 60s of headroom is one stage step's worth of slack; raising this without
// raising LEASE_MS re-opens two workers on one deletion.
const MAX_STEPS_PER_ATTEMPT = 500;
const MAX_ATTEMPT_MILLIS = 240 * 1000;
const SWEEP_PAGE = 20;

// @google-cloud/storage must not enter the cold-start module graph
// (test/cold_start_module_graph.test.js pins it at zero), so the bucket is
// resolved on first object access, exactly like the media runtimes. The shared
// `createLazyBucket` wrapper is not used here because it deliberately forwards
// only name/file/getFiles, and the prefix sweep needs `deleteFiles`; widening
// that shared surface for one caller would change a contract several adapters
// depend on.
function productionPrefixBucket() {
  const { getStorage } = require("firebase-admin/storage");
  return getStorage().bucket();
}

function defaultStages() {
  return createAccountDeletionStages({
    db,
    FieldValue,
    FieldPath,
    authAdmin: getAuth(),
    resolveBucket: productionPrefixBucket,
    deleteTrustedPrefix,
    logger,
  });
}

let productionStages = null;
function sharedStages() {
  productionStages ??= defaultStages();
  return productionStages;
}

function outboxReference(database, outboxId) {
  return database.collection(OUTBOX_COLLECTION).doc(outboxId);
}

function timestampMillis(value) {
  if (!value) return null;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  return null;
}

/**
 * The server-owned kill switch, same shape as `appConfig/gif`.
 *
 * FAIL-CLOSED ON PURPOSE: a missing document means DISABLED. The rollout order
 * in docs/DEPLOYMENT.md deploys the worker and the trigger first, exercises one
 * real account, and only then writes `{ enabled: true }`. A button that calls a
 * half-deployed pipeline is the exact failure ADR-082 records.
 */
async function accountDeletionEnabled(database = db) {
  const snapshot = await database
    .collection(CONFIG_DOCUMENT.collection)
    .doc(CONFIG_DOCUMENT.id)
    .get();
  return snapshot.exists && snapshot.data()?.enabled === true;
}

/**
 * Marks intent and enqueues the teardown. One transaction, no fanout.
 *
 * REPEAT-CALL CONTRACT, from `deleteClubSelf`: a second call on an account
 * already marked returns the existing state and does NOT reset the stage or the
 * cursor. Refusing would wedge an account whose first attempt died after the
 * mark.
 */
async function executeDeleteAccountSelf(
  request,
  {
    database = db,
    now = () => FieldValue.serverTimestamp(),
    nowMs = () => Date.now(),
    enabled = null,
    tombstone = mintReporterTombstone,
  } = {},
) {
  const authentication = requireAuthentication(request);
  // The server half of the client's provider re-authentication. A stolen
  // long-lived session cannot delete an account: `auth_time` must be inside
  // PRIVILEGED_AUTH_MAX_AGE_SECONDS, which only a real re-sign-in refreshes.
  requireRecentPrivilegedAuthentication(authentication);

  const uid = authentication.uid;
  if (!isValidOpaqueUid(uid)) {
    throw new HttpsError("invalid-argument", "A valid account is required.");
  }

  const switchState = enabled === null
    ? await accountDeletionEnabled(database)
    : enabled;
  if (switchState !== true) {
    throw new HttpsError(
      "failed-precondition",
      "Account deletion is temporarily unavailable.",
      { reason: "account-deletion-disabled" },
    );
  }

  const outboxId = outboxIdForUid(uid);
  const userReference = database.collection("users").doc(uid);
  const reference = outboxReference(database, outboxId);
  const rateReference = rateLimitReference(database, RATE_LIMIT_SCOPE, uid);
  const reporterTombstone = tombstone();

  // The budget is a SEPARATE, INDEPENDENT commit, exactly like
  // `consumeClubActionAttempt` in functions/clubs/deletion.js — and for a
  // reason a test caught: consuming it inside the main transaction means every
  // refusal rolls the consumption back, so a missing or foreign account costs
  // an attacker nothing and the budget stops bounding anything.
  await database.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(rateReference);
    consumeRateLimit(transaction, snapshot, {
      reference: rateReference,
      scope: RATE_LIMIT_SCOPE,
      uid,
      nowMs: nowMs(),
      now: now(),
      maxEvents: RATE_LIMIT_MAX_EVENTS,
      windowMs: RATE_LIMIT_WINDOW_MS,
    });
  });

  return database.runTransaction(async (transaction) => {
    const [userSnapshot, outboxSnapshot] = await Promise.all([
      transaction.get(userReference),
      transaction.get(reference),
    ]);
    const timestamp = now();

    if (!userSnapshot.exists) {
      throw new HttpsError("not-found", "This account no longer exists.");
    }

    if (outboxSnapshot.exists) {
      const existing = outboxSnapshot.data() ?? {};
      return {
        state: existing.status === "completed" ? "completed" : "pending",
        stage: typeof existing.stage === "string" ? existing.stage : null,
        requestedAtMillis: timestampMillis(existing.requestedAt),
        alreadyRequested: true,
      };
    }

    // `disabled: true` reuses the DEPLOYED ban authority (accountIsActive() in
    // firestore.rules) instead of inventing a second account-status mechanism.
    // The instant it lands the account can no longer post, message, follow,
    // upload or view-log, so the sweep walks a stable snapshot — and the
    // existing privacy-projection trigger removes the user from other people's
    // screens straight away, which is what pressing the button should look
    // like. `accountDeletion` and `disabled` are both absent from the owner
    // self-write allowlist, so neither needs a new rule to be server-owned.
    transaction.set(
      userReference,
      {
        accountDeletion: accountDeletionMark({ source: "app", now: timestamp }),
        disabled: true,
        isOnline: false,
      },
      { merge: true },
    );
    transaction.create(reference, initialOutboxRow({
      uid,
      source: "app",
      reporterTombstone,
      now: timestamp,
    }));

    return {
      state: "pending",
      stage: STAGE_ORDER[0],
      requestedAtMillis: null,
      alreadyRequested: false,
    };
  });
}

/**
 * The trigger's second entry point.
 *
 * An Auth user deleted out of band (Firebase console, staff tooling, an SDK
 * `user.delete()` elsewhere) has no row. Creating one here is what shrinks the
 * retention window for those paths from "forever" to "one sweep".
 */
async function enqueueAccountDeletionOutbox(
  uid,
  {
    database = db,
    source = "authTrigger",
    now = () => FieldValue.serverTimestamp(),
    tombstone = mintReporterTombstone,
  } = {},
) {
  if (!isValidOpaqueUid(uid)) return { enqueued: false, reason: "invalidUid" };
  const outboxId = outboxIdForUid(uid);
  const reference = outboxReference(database, outboxId);
  return database.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    if (snapshot.exists) {
      return { enqueued: false, reason: "exists", outboxId };
    }
    transaction.create(reference, initialOutboxRow({
      uid,
      source,
      reporterTombstone: tombstone(),
      now: now(),
    }));
    return { enqueued: true, outboxId };
  });
}

// ------------------------------------------------------------------ leasing

function leaseToken(outboxId, attemptCount, millis) {
  const crypto = require("node:crypto");
  return crypto
    .createHash("sha256")
    .update(`account-deletion-lease\0${outboxId}\0${attemptCount}\0${millis}`)
    .digest("hex")
    .slice(0, 32);
}

async function claimOutboxRow(
  reference,
  outboxId,
  {
    database = db,
    nowMs = () => Date.now(),
    maxAbandoned = MAX_ABANDONED_ATTEMPTS,
  } = {},
) {
  return database.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    if (!snapshot.exists) {
      return { claimed: false, terminal: true, reason: "missing" };
    }
    const row = snapshot.data() ?? {};
    if (isTerminalStatus(row.status)) {
      return { claimed: false, terminal: true, reason: row.status };
    }
    const millis = nowMs();
    if (!isValidOpaqueUid(row.uid) || stageIndex(row.stage) < 0) {
      transaction.update(reference, {
        status: "deadLetter",
        lastErrorCode: "data-loss",
        leaseToken: null,
        leaseUntil: null,
        nextAttemptAt: null,
        deadLetterAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return { claimed: false, terminal: true, reason: "data-loss" };
    }
    const nextAttemptAtMs = timestampMillis(row.nextAttemptAt);
    if (row.status === "pending" &&
        nextAttemptAtMs !== null &&
        nextAttemptAtMs > millis) {
      return { claimed: false, terminal: false, reason: "deferred" };
    }
    const leaseUntilMs = timestampMillis(row.leaseUntil);
    if (row.status === "processing" &&
        leaseUntilMs !== null &&
        leaseUntilMs > millis) {
      return { claimed: false, terminal: false, reason: "leased" };
    }
    // Reaching here while the row is STILL `processing` means the previous
    // holder never released, completed or recorded a failure — it died. That
    // is the one failure mode neither `failureCount` nor any backoff can see,
    // because nothing survived to write them. Count it, and bound it: a row
    // that kills eight consecutive workers is a poison pill, and re-claiming
    // it a ninth time only feeds the loop.
    const priorAbandoned = Number.isSafeInteger(row.abandonedCount) &&
      row.abandonedCount >= 0 ? row.abandonedCount : 0;
    const abandoned = row.status === "processing";
    const abandonedCount = abandoned ? priorAbandoned + 1 : priorAbandoned;
    if (abandoned && abandonedCount >= maxAbandoned) {
      transaction.update(reference, {
        status: "deadLetter",
        abandonedCount,
        lastErrorCode: "lease-abandoned",
        leaseToken: null,
        leaseUntil: null,
        nextAttemptAt: null,
        deadLetterAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return {
        claimed: false,
        terminal: true,
        reason: "lease-abandoned",
        uid: row.uid,
        abandonedCount,
      };
    }
    const attemptCount = (Number.isSafeInteger(row.attemptCount) &&
      row.attemptCount >= 0 ? row.attemptCount : 0) + 1;
    const token = leaseToken(outboxId, attemptCount, millis);
    transaction.update(reference, {
      status: "processing",
      attemptCount,
      abandonedCount,
      leaseToken: token,
      leaseUntil: Timestamp.fromMillis(millis + LEASE_MS),
      lastErrorCode: null,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return {
      claimed: true,
      terminal: false,
      leaseToken: token,
      row: { ...row, attemptCount, abandonedCount },
    };
  });
}

async function releaseOutboxRow(
  reference,
  token,
  { stage, cursor, database = db, nowMs = () => Date.now() },
) {
  return database.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    if (!snapshot.exists) return false;
    const row = snapshot.data() ?? {};
    if (row.status !== "processing" || row.leaseToken !== token) return false;
    transaction.update(reference, {
      status: "pending",
      stage,
      cursor: cursor ?? null,
      // Progress is not failure: an attempt that ran out of budget comes
      // straight back rather than serving the failure backoff, and it spends
      // none of the retry budget — reaching here at all means the pipeline
      // moved, so the next transient error starts from a full eight.
      failureCount: 0,
      // The worker lived long enough to hand the row back, so this lease was
      // not abandoned and the ones before it are no longer consecutive.
      abandonedCount: 0,
      nextAttemptAt: Timestamp.fromMillis(nowMs()),
      leaseToken: null,
      leaseUntil: null,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return true;
  });
}

/**
 * Persists the stage marker MID-ATTEMPT, under the same guard
 * `releaseOutboxRow` and `completeOutboxRow` use.
 *
 * This was the one unguarded write in the pipeline. A worker whose lease had
 * expired could stamp `stage: "auth"` onto a row a second worker had already
 * re-claimed at an earlier stage; `mayDeleteAuthUser` then passes and the Auth
 * identity is destroyed with content, social edges and Storage objects still
 * in place, after which the `onDelete` trigger marks the row `completed` and
 * the loss is invisible. False means the lease is gone and the caller MUST
 * stop rather than take the irreversible step.
 */
async function advanceOutboxStage(
  reference,
  token,
  stage,
  { database = db } = {},
) {
  return database.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    if (!snapshot.exists) return false;
    const row = snapshot.data() ?? {};
    if (row.status !== "processing" || row.leaseToken !== token) return false;
    transaction.update(reference, {
      stage,
      cursor: null,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return true;
  });
}

/**
 * Records an advisory flag on the row, under the same lease guard.
 *
 * Today its only caller is the skipped ban digest. `retention.js` states that
 * an unwritten digest is VISIBLE rather than silent, and a log line does not
 * make it so: logs age out, and the operator who has to notice that deleting
 * a banned account reset the ban reads rows. Advisory, so a lost lease is not
 * an error — the row's owner will re-observe the same skip.
 */
async function flagOutboxRow(reference, token, fields, { database = db } = {}) {
  return database.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    if (!snapshot.exists) return false;
    const row = snapshot.data() ?? {};
    if (row.status !== "processing" || row.leaseToken !== token) return false;
    transaction.update(reference, {
      ...fields,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return true;
  });
}

/**
 * Mirrors the pipeline's state onto `users/{uid}.accountDeletion.state`.
 *
 * It is what the PIPELINE tells a signed-in client while the teardown runs.
 * Not the only thing the client can see — the callable's own
 * `accountDeletionMark` already wrote `requestedAt` and `source` beside it,
 * and `disabled: true` is visible on the same document — but the only field
 * that moves as the work progresses, and therefore the only one the app can
 * branch on. `allow get: if isOwner(userId)` keeps working after
 * `disabled: true`, and the field is server-owned by being absent from the
 * update allowlist. Without it the client's `running` and `deadLetter`
 * branches are unreachable and the "this account is being deleted" screen has
 * nothing to read. Best effort by design: the pipeline must never fail because
 * a status mirror could not be written, and `completed` is deliberately absent
 * because the document is deleted at that point.
 */
async function markAccountDeletionState(
  uid,
  state,
  { database = db, log = logger } = {},
) {
  if (!isValidOpaqueUid(uid)) return false;
  try {
    const reference = database.collection("users").doc(uid);
    const snapshot = await reference.get();
    if (!snapshot.exists) return false;
    if (snapshot.data()?.accountDeletion?.state === state) return false;
    await reference.set(
      {
        accountDeletion: {
          state,
          updatedAt: FieldValue.serverTimestamp(),
        },
      },
      { mergeFields: ["accountDeletion.state", "accountDeletion.updatedAt"] },
    );
    return true;
  } catch (error) {
    log.warn?.("account deletion state mirror failed", {
      uid,
      state,
      code: typeof error?.code === "string" ? error.code : "unknown",
    });
    return false;
  }
}

async function recordOutboxFailure(
  reference,
  token,
  error,
  { database = db, nowMs = () => Date.now(), maxAttempts = MAX_ATTEMPTS } = {},
) {
  const outcome = await database.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    if (!snapshot.exists) return { deadLetter: false, stale: true };
    const row = snapshot.data() ?? {};
    if (row.status !== "processing" || row.leaseToken !== token) {
      return { deadLetter: false, stale: true };
    }
    // Rows written before the two counters were split carry no `failureCount`.
    // Treating a missing one as 0 is correct AND safe: `attemptCount` on such a
    // row conflated progress with failure, so inheriting it would dead-letter a
    // healthy long-running deletion on its first error — the exact defect the
    // split removes. A genuinely failing row simply re-earns its eight.
    const failureCount = (Number.isSafeInteger(row.failureCount) &&
      row.failureCount >= 0 ? row.failureCount : 0) + 1;
    const deadLetter = failureCount >= maxAttempts;
    const code = typeof error?.code === "string"
      ? error.code.slice(0, 120)
      : "unknown";
    transaction.update(reference, {
      status: deadLetter ? "deadLetter" : "pending",
      failureCount,
      // An error somebody was alive to report is the opposite of an abandoned
      // lease; the two budgets stay independent.
      abandonedCount: 0,
      nextAttemptAt: deadLetter
        ? null
        : Timestamp.fromMillis(nowMs() + backoffMs(failureCount)),
      leaseToken: null,
      leaseUntil: null,
      lastErrorCode: code,
      ...(deadLetter
        ? { deadLetterAt: FieldValue.serverTimestamp() }
        : {}),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return { deadLetter, stale: false, uid: row.uid };
  });
  if (outcome.deadLetter === true) {
    // A dead letter is a P1 — a user asked to be deleted and it did not
    // happen. Mirroring it onto the account is what lets the app tell them
    // something honest instead of a spinner.
    await markAccountDeletionState(outcome.uid, "deadLetter", { database });
  }
  return outcome;
}

async function completeOutboxRow(
  reference,
  token,
  { database = db } = {},
) {
  return database.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    if (!snapshot.exists) return false;
    const row = snapshot.data() ?? {};
    if (row.status === "completed") return true;
    if (row.status !== "processing" || row.leaseToken !== token) return false;
    transaction.update(reference, {
      status: "completed",
      stage: STAGE_ORDER[STAGE_ORDER.length - 1],
      cursor: null,
      nextAttemptAt: null,
      leaseToken: null,
      leaseUntil: null,
      lastErrorCode: null,
      completedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return true;
  });
}

// ------------------------------------------------------------------- worker

/**
 * One leased attempt over a single row.
 *
 * Walks stages in order until the budget runs out, the row completes, or a
 * stage throws. A throw defers with exponential backoff and, on the eighth
 * failure, dead-letters — which is deliberately a P1: a user asked to be
 * deleted and it did not happen.
 *
 * A worker that DIES instead of throwing reports nothing at all, so the claim
 * counts consecutive abandoned leases separately and dead-letters on the
 * eighth of those too, with a structured warning. Without that second bound a
 * row that crashes its worker is re-claimed by every sweep for ever.
 */
async function processAccountDeletionOutbox(
  outboxId,
  {
    database = db,
    stages = null,
    nowMs = () => Date.now(),
    log = logger,
    maxSteps = MAX_STEPS_PER_ATTEMPT,
    maxMillis = MAX_ATTEMPT_MILLIS,
  } = {},
) {
  if (typeof outboxId !== "string" || !outboxId) {
    return { outboxId: null, processed: false, reason: "invalidId" };
  }
  const runner = stages ?? sharedStages();
  const reference = outboxReference(database, outboxId);
  const claim = await claimOutboxRow(reference, outboxId, { database, nowMs });
  if (!claim.claimed) {
    if (claim.reason === "lease-abandoned") {
      // The operator signal MEDIUM-1 asks for. A dead letter is already a P1,
      // but this one has no `lastErrorCode` a human would recognise and no
      // stack anywhere — the workers that produced it never got to log. Warn
      // with the counter and the ceiling so the row can be found, and mirror
      // the state onto the account so the app stops promising a deletion that
      // has stopped happening.
      log.warn?.("account deletion abandoned its lease too many times", {
        outboxId,
        uid: claim.uid ?? null,
        abandonedCount: claim.abandonedCount ?? null,
        maxAbandonedAttempts: MAX_ABANDONED_ATTEMPTS,
        deadLetter: true,
      });
      await markAccountDeletionState(claim.uid, "deadLetter", { database, log });
      return {
        outboxId,
        processed: false,
        reason: claim.reason,
        deadLetter: true,
      };
    }
    return { outboxId, processed: false, reason: claim.reason };
  }

  const { leaseToken: token, row } = claim;
  const uid = row.uid;
  let stage = row.stage;
  let cursor = row.cursor ?? null;
  const startedAtMs = nowMs();
  let steps = 0;
  let banDigestSkipped = false;

  await markAccountDeletionState(uid, "running", { database, log });

  try {
    while (steps < maxSteps && nowMs() - startedAtMs < maxMillis) {
      if (stage === "auth" &&
          !mayDeleteAuthUser({ ...row, stage, status: "processing" })) {
        // Belt and braces around the one irreversible step. A row that is not
        // exactly at `auth` — or is dead-lettered — must never reach
        // admin.auth().deleteUser().
        const error = new Error("Auth deletion reached out of order.");
        error.code = "failed-precondition";
        throw error;
      }
      const outcome = await runner.runStage(stage, { uid, cursor, row });
      steps += 1;
      log.info?.("account deletion stage", {
        uid,
        stage,
        attemptCount: row.attemptCount,
        outcome: outcome.done ? "advanced" : "continued",
        details: outcome.details ?? null,
      });
      if (outcome.details?.banDigestSkipped === true && !banDigestSkipped) {
        banDigestSkipped = true;
        await flagOutboxRow(reference, token, { banDigestSkipped: true }, {
          database,
        });
      }
      if (!outcome.done) {
        cursor = outcome.cursor ?? null;
        continue;
      }
      const next = stageIndex(stage) + 1;
      cursor = null;
      if (next >= STAGE_ORDER.length) {
        await completeOutboxRow(reference, token, { database });
        return { outboxId, processed: true, completed: true, steps };
      }
      stage = STAGE_ORDER[next];
      // The stage marker is persisted BEFORE the irreversible Auth delete, so
      // the `onDelete` trigger can recognise its own pipeline rather than
      // treating the deletion as out of band.
      if (stage === "auth") {
        const advanced = await advanceOutboxStage(reference, token, stage, {
          database,
        });
        if (!advanced) {
          // Somebody else owns the row now. Handing it over untouched is the
          // whole point of the guard: the new owner re-derives the stage from
          // the row it claimed, and the irreversible step happens once.
          log.warn?.("account deletion lost its lease before the auth stage", {
            uid,
            outboxId,
            stage,
          });
          return {
            outboxId,
            processed: true,
            completed: false,
            stage,
            steps,
            leaseLost: true,
          };
        }
      }
    }
    await releaseOutboxRow(reference, token, {
      stage,
      cursor,
      database,
      nowMs,
    });
    return { outboxId, processed: true, completed: false, stage, steps };
  } catch (error) {
    const outcome = await recordOutboxFailure(reference, token, error, {
      database,
      nowMs,
    });
    log.error?.("account deletion stage failed", {
      uid,
      stage,
      attemptCount: row.attemptCount,
      code: typeof error?.code === "string" ? error.code : "unknown",
      deadLetter: outcome.deadLetter === true,
    });
    return {
      outboxId,
      processed: false,
      failed: true,
      stage,
      deadLetter: outcome.deadLetter === true,
    };
  }
}

/**
 * The retry sweep. Picks up rows whose backoff has elapsed and rows whose
 * lease expired because an instance died mid-attempt.
 */
async function processReadyAccountDeletionOutbox({
  database = db,
  stages = null,
  nowMs = () => Date.now(),
  limit = SWEEP_PAGE,
  log = logger,
} = {}) {
  const now = Timestamp.fromMillis(nowMs());
  const [ready, expired] = await Promise.all([
    database.collection(OUTBOX_COLLECTION)
      .where("status", "==", "pending")
      .where("nextAttemptAt", "<=", now)
      .orderBy("nextAttemptAt")
      .limit(limit)
      .get(),
    database.collection(OUTBOX_COLLECTION)
      .where("status", "==", "processing")
      .where("leaseUntil", "<=", now)
      .orderBy("leaseUntil")
      .limit(limit)
      .get(),
  ]);
  const ids = [...new Set([
    ...ready.docs.map((document) => document.id),
    ...expired.docs.map((document) => document.id),
  ])];
  const results = [];
  for (const outboxId of ids) {
    results.push(await processAccountDeletionOutbox(outboxId, {
      database,
      stages,
      nowMs,
      log,
    }));
  }
  return {
    scanned: ids.length,
    completed: results.filter((entry) => entry.completed === true).length,
    deadLettered: results.filter((entry) => entry.deadLetter === true).length,
  };
}

// ------------------------------------------------------------ registrations

const deleteAccountSelfV1 = onCall(
  {
    region: REGION,
    memory: "256MiB",
    timeoutSeconds: 60,
    maxInstances: 10,
  },
  (request) => executeDeleteAccountSelf(request),
);

const onAccountDeletionOutboxCreated = onDocumentCreated(
  {
    region: REGION,
    document: `${OUTBOX_COLLECTION}/{outboxId}`,
    memory: "512MiB",
    timeoutSeconds: 540,
    maxInstances: 5,
    retry: true,
  },
  async (event) => {
    await processAccountDeletionOutbox(event.params.outboxId);
  },
);

const processAccountDeletionOutboxSchedule = onSchedule(
  {
    region: REGION,
    schedule: "every 2 minutes",
    timeZone: "Etc/UTC",
    memory: "512MiB",
    timeoutSeconds: 540,
    maxInstances: 1,
  },
  async () => {
    await processReadyAccountDeletionOutbox();
  },
);

module.exports = {
  MAX_ATTEMPT_MILLIS,
  MAX_STEPS_PER_ATTEMPT,
  RATE_LIMIT_MAX_EVENTS,
  RATE_LIMIT_SCOPE,
  RATE_LIMIT_WINDOW_MS,
  accountDeletionEnabled,
  advanceOutboxStage,
  claimOutboxRow,
  completeOutboxRow,
  deleteAccountSelfV1,
  enqueueAccountDeletionOutbox,
  executeDeleteAccountSelf,
  markAccountDeletionState,
  onAccountDeletionOutboxCreated,
  outboxReference,
  processAccountDeletionOutbox,
  processAccountDeletionOutboxSchedule,
  processReadyAccountDeletionOutbox,
  recordOutboxFailure,
  releaseOutboxRow,
};
