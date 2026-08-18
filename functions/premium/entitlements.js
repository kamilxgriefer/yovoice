const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { Timestamp, FieldValue } = require("firebase-admin/firestore");
const { logger } = require("firebase-functions/v2");

const { db } = require("../utils/firestore");
const { requireProtectedOwner } = require("../utils/auth");

const REGION = "europe-west1";

const PLANS = Object.freeze({
  MONTHLY: "monthly",
  YEARLY: "yearly",
  NONE: "none",
});

// Entitlement statuses the client/rules treat as premium-active. "grace"
// covers billing-retry windows so a failed card doesn't instantly strip
// identity/creator access mid-cycle.
const ACTIVE_STATUSES = Object.freeze(["active", "trialing", "grace"]);

const DEFAULT_MAX_OWNED_CLUBS = 3;
// Each expired entitlement produces three writes (entitlement + public user
// mirror + removal of a Creator pin). 150 keeps every transaction below
// Firestore's 500-write ceiling while still amortising query overhead.
const PREMIUM_EXPIRY_PAGE_SIZE = 150;
const MAX_PREMIUM_EXPIRY_PAGES = 50;

/**
 * The single writer for `entitlements/{uid}` — the trusted subscription
 * document. firestore.rules denies ALL client writes to this collection
 * (and clients can only read their own), so nothing a modified client
 * does can grant itself premium. The public, cosmetic mirror
 * `users/{uid}.premiumIdentity` is also written only here; it is
 * deliberately absent from the client-writable field allowlist in
 * firestore.rules.
 */
async function applyEntitlements(
  uid,
  {
    plan,
    status,
    currentPeriodEnd,
    source,
    cancelAtPeriodEnd = false,
  },
) {
  const entitlementData = buildEntitlements({
    plan,
    status,
    currentPeriodEnd,
    source,
    cancelAtPeriodEnd,
  });
  const premiumActive = entitlementData.isPremium;

  const userRef = db.collection("users").doc(uid);
  await db.runTransaction(async (transaction) => {
    const userSnapshot = await transaction.get(userRef);
    applyEntitlementsInTransaction(transaction, uid, entitlementData, {
      user: userSnapshot.data() ?? {},
    });
  });

  logger.info("entitlements applied", { uid, plan, status, premiumActive });
  return entitlementData;
}

function buildEntitlements({
  plan,
  status,
  currentPeriodEnd,
  source,
  cancelAtPeriodEnd = false,
}) {
  const premiumActive =
    ACTIVE_STATUSES.includes(status) &&
    currentPeriodEnd instanceof Timestamp &&
    currentPeriodEnd.toMillis() > Date.now();

  return {
    plan,
    status,
    currentPeriodEnd,
    // Derived entitlements. One Premium subscription drives all of them
    // today; future tiers can vary these independently without schema
    // changes.
    isPremium: premiumActive,
    creatorEnabled: premiumActive,
    canCreateClubs: premiumActive,
    premiumIdentityEnabled: premiumActive,
    maxOwnedClubs: DEFAULT_MAX_OWNED_CLUBS,
    source: source ?? "unknown",
    // Billing lifecycle truth for first-party billing surfaces. Admin grants
    // have a validity end but no renewal/cancellation lifecycle. Stripe
    // webhooks set this from the canonical Subscription object.
    cancelAtPeriodEnd: source === "stripe" && cancelAtPeriodEnd === true,
    renewalBehavior:
      source === "stripe" && premiumActive
        ? cancelAtPeriodEnd === true
          ? "ends"
          : "renews"
        : "none",
    updatedAt: FieldValue.serverTimestamp(),
  };
}

function applyEntitlementsInTransaction(
  transaction,
  uid,
  entitlements,
  { user = {}, firestore = db, writeUserProjection = true } = {},
) {
  const premiumActive = entitlements.isPremium === true;
  const entitlementRef = firestore.collection("entitlements").doc(uid);
  const userRef = firestore.collection("users").doc(uid);
  const pinnedPostRef = firestore.collection("creatorPinnedPosts").doc(uid);
  transaction.set(entitlementRef, entitlements, { merge: true });
  // A late provider event must never recreate a deleted/missing profile.
  // The server-only entitlement and billing ledger still reconcile so
  // refunds/cancellation remain auditable and idempotent.
  if (writeUserProjection) {
    transaction.set(
      userRef,
      {
        premiumIdentity: premiumActive,
        // Creator is a paid account mode. Revocation/refund must remove it
        // in the same commit as the entitlement, while server-owned Official
        // accounts remain Official.
        ...(premiumActive !== true && user.accountType === "creator"
          ? { accountType: "personal" }
          : {}),
      },
      { merge: true },
    );
  }
  if (!premiumActive) transaction.delete(pinnedPostRef);
}

