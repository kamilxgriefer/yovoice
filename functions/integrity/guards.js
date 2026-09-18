const crypto = require("node:crypto");

const { HttpsError } = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const { isValidOpaqueUid } = require("../achievements/identity");

const SAFE_ID = /^[A-Za-z0-9_-]{1,128}$/u;
const SAFE_REQUEST_ID = /^[A-Za-z0-9_-]{8,128}$/u;
const PUBLIC_PROFILE_KEYS = Object.freeze([
  "accountType",
  "bannerUrl",
  "bio",
  "country",
  "creatorAudienceVisible",
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
const LEGACY_PUBLIC_PROFILE_KEYS = Object.freeze(
  PUBLIC_PROFILE_KEYS.filter((key) => key !== "creatorAudienceVisible"),
);

// The two "this should be impossible" refusal codes. Every other code is an
// ordinary, expected outcome (a block, a quota, a bad argument) and stays
// silent so the signal below keeps meaning something.
const SILENT_FAILURE_CODES = new Set(["data-loss", "internal"]);

// `fail()` is the single refusal primitive of this backend (~300 call sites in
// ~40 modules). The callable framework logs nothing for an explicitly thrown
// HttpsError, so a `data-loss` or `internal` refusal reached the caller with
// zero server-side evidence — which is exactly how the 2026-09-14 publicProfiles
// skew stayed invisible for 2.2 days. Logging here, rather than at the call
// sites, makes the single refusal primitive the single refusal signal and
// cannot drift when someone adds call site 301.
//
// `message` is a static, author-written English string at every call site, so
// it carries no user data by construction; that is what makes central logging
// privacy-safe. `fn` comes from the Cloud Run environment, so nothing has to be
// threaded through the 300 callers.
function fail(code, message) {
  if (SILENT_FAILURE_CODES.has(code)) {
    logger.warn("integrity refusal", {
      code,
      reason: message,
      fn: process.env.FUNCTION_TARGET ?? process.env.K_SERVICE ?? null,
    });
  }
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

// Every writer of an identity snapshot stores the name this returns
// (reelUploadReservations.authorName, reels.authorName, reelComments.authorName,
// voiceMoments.authorName, conversations.participantNames). The strict readers
// among those — validateReservation, validatePublishedReel,
// validateReelVoiceCommentReservation — assert `value === value.trim()` and
// `length <= 80` UTF-16 code units, and refuse with `data-loss` otherwise. A
// profile name of 81-120 characters whose 80th character is whitespace used to
// be cut to an untrimmed string here, so the reservation was written
// successfully and every later finalize of that draft failed forever.
// Re-trimming after the cut, and asserting the reader's own bound on the
// result, satisfies "assert the bound at every writer" once instead of at nine
// call sites.
//
// Two properties this function owns, because the bound is measured in UTF-16
// code units while a display name is chosen in code points:
//
//  * The cut is taken back to the last WHOLE code point. Slicing at 80 units
//    can land between a surrogate pair, and the lone high surrogate that
//    leaves is not encodable as UTF-8 — @protobufjs/utf8 writes replacement
//    bytes for it, so the value Firestore stores would no longer be the value
//    this guard checked, and a later read of the same row would refuse.
//  * The input is trimmed BEFORE the cut as well as after, so leading
//    whitespace cannot spend part of the budget and a projection that carries
//    trailing whitespace is repaired here rather than refused upstream.
const CANONICAL_DISPLAY_NAME_MAX = 80;

// Cuts `value` to at most `maximum` UTF-16 code units without splitting a
// surrogate pair: a trailing lone high surrogate (0xD800-0xDBFF) is dropped
// rather than kept as an unpaired unit.
function truncateToWholeCodePoints(value, maximum) {
  const cut = value.length > maximum ? value.slice(0, maximum) : value;
  if (cut.length < 1) return cut;
  const lastUnit = cut.charCodeAt(cut.length - 1);
  return lastUnit >= 0xd800 && lastUnit <= 0xdbff
    ? cut.slice(0, cut.length - 1)
    : cut;
}

function canonicalStoredDisplayName(displayName) {
  if (typeof displayName !== "string") {
    fail("data-loss", "The canonical display name is malformed.");
  }
  const canonical = truncateToWholeCodePoints(
    displayName.trim(),
    CANONICAL_DISPLAY_NAME_MAX,
  ).trim();
  if (
    canonical.length < 1 ||
    canonical.length > CANONICAL_DISPLAY_NAME_MAX
  ) {
    fail("data-loss", "The canonical display name is malformed.");
  }
  return canonical;
}

function canonicalPublicProfile(publicSnapshot, expectedUid) {
  requireUid(expectedUid, "public profile uid");
  if (!publicSnapshot?.exists) {
    fail("failed-precondition", "The canonical public profile is unavailable.");
  }
  const publicProfile = publicSnapshot.data() ?? {};
  const keys = Object.keys(publicProfile).sort();
  const exactCurrent = keys.length === PUBLIC_PROFILE_KEYS.length &&
    keys.every((key, index) => key === PUBLIC_PROFILE_KEYS[index]);
  const exactLegacy = keys.length === LEGACY_PUBLIC_PROFILE_KEYS.length &&
    keys.every((key, index) => key === LEGACY_PUBLIC_PROFILE_KEYS[index]);
  if (
    (!exactCurrent && !exactLegacy) ||
    publicProfile.schemaVersion !== 1 ||
    publicProfile.uid !== expectedUid ||
    (exactCurrent && typeof publicProfile.creatorAudienceVisible !== "boolean") ||
    timestampMillis(publicProfile.updatedAt) === null ||
    typeof publicProfile.displayName !== "string" ||
    // The projection is bounded at 120 UTF-16 code units by its single writer
    // (derivePublicProfile). A longer value is out of contract and still
    // refused. Whitespace at either edge is NOT: `updateMyDisplayName` accepts
    // 120 code POINTS, one astral character occupies two units, and the
    // writer's 120-unit cut can therefore land on a space inside a legal name
    // — "😀"x10 + "B"x99 + " " + "😀" is 111 code points and 122 units, and
    // projects to 120 units ending in U+0020. Refusing that made the account
    // permanently unable to publish a Yeel, unable to be opened in a chat by
    // anybody, and invisible in the Moments feed. It is repaired below by
    // canonicalStoredDisplayName instead, which trims before and after its own
    // cut; only a projection with no visible character at all is malformed.
    publicProfile.displayName.trim().length < 1 ||
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
    displayName: canonicalStoredDisplayName(publicProfile.displayName),
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
  CANONICAL_DISPLAY_NAME_MAX,
  SAFE_ID,
  activeProfile,
  assertLedgerReplay,
  assertNotBlocked,
  assertNotRestricted,
  canonicalPair,
  canonicalPublicProfile,
  canonicalStoredDisplayName,
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
