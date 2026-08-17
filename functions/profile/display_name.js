const { getAuth } = require("firebase-admin/auth");
const { Timestamp } = require("firebase-admin/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");

const { requireAuthentication } = require("../utils/auth");
const { db } = require("../utils/firestore");
const {
  consumeRateLimit,
  rateLimitReference,
} = require("../integrity/guards");

const REGION = "europe-west1";
const DISPLAY_NAME_COOLDOWN_MS = 30 * 24 * 60 * 60 * 1000;
const DISPLAY_NAME_RATE_LIMIT = Object.freeze({
  maxEvents: 10,
  windowMs: 60 * 1000,
});
const DISPLAY_NAME_RATE_SCOPE = "profile.displayName";
const MIN_DISPLAY_NAME_CODE_POINTS = 2;
const MAX_DISPLAY_NAME_CODE_POINTS = 120;
const UNSAFE_DISPLAY_NAME_CHARACTERS = /[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]/u;

function exactDisplayNameInput(data) {
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    throw new HttpsError(
      "invalid-argument",
      "A display name is required.",
    );
  }
  const keys = Object.keys(data);
  if (keys.length !== 1 || keys[0] !== "displayName") {
    throw new HttpsError(
      "invalid-argument",
      "Only displayName may be supplied.",
    );
  }
  if (typeof data.displayName !== "string") {
    throw new HttpsError(
      "invalid-argument",
      "Display name must be text.",
    );
  }
  const displayName = data.displayName.trim();
  const length = [...displayName].length;
  if (
    length < MIN_DISPLAY_NAME_CODE_POINTS ||
    length > MAX_DISPLAY_NAME_CODE_POINTS ||
    UNSAFE_DISPLAY_NAME_CHARACTERS.test(displayName)
  ) {
    throw new HttpsError(
      "invalid-argument",
      "Display name must contain 2 to 120 visible characters.",
    );
  }
  return displayName;
}

function timestampMillis(value) {
  if (!value || typeof value.toMillis !== "function") return null;
  const milliseconds = value.toMillis();
  return Number.isSafeInteger(milliseconds) ? milliseconds : null;
}

function publicResult({ displayName, changed, changedAtMs, nowMs }) {
  const nextDisplayNameChangeAtMs = changedAtMs === null
    ? null
    : changedAtMs + DISPLAY_NAME_COOLDOWN_MS;
  return {
    displayName,
    changed,
    displayNameChangedAtMs: changedAtMs,
    nextDisplayNameChangeAtMs,
    canChange: nextDisplayNameChangeAtMs === null || nowMs >= nextDisplayNameChangeAtMs,
  };
}

function activeProfile(snapshot) {
  if (!snapshot.exists) {
    throw new HttpsError(
      "not-found",
      "Your profile does not exist.",
    );
  }
  const profile = snapshot.data() ?? {};
  if (
    profile.banned === true ||
    profile.disabled === true ||
    profile.deleted === true ||
    profile.status === "deleted"
  ) {
    throw new HttpsError(
      "permission-denied",
      "This account cannot change its display name.",
    );
  }
  return profile;
}

async function syncAuthDisplayName(auth, uid, displayName) {
  const user = await auth.getUser(uid);
  if (user.displayName !== displayName) {
    await auth.updateUser(uid, { displayName });
  }
}

async function defaultSyncAuthDisplayName(uid, displayName) {
  return syncAuthDisplayName(getAuth(), uid, displayName);
}

