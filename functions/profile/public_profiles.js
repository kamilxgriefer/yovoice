// Privacy boundary for account identity.
//
// `users/{uid}` is the private account record. It contains email, presence,
// preferences, moderation state, staff mirrors and other operational fields,
// so ordinary clients must never read another account's document (or list the
// collection). Everything intentionally public is copied into the exact,
// server-owned `publicProfiles/{uid}` schema below. Presence is deliberately
// separate: `socialPresence/{uid}` is readable only by the account itself and
// canonical friends under Firestore Rules.

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const functionsV1 = require("firebase-functions/v1");
const { getAuth } = require("firebase-admin/auth");
const { FieldValue, Timestamp } = require("firebase-admin/firestore");
const { createHash } = require("node:crypto");

const { requireAuthentication } = require("../utils/auth");
const { db } = require("../utils/firestore");
const {
  deriveEffectivePremiumAccess,
  hasStaffPreviewAccess,
  isActiveAccountProfile,
} = require("../utils/premium_access");
const {
  assertLedgerReplay,
  consumeRateLimit,
  ledgerData,
  operationIdentity,
  rateLimitReference,
  requireActor,
  requireExactInput,
  requireRequestId,
} = require("../integrity/guards");
const { normalizeProfileVisibility } = require("./profile_visibility");
const {
  cleanupPremiumMessagingPrivacyForDeletedUser,
} = require("../messaging/privacy_cleanup");

const REGION = "europe-west1";
const PUBLIC_PROFILE_SCHEMA_VERSION = 1;
const SOCIAL_PRESENCE_SCHEMA_VERSION = 1;
const DEFAULT_SEARCH_LIMIT = 12;
const MAX_SEARCH_LIMIT = 20;
const MAX_SEARCH_LENGTH = 64;
const SEARCH_MINUTE_LIMIT = 30;
const SEARCH_HOUR_LIMIT = 300;
const SEARCH_MINUTE_MS = 60 * 1000;
const SEARCH_HOUR_MS = 60 * 60 * 1000;
const CREATOR_AUDIENCE_RATE_SCOPE = "profile.creatorAudience";
const CREATOR_AUDIENCE_RATE_LIMIT = Object.freeze({
  maxEvents: 20,
  windowMs: 60 * 1000,
});
const CREATOR_AGE_CONFIRMATION_RATE_SCOPE = "profile.creatorAgeConfirmation";
const CREATOR_AGE_CONFIRMATION_RATE_LIMIT = Object.freeze({
  maxEvents: 5,
  windowMs: 24 * 60 * 60 * 1000,
});
const CREATOR_MINIMUM_AGE_YEARS = 18;
const CREATOR_MAXIMUM_AGE_YEARS = 120;

const PUBLIC_PROFILE_FIELDS = new Set([
  "uid",
  "displayName",
  "username",
  "displayNameSearch",
  "usernameSearch",
  "photoUrl",
  "bannerUrl",
  "bio",
  "country",
  "nativeLanguage",
  "spokenLanguages",
  "learningLanguages",
  "website",
  "statusMessage",
  "accountType",
  "premiumIdentity",
  "creatorAudienceVisible",
  "friendCount",
  "followerCount",
  "followingCount",
  "schemaVersion",
  "updatedAt",
]);

const SOCIAL_PRESENCE_FIELDS = new Set([
  "uid",
  "isOnline",
  "lastSeen",
  "availability",
  "schemaVersion",
  "updatedAt",
]);

const USER_AVAILABILITY_VALUES = new Set([
  "available",
  "away",
  "busy",
  "invisible",
]);

/**
 * What OTHER people may learn about a user's chosen availability.
 *
 * - offline, or 'invisible': projected as isOnline=false / 'offline' — an
 *   invisible account is indistinguishable from a signed-out one.
 * - 'available' | 'away' | 'busy' while online: projected verbatim.
 * - anything else while online (older client, malformed value): 'available'.
 */
function deriveVisibleAvailability(source) {
  const online = source.isOnline === true;
  const chosen =
    typeof source.availability === "string" &&
    USER_AVAILABILITY_VALUES.has(source.availability)
      ? source.availability
      : "available";
  if (!online || chosen === "invisible") {
    return { isOnline: false, availability: "offline" };
  }
  return { isOnline: true, availability: chosen };
}

function safeString(value, maximum, fallback = "") {
  if (typeof value !== "string") return fallback;
  return value.trim().slice(0, maximum);
}

function canonicalUid(value) {
  // UIDs are opaque, case-sensitive identities. Never trim, lowercase or
  // truncate one: any normalization could alias two Auth accounts into the
  // same projection. Firestore document ids cannot contain a path slash.
  return typeof value === "string" &&
    value.length >= 1 &&
    value.length <= 128 &&
    !value.includes("/")
    ? value
    : null;
}

function safeNullableUrl(value, maximum = 2048) {
  const text = safeString(value, maximum);
  if (!text) return null;
  try {
    const parsed = new URL(text);
    // Public profile links are rendered by ordinary clients. Never project
    // clear-text HTTP (or a non-web scheme) from the private account record.
    return parsed.protocol === "https:" ? text : null;
  } catch {
    return null;
  }
}

