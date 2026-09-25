// Pre-registered account takeover remediation — Phase 1 (ADR, "a Google or
// Apple sign-in that inherits a password nobody verified ends every session
// that existed before it").
//
// THE ATTACK. Anyone can register a stranger's address with a password. The
// account stays unverified because only the owner can open the verification
// e-mail. When the owner later signs in with Google or Apple, Firebase (one
// account per e-mail) hands the owner that SAME uid and unlinks the unverified
// password — but the pre-registrant's refresh token keeps working and the ID
// tokens it mints now say `email_verified: true`. Push tokens the
// pre-registrant planted in `users/{uid}/fcmTokens` keep receiving the owner's
// notification metadata even after that session ends.
//
// WHAT THE SERVER CAN SEE. Reproduced in the Auth emulator (firebase-tools
// 15.29.0): after the takeover the password provider is already GONE from
// `providerData` and `emailVerified` is true. The Auth record alone therefore
// cannot tell a taken-over account from one that was created with Google. The
// evidence has to be captured while the password is still there, so this
// module keeps a server-only ledger, `authPasswordLedger/{uid}`, with
// `state: "pending"` for every account seen carrying a password on an
// unverified address. Two writers seed it: the Auth `onCreate` trigger below
// (immediately, for every new account) and the sweeper's bounded `listUsers`
// walk (existing accounts, and accounts whose address became unverified
// later).
//
// ONE AUTHORITY. `remediateAccount()` is the only code that acts. Both
// triggers call it: the owner's own client right after a returning Google or
// Apple sign-in (`secureFederatedSignInV1`, trigger A — the trustworthy party,
// because the pre-registrant cannot stop the owner's client from calling) and
// the scheduled sweeper (trigger B — the website, old app builds, anyone who
// never calls A). It acts only when the account has a Google/Apple identity on
// the account's own address AND either still carries an unverified password,
// or its password vanished while the ledger still said "pending". A password
// its holder verified is the owner's by definition and is never touched.
//
// ORDER (each step closes the gap the next one would leave):
//   1. unlink the password and every identity that is not the owner's, so no
//      NEW session can be minted from the pre-registrant's credentials;
//   2. revoke refresh tokens, so no session that already exists can mint a
//      fresh ID token (production; the emulator does not enforce this);
//   3. write `users/{uid}.authSessionEpoch`, so Firestore and Storage rules
//      refuse, from this moment, every ID token whose `auth_time` is older —
//      including the one the pre-registrant already holds, and including a
//      push-token write racing step 4;
//   4. delete the planted `fcmTokens` (all of them from the sweeper; all but
//      the calling device's from the owner), which no stale session can now
//      re-plant;
//   5. write the audit record and flip the ledger row to "remediated" in one
//      batch.
// A failure at any step throws; the ledger row stays "pending", so the next
// call or sweep repeats the whole sequence. Every step is idempotent.
//
// WHAT THIS DOES NOT DO (Phase 2 needs the Identity Platform upgrade): an ID
// token the pre-registrant already holds stays cryptographically valid until
// it expires (up to one hour). Rules paths gated by `isActiveAccount()` /
// Storage `isActiveUser()` refuse it through the epoch; owner-only reads that
// never consult account state (notifications, incoming calls, DM reads) and
// Cloud Functions callables still accept it until it expires.

const functionsV1 = require("firebase-functions/v1");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const logger = require("firebase-functions/logger");
const { getAuth } = require("firebase-admin/auth");
const {
  FieldPath,
  FieldValue,
  getFirestore,
} = require("firebase-admin/firestore");

const { requireAuthentication } = require("../utils/auth");

const REGION = "europe-west1";

const TRUSTED_FEDERATED_PROVIDERS = Object.freeze(["google.com", "apple.com"]);
const PASSWORD_PROVIDER = "password";

const LEDGER_COLLECTION = "authPasswordLedger";
const AUDIT_COLLECTION = "authTakeoverAudit";
const SWEEP_STATE_COLLECTION = "authTakeoverSweep";
const SWEEP_STATE_DOC = "state";

