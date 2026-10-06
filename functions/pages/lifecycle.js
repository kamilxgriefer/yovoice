// managePageV1: create, update, pause and resume a Premium Page (ADR-233
// §2.2), and clear its public contact details (ADR-241). One op callable,
// europe-west1, App Check in the project's rollout mode
// (enforceAppCheck:false, like every profile callable).
//
// Order inside every op: auth -> exact input -> activation (non-safety only)
// -> rate budget -> gate (writes only) -> content. `create` is the one
// exception the spec makes: its 5/day budget is charged BEFORE activation,
// the gate and any field validation, so probing the adult check or the name
// filter costs the caller.
//
//   op      activation  rate           gate  preconditions            notes
//   create  write       pages.create   yes   active, !muted, verified  adult check before the transaction;
//                                                                     followers carried over (below)
//   update  write       pages.update   yes   active, !muted, verified  allowed while paused; not while suspended
//   pause   NONE        none           NO    none (allowed while muted, unverified)  a safety action (§2.1)
//   resume  write       pages.update   yes   active, !muted, verified  public profile + current name re-checked
//   clearContact NONE    none           NO    none (allowed while muted, unverified,  a safety action (ADR-241): only
//                                             lapsed, paused or suspended)           REMOVES the public contact details
//
// Every write that finds the capability live also RESTORES a lapsed Page to
// `active` (§2.8 "every write path, live"); pause writes the visibility index
// in the same transaction as the Page. clearContact passes no gate, so it
// restores nothing, and nothing it changes decides visibility, so it leaves
// the index alone. Both safety ops are idempotent and keep no ledger.
//
// Every op answers the same owner result, {pageId, kind, status, ownerPaused}
// (pageLifecycleResult): a client that predates an op never sends it and
// reads every other answer exactly as before.
//
// The birth date is used for one calculation and then dropped: never stored,
// never hashed (the ledger's inputHash covers {adultEligibility:true}), never
// logged. An under-18 answer writes pageAdultRefusals/{uid} with no date and
// blocks another attempt for 30 days.
//
// Followers (ADR-234, owner decision 2026-09-29): an account that has or had
// followers creates a Page like any other (the `pageHasAudience` refusal is
// retired). The create transaction also
//   * switches Creator audience OFF when it is on, re-projecting
//     publicProfiles/{uid} in the same commit (publicProfiles reads are
//     allowed only while the projection matches the user record, so a
//     trigger lag would leave the profile unreadable). Re-enabling stays
//     refused while pages/{uid} exists (hooks.js), so a Page's follower
//     edges are never publicly listable;
//   * writes pageFollowCarryJobs/{uid} (follow_carry.js), due 5 minutes
//     later. After the commit, and only for a NEW Page (never a ledger
//     replay), one batch of <= 100 followers is carried over right here; a
//     failure there is logged and left to the pagesMaintenance worker, and
//     the create still succeeds. A new Page has no posts, so no follower can
//     miss anything before the first batch lands.

const { Timestamp } = require("firebase-admin/firestore");
const { onCall } = require("firebase-functions/v2/https");
const defaultLogger = require("firebase-functions/logger");

const {
  assertLedgerReplay,
  assertNotRestricted,
  canonicalPublicProfile,
  consumeRateLimit,
  fail,
  ledgerData,
  operationIdentity,
  rateLimitReference,
  requireActor,
  requireExactInput,
  requireObject,
  requireRequestId,
  timestampMillis,
  transactionGetAll,
} = require("../integrity/guards");
const { likersAccountIsActive } = require("../utils/likers_access");
const { normalizeProfileVisibility } = require("../profile/profile_visibility");
const {
  PUBLIC_PROFILE_FIELDS,
  applyProjectionInTransaction,
  derivePublicProfile,
  requireAdultBirthDate,
} = require("../profile/public_profiles");
const { admitsPublicJoin, canonicalServer } = require("../servers/authority");
const {
  derivePagesCapability,
  pageAccessRequiredError,
  pagesCapabilityReferences,
} = require("./access");
const { assertPagesWriteEnabled } = require("./activation");
const {
  PAGE_CONSENT_VERSION,
  PAGE_ERRORS,
  canonicalPage,
  clearedPageContact,
  derivePageListed,
  newPageDocument,
  pageDisplayNameMirror,
  pageLifecycleResult,
  validatePageFields,
} = require("./contract");
const {
  applyPagePauseInTransaction,
  assertPageNameAllowed,
  pageForSafetyAction,
  pageReference,
} = require("./hooks");
const {
  PAGE_FOLLOW_CARRY_HANDOFF_MS,
  PAGE_FOLLOW_CARRY_LIMITS,
  createPagesFollowCarryService,
  pageFollowCarryJobDocument,
  pageFollowCarryJobReference,
} = require("./follow_carry");
const { restoredPageFields } = require("./lapse");
const {
  applyPageVisibilityInTransaction,
  pageVisibilityReference,
} = require("./visibility");

