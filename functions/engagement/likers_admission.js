// Admission of one "See who liked" list call (ADR-230): steps 3-5 of the
// normative order shared by all three list callables.
//
//   1. auth                    - the callable (requireActor)
//   2. exact input             - the callable (likers_paging.requireLikersListInput)
//   3. activation              - appConfig/likersV1, one plain read
//   4. rate budgets            - likers.list / listHourly / listDaily, in ONE
//                                small transaction over privateRateLimits only
//   5. gate                    - the caller's own users / entitlements /
//                                vipGrants (+ restrictions) docs, plain getAll
//   6. content                 - the callable, inside its uniform refusal
//
// Nothing here reads another user's document or any content path, so every
// refusal describes only the caller and is thrown OUTSIDE the content
// phase's uniform `permission-denied` wrapper.
//
// The likers budgets are the ONLY budgets a list call consumes: browsing
// lists must never lock a viewer out of Moment or Yeel detail, so the Voice
// `read` and Yeel `view` budgets are deliberately not charged. The caller's
// own activeProfile / assertNotRestricted checks, which those budgets used to
// provide, are made explicitly below from the same getAll.

const { HttpsError } = require("firebase-functions/v2/https");
const defaultLogger = require("firebase-functions/logger");

const {
  activeProfile,
  assertNotRestricted,
  consumeRateLimit,
  rateLimitReference,
  transactionGetAll,
} = require("../integrity/guards");
const {
  deriveLikersAccessFromSnapshots,
  likersAccessReferences,
} = require("../utils/likers_access");
const { assertLikersEnabled } = require("./likers_activation");

const MINUTE_MS = 60_000;
const HOUR_MS = 60 * MINUTE_MS;
const DAY_MS = 24 * HOUR_MS;

// Shared by all three list callables. ~10k liker identities per account per
// day at most (500 pages x 20).
const LIKERS_RATE_LIMITS = Object.freeze({
  "likers.list": Object.freeze({ maxEvents: 10, windowMs: MINUTE_MS }),
  "likers.listHourly": Object.freeze({ maxEvents: 120, windowMs: HOUR_MS }),
  "likers.listDaily": Object.freeze({ maxEvents: 500, windowMs: DAY_MS }),
});
const LIKERS_RATE_SCOPES = Object.freeze(Object.keys(LIKERS_RATE_LIMITS));

const LIKERS_ACCESS_REQUIRED_MESSAGE =
  "YO Voice Premium or VIP is required to see who liked.";
const LIKERS_ACCESS_REQUIRED_REASON = "likersAccessRequired";

// Fixed reads of one admission: activation 1 + budgets 3 + caller
// users/entitlements/vipGrants/restrictions 4.
const LIKERS_ADMISSION_READS = 1 + LIKERS_RATE_SCOPES.length + 4;

function requireTiming(timing) {
  if (
    !timing ||
    !Number.isSafeInteger(timing.nowMs) ||
    timing.nowMs < 0 ||
    timing.now === undefined ||
    timing.now === null
  ) {
    throw new TypeError("timing {nowMs, now} is required.");
  }
  return timing;
}

// Step 4. One transaction whose read AND write set is the three
// privateRateLimits docs; it never touches a content path.
async function consumeLikersListBudgets({ db, uid, timing, logger = defaultLogger }) {
  requireTiming(timing);
  return db.runTransaction(async (transaction) => {
    const references = LIKERS_RATE_SCOPES.map((scope) =>
      rateLimitReference(db, scope, uid));
    const snapshots = await transactionGetAll(transaction, ...references);
    LIKERS_RATE_SCOPES.forEach((scope, index) => {
      try {
        consumeRateLimit(transaction, snapshots[index], {
          reference: references[index],
          scope,
          uid,
          nowMs: timing.nowMs,
          now: timing.now,
          ...LIKERS_RATE_LIMITS[scope],
        });
      } catch (error) {
        if (error instanceof HttpsError && error.code === "resource-exhausted") {
          // No uid: the log-based alert keys on scope == "likers.listDaily".
          logger.warn("likers budget exhausted", { scope });
        }
        throw error;
      }
    });
  });
}

function likersAccessRequiredError() {
  return new HttpsError(
    "failed-precondition",
    LIKERS_ACCESS_REQUIRED_MESSAGE,
    { reason: LIKERS_ACCESS_REQUIRED_REASON },
  );
}

function tokenRoleOf(auth) {
  const role = auth?.token?.role;
  return typeof role === "string" ? role : null;
}

// Step 5. Plain reads of the caller's own documents; no transaction.
// The caller's own suspension or communication mute propagates as-is (it
// describes the caller, as getReelViewV2 does); a caller who is merely not
// paid / VIP / staff gets the documented `likersAccessRequired` refusal.
async function assertCanSeeLikers({ db, uid, tokenRole = null, timing }) {
  requireTiming(timing);
  const [userSnapshot, entitlementSnapshot, grantSnapshot, restrictionSnapshot] =
    await db.getAll(
      ...likersAccessReferences(db, uid),
      db.doc(`restrictions/${uid}`),
    );
  activeProfile(userSnapshot, "Your");
  assertNotRestricted(restrictionSnapshot, "Your", timing.nowMs);
  const access = deriveLikersAccessFromSnapshots({
    userSnapshot,
    entitlementSnapshot,
    grantSnapshot,
    tokenRole,
    now: timing.nowMs,
  });
  if (!access.allowed) throw likersAccessRequiredError();
  return {
    access,
    callerProfile: userSnapshot,
    callerRestriction: restrictionSnapshot,
  };
}

// Steps 3-5 in order. `surface` is LIKERS_SURFACES.CONTENT for the Voice
// Moment and Yeel families and LIKERS_SURFACES.SERVER_MESSAGE for the Server
// reactor list (which additionally needs serverMessagesEnabled).
async function admitLikersList({
  db,
  auth,
  surface,
  timing,
  logger = defaultLogger,
}) {
  requireTiming(timing);
  const uid = auth?.uid;
  if (typeof uid !== "string" || uid.length === 0) {
    throw new TypeError("An authenticated caller is required.");
  }
  const activation = await assertLikersEnabled({ db, surface });
  await consumeLikersListBudgets({ db, uid, timing, logger });
  const admitted = await assertCanSeeLikers({
    db,
    uid,
    tokenRole: tokenRoleOf(auth),
    timing,
  });
  return { activation, ...admitted };
}

module.exports = {
  LIKERS_ACCESS_REQUIRED_MESSAGE,
  LIKERS_ACCESS_REQUIRED_REASON,
  LIKERS_ADMISSION_READS,
  LIKERS_RATE_LIMITS,
  LIKERS_RATE_SCOPES,
  admitLikersList,
  assertCanSeeLikers,
  consumeLikersListBudgets,
  likersAccessRequiredError,
  tokenRoleOf,
};