function safeStrings(value, maximumItems = 12, maximumLength = 64) {
  if (!Array.isArray(value)) return [];
  const result = [];
  const seen = new Set();
  for (const item of value) {
    const text = safeString(item, maximumLength);
    const key = text.toLocaleLowerCase("en-US");
    if (!text || seen.has(key)) continue;
    seen.add(key);
    result.push(text);
    if (result.length >= maximumItems) break;
  }
  return result;
}

function safeCount(value) {
  return Number.isSafeInteger(value) && value >= 0 ? value : 0;
}

function paidCreatorAudienceEligibility(source, entitlement, now = Date.now()) {
  if (!isActiveAccountProfile(source) || source.accountType !== "creator" ||
      source.premiumIdentity !== true || source.creatorAgeVerified !== true) {
    return false;
  }
  const access = deriveEffectivePremiumAccess({ user: source, entitlement, now });
  return access.paidActive === true && entitlement?.premiumIdentityEnabled === true &&
    entitlement?.creatorEnabled === true;
}

function creatorAudienceVisibleFromSource(source) {
  return isActiveAccountProfile(source) && source.accountType === "creator" &&
    source.premiumIdentity === true && source.creatorAgeVerified === true &&
    source.creatorAudienceEnabled === true;
}

function normalizeSearchText(value) {
  return safeString(value, MAX_SEARCH_LENGTH)
    .normalize("NFKC")
    .replace(/^@+/u, "")
    .trim()
    .toLocaleLowerCase("en-US");
}

function requireAdultBirthDate(value, nowMs) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/u.test(value)) {
    throw new HttpsError(
      "invalid-argument",
      "birthDate must use the YYYY-MM-DD format.",
    );
  }
  const [year, month, day] = value.split("-").map(Number);
  const candidateMillis = Date.UTC(year, month - 1, day);
  const candidate = new Date(candidateMillis);
  if (
    candidate.getUTCFullYear() !== year ||
    candidate.getUTCMonth() !== month - 1 ||
    candidate.getUTCDate() !== day
  ) {
    throw new HttpsError("invalid-argument", "birthDate is not a real date.");
  }
  const today = new Date(nowMs);
  let age = today.getUTCFullYear() - year;
  const birthdayPending =
    today.getUTCMonth() < month - 1 ||
    (today.getUTCMonth() === month - 1 && today.getUTCDate() < day);
  if (birthdayPending) age -= 1;
  if (age < CREATOR_MINIMUM_AGE_YEARS) {
    throw new HttpsError(
      "failed-precondition",
      "Creator audience requires an adult account holder.",
    );
  }
  if (age > CREATOR_MAXIMUM_AGE_YEARS) {
    throw new HttpsError("invalid-argument", "birthDate is outside the allowed range.");
  }
}

function derivePublicProfile(uid, source) {
  if (!isActiveAccountProfile(source)) return null;

  const username = safeString(source.username, 80);
  const displayName =
    safeString(source.displayName, 120) || username || "YO Voice user";
  const rawAccountType = safeString(source.accountType, 24);
  // Creator is a capability-backed public identity, not merely a private
  // profile string. During the neutral role interlock (and after a completed
  // demotion while destructive cleanup converges), the private Creator mode
  // may deliberately remain intact. Publish it only while an independent
  // paid identity or an active moderator preview still backs it. Official is
  // server-owned and independent of either Premium source.
  const paidPremiumIdentity = source.premiumIdentity === true;
  const staffPreviewIdentity =
    source.roleTransitionInProgress !== true &&
    hasStaffPreviewAccess({ user: source });
  const accountType =
    rawAccountType === "official"
      ? "official"
      : rawAccountType === "creator" &&
          (paidPremiumIdentity || staffPreviewIdentity)
        ? "creator"
        : "personal";
  // Staff preview may display Creator identity, but accepting followers is a
  // paid, age-verified, explicit opt-in. Only a boolean projection leaves the
  // private verification authority; no birth date or verification detail is
  // copied to publicProfiles.
  const creatorAudienceVisible = accountType === "creator" &&
    creatorAudienceVisibleFromSource(source);

  return {
    uid,
    displayName,
    username,
    displayNameSearch: normalizeSearchText(displayName),
    usernameSearch: normalizeSearchText(username),
    // Artwork is private capability media. Nullable compatibility fields stay
    // in the projection schema, but no bearer or external URL is published.
    photoUrl: null,
    bannerUrl: null,
    bio: safeString(source.bio, 220),
    country: safeString(source.country, 64),
    nativeLanguage: safeString(source.nativeLanguage, 64),
    spokenLanguages: safeStrings(source.spokenLanguages),
    learningLanguages: safeStrings(source.learningLanguages),
    website: safeNullableUrl(source.website),
    statusMessage: safeString(source.statusMessage, 120),
    accountType,
    premiumIdentity: paidPremiumIdentity || staffPreviewIdentity,
    creatorAudienceVisible,
    friendCount: safeCount(source.friendCount),
    followerCount: creatorAudienceVisible ? safeCount(source.followerCount) : 0,
    followingCount: creatorAudienceVisible ? safeCount(source.followingCount) : 0,
    schemaVersion: PUBLIC_PROFILE_SCHEMA_VERSION,
  };
}

