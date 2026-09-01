const crypto = require("node:crypto");

const { HttpsError } = require("firebase-functions/v2/https");
const { isValidOpaqueUid } = require("../achievements/identity");

const SAFE_ID = /^[A-Za-z0-9_-]{1,128}$/u;
const SAFE_REQUEST_ID = /^[A-Za-z0-9_-]{8,128}$/u;
const PUBLIC_PROFILE_KEYS = Object.freeze([
  "accountType",
  "bannerUrl",
  "bio",
  "country",
  "displayName",
  "displayNameSearch",
  "followerCount",
  "followingCount",
  "friendCount",
  "learningLanguages",
  "nativeLanguage",
  "photoUrl",
  "premiumIdentity",
  "schemaVersion",
  "spokenLanguages",
  "statusMessage",
  "uid",
  "updatedAt",
  "username",
  "usernameSearch",
  "website",
]);

function fail(code, message) {
  throw new HttpsError(code, message);
}

function requireActor(request, { verified = true } = {}) {
  const auth = request?.auth;
  if (!isValidOpaqueUid(auth?.uid)) {
    fail("unauthenticated", "Authentication is required.");
  }
  if (verified && auth.token?.email_verified !== true) {
    fail("failed-precondition", "Verify your email before continuing.");
  }
  return auth;
}

function requireObject(value, label = "data") {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    fail("invalid-argument", `${label} must be an object.`);
  }
  return value;
}

function requireExactInput(data, allowed, required = []) {
  requireObject(data);
  const allowedSet = new Set(allowed);
  const unknown = Object.keys(data).filter((key) => !allowedSet.has(key));
  if (unknown.length > 0) {
    fail("invalid-argument", `Unsupported field: ${unknown[0]}.`);
  }
  for (const field of required) {
    if (!Object.prototype.hasOwnProperty.call(data, field)) {
      fail("invalid-argument", `${field} is required.`);
    }
  }
  return data;
}

function requireId(value, label = "id") {
  if (typeof value !== "string" || !SAFE_ID.test(value)) {
    fail("invalid-argument", `${label} is invalid.`);
  }
  return value;
}

function requireUid(value, label = "user id") {
  if (!isValidOpaqueUid(value)) {
    fail("invalid-argument", `${label} is invalid.`);
  }
  return value;
}

function requireRequestId(value) {
  if (typeof value !== "string" || !SAFE_REQUEST_ID.test(value)) {
    fail("invalid-argument", "requestId must be 8-128 safe characters.");
  }
  return value;
}

function requireBoolean(value, label) {
  if (typeof value !== "boolean") {
    fail("invalid-argument", `${label} must be a boolean.`);
  }
  return value;
}

function normalizeText(value, maxLength, label, { allowEmpty = false } = {}) {
  if (typeof value !== "string") {
    fail("invalid-argument", `${label} must be text.`);
  }
  const normalized = value.trim();
  if (
    (!allowEmpty && normalized.length === 0) ||
    normalized.length > maxLength
  ) {
    fail(
      "invalid-argument",
      `${label} must contain ${allowEmpty ? "0" : "1"}-${maxLength} characters.`,
    );
  }
  return normalized;
}

function requireSafeInteger(value, label, { min = 0, max = undefined } = {}) {
  if (
    !Number.isSafeInteger(value) ||
    value < min ||
    (max !== undefined && value > max)
  ) {
    fail("invalid-argument", `${label} is invalid.`);
  }
  return value;
}

function canonicalPair(firstId, secondId) {
  requireUid(firstId, "first user id");
  requireUid(secondId, "second user id");
  if (firstId === secondId) {
    fail("invalid-argument", "A direct conversation needs two users.");
  }
  // Firebase Auth UIDs are opaque and case-sensitive. Do not use
  // localeCompare here: locale/ICU ordering can differ from the code-unit
  // ordering used by object-key validation and can even vary by runtime.
  return [firstId, secondId].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
}

function stableValue(value) {
  if (Array.isArray(value)) return value.map(stableValue);
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.keys(value)
        .sort()
        .map((key) => [key, stableValue(value[key])]),
    );
  }
  return value;
}

function digest(...parts) {
  const body = parts
    .map((part) =>
      typeof part === "string" ? part : JSON.stringify(stableValue(part)),
    )
    .join("\u0000");
  return crypto.createHash("sha256").update(body).digest("hex");
}

function operationIdentity(kind, uid, requestId, input) {
  return {
    id: digest("operation", kind, uid, requestId),
    inputHash: digest("input", kind, uid, requestId, input),
  };
}

function activeProfile(snapshot, label) {
  if (!snapshot?.exists) {
    fail("not-found", `${label} profile does not exist.`);
  }
  const profile = snapshot.data() ?? {};
  if (
    profile.banned === true ||
    profile.disabled === true ||
    profile.deleted === true ||
    profile.status === "deleted" ||
    profile.authDeletedAt !== null && profile.authDeletedAt !== undefined
  ) {
    fail("permission-denied", `${label} account is not active.`);
  }
  return profile;
}

function timestampMillis(value) {
  if (value === null || value === undefined) return null;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  return null;
}

function restrictionIsActive(data, nowMs = Date.now()) {
  if (!data || data.type !== "communicationMute") return false;
  if (data.expiresAt === null || data.expiresAt === undefined) return true;
  const expiresAt = timestampMillis(data.expiresAt);
  return expiresAt === null || expiresAt > nowMs;
}