/**
 * Admin/testing grant path — the only way to activate Premium until the
 * store billing adapters are configured. Guarded by the same
 * admin/superAdmin role check the rest of the admin surface uses.
 *
 * data: { uid, plan: 'monthly'|'yearly'|'none', days?: number }
 * plan 'none' revokes.
 */
const adminSetPremiumEntitlements = onCall(
  {
    region: REGION,
    secrets: ["YOVOICE_PROTECTED_OWNER_UID"],
  },
  async (request) => {
    // Paid capability grants are ownership-level writes. A stale or
    // separately assigned superAdmin claim must never mint Premium.
    await requireProtectedOwner(request);

    const uid = String(request.data?.uid ?? "").trim();
    const plan = String(request.data?.plan ?? "").trim();

    if (!uid) {
      throw new HttpsError("invalid-argument", "uid is required.");
    }
    if (![PLANS.MONTHLY, PLANS.YEARLY, PLANS.NONE].includes(plan)) {
      throw new HttpsError(
        "invalid-argument",
        "plan must be monthly, yearly or none.",
      );
    }

    if (plan === PLANS.NONE) {
      return applyEntitlements(uid, {
        plan: PLANS.NONE,
        status: "expired",
        currentPeriodEnd: Timestamp.now(),
        source: "admin",
      });
    }

    const defaultDays = plan === PLANS.YEARLY ? 365 : 30;
    const days = Number.isFinite(Number(request.data?.days))
      ? Math.min(Math.max(Number(request.data.days), 1), 400)
      : defaultDays;

    return applyEntitlements(uid, {
      plan,
      status: "active",
      currentPeriodEnd: Timestamp.fromMillis(
        Date.now() + days * 24 * 60 * 60 * 1000,
      ),
      source: "admin",
    });
  },
);

/**
 * Purchase verification entry point for the mobile/web clients.
 *
 * Deliberately fails until real store verification is configured — the
 * one thing this function must never do is trust the client's word that
 * a purchase happened. Wiring this up requires (per platform):
 *  - App Store: App Store Server API key (Issuer ID, Key ID, .p8) and
 *    transaction verification against the signed JWS payload.
 *  - Play: a service account with androidpublisher scope and
 *    purchases.subscriptionsv2.get verification.
 *  - Web (e.g. Stripe): webhook-driven activation, not client calls.
 * Each adapter should end by calling applyEntitlements() with the
 * verified period end — nothing else changes.
 */
const verifyPurchase = onCall({ region: REGION }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in first.");
  }
  logger.warn("verifyPurchase called but no store adapter is configured", {
    uid,
    platform: request.data?.platform,
  });
  throw new HttpsError(
    "failed-precondition",
    "Purchases are not enabled yet. Premium is coming soon.",
  );
});

async function fetchExpiredPremiumPage({ now, limit }) {
  const snapshot = await db
    .collection("entitlements")
    .where("isPremium", "==", true)
    .where("currentPeriodEnd", "<", now)
    .limit(limit)
    .get();
  return snapshot.docs;
}