function deriveSocialPresence(uid, source) {
  if (!isActiveAccountProfile(source)) return null;
  const lastSeen = source.lastSeen;
  const visible = deriveVisibleAvailability(source);
  return {
    uid,
    isOnline: visible.isOnline,
    lastSeen:
      lastSeen && typeof lastSeen.toDate === "function" ? lastSeen : null,
    availability: visible.availability,
    schemaVersion: SOCIAL_PRESENCE_SCHEMA_VERSION,
  };
}

function valuesEqual(left, right) {
  if (left === right) return true;
  if (left?.toMillis && right?.toMillis) {
    return left.toMillis() === right.toMillis();
  }
  if (Array.isArray(left) && Array.isArray(right)) {
    return (
      left.length === right.length &&
      left.every((value, index) => valuesEqual(value, right[index]))
    );
  }
  return false;
}

function projectionMatches(existing, derived, allowedFields) {
  if (!existing || !derived) return false;
  const keys = Object.keys(existing);
  if (keys.some((key) => !allowedFields.has(key))) return false;
  if (!keys.includes("updatedAt")) return false;
  const derivedKeys = Object.keys(derived);
  if (derivedKeys.some((key) => !keys.includes(key))) return false;
  return derivedKeys.every((key) => valuesEqual(existing[key], derived[key]));
}

function applyProjectionInTransaction(
  transaction,
  reference,
  snapshot,
  derived,
  allowedFields,
) {
  if (derived === null) {
    if (!snapshot.exists) return "absent";
    transaction.delete(reference);
    return "removed";
  }

  const existing = snapshot.exists ? (snapshot.data() ?? {}) : null;
  if (projectionMatches(existing, derived, allowedFields)) return "unchanged";

  // Replace rather than merge. Any accidental/private extra field is removed
  // on the next source event or backfill instead of surviving indefinitely.
  transaction.set(reference, {
    ...derived,
    updatedAt: FieldValue.serverTimestamp(),
  });
  return snapshot.exists ? "updated" : "created";
}

async function fetchAuthUserOrNull(uid) {
  try {
    return await getAuth().getUser(uid);
  } catch (error) {
    if (error?.code === "auth/user-not-found") return null;
    throw error;
  }
}

/**
 * Converges both projections from CURRENT private state. Event payloads are
 * deliberately ignored, so duplicate and out-of-order trigger deliveries are
 * harmless. Presence heartbeats normally result in one small presence write
 * and no public-profile write because exact equality is checked first.
 */
async function syncPrivacyProjectionsForUser(
  uid,
  {
    database = db,
    afterRead = null,
    authUser = undefined,
    fetchAuthUser = fetchAuthUserOrNull,
  } = {},
) {
  const cleanUid = canonicalUid(uid);
  if (!cleanUid) return { outcome: "invalidUid" };

  // Auth is the existence authority. A lingering users/{uid} document after
  // account deletion must never recreate a public identity projection.
  const authoritativeAuthUser =
    authUser === undefined ? await fetchAuthUser(cleanUid) : authUser;
  const authExists =
    authoritativeAuthUser !== null && authoritativeAuthUser?.disabled !== true;

  const sourceRef = database.collection("users").doc(cleanUid);
  const profileRef = database.collection("publicProfiles").doc(cleanUid);
  const presenceRef = database.collection("socialPresence").doc(cleanUid);

  // Source and both projections are one transaction read-set. An older
  // trigger/backfill can no longer overwrite a newer profile: if the source
  // changes after these reads, Firestore retries with the current revision.
  return database.runTransaction(async (transaction) => {
    const [sourceSnapshot, profileSnapshot, presenceSnapshot] =
      await transaction.getAll(sourceRef, profileRef, presenceRef);
    if (typeof afterRead === "function") {
      await afterRead({ sourceSnapshot, profileSnapshot, presenceSnapshot });
    }
    const source =
      authExists && sourceSnapshot.exists
        ? (sourceSnapshot.data() ?? {})
        : null;

    const profile = applyProjectionInTransaction(
      transaction,
      profileRef,
      profileSnapshot,
      derivePublicProfile(cleanUid, source),
      PUBLIC_PROFILE_FIELDS,
    );
    const presence = applyProjectionInTransaction(
      transaction,
      presenceRef,
      presenceSnapshot,
      deriveSocialPresence(cleanUid, source),
      SOCIAL_PRESENCE_FIELDS,
    );
    return { outcome: "synchronised", profile, presence };
  });
}

const onUserPrivacySourceChanged = onDocumentWritten(
  {
    document: "users/{uid}",
    region: REGION,
    retry: true,
  },
  async (event) => {
    await syncPrivacyProjectionsForUser(event.params.uid);
  },
);

