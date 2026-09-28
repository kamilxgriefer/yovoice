const { Timestamp } = require("firebase-admin/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");

const { consumeRateLimit, rateLimitReference } = require("../integrity/guards");
const {
  applyPagePauseInTransaction,
  pageForSafetyAction,
  pageReference,
  pageVisibilityReference,
} = require("../pages/hooks");
const { requireAuthentication } = require("../utils/auth");
const { db } = require("../utils/firestore");

const REGION = "europe-west1";
const PROFILE_VISIBILITIES = Object.freeze(["public", "friends", "private"]);
const PROFILE_VISIBILITY_RATE_LIMIT = Object.freeze({
  maxEvents: 20,
  windowMs: 60 * 1000,
});
const PROFILE_VISIBILITY_RATE_SCOPE = "profile.visibility";

function normalizeProfileVisibility(value, { legacyDefault = "public" } = {}) {
  if (value === undefined || value === null || value === "") {
    return legacyDefault;
  }
  return PROFILE_VISIBILITIES.includes(value) ? value : "private";
}

function exactVisibilityInput(data) {
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    throw new HttpsError("invalid-argument", "A profile visibility is required.");
  }
  const keys = Object.keys(data);
  if (keys.length !== 1 || keys[0] !== "visibility" ||
      typeof data.visibility !== "string" ||
      !PROFILE_VISIBILITIES.includes(data.visibility)) {
    throw new HttpsError(
      "invalid-argument",
      "Visibility must be public, friends or private.",
    );
  }
  return data.visibility;
}

function activeProfile(snapshot) {
  if (!snapshot.exists) {
    throw new HttpsError("not-found", "Your profile does not exist.");
  }
  const profile = snapshot.data() ?? {};
  if (profile.banned === true || profile.disabled === true ||
      profile.deleted === true || profile.status === "deleted") {
    throw new HttpsError(
      "permission-denied",
      "This account cannot change profile visibility.",
    );
  }
  return profile;
}

function createProfileVisibilityService({
  firestore,
  TimestampImpl = Timestamp,
  clock = () => Date.now(),
  rateLimit = PROFILE_VISIBILITY_RATE_LIMIT,
}) {
  if (!firestore || typeof TimestampImpl?.fromMillis !== "function" ||
      typeof clock !== "function") {
    throw new TypeError("firestore, Timestamp and clock are required.");
  }

  async function setMyProfileVisibility(request) {
    const auth = requireAuthentication(request);
    const visibility = exactVisibilityInput(request.data);
    const nowMs = clock();
    if (!Number.isSafeInteger(nowMs) || nowMs < 0) {
      throw new TypeError("clock must return epoch milliseconds.");
    }
    const now = TimestampImpl.fromMillis(nowMs);
    const profileRef = firestore.collection("users").doc(auth.uid);
    const consentRef = firestore.collection("marketingConsents").doc(auth.uid);
    const showcaseRef = firestore.collection("publicShowcase").doc("live");
    const showcaseControlRef = firestore
      .collection("privateShowcaseControl")
      .doc("live");
    const rateRef = rateLimitReference(
      firestore,
      PROFILE_VISIBILITY_RATE_SCOPE,
      auth.uid,
    );

    // Valid requests consume a private, server-time budget even when the
    // account later fails its active-state check. This contains callable and
    // transaction abuse without exposing quota state to the client.
    await firestore.runTransaction(async (transaction) => {
      const rateSnapshot = await transaction.get(rateRef);
      consumeRateLimit(transaction, rateSnapshot, {
        reference: rateRef,
        scope: PROFILE_VISIBILITY_RATE_SCOPE,
        uid: auth.uid,
        nowMs,
        now,
        ...rateLimit,
      });
    });

    const pageRef = pageReference(firestore, auth.uid);
    return firestore.runTransaction(async (transaction) => {
      const [profileSnapshot, showcaseSnapshot, showcaseControlSnapshot,
        pageSnapshot] = await transaction.getAll(
        profileRef,
        showcaseRef,
        showcaseControlRef,
        pageRef,
      );
      const profile = activeProfile(profileSnapshot);
      // Premium Pages (ADR-233 §2.2, D5): a running Page needs a public
      // profile. Leaving "public" PAUSES the Page in this same transaction;
      // it never refuses, because going private is a safety action. The
      // visibility index is read only when a pause will actually be written,
      // and before any write (Firestore transactions read first).
      const page = visibility === "public"
        ? null
        : pageForSafetyAction(pageSnapshot, auth.uid);
      const pageVisibilitySnapshot = page !== null && page.ownerPaused !== true
        ? await transaction.get(pageVisibilityReference(firestore))
        : null;
      const current = normalizeProfileVisibility(profile.profileVisibility);
      const changed = current !== visibility ||
        profile.profileVisibility !== visibility;

      if (changed) {
        transaction.update(profileRef, {
          profileVisibility: visibility,
          profileVisibilityUpdatedAt: now,
        });
      }

      if (visibility !== "public") {
        // Non-public app visibility is stronger than an older website opt-in.
        // Revoke that consent in the same transaction as the canonical value.
        transaction.set(consentRef, {
          schemaVersion: 1,
          showProfileOnWebsite: false,
          showActivityOnWebsite: false,
          updatedAt: now,
        });

        // publicShowcase intentionally stores no uid, so an individual row
        // cannot be safely identified for removal. Privacy wins over temporary
        // completeness: clear public people atomically, and the one-minute
        // scheduler repopulates the remaining eligible consented accounts.
        if (showcaseSnapshot.exists) {
          transaction.update(showcaseRef, { people: [] });
        }
        const storedGeneration = showcaseControlSnapshot.exists
          ? showcaseControlSnapshot.data()?.privacyGeneration
          : 0;
        const privacyGeneration = Number.isSafeInteger(storedGeneration) &&
          storedGeneration >= 0
          ? storedGeneration + 1
          : 1;
        // A publisher that began before this privacy change may still hold an
        // old computed person row. Moving this private generation in the same
        // transaction makes that stale publisher abort instead of re-inserting
        // the profile after the immediate people clear.
        transaction.set(showcaseControlRef, {
          privacyGeneration,
          updatedAt: now,
        });
      }

      if (pageVisibilitySnapshot !== null) {
        applyPagePauseInTransaction(transaction, {
          db: firestore,
          uid: auth.uid,
          page,
          visibilitySnapshot: pageVisibilitySnapshot,
          now,
        });
      }

      // The response keeps its exact two keys (installed clients parse it
      // strictly); the owner learns about the pause from pages/{uid}.
      return { visibility, changed };
    });
  }

  return Object.freeze({ setMyProfileVisibility });
}

const service = createProfileVisibilityService({ firestore: db });

const setMyProfileVisibility = onCall(
  { region: REGION, enforceAppCheck: false },
  service.setMyProfileVisibility,
);

module.exports = {
  PROFILE_VISIBILITIES,
  PROFILE_VISIBILITY_RATE_LIMIT,
  PROFILE_VISIBILITY_RATE_SCOPE,
  createProfileVisibilityService,
  exactVisibilityInput,
  normalizeProfileVisibility,
  setMyProfileVisibility,
};
