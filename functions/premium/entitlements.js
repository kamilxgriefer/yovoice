const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { Timestamp, FieldValue } = require("firebase-admin/firestore");
const { logger } = require("firebase-functions/v2");

const { db } = require("../utils/firestore");
const { requireUserManager } = require("../utils/auth");

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

/**
 * The single writer for `entitlements/{uid}` — the trusted subscription
 * document. firestore.rules denies ALL client writes to this collection
 * (and clients can only read their own), so nothing a modified client
 * does can grant itself premium. The public, cosmetic mirror
 * `users/{uid}.premiumIdentity` is also written only here; it is
 * deliberately absent from the client-writable field allowlist in
 * firestore.rules.
 */
async function applyEntitlements(uid, { plan, status, currentPeriodEnd, source }) {
  const premiumActive =
    ACTIVE_STATUSES.includes(status) &&
    currentPeriodEnd instanceof Timestamp &&
    currentPeriodEnd.toMillis() > Date.now();

  const entitlements = {
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
    updatedAt: FieldValue.serverTimestamp(),
  };

  const batch = db.batch();
  batch.set(db.collection("entitlements").doc(uid), entitlements, {
    merge: true,
  });
  batch.set(
    db.collection("users").doc(uid),
    { premiumIdentity: premiumActive },
    { merge: true },
  );
  await batch.commit();

  logger.info("entitlements applied", { uid, plan, status, premiumActive });
  return entitlements;
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
  { region: REGION },
  async (request) => {
    requireUserManager(request);

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

/**
 * Daily sweep: the authoritative premium check is time-based
 * (currentPeriodEnd), so expiry needs no job — but the cosmetic
 * users/{uid}.premiumIdentity mirror would otherwise linger after
 * expiry. This keeps the visible ring honest within a day of lapse.
 */
const expirePremiumIdentity = onSchedule(
  { region: REGION, schedule: "every 24 hours" },
  async () => {
    const now = Timestamp.now();
    const stale = await db
      .collection("entitlements")
      .where("isPremium", "==", true)
      .where("currentPeriodEnd", "<", now)
      .get();

    if (stale.empty) return;

    const batch = db.batch();
    for (const doc of stale.docs) {
      batch.set(
        doc.ref,
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
      batch.set(
        db.collection("users").doc(doc.id),
        { premiumIdentity: false },
        { merge: true },
      );
    }
    await batch.commit();
    logger.info("premium identity expired", { count: stale.size });
  },
);

module.exports = {
  adminSetPremiumEntitlements,
  verifyPurchase,
  expirePremiumIdentity,
  applyEntitlements,
};