async function handleAuthUserDeleted(uid, { database = db } = {}) {
  const cleanUid = canonicalUid(uid);
  if (!cleanUid) return { outcome: "invalidUid" };
  const sourceRef = database.collection("users").doc(cleanUid);
  const projectionRefs = [
    database.collection("publicProfiles").doc(cleanUid),
    database.collection("socialPresence").doc(cleanUid),
    database.collection("publicBadges").doc(cleanUid),
    database.collection("userDirectory").doc(cleanUid),
    // Consent belongs to this exact Auth identity. Keeping it after account
    // deletion could silently opt a later re-created uid back into the public
    // website showcase.
    database.collection("marketingConsents").doc(cleanUid),
  ];

  await database.runTransaction(async (transaction) => {
    const source = await transaction.get(sourceRef);
    if (source.exists) {
      transaction.set(
        sourceRef,
        {
          disabled: true,
          isOnline: false,
          premiumIdentity: false,
          creatorAudienceEnabled: FieldValue.delete(),
          creatorAgeVerified: FieldValue.delete(),
          creatorAgeVerifiedAt: FieldValue.delete(),
          creatorAgeVerificationMethod: FieldValue.delete(),
          authDeletedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }
    for (const reference of projectionRefs) transaction.delete(reference);
  });
  return { outcome: "retired" };
}

/**
 * Runs the account-deletion boundary in a strict order.
 *
 * Retiring the private source profile first makes every direct-message
 * transaction that depends on an active account retry or fail. Only then is
 * owner-indexed privacy state erased. A retry repeats both idempotent steps.
 */
async function handleAuthUserDeletionLifecycle(
  uid,
  {
    database = db,
    retireIdentity = handleAuthUserDeleted,
    cleanupPrivacy = cleanupPremiumMessagingPrivacyForDeletedUser,
  } = {},
) {
  const retirement = await retireIdentity(uid, { database });
  const privacyCleanup = await cleanupPrivacy(uid, { database });
  return { retirement, privacyCleanup };
}

// Auth deletion has no Firestore source event of its own. This trigger closes
// that lifecycle gap immediately; the bounded backfill remains the recovery
// path for accounts deleted before this trigger was deployed.
const onAuthUserDeleted = functionsV1
  .runWith({ failurePolicy: true })
  .region(REGION)
  .auth.user()
  .onDelete(async (user) => {
    await handleAuthUserDeletionLifecycle(user.uid);
  });

function searchResult(snapshot, authority = {}, relationshipStatus = "none") {
  const data = snapshot.data() ?? {};
  const accountType = ["personal", "creator", "official"].includes(
    authority.accountType,
  )
    ? authority.accountType
    : "personal";
  return {
    uid: snapshot.id,
    displayName: safeString(data.displayName, 120) || "YO Voice user",
    username: safeString(data.username, 80),
    photoUrl: null,
    bio: safeString(data.bio, 220),
    statusMessage: safeString(data.statusMessage, 120),
    accountType,
    premiumIdentity: authority.premiumIdentity === true,
    creatorAudienceVisible: authority.creatorAudienceVisible === true,
    followerCount: authority.creatorAudienceVisible === true
      ? safeCount(data.followerCount)
      : 0,
    relationshipStatus,
    // This is an opaque cache revision, not a media URL. The client still
    // exchanges the uid for a short-lived viewer-authorized media grant.
    profileUpdatedAtMillis: timestampMillis(data.updatedAt, null),
  };
}

function exactPendingRequest(snapshot, senderId) {
  return snapshot?.exists && snapshot.data()?.senderId === senderId;
}

function exactFriendshipGuard(snapshot, ownerId, friendId) {
  if (!snapshot?.exists) return false;
  const data = snapshot.data() ?? {};
  const keys = Object.keys(data).sort();
  const expected = ["establishedAt", "friendId", "ownerId", "schemaVersion"];
  return (
    keys.length === expected.length &&
    keys.every((key, index) => key === expected[index]) &&
    data.ownerId === ownerId &&
    data.friendId === friendId &&
    data.schemaVersion === 1 &&
    data.establishedAt &&
    typeof data.establishedAt.toMillis === "function"
  );
}

function sourceProfileVisibleToCaller({
  callerId,
  targetId,
  source,
  forwardGuard,
  reverseGuard,
}) {
  const visibility = normalizeProfileVisibility(source?.profileVisibility);
  if (visibility === "public") return true;
  if (visibility === "private") return false;
  return (
    exactFriendshipGuard(forwardGuard, callerId, targetId) &&
    exactFriendshipGuard(reverseGuard, targetId, callerId)
  );
}

async function requireActiveCaller(uid) {
  const snapshot = await db.collection("users").doc(uid).get();
  const data = snapshot.exists ? (snapshot.data() ?? {}) : null;
  if (!isActiveAccountProfile(data)) {
    throw new HttpsError("permission-denied", "The account is not active.");
  }
}

function searchRateLimitReference(uid) {
  // Do not put a raw uid into a document id (Auth accepts a wider character
  // vocabulary than Firestore paths), and do not duplicate the uid into the
  // stored payload. This collection is Admin-SDK-only under Rules.
  const digest = createHash("sha256").update(uid).digest("hex");
  return db
    .collection("privateRateLimits")
    .doc(`searchPublicProfiles_${digest}`);
}

function timestampMillis(value, fallback) {
  return value && typeof value.toMillis === "function"
    ? value.toMillis()
    : fallback;
}

async function consumeSearchRateLimit(
  uid,
  {
    now = Timestamp.now(),
    minuteLimit = SEARCH_MINUTE_LIMIT,
    hourLimit = SEARCH_HOUR_LIMIT,
  } = {},
) {
  const reference = searchRateLimitReference(uid);
  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    const current = snapshot.exists ? (snapshot.data() ?? {}) : {};
    const nowMs = now.toMillis();

    const hasMinuteStart =
      current.minuteStartedAt &&
      typeof current.minuteStartedAt.toMillis === "function";
    const minuteStartedMs = timestampMillis(current.minuteStartedAt, nowMs);
    const minuteExpired =
      !hasMinuteStart || nowMs - minuteStartedMs >= SEARCH_MINUTE_MS;
    const minuteCount = minuteExpired
      ? 1
      : Number.isSafeInteger(current.minuteCount)
        ? current.minuteCount + 1
        : 1;

    const hasHourStart =
      current.hourStartedAt &&
      typeof current.hourStartedAt.toMillis === "function";
    const hourStartedMs = timestampMillis(current.hourStartedAt, nowMs);
    const hourExpired =
      !hasHourStart || nowMs - hourStartedMs >= SEARCH_HOUR_MS;
    const hourCount = hourExpired
      ? 1
      : Number.isSafeInteger(current.hourCount)
        ? current.hourCount + 1
        : 1;

    if (minuteCount > minuteLimit || hourCount > hourLimit) {
      throw new HttpsError(
        "resource-exhausted",
        "Too many profile searches. Please wait and try again.",
      );
    }

    transaction.set(reference, {
      kind: "searchPublicProfiles",
      minuteStartedAt: minuteExpired ? now : current.minuteStartedAt,
      minuteCount,
      hourStartedAt: hourExpired ? now : current.hourStartedAt,
      hourCount,
      updatedAt: now,
    });
    return { minuteCount, hourCount };
  });
}