const REGION = "europe-west1";
const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * HOUR_MS;
const PAGE_ADULT_REFUSAL_COOLDOWN_MS = 30 * DAY_MS;
const PAGES_LIFECYCLE_RATE_LIMITS = Object.freeze({
  "pages.create": Object.freeze({ maxEvents: 5, windowMs: DAY_MS }),
  "pages.update": Object.freeze({ maxEvents: 20, windowMs: HOUR_MS }),
});
const MANAGE_PAGE_OPS = Object.freeze([
  "create", "update", "pause", "resume", "clearContact",
]);
// The ops that must work whatever state the Page, the account or the kill
// switch is in (activation.js PAGES_SAFETY_ACTIONS): no verified e-mail, no
// activation read, no rate budget, no capability gate.
const MANAGE_PAGE_SAFETY_OPS = Object.freeze(["pause", "clearContact"]);
const MANAGE_PAGE_FIELDS = Object.freeze({
  create: Object.freeze([
    "requestId", "op", "kind", "category", "description", "business",
    "community", "birthDate", "consentVersion",
  ]),
  update: Object.freeze([
    "requestId", "op", "category", "description", "business", "community",
  ]),
  pause: Object.freeze(["requestId", "op"]),
  resume: Object.freeze(["requestId", "op"]),
  clearContact: Object.freeze(["requestId", "op"]),
});
const LEDGER_KINDS = Object.freeze({
  create: "pages.page.create.v1",
  update: "pages.page.update.v1",
  resume: "pages.page.resume.v1",
});

function exactManagePageInput(data) {
  requireObject(data);
  const op = data.op;
  if (typeof op !== "string" || !MANAGE_PAGE_OPS.includes(op)) {
    fail("invalid-argument", "op is invalid.");
  }
  const fields = MANAGE_PAGE_FIELDS[op];
  requireExactInput(data, fields, fields);
  const requestId = requireRequestId(data.requestId);
  if (op === "create") {
    if (data.consentVersion !== PAGE_CONSENT_VERSION) {
      fail("invalid-argument", "consentVersion is unsupported.");
    }
    if (data.birthDate !== null && typeof data.birthDate !== "string") {
      fail("invalid-argument", "birthDate must be text or null.");
    }
  }
  return { ...data, op, requestId };
}

function accountNotActive() {
  fail("permission-denied", "Your account is not active.");
}

function errorCode(error) {
  return typeof error?.code === "string" || Number.isSafeInteger(error?.code) ? error.code : null;
}

function refusalIsActive(snapshot, nowMs) {
  if (!snapshot?.exists) return false;
  const refusedAtMs = timestampMillis(snapshot.data()?.refusedAt);
  // A malformed refusal record fails closed until an operator removes it.
  if (refusedAtMs === null) return true;
  return nowMs - refusedAtMs < PAGE_ADULT_REFUSAL_COOLDOWN_MS;
}