function createDisplayNameService({
  firestore,
  TimestampImpl = Timestamp,
  clock = () => Date.now(),
  syncAuthDisplayName = defaultSyncAuthDisplayName,
  rateLimit = DISPLAY_NAME_RATE_LIMIT,
}) {
  if (!firestore || typeof TimestampImpl?.fromMillis !== "function") {
    throw new TypeError("firestore and Timestamp are required.");
  }
  if (typeof clock !== "function" || typeof syncAuthDisplayName !== "function") {
    throw new TypeError("clock and syncAuthDisplayName must be functions.");
  }

  async function updateMyDisplayName(request) {
    const auth = requireAuthentication(request);
    if (auth.token?.email_verified !== true) {
      throw new HttpsError(
        "failed-precondition",
        "Verify your email before changing your display name.",
        { reason: "email-verification-required" },
      );
    }
    const displayName = exactDisplayNameInput(request.data);
    const nowMs = clock();
    if (!Number.isSafeInteger(nowMs) || nowMs < 0) {
      throw new TypeError("clock must return epoch milliseconds.");
    }
    const now = TimestampImpl.fromMillis(nowMs);
    const profileRef = firestore.collection("users").doc(auth.uid);
    const rateRef = rateLimitReference(
      firestore,
      DISPLAY_NAME_RATE_SCOPE,
      auth.uid,
    );

    // This is deliberately a separate first transaction. If quota lived in
    // the profile transaction, any later cooldown/integrity exception would
    // abort the counter write and rejected requests would be free. Validation
    // above is local; every valid request that reaches profile state consumes
    // the budget whether the profile decision succeeds or fails.
    await firestore.runTransaction(async (transaction) => {
      const rateSnapshot = await transaction.get(rateRef);
      consumeRateLimit(transaction, rateSnapshot, {
        reference: rateRef,
        scope: DISPLAY_NAME_RATE_SCOPE,
        uid: auth.uid,
        nowMs,
        now,
        ...rateLimit,
      });
    });

    const result = await firestore.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(profileRef);
      const profile = activeProfile(snapshot);
      const currentDisplayName = typeof profile.displayName === "string"
        ? profile.displayName
        : "";
      const storedChangedAt = profile.displayNameChangedAt;
      const changedAtMs = storedChangedAt === undefined
        ? null
        : timestampMillis(storedChangedAt);

      // A server-owned cooldown value with an invalid shape is an integrity
      // failure, never permission to silently reset the thirty-day window.
      if (storedChangedAt !== undefined && changedAtMs === null) {
        throw new HttpsError(
          "failed-precondition",
          "Display name change state is invalid.",
          { reason: "display-name-state-invalid" },
        );
      }

      // Retrying the same canonical name is always safe. It neither advances
      // the cooldown nor fails inside it, and the Auth mirror is retried below.
      if (currentDisplayName === displayName) {
        return publicResult({
          displayName,
          changed: false,
          changedAtMs,
          nowMs,
        });
      }

      const nextChangeAtMs = changedAtMs === null
        ? null
        : changedAtMs + DISPLAY_NAME_COOLDOWN_MS;
      if (nextChangeAtMs !== null && nowMs < nextChangeAtMs) {
        throw new HttpsError(
          "failed-precondition",
          "Display name can be changed once every 30 days.",
          {
            reason: "display-name-cooldown",
            nextDisplayNameChangeAtMs: nextChangeAtMs,
            retryAfterSeconds: Math.ceil((nextChangeAtMs - nowMs) / 1000),
          },
        );
      }

      transaction.update(profileRef, {
        displayName,
        displayNameChangedAt: now,
        profileUpdatedAt: now,
      });
      return publicResult({
        displayName,
        changed: true,
        changedAtMs: nowMs,
        nowMs,
      });
    });

    try {
      await syncAuthDisplayName(auth.uid, result.displayName);
    } catch (error) {
      if (error?.code === "auth/user-not-found") {
        throw new HttpsError(
          "failed-precondition",
          "The authenticated account no longer exists.",
          {
            reason: "auth-account-missing",
            displayName: result.displayName,
            displayNameChangedAtMs: result.displayNameChangedAtMs,
            nextDisplayNameChangeAtMs: result.nextDisplayNameChangeAtMs,
          },
        );
      }
      throw new HttpsError(
        "unavailable",
        "Display name was saved, but account identity sync is pending. Retry the same name.",
        {
          reason: "auth-display-name-sync-pending",
          displayName: result.displayName,
          displayNameChangedAtMs: result.displayNameChangedAtMs,
          nextDisplayNameChangeAtMs: result.nextDisplayNameChangeAtMs,
        },
      );
    }

    return result;
  }

  return Object.freeze({ updateMyDisplayName });
}

const service = createDisplayNameService({ firestore: db });

const updateMyDisplayName = onCall(
  { region: REGION, enforceAppCheck: false },
  service.updateMyDisplayName,
);

module.exports = {
  DISPLAY_NAME_COOLDOWN_MS,
  DISPLAY_NAME_RATE_LIMIT,
  MAX_DISPLAY_NAME_CODE_POINTS,
  MIN_DISPLAY_NAME_CODE_POINTS,
  createDisplayNameService,
  exactDisplayNameInput,
  syncAuthDisplayName,
  updateMyDisplayName,
};
