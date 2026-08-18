const { getAuth } = require("firebase-admin/auth");
const { onCall, HttpsError } = require("firebase-functions/v2/https");

const { requireAuthentication } = require("../utils/auth");

const REGION = "europe-west1";
const RECENT_AUTH_MAX_AGE_SECONDS = 10 * 60;
const FIREBASE_ID_TOKEN_MAX_AGE_SECONDS = 60 * 60;

function requireEmptyInput(data) {
  if (
    data === undefined ||
    data === null ||
    (typeof data === "object" &&
      !Array.isArray(data) &&
      Object.keys(data).length === 0)
  ) {
    return;
  }
  throw new HttpsError(
    "invalid-argument",
    "This action does not accept any input fields.",
  );
}

function requireRecentAuthentication(auth, nowSeconds) {
  const authTime = auth.token?.auth_time;
  if (
    !Number.isSafeInteger(authTime) ||
    !Number.isSafeInteger(nowSeconds) ||
    authTime < 0 ||
    nowSeconds < authTime ||
    nowSeconds - authTime > RECENT_AUTH_MAX_AGE_SECONDS
  ) {
    throw new HttpsError(
      "failed-precondition",
      "Sign in again before signing out every device.",
      { reason: "recent-authentication-required" },
    );
  }
}

function createSessionManagementService({
  auth,
  clock = () => Date.now(),
}) {
  if (!auth || typeof auth.revokeRefreshTokens !== "function") {
    throw new TypeError("An Auth service with revokeRefreshTokens is required.");
  }
  if (typeof clock !== "function") {
    throw new TypeError("clock must be a function.");
  }

  async function revokeMyRefreshTokens(request) {
    const caller = requireAuthentication(request);
    requireEmptyInput(request.data);

    const nowMs = clock();
    if (!Number.isSafeInteger(nowMs) || nowMs < 0) {
      throw new TypeError("clock must return epoch milliseconds.");
    }
    requireRecentAuthentication(caller, Math.floor(nowMs / 1000));

    try {
      await auth.revokeRefreshTokens(caller.uid);
    } catch (_) {
      // Never forward Admin SDK detail to a client. It can contain project or
      // provider state and does not give the account owner a recovery action.
      throw new HttpsError(
        "unavailable",
        "YO Voice could not sign out your other devices. Try again.",
      );
    }

    return {
      revoked: true,
      // Firebase revokes account-wide refresh tokens. Already-issued ID
      // tokens are stateless and can remain valid until their one-hour
      // lifetime ends, so the client must not promise immediate eviction.
      completeWithinSeconds: FIREBASE_ID_TOKEN_MAX_AGE_SECONDS,
    };
  }

  return Object.freeze({ revokeMyRefreshTokens });
}

const revokeMyRefreshTokens = onCall(
  { region: REGION, enforceAppCheck: false },
  async (request) => createSessionManagementService({ auth: getAuth() })
    .revokeMyRefreshTokens(request),
);

module.exports = {
  FIREBASE_ID_TOKEN_MAX_AGE_SECONDS,
  RECENT_AUTH_MAX_AGE_SECONDS,
  createSessionManagementService,
  requireEmptyInput,
  requireRecentAuthentication,
  revokeMyRefreshTokens,
};