const LEDGER_STATE = Object.freeze({
  PENDING: "pending",
  VERIFIED: "verified",
  REMEDIATED: "remediated",
});

const TRIGGER = Object.freeze({
  OWNER: "ownerSignIn",
  SWEEPER: "sweeper",
});

// A caller keeps its own push registration only when its session is the
// account's latest sign-in and is fresh; anything else is purged like the
// sweeper purges.
const OWNER_CALL_MAX_AUTH_AGE_SECONDS = 10 * 60;
const MAX_FCM_TOKEN_ID_LENGTH = 1500;
const FCM_PURGE_PAGE_SIZE = 400;
const FCM_PURGE_MAX_PAGES = 25;

// Report-only threshold for never-verified password-only accounts.
const STALE_UNVERIFIED_REPORT_AGE_MS = 7 * 24 * 60 * 60 * 1000;
const STALE_REPORT_SAMPLE_LIMIT = 100;

const SWEEP_LEDGER_PAGE_SIZE = 300;
const GET_USERS_BATCH_SIZE = 100;
const SWEEP_LIST_USERS_PAGE_SIZE = 1000;
const SWEEP_LIST_USERS_PAGES_PER_RUN = 2;
const SWEEP_WALK_MIN_INTERVAL_MS = 60 * 60 * 1000;
const SWEEP_TIME_BUDGET_MS = 240 * 1000;

function normalizeEmail(value) {
  return typeof value === "string" ? value.trim().toLowerCase() : "";
}

function providerIdsOf(user) {
  return (Array.isArray(user?.providerData) ? user.providerData : [])
    .map((provider) => provider?.providerId)
    .filter((providerId) => typeof providerId === "string" && providerId);
}

/**
 * Decides, from the Auth record and the ledger row alone, whether the account
 * is in the takeover state. Pure: no I/O, no clock.
 *
 * verdicts:
 *  - "takeover": remediate. `keepProviders` are the Google/Apple identities on
 *    the account's own address; `unlinkProviders` is everything else.
 *  - "verified": the password on this account is verified; the ledger row (if
 *    any) can stop watching it.
 *  - "ambiguous": a pending password became verified while a Google/Apple
 *    identity was also linked. Firebase links a verified password instead of
 *    replacing it, so this is treated as the owner's and NOT touched — but it
 *    is reported, because it is also what a production difference from the
 *    emulator (linking an unverified password) would look like.
 *  - "unverifiedPassword": a password on an unverified address with no
 *    Google/Apple identity yet; the ledger must watch it.
 *  - "clean": nothing to do.
 */
function planRemediation(user, ledgerRow = null) {
  const email = normalizeEmail(user?.email);
  const providers = Array.isArray(user?.providerData) ? user.providerData : [];
  const hasPassword = providers.some(
    (provider) => provider?.providerId === PASSWORD_PROVIDER,
  );
  const emailVerified = user?.emailVerified === true;
  const ledgerPending = ledgerRow?.state === LEDGER_STATE.PENDING;

  // A Google/Apple identity counts as the owner's only when it is on the
  // account's own address. An identity without an e-mail cannot be attributed
  // to a different address, so it is kept rather than stripped.
  const ownFederated = email
    ? providers.filter((provider) => {
      if (!TRUSTED_FEDERATED_PROVIDERS.includes(provider?.providerId)) {
        return false;
      }
      const providerEmail = normalizeEmail(provider.email);
      return providerEmail === "" || providerEmail === email;
    })
    : [];

  if (ownFederated.length === 0) {
    if (hasPassword && !emailVerified) {
      return { verdict: "unverifiedPassword", reason: "awaitingVerification" };
    }
    if (hasPassword && emailVerified && ledgerPending) {
      return { verdict: "verified", reason: "passwordVerified" };
    }
    return { verdict: "clean", reason: "noOwnFederatedIdentity" };
  }

  let reason = null;
  if (hasPassword && !emailVerified) {
    reason = "unverifiedPasswordBesideFederated";
  } else if (!hasPassword && ledgerPending) {
    reason = "unverifiedPasswordReplacedByFederated";
  }

  if (reason === null) {
    if (hasPassword && emailVerified && ledgerPending) {
      return { verdict: "ambiguous", reason: "verifiedPasswordBesideFederated" };
    }
    return { verdict: "clean", reason: "noUnverifiedPassword" };
  }

  const keepProviders = [...new Set(ownFederated.map((p) => p.providerId))];
  const unlinkProviders = [...new Set(providerIdsOf(user))]
    .filter((providerId) => !keepProviders.includes(providerId));
  return { verdict: "takeover", reason, keepProviders, unlinkProviders };
}