function assertNotRestricted(snapshot, label, nowMs) {
  if (snapshot?.exists && restrictionIsActive(snapshot.data(), nowMs)) {
    fail("permission-denied", `${label} account cannot communicate right now.`);
  }
}

function assertNotBlocked(firstSnapshot, secondSnapshot) {
  if (firstSnapshot?.exists || secondSnapshot?.exists) {
    fail(
      "failed-precondition",
      "This action is unavailable because of a block.",
    );
  }
}

function canonicalPublicProfile(publicSnapshot, expectedUid) {
  requireUid(expectedUid, "public profile uid");
  if (!publicSnapshot?.exists) {
    fail("failed-precondition", "The canonical public profile is unavailable.");
  }
  const publicProfile = publicSnapshot.data() ?? {};
  const keys = Object.keys(publicProfile).sort();
  if (
    keys.length !== PUBLIC_PROFILE_KEYS.length ||
    keys.some((key, index) => key !== PUBLIC_PROFILE_KEYS[index]) ||
    publicProfile.schemaVersion !== 1 ||
    publicProfile.uid !== expectedUid ||
    timestampMillis(publicProfile.updatedAt) === null ||
    typeof publicProfile.displayName !== "string" ||
    publicProfile.displayName !== publicProfile.displayName.trim() ||
    publicProfile.displayName.length < 1 ||
    publicProfile.displayName.length > 120
  ) {
    fail("data-loss", "The canonical public profile is malformed.");
  }
  const photoCandidate = publicProfile.photoUrl;
  if (photoCandidate !== null) {
    if (
      typeof photoCandidate !== "string" ||
      photoCandidate !== photoCandidate.trim() ||
      photoCandidate.length > 2048
    ) {
      fail("data-loss", "The canonical public profile photo is malformed.");
    }
    try {
      if (new URL(photoCandidate).protocol !== "https:") {
        fail("data-loss", "The canonical public profile photo is malformed.");
      }
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      fail("data-loss", "The canonical public profile photo is malformed.");
    }
  }
  return {
    displayName: publicProfile.displayName.slice(0, 80),
    // Identity snapshots carry uid + name only. Renderers resolve private
    // artwork through a viewer-authorized, short-lived media grant.
    photoUrl: null,
  };
}

function nonNegativeCount(value, label) {
  if (!Number.isSafeInteger(value) || value < 0) {
    fail("data-loss", `${label} is not a valid canonical counter.`);
  }
  return value;
}

function incrementCanonicalCount(value, label) {
  const count = nonNegativeCount(value, label);
  if (count === Number.MAX_SAFE_INTEGER) {
    fail("data-loss", `${label} cannot be incremented safely.`);
  }
  return count + 1;
}

function assertLedgerReplay(snapshot, { kind, uid, inputHash }) {
  if (!snapshot?.exists) return null;
  const data = snapshot.data() ?? {};
  if (
    data.kind !== kind ||
    data.ownerId !== uid ||
    data.inputHash !== inputHash ||
    !data.result ||
    typeof data.result !== "object"
  ) {
    fail("already-exists", "requestId was already used for another operation.");
  }
  return data.result;
}

function ledgerData({ kind, uid, requestId, inputHash, result, now }) {
  return {
    schemaVersion: 1,
    kind,
    ownerId: uid,
    requestId,
    inputHash,
    result,
    createdAt: now,
  };
}

function rateLimitReference(db, scope, uid) {
  return db.doc(`privateRateLimits/${digest("rate", scope, uid)}`);
}

function consumeRateLimit(
  transaction,
  snapshot,
  { reference, scope, uid, nowMs, now, maxEvents, windowMs },
) {
  requireSafeInteger(maxEvents, "maxEvents", { min: 1, max: 10000 });
  requireSafeInteger(windowMs, "windowMs", { min: 1000 });
  const data = snapshot?.exists ? (snapshot.data() ?? {}) : {};
  const priorStart = timestampMillis(data.windowStartedAt);
  const sameWindow =
    data.ownerId === uid &&
    data.scope === scope &&
    Number.isFinite(priorStart) &&
    nowMs >= priorStart &&
    nowMs - priorStart < windowMs;
  const priorCount = sameWindow ? data.count : 0;
  if (!Number.isSafeInteger(priorCount) || priorCount < 0) {
    fail("data-loss", "The private rate-limit state is invalid.");
  }
  if (priorCount >= maxEvents) {
    fail("resource-exhausted", "Too many requests. Please try again later.");
  }
  transaction.set(reference, {
    schemaVersion: 1,
    ownerId: uid,
    scope,
    windowStartedAt: sameWindow ? data.windowStartedAt : now,
    count: priorCount + 1,
    updatedAt: now,
  });
}

async function transactionGetAll(transaction, ...references) {
  if (typeof transaction.getAll === "function") {
    return transaction.getAll(...references);
  }
  const results = [];
  for (const reference of references) {
    results.push(await transaction.get(reference));
  }
  return results;
}

module.exports = {
  SAFE_ID,
  activeProfile,
  assertLedgerReplay,
  assertNotBlocked,
  assertNotRestricted,
  canonicalPair,
  canonicalPublicProfile,
  consumeRateLimit,
  digest,
  fail,
  incrementCanonicalCount,
  isValidOpaqueUid,
  ledgerData,
  nonNegativeCount,
  normalizeText,
  operationIdentity,
  rateLimitReference,
  requireActor,
  requireBoolean,
  requireExactInput,
  requireId,
  requireObject,
  requireRequestId,
  requireSafeInteger,
  requireUid,
  restrictionIsActive,
  timestampMillis,
  transactionGetAll,
};