const searchPublicProfiles = onCall(
  { region: REGION, enforceAppCheck: false },
  async (request) => {
    const auth = requireAuthentication(request);
    // App Check is not enforced yet. Every invocation — including malformed
    // search attempts — consumes a server-time, transactional quota before it
    // can issue either prefix query, containing both enumeration and cost.
    await consumeSearchRateLimit(auth.uid);
    await requireActiveCaller(auth.uid);
    if (auth.token?.email_verified !== true) {
      throw new HttpsError(
        "failed-precondition",
        "Verify your email before searching for people.",
      );
    }

    const rawQuery = request.data?.query;
    if (typeof rawQuery !== "string" || rawQuery.length > MAX_SEARCH_LENGTH) {
      throw new HttpsError(
        "invalid-argument",
        `Search text must be at most ${MAX_SEARCH_LENGTH} characters.`,
      );
    }
    const term = normalizeSearchText(rawQuery);
    if (term.length < 2) {
      throw new HttpsError(
        "invalid-argument",
        "Enter at least two characters to search.",
      );
    }
    const parsedLimit = Number.parseInt(request.data?.limit, 10);
    const limit = Number.isFinite(parsedLimit)
      ? Math.min(Math.max(parsedLimit, 1), MAX_SEARCH_LIMIT)
      : DEFAULT_SEARCH_LIMIT;
    const rawAccountTypes = request.data?.accountTypes;
    let accountTypes = null;
    if (rawAccountTypes !== undefined) {
      if (
        !Array.isArray(rawAccountTypes) ||
        rawAccountTypes.length === 0 ||
        rawAccountTypes.length > 3 ||
        rawAccountTypes.some(
          (value) =>
            typeof value !== "string" ||
            !["personal", "creator", "official"].includes(value),
        )
      ) {
        throw new HttpsError(
          "invalid-argument",
          "Account types must contain only personal, creator or official.",
        );
      }
      accountTypes = new Set(rawAccountTypes);
    }
    const queryLimit = Math.min(limit * 2, MAX_SEARCH_LIMIT * 2);
    const end = `${term}\uf8ff`;

    const profiles = db.collection("publicProfiles");
    const requestedTypes = accountTypes === null ? null : [...accountTypes];
    const displayNameQuery = requestedTypes
      ? profiles.where("accountType", "in", requestedTypes)
      : profiles;
    const usernameQuery = requestedTypes
      ? profiles.where("accountType", "in", requestedTypes)
      : profiles;
    const [byDisplayName, byUsername] = await Promise.all([
      displayNameQuery
        .orderBy("displayNameSearch")
        .startAt(term)
        .endAt(end)
        .limit(queryLimit)
        .get(),
      usernameQuery
        .orderBy("usernameSearch")
        .startAt(term)
        .endAt(end)
        .limit(queryLimit)
        .get(),
    ]);

    const candidates = new Map();
    for (const snapshot of [...byUsername.docs, ...byDisplayName.docs]) {
      if (snapshot.id === auth.uid) continue;
      if (
        accountTypes !== null &&
        !accountTypes.has(snapshot.data()?.accountType ?? "personal")
      ) {
        continue;
      }
      candidates.set(snapshot.id, snapshot);
      if (candidates.size >= MAX_SEARCH_LIMIT * 2) break;
    }

    const candidateIds = [...candidates.keys()];
    const [
      forwardBlocks,
      reverseBlocks,
      sourceProfiles,
      entitlements,
      forwardFriendships,
      reverseFriendships,
      outgoingRequests,
      incomingRequests,
    ] =
      candidateIds.length === 0
        ? [[], [], [], [], [], [], [], []]
        : await Promise.all([
            // Never enumerate the caller's whole block list. A caller controls
            // its size, so doing that would make every search arbitrarily costly.
            // Only the bounded candidate set (at most 40 ids) is inspected.
            db.getAll(
              ...candidateIds.map((uid) =>
                db
                  .collection("users")
                  .doc(auth.uid)
                  .collection("blocked")
                  .doc(uid),
              ),
            ),
            db.getAll(
              ...candidateIds.map((uid) =>
                db
                  .collection("users")
                  .doc(uid)
                  .collection("blocked")
                  .doc(auth.uid),
              ),
            ),
            // A stale projection must stop being searchable immediately after a
            // ban/disable/delete, even before the retrying trigger removes it.
            db.getAll(
              ...candidateIds.map((uid) => db.collection("users").doc(uid)),
            ),
            db.getAll(
              ...candidateIds.map((uid) =>
                db.collection("entitlements").doc(uid),
              ),
            ),
            db.getAll(
              ...candidateIds.map((uid) =>
                db
                  .collection("friendshipGuards")
                  .doc(auth.uid)
                  .collection("friends")
                  .doc(uid),
              ),
            ),
            db.getAll(
              ...candidateIds.map((uid) =>
                db
                  .collection("friendshipGuards")
                  .doc(uid)
                  .collection("friends")
                  .doc(auth.uid),
              ),
            ),
            // The bounded candidate set lets search return relationship
            // state without the client issuing four extra reads per row.
            db.getAll(
              ...candidateIds.map((uid) =>
                db.doc(`users/${uid}/friendRequests/${auth.uid}`),
              ),
            ),
            db.getAll(
              ...candidateIds.map((uid) =>
                db.doc(`users/${auth.uid}/friendRequests/${uid}`),
              ),
            ),
          ]);
    const hidden = new Set();
    const authorityByUid = new Map();
    const nowMillis = Date.now();
    for (let index = 0; index < candidateIds.length; index += 1) {
      if (forwardBlocks[index]?.exists || reverseBlocks[index]?.exists) {
        hidden.add(candidateIds[index]);
      }
    }
    for (let index = 0; index < sourceProfiles.length; index += 1) {
      const snapshot = sourceProfiles[index];
      const source = snapshot.exists ? (snapshot.data() ?? {}) : null;
      if (!isActiveAccountProfile(source)) {
        hidden.add(snapshot.id);
        continue;
      }
      if (
        !sourceProfileVisibleToCaller({
          callerId: auth.uid,
          targetId: snapshot.id,
          source,
          forwardGuard: forwardFriendships[index],
          reverseGuard: reverseFriendships[index],
        })
      ) {
        hidden.add(snapshot.id);
        continue;
      }
      const entitlement = entitlements[index]?.data() ?? null;
      const access = deriveEffectivePremiumAccess({
        user: source,
        entitlement,
        now: nowMillis,
      });
      const creatorActive =
        source.accountType === "creator" && access.creatorEnabled;
      const canonicalAccountType =
        source.accountType === "official"
          ? "official"
          : creatorActive
            ? "creator"
            : "personal";
      if (accountTypes !== null && !accountTypes.has(canonicalAccountType)) {
        hidden.add(snapshot.id);
        continue;
      }
      authorityByUid.set(snapshot.id, {
        accountType: canonicalAccountType,
        premiumIdentity: access.premiumIdentityEnabled,
        creatorAudienceVisible:
          canonicalAccountType === "creator" &&
          source.creatorAudienceEnabled === true &&
          paidCreatorAudienceEligibility(source, entitlement, nowMillis),
      });
    }

    const relationshipByUid = new Map();
    for (let index = 0; index < candidateIds.length; index += 1) {
      const uid = candidateIds[index];
      const friends =
        exactFriendshipGuard(forwardFriendships[index], auth.uid, uid) &&
        exactFriendshipGuard(reverseFriendships[index], uid, auth.uid);
      const status = friends
        ? "friends"
        : exactPendingRequest(outgoingRequests[index], auth.uid)
          ? "requestSent"
          : exactPendingRequest(incomingRequests[index], uid)
            ? "requestReceived"
            : "none";
      relationshipByUid.set(uid, status);
    }

    const results = candidateIds
      .filter((uid) => !hidden.has(uid))
      .map((uid) =>
        searchResult(
          candidates.get(uid),
          authorityByUid.get(uid),
          relationshipByUid.get(uid),
        ),
      )
      .sort((left, right) => {
        const leftUsername = normalizeSearchText(left.username);
        const rightUsername = normalizeSearchText(right.username);
        if (leftUsername === term && rightUsername !== term) return -1;
        if (rightUsername === term && leftUsername !== term) return 1;
        return left.displayName.localeCompare(right.displayName);
      })
      .slice(0, limit);

    return { profiles: results };
  },
);