function createPagesLifecycleService({
  firestore,
  TimestampImpl = Timestamp,
  clock = () => Date.now(),
  logger = defaultLogger,
  rateLimits = PAGES_LIFECYCLE_RATE_LIMITS,
  adultCheck = requireAdultBirthDate,
  followCarry = null,
}) {
  if (!firestore || typeof TimestampImpl?.fromMillis !== "function" ||
      typeof clock !== "function" || typeof adultCheck !== "function") {
    throw new TypeError("firestore, Timestamp, clock and adultCheck are required.");
  }
  const carry = followCarry ?? createPagesFollowCarryService({
    firestore, TimestampImpl, clock, logger,
  });

  function timing() {
    const nowMs = clock();
    if (!Number.isSafeInteger(nowMs) || nowMs < 0) {
      throw new TypeError("clock must return epoch milliseconds.");
    }
    return { nowMs, now: TimestampImpl.fromMillis(nowMs) };
  }

  // One small transaction over the one privateRateLimits row, committed
  // BEFORE the content transaction, so a refused request still costs.
  async function chargeRate(scope, uid, { nowMs, now }) {
    const reference = rateLimitReference(firestore, scope, uid);
    await firestore.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(reference);
      consumeRateLimit(transaction, snapshot, {
        reference,
        scope,
        uid,
        nowMs,
        now,
        ...rateLimits[scope],
      });
    });
  }

  function gate(snapshots, auth, nowMs) {
    const capability = derivePagesCapability(snapshots, {
      tokenRole: typeof auth.token?.role === "string" ? auth.token.role : null,
      now: nowMs,
    });
    if (!capability.allowed) throw pageAccessRequiredError();
    return capability;
  }

  // Common write preconditions (§2.2), from snapshots read in the caller's
  // transaction: an active account and no communication mute. The verified
  // e-mail was already required by requireActor.
  function assertWritePreconditions(userSnapshot, restrictionSnapshot, nowMs) {
    const user = userSnapshot?.exists ? (userSnapshot.data() ?? null) : null;
    if (!likersAccountIsActive(user)) accountNotActive();
    assertNotRestricted(restrictionSnapshot, "Your", nowMs);
    return user;
  }

  async function assertLinkedServer(transaction, uid, community) {
    const serverId = community?.linkedServerId ?? null;
    if (serverId === null) return;
    const snapshot = await transaction.get(firestore.doc(`clubs/${serverId}`));
    let server;
    try {
      server = canonicalServer(snapshot);
    } catch {
      throw PAGE_ERRORS.linkedServerInvalid();
    }
    if (!admitsPublicJoin(server) || server.ownerId !== uid) {
      throw PAGE_ERRORS.linkedServerInvalid();
    }
  }

  function publicPageName(publicSnapshot, uid) {
    canonicalPublicProfile(publicSnapshot, uid);
    const displayName = pageDisplayNameMirror(publicSnapshot.data().displayName);
    if (displayName === null) fail("data-loss", "The canonical public profile is malformed.");
    assertPageNameAllowed(displayName);
    return displayName;
  }

  function assertPublicProfile(user) {
    if (normalizeProfileVisibility(user.profileVisibility) !== "public") {
      throw PAGE_ERRORS.profileNotPublic();
    }
  }

  // ------------------------------------------------------------------ create

  async function adultEligibility({ uid, user, birthDate, timed }) {
    if (user?.creatorAgeVerified === true) return;
    const refusalRef = firestore.doc(`pageAdultRefusals/${uid}`);
    if (refusalIsActive(await refusalRef.get(), timed.nowMs)) {
      throw PAGE_ERRORS.adultRequired();
    }
    if (birthDate === null) {
      fail("invalid-argument", "birthDate is required.");
    }
    try {
      adultCheck(birthDate, timed.nowMs);
    } catch (error) {
      if (error?.code !== "failed-precondition") throw error;
      // Under 18: a dated record of the REFUSAL only, never of the date.
      await refusalRef.set({ schemaVersion: 1, refusedAt: timed.now });
      throw PAGE_ERRORS.adultRequired();
    }
  }

  async function create(auth, input, timed) {
    const uid = auth.uid;
    await chargeRate("pages.create", uid, timed);
    await assertPagesWriteEnabled({ db: firestore, uid, logger });
    const [userSnapshot, entitlementSnapshot, grantSnapshot] =
      await firestore.getAll(...pagesCapabilityReferences(firestore, uid));
    gate({ userSnapshot, entitlementSnapshot, grantSnapshot }, auth, timed.nowMs);
    await adultEligibility({
      uid,
      user: userSnapshot.exists ? userSnapshot.data() : null,
      birthDate: input.birthDate,
      timed,
    });
    const fields = validatePageFields(input);
    const identity = operationIdentity(LEDGER_KINDS.create, uid, input.requestId, {
      op: "create",
      kind: fields.kind,
      category: fields.category,
      description: fields.description,
      business: fields.business,
      community: fields.community,
      consentVersion: PAGE_CONSENT_VERSION,
      adultEligibility: true,
    });
    const pageRef = pageReference(firestore, uid);
    const publicRef = firestore.doc(`publicProfiles/${uid}`);
    const ledgerRef = firestore.doc(`integrityOperationLedgers/${identity.id}`);
    const outcome = await firestore.runTransaction(async (transaction) => {
      const [user, entitlement, grant, restriction, pageSnapshot, publicSnapshot,
        ledgerSnapshot, visibilitySnapshot] = await transactionGetAll(
        transaction,
        ...pagesCapabilityReferences(firestore, uid),
        firestore.doc(`restrictions/${uid}`),
        pageRef,
        publicRef,
        ledgerRef,
        pageVisibilityReference(firestore),
      );
      const profile = assertWritePreconditions(user, restriction, timed.nowMs);
      const prior = assertLedgerReplay(ledgerSnapshot, {
        kind: LEDGER_KINDS.create,
        uid,
        inputHash: identity.inputHash,
      });
      if (prior) return { result: prior, created: false };
      gate({ userSnapshot: user, entitlementSnapshot: entitlement, grantSnapshot: grant },
        auth, timed.nowMs);
      if (pageSnapshot.exists) throw PAGE_ERRORS.exists();
      assertPublicProfile(profile);
      const displayName = publicPageName(publicSnapshot, uid);
      // Followers never refuse a Page (ADR-234): they are carried over.
      await assertLinkedServer(transaction, uid, fields.community);

      // Every read is done; the writes follow.
      if (profile.creatorAudienceEnabled === true) {
        // A Page's followers are Page followers: the Creator audience (a
        // publicly listable edge set) closes in the same commit.
        transaction.update(firestore.doc(`users/${uid}`), { creatorAudienceEnabled: false });
        applyProjectionInTransaction(
          transaction,
          publicRef,
          publicSnapshot,
          derivePublicProfile(uid, { ...profile, creatorAudienceEnabled: false }),
          PUBLIC_PROFILE_FIELDS,
        );
      }
      const page = newPageDocument({ pageId: uid, fields, displayName, now: timed.now });
      const result = pageLifecycleResult(page);
      transaction.create(pageRef, page);
      applyPageVisibilityInTransaction(transaction, {
        db: firestore,
        snapshot: visibilitySnapshot,
        pageId: uid,
        page,
        now: timed.now,
        logger,
      });
      // Always written: edges, not the (possibly drifted) counter, decide.
      transaction.set(pageFollowCarryJobReference(firestore, uid), pageFollowCarryJobDocument({
        pageId: uid,
        now: timed.now,
        nextAttemptAt: TimestampImpl.fromMillis(timed.nowMs + PAGE_FOLLOW_CARRY_HANDOFF_MS),
      }));
      transaction.create(ledgerRef, ledgerData({
        kind: LEDGER_KINDS.create,
        uid,
        requestId: input.requestId,
        inputHash: identity.inputHash,
        result,
        now: timed.now,
      }));
      return { result, created: true };
    });
    if (outcome.created) {
      try {
        await carry.runJob(uid, { maxBatches: PAGE_FOLLOW_CARRY_LIMITS.createBatches });
      } catch (error) {
        // The job stays; pagesMaintenance carries the followers over.
        logger.warn("pages follow carry-over deferred", { code: errorCode(error) });
      }
    }
    return outcome.result;
  }

  // ------------------------------------------------------- update + resume

  async function ownerWrite(op, auth, input, timed, mutate) {
    const uid = auth.uid;
    await assertPagesWriteEnabled({ db: firestore, uid, logger });
    await chargeRate("pages.update", uid, timed);
    const hashed = op === "update"
      ? {
          op,
          category: input.category,
          description: input.description,
          business: input.business,
          community: input.community,
        }
      : { op };
    const identity = operationIdentity(LEDGER_KINDS[op], uid, input.requestId, hashed);
    const pageRef = pageReference(firestore, uid);
    const ledgerRef = firestore.doc(`integrityOperationLedgers/${identity.id}`);
    return firestore.runTransaction(async (transaction) => {
      const [user, entitlement, grant, restriction, pageSnapshot, publicSnapshot,
        ledgerSnapshot, visibilitySnapshot] = await transactionGetAll(
        transaction,
        ...pagesCapabilityReferences(firestore, uid),
        firestore.doc(`restrictions/${uid}`),
        pageRef,
        firestore.doc(`publicProfiles/${uid}`),
        ledgerRef,
        pageVisibilityReference(firestore),
      );
      const profile = assertWritePreconditions(user, restriction, timed.nowMs);
      const prior = assertLedgerReplay(ledgerSnapshot, {
        kind: LEDGER_KINDS[op],
        uid,
        inputHash: identity.inputHash,
      });
      if (prior) return prior;
      gate({ userSnapshot: user, entitlementSnapshot: entitlement, grantSnapshot: grant },
        auth, timed.nowMs);
      const page = canonicalPage(pageSnapshot, uid);
      if (page === null) throw PAGE_ERRORS.notFound();
      if (page.suspended) throw PAGE_ERRORS.suspended();

      const changes = await mutate({ transaction, page, profile, publicSnapshot });
      // The capability is live (the gate passed): a lapsed Page is restored.
      const next = {
        ...page,
        ...changes,
        ...restoredPageFields(page),
        updatedAt: timed.now,
      };
      next.listed = derivePageListed(next);
      const update = { ...changes, ...restoredPageFields(page), listed: next.listed,
        updatedAt: timed.now };
      transaction.update(pageRef, update);
      applyPageVisibilityInTransaction(transaction, {
        db: firestore,
        snapshot: visibilitySnapshot,
        pageId: uid,
        page: next,
        now: timed.now,
        logger,
      });
      const result = pageLifecycleResult(next);
      transaction.create(ledgerRef, ledgerData({
        kind: LEDGER_KINDS[op],
        uid,
        requestId: input.requestId,
        inputHash: identity.inputHash,
        result,
        now: timed.now,
      }));
      return result;
    });
  }

  function update(auth, input, timed) {
    return ownerWrite("update", auth, input, timed, async ({ transaction, page }) => {
      const fields = validatePageFields({
        kind: page.kind,
        category: input.category,
        description: input.description,
        business: input.business,
        community: input.community,
      });
      const priorServer = page.community?.linkedServerId ?? null;
      const nextServer = fields.community?.linkedServerId ?? null;
      // An unchanged link is not re-validated: the owner may still edit the
      // rest after the server went private (readers omit a non-public link).
      if (nextServer !== null && nextServer !== priorServer) {
        await assertLinkedServer(transaction, auth.uid, fields.community);
      }
      return {
        category: fields.category,
        description: fields.description,
        business: fields.business,
        community: fields.community,
      };
    });
  }

  function resume(auth, input, timed) {
    return ownerWrite("resume", auth, input, timed, async ({ profile, publicSnapshot }) => {
      assertPublicProfile(profile);
      publicPageName(publicSnapshot, auth.uid);
      return { ownerPaused: false };
    });
  }

  // ------------------------------------------------------------------ pause

  async function pause(auth, timed) {
    const uid = auth.uid;
    const pageRef = pageReference(firestore, uid);
    return firestore.runTransaction(async (transaction) => {
      const [pageSnapshot, visibilitySnapshot] = await transactionGetAll(
        transaction,
        pageRef,
        pageVisibilityReference(firestore),
      );
      const page = pageForSafetyAction(pageSnapshot, uid, logger);
      if (page === null) throw PAGE_ERRORS.notFound();
      const next = applyPagePauseInTransaction(transaction, {
        db: firestore,
        uid,
        page,
        visibilitySnapshot,
        now: timed.now,
        logger,
      });
      return pageLifecycleResult(next ?? page);
    });
  }

  // ----------------------------------------------------------- clearContact

  // Removes the public contact details of the caller's own Page (ADR-241).
  // The create consent promises "you can clear them any time", and an owner
  // whose Premium lapsed, whose Page is suspended or who is muted cannot
  // `update`: this op keeps the promise. It can only take public data away,
  // so it is a safety action like pause: one transaction over pages/{uid},
  // tolerant of a malformed Page, a write only when something is stored.
  async function clearContact(auth, timed) {
    const uid = auth.uid;
    const pageRef = pageReference(firestore, uid);
    return firestore.runTransaction(async (transaction) => {
      const pageSnapshot = await transaction.get(pageRef);
      const page = pageForSafetyAction(pageSnapshot, uid, logger);
      if (page === null) throw PAGE_ERRORS.notFound();
      const business = clearedPageContact(page);
      if (business === undefined) return pageLifecycleResult(page);
      transaction.update(pageRef, { business, updatedAt: timed.now });
      return pageLifecycleResult({ ...page, business });
    });
  }

  async function managePageV1(request) {
    // Only the safety actions (pause, clearContact) may run unverified;
    // every other op needs the verified e-mail the common write
    // preconditions require.
    const op = request?.data?.op;
    const auth = requireActor(request, { verified: !MANAGE_PAGE_SAFETY_OPS.includes(op) });
    const input = exactManagePageInput(request.data);
    const timed = timing();
    switch (input.op) {
      case "create": return create(auth, input, timed);
      case "update": return update(auth, input, timed);
      case "resume": return resume(auth, input, timed);
      case "pause": return pause(auth, timed);
      case "clearContact": return clearContact(auth, timed);
      default: return fail("invalid-argument", "op is invalid.");
    }
  }

  return Object.freeze({ managePageV1 });
}

let defaultService = null;
function service() {
  if (defaultService === null) {
    const { db } = require("../utils/firestore");
    defaultService = createPagesLifecycleService({ firestore: db });
  }
  return defaultService;
}

const managePageV1 = onCall(
  { region: REGION, enforceAppCheck: false },
  (request) => service().managePageV1(request),
);

module.exports = {
  MANAGE_PAGE_FIELDS,
  MANAGE_PAGE_OPS,
  MANAGE_PAGE_SAFETY_OPS,
  PAGE_ADULT_REFUSAL_COOLDOWN_MS,
  PAGES_LIFECYCLE_RATE_LIMITS,
  createPagesLifecycleService,
  exactManagePageInput,
  managePageV1,
};