async function commitExpiredPremiumPage(documents, { now }) {
  if (documents.length === 0) return 0;
  return db.runTransaction(async (transaction) => {
    // Re-read inside the transaction so a concurrent verified renewal cannot
    // be overwritten by a sweep that queried the old expiry milliseconds
    // earlier. Firestore retries this transaction on any concurrent change.
    const entitlementRefs = documents.map((document) => document.ref);
    const userRefs = documents.map((document) =>
      db.collection("users").doc(document.id),
    );
    const snapshots = await transaction.getAll(
      ...entitlementRefs,
      ...userRefs,
    );
    const currentDocuments = snapshots.slice(0, entitlementRefs.length);
    const currentUsers = snapshots.slice(entitlementRefs.length);
    let expired = 0;
    for (let index = 0; index < currentDocuments.length; index += 1) {
      const document = currentDocuments[index];
      const data = document.data() ?? {};
      const periodEndMillis = data.currentPeriodEnd?.toMillis?.();
      if (
        data.isPremium !== true ||
        !Number.isFinite(periodEndMillis) ||
        periodEndMillis >= now.toMillis()
      ) {
        continue;
      }
      transaction.set(
        document.ref,
        {
          isPremium: false,
          creatorEnabled: false,
          canCreateClubs: false,
          premiumIdentityEnabled: false,
          status: "expired",
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      transaction.delete(
        db.collection("creatorPinnedPosts").doc(document.id),
      );
      const user = currentUsers[index]?.data() ?? {};
      transaction.set(
        db.collection("users").doc(document.id),
        {
          premiumIdentity: false,
          ...(user.accountType === "creator"
            ? { accountType: "personal" }
            : {}),
        },
        { merge: true },
      );
      expired += 1;
    }
    return expired;
  });
}

/**
 * Drains expired Premium projections in bounded pages. The query repeats
 * without a cursor because every committed page leaves the predicate
 * (`isPremium == true`) atomically; this also makes a retry resume naturally.
 */
async function expirePremiumIdentityPages({
  now = Timestamp.now(),
  pageSize = PREMIUM_EXPIRY_PAGE_SIZE,
  maxPages = MAX_PREMIUM_EXPIRY_PAGES,
  fetchPage = fetchExpiredPremiumPage,
  commitPage = commitExpiredPremiumPage,
} = {}) {
  if (
    !Number.isInteger(pageSize) ||
    pageSize < 1 ||
    pageSize > PREMIUM_EXPIRY_PAGE_SIZE
  ) {
    throw new TypeError(`pageSize must be between 1 and ${PREMIUM_EXPIRY_PAGE_SIZE}.`);
  }
  if (!Number.isInteger(maxPages) || maxPages < 1) {
    throw new TypeError("maxPages must be a positive integer.");
  }

  let expiredCount = 0;
  let pages = 0;
  let lastPageWasFull = false;

  while (pages < maxPages) {
    const documents = await fetchPage({ now, limit: pageSize });
    if (!Array.isArray(documents) || documents.length === 0) {
      lastPageWasFull = false;
      break;
    }
    if (documents.length > pageSize) {
      throw new Error("Premium expiry source exceeded its bounded page size.");
    }
    const committed = await commitPage(documents, { now });
    expiredCount += Number.isFinite(committed)
      ? committed
      : documents.length;
    pages += 1;
    lastPageWasFull = documents.length === pageSize;
    if (!lastPageWasFull) break;
  }

  // At the invocation cap, one bounded probe distinguishes an exactly-full
  // final page from actual remaining work. Access is still time-gated by the
  // authoritative entitlement; only the public identity mirror is delayed.
  let truncated = false;
  if (pages === maxPages && lastPageWasFull) {
    const remaining = await fetchPage({ now, limit: 1 });
    truncated = Array.isArray(remaining) && remaining.length > 0;
  }

  return { expiredCount, pages, truncated };
}

/**
 * Daily sweep: the authoritative premium check is time-based
 * (currentPeriodEnd), so expiry needs no job — but the cosmetic
 * users/{uid}.premiumIdentity mirror would otherwise linger after
 * expiry. This keeps the visible ring honest within a day of lapse.
 */
const expirePremiumIdentity = onSchedule(
  {
    region: REGION,
    schedule: "every 24 hours",
    timeoutSeconds: 300,
    memory: "512MiB",
  },
  async () => {
    const outcome = await expirePremiumIdentityPages();
    if (outcome.expiredCount > 0) {
      logger.info("premium identity expired", outcome);
    }
    if (outcome.truncated) {
      logger.warn("premium expiry sweep reached its invocation bound", outcome);
    }
  },
);

module.exports = {
  adminSetPremiumEntitlements,
  verifyPurchase,
  expirePremiumIdentity,
  expirePremiumIdentityPages,
  fetchExpiredPremiumPage,
  commitExpiredPremiumPage,
  PREMIUM_EXPIRY_PAGE_SIZE,
  MAX_PREMIUM_EXPIRY_PAGES,
  applyEntitlements,
  buildEntitlements,
  applyEntitlementsInTransaction,
};