async function setCreatorAudienceEnabledHandler(
  request,
  {
    database = db,
    now = Timestamp.now(),
    rateLimit = CREATOR_AUDIENCE_RATE_LIMIT,
  } = {},
) {
  const auth = requireActor(request);
  requireExactInput(request.data, ["enabled", "requestId"], ["enabled", "requestId"]);
  if (typeof request.data.enabled !== "boolean") {
    throw new HttpsError("invalid-argument", "enabled must be a boolean.");
  }
  const enabled = request.data.enabled;
  const requestId = requireRequestId(request.data.requestId);
  const identity = operationIdentity(
    "profile.creator.audience.v1",
    auth.uid,
    requestId,
    { enabled },
  );
  const userRef = database.collection("users").doc(auth.uid);
  const entitlementRef = database.collection("entitlements").doc(auth.uid);
  const profileRef = database.collection("publicProfiles").doc(auth.uid);
  const ledgerRef = database.collection("integrityOperationLedgers").doc(identity.id);
  const rateRef = rateLimitReference(database, CREATOR_AUDIENCE_RATE_SCOPE, auth.uid);
  const nowMs = timestampMillis(now, null);
  if (!Number.isSafeInteger(nowMs) || nowMs < 0) {
    throw new TypeError("now must be a Firestore Timestamp.");
  }
  return database.runTransaction(async (transaction) => {
    const [userSnapshot, entitlementSnapshot, profileSnapshot, ledgerSnapshot,
      rateSnapshot] = await transaction.getAll(
      userRef,
      entitlementRef,
      profileRef,
      ledgerRef,
      rateRef,
    );
    const source = userSnapshot.exists ? (userSnapshot.data() ?? {}) : null;
    if (!isActiveAccountProfile(source)) {
      throw new HttpsError("permission-denied", "The account is not active.");
    }
    const entitlement = entitlementSnapshot.exists
      ? (entitlementSnapshot.data() ?? {})
      : null;
    if (enabled && !paidCreatorAudienceEligibility(source, entitlement, now)) {
      // One deliberately generic refusal: neither Premium status nor private
      // age-verification state is disclosed through the callable.
      throw new HttpsError(
        "failed-precondition",
        "Creator audience is unavailable for this account.",
      );
    }
    const prior = assertLedgerReplay(ledgerSnapshot, {
      kind: "profile.creator.audience.v1",
      uid: auth.uid,
      inputHash: identity.inputHash,
    });
    if (prior) {
      if (source.creatorAudienceEnabled !== prior.creatorAudienceEnabled) {
        throw new HttpsError(
          "aborted",
          "Creator audience changed after the original request.",
        );
      }
      return prior;
    }
    // The shared private rate-limit row and the operation ledger commit in
    // the same transaction. A concurrent replay sees the ledger and is free;
    // every distinct operation consumes one bounded slot before its receipt
    // can be created.
    consumeRateLimit(transaction, rateSnapshot, {
      reference: rateRef,
      scope: CREATOR_AUDIENCE_RATE_SCOPE,
      uid: auth.uid,
      now,
      nowMs,
      ...rateLimit,
    });
    const nextSource = { ...source, creatorAudienceEnabled: enabled };
    const derived = derivePublicProfile(auth.uid, nextSource);
    const result = {
      creatorAudienceEnabled: enabled,
      creatorAudienceVisible: derived?.creatorAudienceVisible === true,
      changed: source.creatorAudienceEnabled !== enabled,
    };
    transaction.update(userRef, { creatorAudienceEnabled: enabled });
    applyProjectionInTransaction(
      transaction,
      profileRef,
      profileSnapshot,
      derived,
      PUBLIC_PROFILE_FIELDS,
    );
    transaction.create(ledgerRef, ledgerData({
      kind: "profile.creator.audience.v1",
      uid: auth.uid,
      requestId,
      inputHash: identity.inputHash,
      result,
      now,
    }));
    return result;
  });
}