function validFcmTokenId(value) {
  return typeof value === "string" &&
    value.length > 0 &&
    value.length <= MAX_FCM_TOKEN_ID_LENGTH &&
    !value.includes("/") &&
    value !== "." &&
    value !== ".." &&
    !/^__.*__$/u.test(value);
}

function parseOwnerInput(data) {
  if (data === undefined || data === null) return { fcmToken: null };
  if (typeof data !== "object" || Array.isArray(data)) {
    throw new HttpsError("invalid-argument", "This action takes an object.");
  }
  const keys = Object.keys(data);
  if (keys.some((key) => key !== "fcmToken")) {
    throw new HttpsError("invalid-argument", "Unsupported field.");
  }
  if (data.fcmToken === undefined || data.fcmToken === null) {
    return { fcmToken: null };
  }
  if (!validFcmTokenId(data.fcmToken)) {
    throw new HttpsError("invalid-argument", "fcmToken is invalid.");
  }
  return { fcmToken: data.fcmToken };
}

/**
 * Whether the calling session may keep its device's push registration. The
 * session must be a sign-in with one of the identities being KEPT, carry that
 * exact identity, be fresh, and be the account's latest sign-in. A
 * pre-registrant who had linked a Google identity of their own before the
 * takeover fails every one of these.
 */
function callerMayKeepDevice(caller, user, plan, nowSeconds) {
  const firebase = caller?.token?.firebase ?? {};
  const provider = firebase.sign_in_provider;
  if (!plan.keepProviders.includes(provider)) return false;

  const keptIdentity = (user.providerData ?? [])
    .find((entry) => entry?.providerId === provider)?.uid;
  const tokenIdentities = firebase.identities?.[provider];
  if (
    typeof keptIdentity !== "string" ||
    !Array.isArray(tokenIdentities) ||
    !tokenIdentities.includes(keptIdentity)
  ) {
    return false;
  }

  const authTime = caller?.token?.auth_time;
  if (
    !Number.isSafeInteger(authTime) ||
    authTime > nowSeconds + 60 ||
    nowSeconds - authTime > OWNER_CALL_MAX_AUTH_AGE_SECONDS
  ) {
    return false;
  }
  const lastSignInMs = Date.parse(user.metadata?.lastSignInTime ?? "");
  return Number.isFinite(lastSignInMs) &&
    authTime >= Math.floor(lastSignInMs / 1000);
}

function isNotFound(error) {
  return error?.code === "auth/user-not-found";
}

