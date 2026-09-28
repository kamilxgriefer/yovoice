const { Timestamp } = require("firebase-admin/firestore");
const { onCall } = require("firebase-functions/v2/https");

const {
  activeProfile,
  consumeRateLimit,
  fail,
  rateLimitReference,
  requireActor,
} = require("../integrity/guards");
const { db } = require("../utils/firestore");

// "Hide my likes" (ADR-230). The setting is `likesHidden` on the PRIVATE
// users/{uid} document (owner-get only), next to `profileVisibility`, which
// set the precedent: a server-written field that is deliberately absent from
// the owner update allowlist in firestore.rules, so the only writer is this
// callable. Every likers list and Top reactions read users/{likerId} anyway,
// so honouring the setting costs no extra read.
//
// Deliberately NOT behind appConfig/likersV1: people must be able to opt out
// before any list is ever exposed.

const REGION = "europe-west1";
const LIKES_VISIBILITY_RATE_LIMIT = Object.freeze({
  maxEvents: 20,
  windowMs: 60 * 1000,
});
const LIKES_VISIBILITY_RATE_SCOPE = "likes.visibility";

function exactLikesHiddenInput(data) {
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    fail("invalid-argument", "A hidden flag is required.");
  }
  const keys = Object.keys(data);
  if (keys.length !== 1 || keys[0] !== "hidden" ||
      typeof data.hidden !== "boolean") {
    fail("invalid-argument", "hidden must be a boolean.");
  }
  return data.hidden;
}

// The stored value already equals the request. A missing field is the
// visible default, so asking to be visible changes nothing. A malformed
// stored value (read as HIDDEN by likesHiddenOf, fail closed) is never
// "unchanged": any request repairs it to a real boolean.
function storedLikesHiddenMatches(profile, hidden) {
  const stored = profile.likesHidden;
  if (stored === undefined) return hidden === false;
  return stored === hidden;
}

function createLikesVisibilityService({
  firestore,
  TimestampImpl = Timestamp,
  clock = () => Date.now(),
  rateLimit = LIKES_VISIBILITY_RATE_LIMIT,
}) {
  if (!firestore || typeof TimestampImpl?.fromMillis !== "function" ||
      typeof clock !== "function") {
    throw new TypeError("firestore, Timestamp and clock are required.");
  }

  async function setMyLikesHiddenV1(request) {
    // An opt-out is a privacy protection: it does not require a verified
    // e-mail, exactly like setMyProfileVisibility.
    const auth = requireActor(request, { verified: false });
    const hidden = exactLikesHiddenInput(request.data);
    const nowMs = clock();
    if (!Number.isSafeInteger(nowMs) || nowMs < 0) {
      throw new TypeError("clock must return epoch milliseconds.");
    }
    const now = TimestampImpl.fromMillis(nowMs);
    const profileRef = firestore.collection("users").doc(auth.uid);
    const rateRef = rateLimitReference(
      firestore,
      LIKES_VISIBILITY_RATE_SCOPE,
      auth.uid,
    );

    // A valid request consumes a private, server-time budget in its own
    // small transaction, even when the account then fails its active-state
    // check (the setMyProfileVisibility precedent).
    await firestore.runTransaction(async (transaction) => {
      const rateSnapshot = await transaction.get(rateRef);
      consumeRateLimit(transaction, rateSnapshot, {
        reference: rateRef,
        scope: LIKES_VISIBILITY_RATE_SCOPE,
        uid: auth.uid,
        nowMs,
        now,
        ...rateLimit,
      });
    });

    return firestore.runTransaction(async (transaction) => {
      const profileSnapshot = await transaction.get(profileRef);
      const profile = activeProfile(profileSnapshot, "Your");
      const changed = !storedLikesHiddenMatches(profile, hidden);
      if (changed) {
        transaction.update(profileRef, {
          likesHidden: hidden,
          likesHiddenUpdatedAt: now,
        });
      }
      return { hidden, changed };
    });
  }

  return Object.freeze({ setMyLikesHiddenV1 });
}

const service = createLikesVisibilityService({ firestore: db });

const setMyLikesHiddenV1 = onCall(
  { region: REGION, enforceAppCheck: false },
  service.setMyLikesHiddenV1,
);

module.exports = {
  LIKES_VISIBILITY_RATE_LIMIT,
  LIKES_VISIBILITY_RATE_SCOPE,
  createLikesVisibilityService,
  exactLikesHiddenInput,
  setMyLikesHiddenV1,
};