async function confirmCreatorAdultEligibilityHandler(
  request,
  {
    database = db,
    now = Timestamp.now(),
    rateLimit = CREATOR_AGE_CONFIRMATION_RATE_LIMIT,
  } = {},
) {
  const auth = requireActor(request);
  requireExactInput(
    request.data,
    ["birthDate", "requestId"],
    ["birthDate", "requestId"],
  );
  const requestId = requireRequestId(request.data.requestId);
  const nowMs = timestampMillis(now, null);
  if (!Number.isSafeInteger(nowMs) || nowMs < 0) {
    throw new TypeError("now must be a Firestore Timestamp.");
  }
  // The date is used only for this calculation. It is never written to
  // Firestore, an operation ledger, a public projection or a log entry.
  requireAdultBirthDate(request.data.birthDate, nowMs);

  const identity = operationIdentity(
    "profile.creator.ageConfirmation.v1",
    auth.uid,
    requestId,
    { adultEligibility: true },
  );
  const userRef = database.collection("users").doc(auth.uid);
  const entitlementRef = database.collection("entitlements").doc(auth.uid);
  const profileRef = database.collection("publicProfiles").doc(auth.uid);
  const ledgerRef = database.collection("integrityOperationLedgers").doc(identity.id);
  const rateRef = rateLimitReference(
    database,
    CREATOR_AGE_CONFIRMATION_RATE_SCOPE,
    auth.uid,
  );

  return database.runTransaction(async (transaction) => {
    const [userSnapshot, entitlementSnapshot, profileSnapshot, ledgerSnapshot,
      rateSnapshot] = await transaction.getAll(
      userRef,
      entitlementRef,
      profileRef,
      ledgerRef,
      rateRef,
    );
    const source = userSnapshot.exists ? (userSnapshot.data() ?? {}) : null;
    if (!isActiveAccountProfile(source)) {
      throw new HttpsError("permission-denied", "The account is not active.");
    }
    const entitlement = entitlementSnapshot.exists
      ? (entitlementSnapshot.data() ?? {})
      : null;
    const access = deriveEffectivePremiumAccess({
      user: source,
      entitlement,
      now: nowMs,
    });
    if (
      source.accountType !== "creator" ||
      source.premiumIdentity !== true ||
      access.paidActive !== true ||
      entitlement?.premiumIdentityEnabled !== true ||
      entitlement?.creatorEnabled !== true
    ) {
      throw new HttpsError(
        "failed-precondition",
        "Age confirmation is unavailable for this account.",
      );
    }
    const prior = assertLedgerReplay(ledgerSnapshot, {
      kind: "profile.creator.ageConfirmation.v1",
      uid: auth.uid,
      inputHash: identity.inputHash,
    });
    if (prior) return prior;

    consumeRateLimit(transaction, rateSnapshot, {
      reference: rateRef,
      scope: CREATOR_AGE_CONFIRMATION_RATE_SCOPE,
      uid: auth.uid,
      now,
      nowMs,
      ...rateLimit,
    });
    const changed = source.creatorAgeVerified !== true;
    const result = { creatorAgeVerified: true, changed };
    if (changed) {
      const nextSource = {
        ...source,
        creatorAgeVerified: true,
        creatorAgeVerifiedAt: now,
        creatorAgeVerificationMethod: "self_declared_birth_date",
      };
      transaction.update(userRef, {
        creatorAgeVerified: true,
        creatorAgeVerifiedAt: now,
        creatorAgeVerificationMethod: "self_declared_birth_date",
      });
      applyProjectionInTransaction(
        transaction,
        profileRef,
        profileSnapshot,
        derivePublicProfile(auth.uid, nextSource),
        PUBLIC_PROFILE_FIELDS,
      );
    }
    transaction.create(ledgerRef, ledgerData({
      kind: "profile.creator.ageConfirmation.v1",
      uid: auth.uid,
      requestId,
      inputHash: identity.inputHash,
      result,
      now,
    }));
    return result;
  });
}