function createFederatedTakeoverService({
  auth,
  db,
  clock = () => Date.now(),
  log = logger,
} = {}) {
  if (!auth || typeof auth.getUser !== "function") {
    throw new TypeError("An Admin Auth service is required.");
  }
  if (!db || typeof db.collection !== "function") {
    throw new TypeError("A Firestore database is required.");
  }

  const ledgerRef = (uid) => db.collection(LEDGER_COLLECTION).doc(uid);
  const sweepStateRef = () =>
    db.collection(SWEEP_STATE_COLLECTION).doc(SWEEP_STATE_DOC);

  async function readLedger(uid) {
    const snapshot = await ledgerRef(uid).get();
    return snapshot.exists ? snapshot.data() : null;
  }

  async function markLedger(uid, state, extra = {}) {
    await ledgerRef(uid).set({
      state,
      updatedAt: FieldValue.serverTimestamp(),
      ...extra,
    }, { merge: true });
  }

  /** Seeds (or re-arms) the ledger row for an unverified password. */
  async function watchUnverifiedPassword(uid, source, existing) {
    if (existing?.state === LEDGER_STATE.PENDING) return false;
    await ledgerRef(uid).set({
      state: LEDGER_STATE.PENDING,
      source,
      ...(existing ? {} : { firstSeenAt: FieldValue.serverTimestamp() }),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    return true;
  }

  async function writeSessionEpoch(uid) {
    // +1: every session that started in or before the second in which the
    // pre-registrant's credentials were removed is dead. Nobody can sign in
    // with those credentials after step 1, and the owner's own re-sign-in is
    // a human action that takes longer than a second.
    const epoch = Math.floor(clock() / 1000) + 1;
    const userRef = db.collection("users").doc(uid);
    return db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(userRef);
      const current = snapshot.exists
        ? snapshot.get("authSessionEpoch")
        : null;
      const next = Number.isSafeInteger(current) && current > epoch
        ? current
        : epoch;
      // A partial private document is a supported state (presence and the
      // profile bootstrap both merge into one), so the epoch is written even
      // before the owner's profile exists: a stale session must not regain
      // rules access when the owner's app creates it.
      transaction.set(userRef, { authSessionEpoch: next }, { merge: true });
      return next;
    });
  }

  async function purgeFcmTokens(uid, keepTokenId) {
    const tokens = db.collection("users").doc(uid).collection("fcmTokens");
    let deleted = 0;
    let keptCallerToken = false;
    for (let page = 0; page < FCM_PURGE_MAX_PAGES; page += 1) {
      const snapshot = await tokens.limit(FCM_PURGE_PAGE_SIZE).get();
      const doomed = snapshot.docs.filter((entry) => {
        if (keepTokenId && entry.id === keepTokenId) {
          keptCallerToken = true;
          return false;
        }
        return true;
      });
      if (doomed.length === 0) return { deleted, keptCallerToken };
      const batch = db.batch();
      for (const entry of doomed) batch.delete(entry.ref);
      await batch.commit();
      deleted += doomed.length;
    }
    // The epoch is already in force, so nothing can be adding tokens; running
    // out of pages means an abusive volume. Leave the row pending and retry.
    throw new Error("fcmTokens purge did not finish within its page budget.");
  }

  /**
   * The single remediation authority. Returns
   * `{ status: "remediated" | "clean" | "gone", ... }`.
   */
  async function remediateAccount(uid, {
    trigger,
    user: knownUser = null,
    ledger: knownLedger,
    caller = null,
    keepFcmToken = null,
  } = {}) {
    if (!Object.values(TRIGGER).includes(trigger)) {
      throw new TypeError("An explicit remediation trigger is required.");
    }

    let user = knownUser;
    if (!user) {
      try {
        user = await auth.getUser(uid);
      } catch (error) {
        if (!isNotFound(error)) throw error;
        await ledgerRef(uid).delete();
        return { status: "gone" };
      }
    }
    const ledger = knownLedger === undefined ? await readLedger(uid) : knownLedger;
    const plan = planRemediation(user, ledger);

    if (plan.verdict === "verified" || plan.verdict === "ambiguous") {
      await markLedger(uid, LEDGER_STATE.VERIFIED, {
        verifiedReason: plan.reason,
      });
      if (plan.verdict === "ambiguous") {
        log.warn("federated takeover: pending password verified beside a " +
          "Google/Apple identity; left untouched", { uid, trigger });
      }
      return { status: "clean", verdict: plan.verdict };
    }
    if (plan.verdict !== "takeover") {
      return { status: "clean", verdict: plan.verdict };
    }

    const providersBefore = providerIdsOf(user);

    // 1. No new session from the pre-registrant's credentials.
    if (plan.unlinkProviders.length > 0) {
      await auth.updateUser(uid, { providersToUnlink: plan.unlinkProviders });
    }
    // 2. No refresh of a session that already exists.
    await auth.revokeRefreshTokens(uid);
    // 3. Rules refuse every older ID token from here on.
    const sessionEpoch = await writeSessionEpoch(uid);
    // 4. Nothing planted survives, and nothing stale can re-plant.
    const nowSeconds = Math.floor(clock() / 1000);
    const keep = trigger === TRIGGER.OWNER &&
      keepFcmToken &&
      callerMayKeepDevice(caller, user, plan, nowSeconds)
      ? keepFcmToken
      : null;
    const purge = await purgeFcmTokens(uid, keep);

    // 5. Audit + ledger, together.
    const auditRef = db.collection(AUDIT_COLLECTION).doc();
    const batch = db.batch();
    batch.set(auditRef, {
      schemaVersion: 1,
      uid,
      trigger,
      reason: plan.reason,
      providersBefore,
      providersUnlinked: plan.unlinkProviders,
      providersKept: plan.keepProviders,
      refreshTokensRevoked: true,
      sessionEpoch,
      fcmTokensDeleted: purge.deleted,
      callerDeviceKept: purge.keptCallerToken,
      ledgerStateBefore: ledger?.state ?? null,
      createdAt: FieldValue.serverTimestamp(),
    });
    batch.set(ledgerRef(uid), {
      state: LEDGER_STATE.REMEDIATED,
      remediatedAt: FieldValue.serverTimestamp(),
      remediatedBy: trigger,
      lastAuditId: auditRef.id,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    await batch.commit();

    log.warn("federated takeover remediated", {
      uid,
      trigger,
      reason: plan.reason,
      providersUnlinked: plan.unlinkProviders,
      fcmTokensDeleted: purge.deleted,
      auditId: auditRef.id,
    });

    return {
      status: "remediated",
      auditId: auditRef.id,
      sessionEpoch,
      providersUnlinked: plan.unlinkProviders,
      fcmTokensDeleted: purge.deleted,
      callerDeviceKept: purge.keptCallerToken,
    };
  }

  /** Trigger A: the owner's own client after a returning Google/Apple sign-in. */
  async function secureFederatedSignIn(request) {
    const caller = requireAuthentication(request);
    const { fcmToken } = parseOwnerInput(request.data);

    const provider = caller.token?.firebase?.sign_in_provider;
    if (!TRUSTED_FEDERATED_PROVIDERS.includes(provider)) {
      return { status: "notApplicable", reauthenticate: false };
    }

    let outcome;
    try {
      outcome = await remediateAccount(caller.uid, {
        trigger: TRIGGER.OWNER,
        caller,
        keepFcmToken: fcmToken,
      });
    } catch (error) {
      log.error("federated takeover: owner-triggered remediation failed", {
        uid: caller.uid,
        code: typeof error?.code === "string" ? error.code : "unknown",
      });
      // Never forward Admin SDK detail. The sweeper retries the same row.
      throw new HttpsError(
        "unavailable",
        "YO Voice could not finish securing this sign-in. Try again.",
      );
    }

    if (outcome.status === "remediated") {
      // The owner's own refresh token was revoked with everyone else's, and
      // the session epoch refuses this session's ID token in rules. The
      // client must sign in again once; that new session is after the epoch.
      return { status: "remediated", reauthenticate: true };
    }
    return { status: "clean", reauthenticate: false };
  }

  /** Auth onCreate: capture the evidence while the password is still there. */
  async function recordPasswordAccountOrigin(user) {
    const uid = user?.uid;
    if (typeof uid !== "string" || uid.length === 0) return { recorded: false };
    const plan = planRemediation(user, null);
    if (plan.verdict !== "unverifiedPassword" && plan.verdict !== "takeover") {
      return { recorded: false };
    }
    try {
      await ledgerRef(uid).create({
        state: LEDGER_STATE.PENDING,
        source: "authCreate",
        firstSeenAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return { recorded: true };
    } catch (error) {
      // ALREADY_EXISTS: a retried delivery, or the sweeper got there first.
      if (error?.code === 6) return { recorded: false };
      throw error;
    }
  }

  async function sweepLedger(state, deadline, counts) {
    let query = db.collection(LEDGER_COLLECTION)
      .where("state", "==", LEDGER_STATE.PENDING)
      .orderBy(FieldPath.documentId())
      .limit(SWEEP_LEDGER_PAGE_SIZE);
    if (typeof state.ledgerCursor === "string" && state.ledgerCursor) {
      query = query.startAfter(state.ledgerCursor);
    }
    const snapshot = await query.get();
    const rows = snapshot.docs;
    let lastProcessed = null;

    for (let start = 0; start < rows.length; start += GET_USERS_BATCH_SIZE) {
      if (clock() > deadline) break;
      const slice = rows.slice(start, start + GET_USERS_BATCH_SIZE);
      const result = await auth.getUsers(slice.map((row) => ({ uid: row.id })));
      const users = new Map(result.users.map((user) => [user.uid, user]));
      for (const row of slice) {
        const user = users.get(row.id);
        counts.ledgerChecked += 1;
        try {
          if (!user) {
            await ledgerRef(row.id).delete();
            counts.ledgerGone += 1;
          } else {
            const outcome = await remediateAccount(row.id, {
              trigger: TRIGGER.SWEEPER,
              user,
              ledger: row.data(),
            });
            if (outcome.status === "remediated") counts.remediated += 1;
            if (outcome.verdict === "verified" || outcome.verdict === "ambiguous") {
              counts.ledgerVerified += 1;
            }
          }
        } catch (error) {
          counts.failed += 1;
          log.error("federated takeover sweep: ledger row failed", {
            uid: row.id,
            code: typeof error?.code === "string" ? error.code : "unknown",
          });
        }
        lastProcessed = row.id;
      }
    }

    const finished = rows.length < SWEEP_LEDGER_PAGE_SIZE &&
      lastProcessed === (rows.at(-1)?.id ?? null);
    return finished ? null : lastProcessed ?? state.ledgerCursor ?? null;
  }

  async function sweepUsers(state, deadline, counts, nowMs) {
    const walk = { ...(state.walk ?? {}) };
    const lastCompletedMs = walk.lastCompletedAtMs;
    const inPass = typeof walk.pageToken === "string" && walk.pageToken;
    if (
      !inPass &&
      Number.isSafeInteger(lastCompletedMs) &&
      nowMs - lastCompletedMs < SWEEP_WALK_MIN_INTERVAL_MS
    ) {
      return { walk, report: null };
    }
    if (!inPass) {
      walk.passStats = { scanned: 0, seeded: 0, stalePasswordOnly: 0 };
      walk.staleSample = [];
    }
    const stats = { scanned: 0, seeded: 0, stalePasswordOnly: 0, ...walk.passStats };
    const staleSample = Array.isArray(walk.staleSample) ? [...walk.staleSample] : [];
    let pageToken = inPass ? walk.pageToken : undefined;
    let passComplete = false;

    for (let page = 0; page < SWEEP_LIST_USERS_PAGES_PER_RUN; page += 1) {
      if (clock() > deadline) break;
      const result = await auth.listUsers(SWEEP_LIST_USERS_PAGE_SIZE, pageToken);
      const candidates = [];
      for (const user of result.users) {
        stats.scanned += 1;
        const plan = planRemediation(user, null);
        if (plan.verdict === "unverifiedPassword" || plan.verdict === "takeover") {
          candidates.push({ user, plan });
        }
        const providers = providerIdsOf(user);
        const createdMs = Date.parse(user.metadata?.creationTime ?? "");
        if (
          user.emailVerified !== true &&
          providers.length === 1 &&
          providers[0] === PASSWORD_PROVIDER &&
          Number.isFinite(createdMs) &&
          nowMs - createdMs > STALE_UNVERIFIED_REPORT_AGE_MS
        ) {
          stats.stalePasswordOnly += 1;
          if (staleSample.length < STALE_REPORT_SAMPLE_LIMIT) {
            staleSample.push({
              uid: user.uid,
              createdAt: new Date(createdMs).toISOString(),
            });
          }
        }
      }

      if (candidates.length > 0) {
        const snapshots = await db.getAll(
          ...candidates.map(({ user }) => ledgerRef(user.uid)),
        );
        for (let index = 0; index < candidates.length; index += 1) {
          const { user, plan } = candidates[index];
          const existing = snapshots[index].exists ? snapshots[index].data() : null;
          try {
            if (plan.verdict === "takeover") {
              const outcome = await remediateAccount(user.uid, {
                trigger: TRIGGER.SWEEPER,
                user,
                ledger: existing,
              });
              if (outcome.status === "remediated") counts.remediated += 1;
            } else if (await watchUnverifiedPassword(user.uid, "sweep", existing)) {
              stats.seeded += 1;
              counts.seeded += 1;
            }
          } catch (error) {
            counts.failed += 1;
            log.error("federated takeover sweep: account failed", {
              uid: user.uid,
              code: typeof error?.code === "string" ? error.code : "unknown",
            });
          }
        }
      }

      pageToken = result.pageToken;
      if (!pageToken) {
        passComplete = true;
        break;
      }
    }

    let report = null;
    if (passComplete) {
      report = { ...stats, staleSample };
      walk.pageToken = null;
      walk.lastCompletedAtMs = nowMs;
      walk.passStats = { scanned: 0, seeded: 0, stalePasswordOnly: 0 };
      walk.staleSample = [];
    } else {
      walk.pageToken = pageToken ?? null;
      walk.passStats = stats;
      walk.staleSample = staleSample;
    }
    return { walk, report };
  }

  /** Trigger B: one bounded sweep. */
  async function runSweep() {
    const startedMs = clock();
    const deadline = startedMs + SWEEP_TIME_BUDGET_MS;
    const stateSnapshot = await sweepStateRef().get();
    const state = stateSnapshot.exists ? stateSnapshot.data() : {};
    const counts = {
      ledgerChecked: 0,
      ledgerGone: 0,
      ledgerVerified: 0,
      seeded: 0,
      remediated: 0,
      failed: 0,
    };

    const ledgerCursor = await sweepLedger(state, deadline, counts);
    const { walk, report } = await sweepUsers(state, deadline, counts, startedMs);

    await sweepStateRef().set({
      ledgerCursor,
      walk,
      updatedAt: FieldValue.serverTimestamp(),
    });

    log.info("federated takeover sweep", counts);
    if (report) {
      // REPORT ONLY. Deleting never-verified accounts is the owner's
      // decision (ADR); no deletion code runs here.
      log.warn("never-verified password-only accounts older than 7 days", {
        count: report.stalePasswordOnly,
        scanned: report.scanned,
        sample: report.staleSample,
      });
    }
    return { ...counts, walkPassReport: report };
  }

  return Object.freeze({
    recordPasswordAccountOrigin,
    remediateAccount,
    runSweep,
    secureFederatedSignIn,
  });
}

let defaultService = null;
function service() {
  defaultService ??= createFederatedTakeoverService({
    auth: getAuth(),
    db: getFirestore(),
  });
  return defaultService;
}

const secureFederatedSignInV1 = onCall(
  { region: REGION, enforceAppCheck: false },
  (request) => service().secureFederatedSignIn(request),
);

// Retried on failure: `create()` makes a second delivery a no-op.
const onAuthUserCreated = functionsV1
  .runWith({ failurePolicy: true })
  .region(REGION)
  .auth.user()
  .onCreate(async (user) => {
    await service().recordPasswordAccountOrigin(user);
  });

const sweepFederatedTakeoverSchedule = onSchedule(
  {
    region: REGION,
    schedule: "every 5 minutes",
    timeZone: "Etc/UTC",
    memory: "256MiB",
    timeoutSeconds: 300,
    maxInstances: 1,
  },
  async () => {
    await service().runSweep();
  },
);

module.exports = {
  AUDIT_COLLECTION,
  LEDGER_COLLECTION,
  LEDGER_STATE,
  OWNER_CALL_MAX_AUTH_AGE_SECONDS,
  STALE_UNVERIFIED_REPORT_AGE_MS,
  SWEEP_STATE_COLLECTION,
  TRIGGER,
  TRUSTED_FEDERATED_PROVIDERS,
  callerMayKeepDevice,
  createFederatedTakeoverService,
  onAuthUserCreated,
  planRemediation,
  secureFederatedSignInV1,
  sweepFederatedTakeoverSchedule,
};