const setCreatorAudienceEnabled = onCall(
  // App Check stays in rollout/metrics mode with the surrounding profile
  // callables. The transactional quota is the immediate abuse boundary; a
  // unilateral enforcement flip would reject currently released clients.
  { region: REGION, enforceAppCheck: false },
  (request) => setCreatorAudienceEnabledHandler(request),
);

const confirmCreatorAdultEligibility = onCall(
  { region: REGION, enforceAppCheck: false },
  (request) => confirmCreatorAdultEligibilityHandler(request),
);

module.exports = {
  DEFAULT_SEARCH_LIMIT,
  MAX_SEARCH_LIMIT,
  MAX_SEARCH_LENGTH,
  SEARCH_HOUR_LIMIT,
  SEARCH_HOUR_MS,
  SEARCH_MINUTE_LIMIT,
  SEARCH_MINUTE_MS,
  CREATOR_AUDIENCE_RATE_LIMIT,
  CREATOR_AUDIENCE_RATE_SCOPE,
  CREATOR_AGE_CONFIRMATION_RATE_LIMIT,
  CREATOR_AGE_CONFIRMATION_RATE_SCOPE,
  CREATOR_MAXIMUM_AGE_YEARS,
  CREATOR_MINIMUM_AGE_YEARS,
  PUBLIC_PROFILE_FIELDS,
  PUBLIC_PROFILE_SCHEMA_VERSION,
  SOCIAL_PRESENCE_FIELDS,
  SOCIAL_PRESENCE_SCHEMA_VERSION,
  USER_AVAILABILITY_VALUES,
  canonicalUid,
  creatorAudienceVisibleFromSource,
  derivePublicProfile,
  deriveSocialPresence,
  deriveVisibleAvailability,
  normalizeSearchText,
  requireAdultBirthDate,
  projectionMatches,
  fetchAuthUserOrNull,
  consumeSearchRateLimit,
  exactFriendshipGuard,
  sourceProfileVisibleToCaller,
  syncPrivacyProjectionsForUser,
  handleAuthUserDeleted,
  handleAuthUserDeletionLifecycle,
  onUserPrivacySourceChanged,
  onAuthUserDeleted,
  paidCreatorAudienceEligibility,
  searchPublicProfiles,
  setCreatorAudienceEnabled,
  setCreatorAudienceEnabledHandler,
  confirmCreatorAdultEligibility,
  confirmCreatorAdultEligibilityHandler,
};
