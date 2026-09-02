const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { createHash, randomUUID } = require("node:crypto");
const {
  FieldPath,
  FieldValue,
  Timestamp,
} = require("firebase-admin/firestore");

const { requireAuthentication } = require("../utils/auth");
const { db, normalizeText } = require("../utils/firestore");
const {
  canonicalNotificationData,
  notificationReference,
  restrictionIsActive,
} = require("../notifications/canonical");
const {
  sourceProfileVisibleToCaller,
} = require("../profile/public_profiles");

const REGION = "europe-west1";
const SAFE_ID = /^[A-Za-z0-9_-]{1,128}$/u;
const FRIENDSHIP_GUARD_SCHEMA_VERSION = 1;
const SOCIAL_CAPACITY_SCHEMA_VERSION = 1;
const MAX_FRIENDS = 500;
const MAX_FOLLOWING = 1000;
const MAX_PENDING_REQUESTS = 200;
const MAX_BLOCKED_USERS = 1000;
const MAX_FRIENDS_EXPANDED = 10;
const MAX_FRIENDS_SCANNED_FOR_DISCOVERY = 50;
const MAX_EXPANDED_FRIENDS_PER_SOURCE = 50;
const MAX_SUGGESTION_CANDIDATES = 40;
const MAX_MUTUAL_FRIENDS_SCANNED = 50;
const DEFAULT_SUGGESTION_LIMIT = 10;
const MAX_SUGGESTION_LIMIT = 25;
const FRIEND_DISCOVERY_MINUTE_LIMIT = 2;
const FRIEND_DISCOVERY_HOUR_LIMIT = 20;
const FRIEND_DISCOVERY_CACHE_TTL_MS = 30 * 1000;
// Quota and cache reads happen before these budgets. Every subsequent
// Firestore graph/profile read must reserve its worst-case document count.
const SUGGESTION_GRAPH_READ_BUDGET = 900;
const MUTUAL_GRAPH_READ_BUDGET = 420;
const FRIEND_DISCOVERY_MAX_INSTANCES = 20;
const SOCIAL_READ_MINUTE_LIMIT = 30;
const SOCIAL_READ_HOUR_LIMIT = 300;
const SOCIAL_MUTATION_MINUTE_LIMIT = 60;
const SOCIAL_MUTATION_HOUR_LIMIT = 600;
const QUOTA_MINUTE_MS = 60 * 1000;
const QUOTA_HOUR_MS = 60 * 60 * 1000;
const SOCIAL_CAPACITY_FIELDS = Object.freeze({
  blocked: {
    countField: "blockedCount",
    overflowField: "blockedOverflowed",
    collection: "blocked",
    maximum: MAX_BLOCKED_USERS,
  },
  pendingOutgoing: {
    countField: "pendingOutgoingCount",
    overflowField: "pendingOutgoingOverflowed",
    collection: "sentFriendRequests",
    maximum: MAX_PENDING_REQUESTS,
  },
  pendingIncoming: {
    countField: "pendingIncomingCount",
    overflowField: "pendingIncomingOverflowed",
    collection: "friendRequests",
    maximum: MAX_PENDING_REQUESTS,
  },
});

function newSocialNotificationId(type, actorId) {
  return `${type}_${actorId}_${randomUUID().replaceAll("-", "")}`;
}

function storedNotificationId(data, prefix) {
  const candidate = normalizeText(data?.notificationId, 320);
  return candidate.startsWith(`${prefix}_`) &&
    /^[A-Za-z0-9_-]{1,320}$/u.test(candidate)
    ? candidate
    : null;
}

function storedAcceptanceNotification(data, firstUserId, secondUserId) {
  const recipientId = data?.acceptanceRecipientId;
  if (![firstUserId, secondUserId].includes(recipientId)) return null;
  const actorId = recipientId === firstUserId ? secondUserId : firstUserId;
  const notificationId = storedNotificationId(
    { notificationId: data?.acceptanceNotificationId },
    `friendAccepted_${actorId}`,
  );
  return notificationId ? { recipientId, notificationId } : null;
}

function targetIdFrom(request) {
  const targetUserId = normalizeText(
    request.data?.targetUserId ?? request.data?.senderId,
    128,
  );
  if (!SAFE_ID.test(targetUserId)) {
    throw new HttpsError(
      "invalid-argument",
      "A valid target user is required.",
    );
  }
  return targetUserId;
}

function requireVerified(auth) {
  if (auth.token?.email_verified !== true) {
    throw new HttpsError(
      "failed-precondition",
      "Verify your email before connecting with people.",
    );
  }
}

function profileData(snapshot, label) {
  if (!snapshot.exists) {
    throw new HttpsError("not-found", `${label} profile does not exist.`);
  }
  const data = snapshot.data() ?? {};
  if (data.banned === true || data.disabled === true) {
    throw new HttpsError(
      "permission-denied",
      `${label} account is not active.`,
    );
  }
  return data;
}

function ensureNotRestricted(snapshot, label) {
  if (restrictionIsActive(snapshot.exists ? snapshot.data() : null)) {
    throw new HttpsError(
      "permission-denied",
      `${label} account cannot create social connections right now.`,
    );
  }
}

function ensureNotBlocked(first, second) {
  if (first.exists || second.exists) {
    throw new HttpsError(
      "failed-precondition",
      "This action is unavailable because one of the accounts has blocked the other.",
    );
  }
}

function countOf(profile, field) {
  const value = profile?.[field] ?? 0;
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new HttpsError(
      "data-loss",
      `The canonical ${field} value is invalid. Please contact support.`,
    );
  }
  return value;
}

function requireCapacity(profile, field, maximum, message) {
  if (countOf(profile, field) >= maximum) {
    throw new HttpsError("resource-exhausted", message);
  }
}

function timestampMillis(value, fallback) {
  return value && typeof value.toMillis === "function"
    ? value.toMillis()
    : fallback;
}

function socialRateLimitReference(uid, kind) {
  const digest = createHash("sha256").update(uid).digest("hex");
  return db.doc(`privateRateLimits/socialGraph_${kind}_${digest}`);
}

function friendDiscoveryDigest(...parts) {
  return createHash("sha256")
    .update(parts.join("\u0000"))
    .digest("hex");
}

function friendDiscoveryRateLimitReference(uid, kind) {
  return db.doc(
    `privateRateLimits/friendDiscovery_${kind}_${friendDiscoveryDigest(uid)}`,
  );
}

function friendDiscoveryCacheReference(uid, kind) {
  // One deterministic document per uid and endpoint keeps cache storage
  // bounded. Mutual lookups store/validate the current target inside that
  // document instead of creating an attacker-controlled document per pair.
  return db.doc(
    `privateFriendDiscoveryCaches/${friendDiscoveryDigest(kind, uid)}`,
  );
}

function socialCapacityReference(uid) {
  return db.doc(
    `privateSocialGraphCapacities/${friendDiscoveryDigest(uid)}`,
  );
}

function socialCapacityState(uid, snapshot) {
  const data = snapshot.exists ? (snapshot.data() ?? {}) : {};
  if (
    snapshot.exists &&
    (data.kind !== "socialGraphCapacity" ||
      data.schemaVersion !== SOCIAL_CAPACITY_SCHEMA_VERSION)
  ) {
    throw new HttpsError(
      "data-loss",
      "The private social capacity ledger is not canonical.",
    );
  }
  return {
    uid,
    reference: socialCapacityReference(uid),
    data: { ...data },
    patch: {},
  };
}

function canonicalCapacityValue(state, kind) {
  const config = SOCIAL_CAPACITY_FIELDS[kind];
  if (!config) throw new TypeError("Unknown social capacity kind.");
  const count = state.data[config.countField];
  const overflowed = state.data[config.overflowField];
  if (count === undefined && overflowed === undefined) return null;
  if (
    !Number.isSafeInteger(count) ||
    count < 0 ||
    count > config.maximum + 1 ||
    typeof overflowed !== "boolean" ||
    (overflowed && count !== config.maximum + 1) ||
    (!overflowed && count > config.maximum)
  ) {
    throw new HttpsError(
      "data-loss",
      "The private social capacity value is invalid.",
    );
  }
  return { count, overflowed, config };
}

async function ensureSocialCapacity(transaction, state, kind) {
  const existing = canonicalCapacityValue(state, kind);
  if (existing) return existing;
  const config = SOCIAL_CAPACITY_FIELDS[kind];
  const snapshot = await transaction.get(
    db
      .doc(`users/${state.uid}`)
      .collection(config.collection)
      .limit(config.maximum + 1),
  );
  const overflowed = snapshot.size > config.maximum;
  const count = overflowed ? config.maximum + 1 : snapshot.size;
  Object.assign(state.data, {
    [config.countField]: count,
    [config.overflowField]: overflowed,
  });
  Object.assign(state.patch, {
    [config.countField]: count,
    [config.overflowField]: overflowed,
    [`${kind}MigratedAt`]: FieldValue.serverTimestamp(),
  });
  return { count, overflowed, config };
}

function adjustSocialCapacity(state, kind, delta) {
  const current = canonicalCapacityValue(state, kind);
  if (!current) {
    throw new TypeError("Social capacity must be initialized before use.");
  }
  if (delta > 0 && (current.overflowed || current.count >= current.config.maximum)) {
    return false;
  }
  if (delta < 0 && current.count <= 0) {
    throw new HttpsError(
      "data-loss",
      "The private social capacity ledger has drifted.",
    );
  }
  if (delta < 0 && current.overflowed) {
    // The bounded bootstrap only proves "more than max". Decrementing that
    // lower bound would pretend we know the exact legacy size, so it remains
    // fail-closed until an audited offline recount repairs the ledger.
    return true;
  }
  const count = current.count + delta;
  // An overflow flag deliberately never clears on a client operation. A
  // legacy graph beyond the bounded migration window needs an audited repair;
  // guessing that enough rows were removed could reopen an over-cap account.
  const overflowed = false;
  Object.assign(state.data, {
    [current.config.countField]: count,
    [current.config.overflowField]: overflowed,
  });
  Object.assign(state.patch, {
    [current.config.countField]: count,
    [current.config.overflowField]: overflowed,
  });
  return true;
}

function socialCapacityHasRoom(state, kind) {
  const current = canonicalCapacityValue(state, kind);
  if (!current) {
    throw new TypeError("Social capacity must be initialized before use.");
  }
  return !current.overflowed && current.count < current.config.maximum;
}

function persistSocialCapacity(transaction, state) {
  if (Object.keys(state.patch).length === 0) return;
  transaction.set(
    state.reference,
    {
      kind: "socialGraphCapacity",
      schemaVersion: SOCIAL_CAPACITY_SCHEMA_VERSION,
      ...state.patch,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

class GraphReadBudget {
  constructor(limit) {
    this.limit = limit;
    this.reserved = 0;
  }

  reserve(count) {
    if (!Number.isSafeInteger(count) || count < 0) {
      throw new TypeError("The graph read reservation is invalid.");
    }
    if (this.reserved + count > this.limit) {
      throw new HttpsError(
        "resource-exhausted",
        "This social graph is too large to inspect safely.",
      );
    }
    this.reserved += count;
  }
}

/**
 * A dedicated low budget for the two graph-amplifying discovery callables.
 * It is intentionally separate from cheap social reads: otherwise an attacker
 * could spend the broad generic allowance on thousands of downstream reads.
 */
async function consumeFriendDiscoveryRateLimit(
  uid,
  kind,
  {
    now = Timestamp.now(),
    minuteLimit = FRIEND_DISCOVERY_MINUTE_LIMIT,
    hourLimit = FRIEND_DISCOVERY_HOUR_LIMIT,
  } = {},
) {
  if (!["suggestions", "mutuals"].includes(kind)) {
    throw new TypeError("Unknown friend-discovery quota kind.");
  }
  const reference = friendDiscoveryRateLimitReference(uid, kind);
  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    const current = snapshot.exists ? (snapshot.data() ?? {}) : {};
    const nowMs = now.toMillis();

    const minuteStartedMs = timestampMillis(current.minuteStartedAt, nowMs);
    const minuteExpired =
      !current.minuteStartedAt ||
      typeof current.minuteStartedAt.toMillis !== "function" ||
      nowMs - minuteStartedMs >= QUOTA_MINUTE_MS;
    const minuteCount = minuteExpired
      ? 1
      : Number.isSafeInteger(current.minuteCount)
        ? current.minuteCount + 1
        : 1;

    const hourStartedMs = timestampMillis(current.hourStartedAt, nowMs);
    const hourExpired =
      !current.hourStartedAt ||
      typeof current.hourStartedAt.toMillis !== "function" ||
      nowMs - hourStartedMs >= QUOTA_HOUR_MS;
    const hourCount = hourExpired
      ? 1
      : Number.isSafeInteger(current.hourCount)
        ? current.hourCount + 1
        : 1;

    if (minuteCount > minuteLimit || hourCount > hourLimit) {
      throw new HttpsError(
        "resource-exhausted",
        "Friend discovery is temporarily limited. Please wait and try again.",
      );
    }

    transaction.set(reference, {
      kind: `friendDiscovery.${kind}`,
      minuteStartedAt: minuteExpired ? now : current.minuteStartedAt,
      minuteCount,
      hourStartedAt: hourExpired ? now : current.hourStartedAt,
      hourCount,
      updatedAt: now,
    });
    return { minuteCount, hourCount };
  });
}

/**
 * Consumes a private, transactional budget before a social operation reaches
 * any attacker-amplifiable graph query. The document id never contains a raw
 * Auth uid and Rules expose neither counters nor reset times.
 */
async function consumeSocialRateLimit(
  uid,
  kind,
  {
    now = Timestamp.now(),
    minuteLimit = kind === "read"
      ? SOCIAL_READ_MINUTE_LIMIT
      : SOCIAL_MUTATION_MINUTE_LIMIT,
    hourLimit = kind === "read"
      ? SOCIAL_READ_HOUR_LIMIT
      : SOCIAL_MUTATION_HOUR_LIMIT,
  } = {},
) {
  if (!["read", "mutation"].includes(kind)) {
    throw new TypeError("Unknown social quota kind.");
  }
  const reference = socialRateLimitReference(uid, kind);
  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    const current = snapshot.exists ? (snapshot.data() ?? {}) : {};
    const nowMs = now.toMillis();

    const hasMinuteStart =
      current.minuteStartedAt &&
      typeof current.minuteStartedAt.toMillis === "function";
    const minuteStartedMs = timestampMillis(current.minuteStartedAt, nowMs);
    const minuteExpired =
      !hasMinuteStart || nowMs - minuteStartedMs >= QUOTA_MINUTE_MS;
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
      !hasHourStart || nowMs - hourStartedMs >= QUOTA_HOUR_MS;
    const hourCount = hourExpired
      ? 1
      : Number.isSafeInteger(current.hourCount)
        ? current.hourCount + 1
        : 1;

    if (minuteCount > minuteLimit || hourCount > hourLimit) {
      throw new HttpsError(
        "resource-exhausted",
        "Too many social actions. Please wait and try again.",
      );
    }

    transaction.set(reference, {
      kind: `socialGraph.${kind}`,
      minuteStartedAt: minuteExpired ? now : current.minuteStartedAt,
      minuteCount,
      hourStartedAt: hourExpired ? now : current.hourStartedAt,
      hourCount,
      updatedAt: now,
    });
    return { minuteCount, hourCount };
  });
}

async function requireActiveProfile(
  uid,
  label = "The account",
  readBudget = null,
) {
  readBudget?.reserve(1);
  const snapshot = await db.doc(`users/${uid}`).get();
  return profileData(snapshot, label);
}

async function requireVisiblePair(firstId, secondId) {
  const [firstBlock, secondBlock] = await Promise.all([
    db.doc(`users/${firstId}/blocked/${secondId}`).get(),
    db.doc(`users/${secondId}/blocked/${firstId}`).get(),
  ]);
  ensureNotBlocked(firstBlock, secondBlock);
}

async function requireTargetProfileVisibleToCaller(
  callerId,
  targetId,
  readBudget = null,
) {
  readBudget?.reserve(6);
  const [source, projection, forwardGuard, reverseGuard, firstBlock, secondBlock] =
    await Promise.all([
      db.doc(`users/${targetId}`).get(),
      db.doc(`publicProfiles/${targetId}`).get(),
      friendshipGuardReference(callerId, targetId).get(),
      friendshipGuardReference(targetId, callerId).get(),
      db.doc(`users/${callerId}/blocked/${targetId}`).get(),
      db.doc(`users/${targetId}/blocked/${callerId}`).get(),
    ]);

  const sourceData = profileData(source, "The selected");
  ensureNotBlocked(firstBlock, secondBlock);
  if (
    !projection.exists ||
    !sourceProfileVisibleToCaller({
      callerId,
      targetId,
      source: sourceData,
      forwardGuard,
      reverseGuard,
    })
  ) {
    // Do not expose whether the denial came from privacy settings or a stale
    // projection. Both mean the target graph is outside the caller's view.
    throw new HttpsError(
      "permission-denied",
      "The selected profile is not available to this account.",
    );
  }
  return sourceData;
}

function canonicalName(profile) {
  return (
    normalizeText(profile.displayName || profile.username, 80) ||
    "YO Voice user"
  );
}

function canonicalPhoto(profile) {
  return null;
}

function friendReference(ownerId, friendId) {
  return db.doc(`users/${ownerId}/friends/${friendId}`);
}

function friendshipGuardReference(ownerId, friendId) {
  return db.doc(`friendshipGuards/${ownerId}/friends/${friendId}`);
}

function canonicalFriendshipGuard(ownerId, friendId, establishedAt) {
  return {
    ownerId,
    friendId,
    schemaVersion: FRIENDSHIP_GUARD_SCHEMA_VERSION,
    establishedAt,
  };
}

function incomingRequestReference(recipientId, senderId) {
  return db.doc(`users/${recipientId}/friendRequests/${senderId}`);
}

function sentRequestReference(senderId, recipientId) {
  return db.doc(`users/${senderId}/sentFriendRequests/${recipientId}`);
}

function followingReference(followerId, targetId) {
  return db.doc(`users/${followerId}/following/${targetId}`);
}

function followerReference(targetId, followerId) {
  return db.doc(`users/${targetId}/followers/${followerId}`);
}

// friends/{id} subcollection reads are owner-only in firestore.rules — by
// design, friend lists are private. Mutual-friend/suggestion computation
// needs to read OTHER users' friend lists, which only the Admin SDK
// (running here, server-side) can do without weakening that rule for every
// client. Neither callable exposes anyone's friend list directly — only
// aggregate counts and the resulting candidate profiles.

async function boundedIds(
  query,
  maximum,
  label,
  { failOnOverflow = true, readBudget = null } = {},
) {
  readBudget?.reserve(maximum + (failOnOverflow ? 1 : 0));
  const snapshot = await query.limit(maximum + (failOnOverflow ? 1 : 0)).get();
  if (failOnOverflow && snapshot.size > maximum) {
    throw new HttpsError(
      "resource-exhausted",
      `${label} exceeds the supported safety limit. Please contact support.`,
    );
  }
  return snapshot.docs.slice(0, maximum).map((doc) => doc.id);
}

async function friendIdsOf(
  userId,
  {
    maximum = MAX_FRIENDS,
    failOnOverflow = true,
    label = "The friend graph",
    readBudget = null,
  } = {},
) {
  // Server-only friendship guards, not legacy user-readable mirrors, are the
  // authority for presence and graph discovery. No automatic backfill trusts
  // old symmetric documents: they require an explicit reviewed migration.
  return boundedIds(
    db
      .collection("friendshipGuards")
      .doc(userId)
      .collection("friends")
      .orderBy(FieldPath.documentId()),
    maximum,
    label,
    { failOnOverflow, readBudget },
  );
}

async function profileSummaries(userIds, callerId, readBudget = null) {
  if (userIds.length === 0) return new Map();
  readBudget?.reserve(userIds.length * 6);
  const [
    snapshots,
    sources,
    forwardGuards,
    reverseGuards,
    forwardBlocks,
    reverseBlocks,
  ] = await Promise.all([
    db.getAll(...userIds.map((id) => db.collection("publicProfiles").doc(id))),
    // A retrying projection can be briefly stale. Re-check the private
    // authority so a deleted, banned or disabled account is never disclosed.
    db.getAll(...userIds.map((id) => db.collection("users").doc(id))),
    db.getAll(...userIds.map((id) => friendshipGuardReference(callerId, id))),
    db.getAll(...userIds.map((id) => friendshipGuardReference(id, callerId))),
    db.getAll(...userIds.map((id) => db.doc(`users/${callerId}/blocked/${id}`))),
    db.getAll(...userIds.map((id) => db.doc(`users/${id}/blocked/${callerId}`))),
  ]);
  const result = new Map();
  for (let index = 0; index < snapshots.length; index += 1) {
    const snapshot = snapshots[index];
    const source = sources[index];
    const sourceData = source.exists ? (source.data() ?? {}) : null;
    if (
      !snapshot.exists ||
      !sourceData ||
      sourceData.banned === true ||
      sourceData.disabled === true ||
      forwardBlocks[index]?.exists ||
      reverseBlocks[index]?.exists ||
      !sourceProfileVisibleToCaller({
        callerId,
        targetId: snapshot.id,
        source: sourceData,
        forwardGuard: forwardGuards[index],
        reverseGuard: reverseGuards[index],
      })
    ) {
      continue;
    }
    const data = snapshot.data() ?? {};
    result.set(snapshot.id, {
      uid: snapshot.id,
      displayName: normalizeText(
        data.displayName || data.username || "YO Voice user",
        120,
      ),
      // Media is resolved by uid through the private media grant service.
      // Never turn a stale projection URL into a caller-controlled fetch.
      photoUrl: null,
      profileUpdatedAtMillis:
        data.updatedAt && typeof data.updatedAt.toMillis === "function"
          ? data.updatedAt.toMillis()
          : null,
    });
  }
  return result;
}

async function safeSuggestionSummaries(entries, callerId, readBudget) {
  if (entries.length === 0) return [];
  const ids = entries.map((entry) => entry.uid);
  readBudget.reserve(ids.length * 8);
  const [
    projections,
    sources,
    forwardGuards,
    reverseGuards,
    forwardBlocks,
    reverseBlocks,
    incomingRequests,
    outgoingRequests,
  ] = await Promise.all([
    db.getAll(...ids.map((id) => db.doc(`publicProfiles/${id}`))),
    db.getAll(...ids.map((id) => db.doc(`users/${id}`))),
    db.getAll(...ids.map((id) => friendshipGuardReference(callerId, id))),
    db.getAll(...ids.map((id) => friendshipGuardReference(id, callerId))),
    db.getAll(...ids.map((id) => db.doc(`users/${callerId}/blocked/${id}`))),
    db.getAll(...ids.map((id) => db.doc(`users/${id}/blocked/${callerId}`))),
    db.getAll(
      ...ids.map((id) => incomingRequestReference(callerId, id)),
    ),
    db.getAll(...ids.map((id) => sentRequestReference(callerId, id))),
  ]);

  const visible = [];
  for (let index = 0; index < ids.length; index += 1) {
    const uid = ids[index];
    const source = sources[index];
    const projection = projections[index];
    const sourceData = source.exists ? (source.data() ?? {}) : null;
    if (
      !projection.exists ||
      !sourceData ||
      sourceData.banned === true ||
      sourceData.disabled === true ||
      forwardGuards[index]?.exists ||
      reverseGuards[index]?.exists ||
      forwardBlocks[index]?.exists ||
      reverseBlocks[index]?.exists ||
      incomingRequests[index]?.exists ||
      outgoingRequests[index]?.exists ||
      !sourceProfileVisibleToCaller({
        callerId,
        targetId: uid,
        source: sourceData,
        forwardGuard: forwardGuards[index],
        reverseGuard: reverseGuards[index],
      })
    ) {
      continue;
    }
    const projectionData = projection.data() ?? {};
    visible.push({
      uid,
      displayName: normalizeText(
        projectionData.displayName ||
          projectionData.username ||
          "YO Voice user",
        120,
      ),
      photoUrl: null,
      profileUpdatedAtMillis:
        projectionData.updatedAt &&
        typeof projectionData.updatedAt.toMillis === "function"
          ? projectionData.updatedAt.toMillis()
          : null,
      mutualCount: entries[index].mutualCount,
    });
  }
  return visible;
}

function freshCacheData(
  snapshot,
  now,
  expectedKind,
  expectedTargetId = null,
) {
  if (!snapshot.exists) return null;
  const data = snapshot.data() ?? {};
  if (data.kind !== expectedKind) return null;
  if (expectedTargetId !== null && data.targetId !== expectedTargetId) {
    return null;
  }
  const expiresAt = data.expiresAt;
  if (
    !expiresAt ||
    typeof expiresAt.toMillis !== "function" ||
    expiresAt.toMillis() <= now.toMillis()
  ) {
    return null;
  }
  return data;
}

function validSuggestionCacheEntries(data) {
  if (!Array.isArray(data?.entries)) return null;
  const entries = data.entries
    .slice(0, MAX_SUGGESTION_CANDIDATES)
    .map((entry) => ({
      uid: normalizeText(entry?.uid, 128),
      mutualCount: entry?.mutualCount,
    }));
  if (
    entries.some(
      (entry) =>
        !SAFE_ID.test(entry.uid) ||
        !Number.isSafeInteger(entry.mutualCount) ||
        entry.mutualCount < 1 ||
        entry.mutualCount > MAX_FRIENDS_EXPANDED,
    )
  ) {
    return null;
  }
  return entries;
}

function validMutualCacheIds(data) {
  if (!Array.isArray(data?.ids)) return null;
  const ids = data.ids
    .slice(0, MAX_MUTUAL_FRIENDS_SCANNED)
    .map((value) => normalizeText(value, 128));
  return ids.every((uid) => SAFE_ID.test(uid)) ? ids : null;
}

function discoveryCacheData(kind, now, values, graphReadUpperBound) {
  return {
    kind,
    ...values,
    computedAt: now,
    expiresAt: Timestamp.fromMillis(
      now.toMillis() + FRIEND_DISCOVERY_CACHE_TTL_MS,
    ),
    graphReadUpperBound,
  };
}

const getMutualFriends = onCall(
  {
    region: REGION,
    enforceAppCheck: false,
    maxInstances: FRIEND_DISCOVERY_MAX_INSTANCES,
  },
  async (request) => {
    const auth = requireAuthentication(request);
    const targetUserId = normalizeText(request.data?.targetUserId, 128);

    if (!SAFE_ID.test(targetUserId)) {
      throw new HttpsError("invalid-argument", "targetUserId is required.");
    }
    if (targetUserId === auth.uid) {
      return { count: 0, sample: [] };
    }

    // This atomic one-document transaction must finish before any profile or
    // graph read. N+1 therefore costs one denied quota read, not hundreds of
    // downstream reads.
    await consumeFriendDiscoveryRateLimit(auth.uid, "mutuals");
    const now = Timestamp.now();
    const readBudget = new GraphReadBudget(MUTUAL_GRAPH_READ_BUDGET);

    await Promise.all([
      requireActiveProfile(auth.uid, "Your", readBudget),
      requireTargetProfileVisibleToCaller(
        auth.uid,
        targetUserId,
        readBudget,
      ),
    ]);

    const cacheRef = friendDiscoveryCacheReference(auth.uid, "mutuals");
    const cacheSnapshot = await cacheRef.get();
    const cache = freshCacheData(
      cacheSnapshot,
      now,
      "mutuals",
      targetUserId,
    );
    let mutualIds = validMutualCacheIds(cache);
    const cacheMiss = mutualIds === null;
    if (cacheMiss) {
      const [mine, theirs] = await Promise.all([
        friendIdsOf(auth.uid, {
          maximum: MAX_MUTUAL_FRIENDS_SCANNED,
          failOnOverflow: false,
          label: "Your mutual-friend scan",
          readBudget,
        }),
        friendIdsOf(targetUserId, {
          maximum: MAX_MUTUAL_FRIENDS_SCANNED,
          failOnOverflow: false,
          label: "The selected mutual-friend scan",
          readBudget,
        }),
      ]);
      const theirSet = new Set(theirs);
      mutualIds = mine.filter((id) => theirSet.has(id));
    }

    // Cache contains only raw intersection ids. Active state, privacy and
    // bilateral blocks are revalidated on every response, including hits.
    const profiles = await profileSummaries(mutualIds, auth.uid, readBudget);
    const visibleMutualIds = mutualIds.filter((id) => profiles.has(id));
    const sampleIds = visibleMutualIds.slice(0, 6);

    if (cacheMiss) {
      await cacheRef
        .set(
          discoveryCacheData(
            "mutuals",
            now,
            { targetId: targetUserId, ids: mutualIds },
            readBudget.reserved,
          ),
        )
        .catch(() => undefined);
    }

    return {
      count: visibleMutualIds.length,
      sample: sampleIds.map((id) => profiles.get(id)).filter(Boolean),
    };
  },
);

const getFriendSuggestions = onCall(
  {
    region: REGION,
    enforceAppCheck: false,
    maxInstances: FRIEND_DISCOVERY_MAX_INSTANCES,
  },
  async (request) => {
    const auth = requireAuthentication(request);
    // Keep App Check in telemetry/rollout mode until every shipped client has
    // a configured provider. Auth + this server-side atomic quota remain the
    // enforcement boundary during that rollout.
    await consumeFriendDiscoveryRateLimit(auth.uid, "suggestions");
    const limit = Math.min(
      Math.max(
        Number.parseInt(request.data?.limit, 10) || DEFAULT_SUGGESTION_LIMIT,
        1,
      ),
      MAX_SUGGESTION_LIMIT,
    );
    const now = Timestamp.now();
    const readBudget = new GraphReadBudget(SUGGESTION_GRAPH_READ_BUDGET);

    await requireActiveProfile(auth.uid, "Your", readBudget);

    const cacheRef = friendDiscoveryCacheReference(auth.uid, "suggestions");
    const cacheSnapshot = await cacheRef.get();
    const cache = freshCacheData(cacheSnapshot, now, "suggestions");
    let ranked = validSuggestionCacheEntries(cache);
    const cacheMiss = ranked === null;
    if (cacheMiss) {
      const myFriendIds = await friendIdsOf(auth.uid, {
        maximum: MAX_FRIENDS_SCANNED_FOR_DISCOVERY,
        failOnOverflow: false,
        label: "The suggestion source graph",
        readBudget,
      });
      const exclude = new Set([auth.uid, ...myFriendIds]);
      const expandIds = myFriendIds.slice(0, MAX_FRIENDS_EXPANDED);
      const theirFriendLists = await Promise.all(
        expandIds.map((userId) =>
          friendIdsOf(userId, {
            maximum: MAX_EXPANDED_FRIENDS_PER_SOURCE,
            failOnOverflow: false,
            label: "A suggestion expansion graph",
            readBudget,
          }),
        ),
      );

      const mutualCounts = new Map();
      for (const list of theirFriendLists) {
        for (const candidateId of list) {
          if (exclude.has(candidateId)) continue;
          if (
            mutualCounts.has(candidateId) ||
            mutualCounts.size < MAX_SUGGESTION_CANDIDATES
          ) {
            mutualCounts.set(
              candidateId,
              (mutualCounts.get(candidateId) ?? 0) + 1,
            );
          }
        }
      }

      ranked = [...mutualCounts.entries()]
        .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
        .slice(0, MAX_SUGGESTION_CANDIDATES)
        .map(([uid, mutualCount]) => ({ uid, mutualCount }));
    }

    // Unlike the old implementation, no complete block/request collection is
    // scanned. The bounded candidate set is checked by exact document ids,
    // and all sensitive visibility state is revalidated even on cache hits.
    const suggestions = await safeSuggestionSummaries(
      ranked,
      auth.uid,
      readBudget,
    );

    if (cacheMiss) {
      await cacheRef
        .set(
          discoveryCacheData(
            "suggestions",
            now,
            { entries: ranked },
            readBudget.reserved,
          ),
        )
        .catch(() => undefined);
    }

    return {
      suggestions: suggestions.slice(0, limit),
    };
  },
);

/**
 * Creates a request, or accepts the other party's existing request. Every
 * mirror, counter and notification is part of one Admin transaction; clients
 * cannot pick persisted identity fields or timestamps.
 */
const sendFriendRequest = onCall(
  { region: REGION, enforceAppCheck: false },
  async (request) => {
    const auth = requireAuthentication(request);
    await consumeSocialRateLimit(auth.uid, "mutation");
    requireVerified(auth);
    const targetUserId = targetIdFrom(request);
    if (targetUserId === auth.uid) {
      throw new HttpsError("invalid-argument", "You cannot add yourself.");
    }

    const actorRef = db.doc(`users/${auth.uid}`);
    const targetRef = db.doc(`users/${targetUserId}`);
    const actorRestrictionRef = db.doc(`restrictions/${auth.uid}`);
    const targetRestrictionRef = db.doc(`restrictions/${targetUserId}`);
    const actorBlockRef = db.doc(`users/${auth.uid}/blocked/${targetUserId}`);
    const targetBlockRef = db.doc(`users/${targetUserId}/blocked/${auth.uid}`);
    const myFriendRef = friendReference(auth.uid, targetUserId);
    const theirFriendRef = friendReference(targetUserId, auth.uid);
    const myGuardRef = friendshipGuardReference(auth.uid, targetUserId);
    const theirGuardRef = friendshipGuardReference(targetUserId, auth.uid);
    const outgoingRef = incomingRequestReference(targetUserId, auth.uid);
    const outgoingMirrorRef = sentRequestReference(auth.uid, targetUserId);
    const incomingRef = incomingRequestReference(auth.uid, targetUserId);
    const incomingMirrorRef = sentRequestReference(targetUserId, auth.uid);
    const actorCapacityRef = socialCapacityReference(auth.uid);
    const targetCapacityRef = socialCapacityReference(targetUserId);
    const requestNotificationId = newSocialNotificationId(
      "friendRequest",
      auth.uid,
    );
    const targetNotificationRef = notificationReference(
      targetUserId,
      requestNotificationId,
    );
    const legacyTargetNotificationRef = notificationReference(
      targetUserId,
      `friendRequest_${auth.uid}`,
    );
    const acceptedNotificationId = newSocialNotificationId(
      "friendAccepted",
      auth.uid,
    );
    const acceptedNotificationRef = notificationReference(
      targetUserId,
      acceptedNotificationId,
    );
    const legacyAcceptedNotificationRef = notificationReference(
      targetUserId,
      `friendAccepted_${auth.uid}`,
    );
    const legacyActorRequestNotificationRef = notificationReference(
      auth.uid,
      `friendRequest_${targetUserId}`,
    );

    const result = await db.runTransaction(async (transaction) => {
      const [
        actorSnapshot,
        targetSnapshot,
        actorRestriction,
        targetRestriction,
        actorBlock,
        targetBlock,
        myFriend,
        theirFriend,
        myGuard,
        theirGuard,
        outgoing,
        outgoingMirror,
        incoming,
        incomingMirror,
        actorCapacitySnapshot,
        targetCapacitySnapshot,
      ] = await transaction.getAll(
        actorRef,
        targetRef,
        actorRestrictionRef,
        targetRestrictionRef,
        actorBlockRef,
        targetBlockRef,
        myFriendRef,
        theirFriendRef,
        myGuardRef,
        theirGuardRef,
        outgoingRef,
        outgoingMirrorRef,
        incomingRef,
        incomingMirrorRef,
        actorCapacityRef,
        targetCapacityRef,
      );
      const actorCapacity = socialCapacityState(
        auth.uid,
        actorCapacitySnapshot,
      );
      const targetCapacity = socialCapacityState(
        targetUserId,
        targetCapacitySnapshot,
      );
      const actor = profileData(actorSnapshot, "Your");
      const target = profileData(targetSnapshot, "The selected");
      ensureNotRestricted(actorRestriction, "Your");
      ensureNotRestricted(targetRestriction, "The selected");
      ensureNotBlocked(actorBlock, targetBlock);

      if (myFriend.exists !== theirFriend.exists) {
        throw new HttpsError(
          "data-loss",
          "The friendship mirrors are inconsistent. Please contact support.",
        );
      }
      if (myGuard.exists !== theirGuard.exists) {
        throw new HttpsError(
          "data-loss",
          "The friendship guards are inconsistent. Please contact support.",
        );
      }
      if (myFriend.exists !== myGuard.exists) {
        // Deliberately do not bless legacy symmetric mirrors. They may have
        // been forged under old Rules and need a reviewed migration.
        throw new HttpsError(
          "data-loss",
          "This legacy friendship must be reviewed before it can be used.",
        );
      }
      if (myFriend.exists) {
        return { outcome: "alreadyFriends", changed: false };
      }
      if (outgoing.exists) {
        // Heal a legacy missing private mirror without replaying the event or
        // resurrecting a notification the recipient intentionally deleted.
        if (!outgoingMirror.exists) {
          await ensureSocialCapacity(
            transaction,
            actorCapacity,
            "pendingOutgoing",
          );
          if (!socialCapacityHasRoom(actorCapacity, "pendingOutgoing")) {
            persistSocialCapacity(transaction, actorCapacity);
            return { capacityExceeded: true };
          }
          adjustSocialCapacity(actorCapacity, "pendingOutgoing", 1);
          persistSocialCapacity(transaction, actorCapacity);
          const existingNotificationId = storedNotificationId(
            outgoing.data(),
            `friendRequest_${auth.uid}`,
          );
          transaction.set(outgoingMirrorRef, {
            receiverId: targetUserId,
            ...(existingNotificationId
              ? { notificationId: existingNotificationId }
              : {}),
            createdAt:
              outgoing.data()?.createdAt ?? FieldValue.serverTimestamp(),
          });
        }
        return { outcome: "alreadyPending", changed: false };
      }

      if (incoming.exists) {
        if (incoming.data()?.senderId !== targetUserId) {
          throw new HttpsError(
            "data-loss",
            "The pending friend request is not canonical.",
          );
        }
        const timestamp = FieldValue.serverTimestamp();
        requireCapacity(
          actor,
          "friendCount",
          MAX_FRIENDS,
          "You have reached the friend limit.",
        );
        requireCapacity(
          target,
          "friendCount",
          MAX_FRIENDS,
          "The selected account has reached the friend limit.",
        );
        await ensureSocialCapacity(
          transaction,
          actorCapacity,
          "pendingIncoming",
        );
        if (incomingMirror.exists) {
          await ensureSocialCapacity(
            transaction,
            targetCapacity,
            "pendingOutgoing",
          );
        }
        adjustSocialCapacity(actorCapacity, "pendingIncoming", -1);
        if (incomingMirror.exists) {
          adjustSocialCapacity(targetCapacity, "pendingOutgoing", -1);
        }
        persistSocialCapacity(transaction, actorCapacity);
        persistSocialCapacity(transaction, targetCapacity);
        transaction.create(myFriendRef, {
          userId: targetUserId,
          acceptanceNotificationId: acceptedNotificationId,
          acceptanceRecipientId: targetUserId,
          createdAt: timestamp,
        });
        transaction.create(theirFriendRef, {
          userId: auth.uid,
          acceptanceNotificationId: acceptedNotificationId,
          acceptanceRecipientId: targetUserId,
          createdAt: timestamp,
        });
        transaction.create(
          myGuardRef,
          canonicalFriendshipGuard(auth.uid, targetUserId, timestamp),
        );
        transaction.create(
          theirGuardRef,
          canonicalFriendshipGuard(targetUserId, auth.uid, timestamp),
        );
        transaction.update(actorRef, {
          friendCount: countOf(actor, "friendCount") + 1,
        });
        transaction.update(targetRef, {
          friendCount: countOf(target, "friendCount") + 1,
        });
        transaction.delete(incomingRef);
        transaction.delete(incomingMirrorRef);
        transaction.delete(legacyAcceptedNotificationRef);
        transaction.create(
          acceptedNotificationRef,
          canonicalNotificationData({
            actorId: auth.uid,
            actorProfile: actor,
            type: "friendAccepted",
            dedupeKey: acceptedNotificationId,
          }),
        );
        // This row is an actionable request, not permanent activity history.
        // Removing it prevents a resolved request from lingering in the bell
        // and makes a later request lifecycle a real document create + push.
        const incomingNotificationId = storedNotificationId(
          incoming.data(),
          `friendRequest_${targetUserId}`,
        );
        if (incomingNotificationId) {
          transaction.delete(
            notificationReference(auth.uid, incomingNotificationId),
          );
        }
        transaction.delete(legacyActorRequestNotificationRef);
        return { outcome: "accepted", changed: true };
      }

      await ensureSocialCapacity(
        transaction,
        actorCapacity,
        "pendingOutgoing",
      );
      await ensureSocialCapacity(
        transaction,
        targetCapacity,
        "pendingIncoming",
      );
      if (
        !socialCapacityHasRoom(actorCapacity, "pendingOutgoing") ||
        !socialCapacityHasRoom(targetCapacity, "pendingIncoming")
      ) {
        // Persist a one-time bounded legacy migration even when it discovers
        // a full collection. Throwing inside the transaction would roll this
        // state back and let an attacker force the 201-read scan repeatedly.
        persistSocialCapacity(transaction, actorCapacity);
        persistSocialCapacity(transaction, targetCapacity);
        return { capacityExceeded: true };
      }
      adjustSocialCapacity(actorCapacity, "pendingOutgoing", 1);
      adjustSocialCapacity(targetCapacity, "pendingIncoming", 1);
      persistSocialCapacity(transaction, actorCapacity);
      persistSocialCapacity(transaction, targetCapacity);
      const timestamp = FieldValue.serverTimestamp();
      transaction.create(outgoingRef, {
        senderId: auth.uid,
        senderName: canonicalName(actor),
        senderPhotoUrl: canonicalPhoto(actor),
        notificationId: requestNotificationId,
        createdAt: timestamp,
      });
      transaction.create(outgoingMirrorRef, {
        receiverId: targetUserId,
        notificationId: requestNotificationId,
        createdAt: timestamp,
      });
      // Legacy rows used one id for the lifetime of a pair. Retire that row,
      // then create a generation-specific id so the first post-upgrade
      // lifecycle also produces an onCreate push.
      transaction.delete(legacyTargetNotificationRef);
      transaction.create(
        targetNotificationRef,
        canonicalNotificationData({
          actorId: auth.uid,
          actorProfile: actor,
          type: "friendRequest",
          dedupeKey: requestNotificationId,
        }),
      );
      return { outcome: "requested", changed: true };
    });
    if (result.capacityExceeded === true) {
      throw new HttpsError(
        "resource-exhausted",
        "The pending friend-request limit has been reached.",
      );
    }
    return result;
  },
);

const respondToFriendRequest = onCall(
  { region: REGION, enforceAppCheck: false },
  async (request) => {
    const auth = requireAuthentication(request);
    await consumeSocialRateLimit(auth.uid, "mutation");
    const senderId = targetIdFrom(request);
    const accept = request.data?.accept;
    if (typeof accept !== "boolean") {
      throw new HttpsError(
        "invalid-argument",
        "An accept decision is required.",
      );
    }
    if (senderId === auth.uid) {
      throw new HttpsError("invalid-argument", "The sender is invalid.");
    }

    const actorRef = db.doc(`users/${auth.uid}`);
    const senderRef = db.doc(`users/${senderId}`);
    const actorRestrictionRef = db.doc(`restrictions/${auth.uid}`);
    const senderRestrictionRef = db.doc(`restrictions/${senderId}`);
    const actorBlockRef = db.doc(`users/${auth.uid}/blocked/${senderId}`);
    const senderBlockRef = db.doc(`users/${senderId}/blocked/${auth.uid}`);
    const requestRef = incomingRequestReference(auth.uid, senderId);
    const sentRef = sentRequestReference(senderId, auth.uid);
    const actorCapacityRef = socialCapacityReference(auth.uid);
    const senderCapacityRef = socialCapacityReference(senderId);
    const myFriendRef = friendReference(auth.uid, senderId);
    const senderFriendRef = friendReference(senderId, auth.uid);
    const myGuardRef = friendshipGuardReference(auth.uid, senderId);
    const senderGuardRef = friendshipGuardReference(senderId, auth.uid);
    const legacyRequestNotificationRef = notificationReference(
      auth.uid,
      `friendRequest_${senderId}`,
    );
    const acceptedNotificationId = newSocialNotificationId(
      "friendAccepted",
      auth.uid,
    );
    const acceptedNotificationRef = notificationReference(
      senderId,
      acceptedNotificationId,
    );
    const legacyAcceptedNotificationRef = notificationReference(
      senderId,
      `friendAccepted_${auth.uid}`,
    );

    return db.runTransaction(async (transaction) => {
      const [
        actorSnapshot,
        senderSnapshot,
        actorRestriction,
        senderRestriction,
        actorBlock,
        senderBlock,
        pending,
        sent,
        myFriend,
        senderFriend,
        myGuard,
        senderGuard,
        actorCapacitySnapshot,
        senderCapacitySnapshot,
      ] = await transaction.getAll(
        actorRef,
        senderRef,
        actorRestrictionRef,
        senderRestrictionRef,
        actorBlockRef,
        senderBlockRef,
        requestRef,
        sentRef,
        myFriendRef,
        senderFriendRef,
        myGuardRef,
        senderGuardRef,
        actorCapacityRef,
        senderCapacityRef,
      );
      const actorCapacity = socialCapacityState(
        auth.uid,
        actorCapacitySnapshot,
      );
      const senderCapacity = socialCapacityState(
        senderId,
        senderCapacitySnapshot,
      );
      const actor = profileData(actorSnapshot, "Your");

      if (!pending.exists) {
        if (
          accept &&
          myFriend.exists &&
          senderFriend.exists &&
          myGuard.exists &&
          senderGuard.exists
        ) {
          transaction.delete(legacyRequestNotificationRef);
          return { outcome: "alreadyAccepted", changed: false };
        }
        if (!accept) {
          transaction.delete(legacyRequestNotificationRef);
          return { outcome: "alreadyResolved", changed: false };
        }
        throw new HttpsError(
          "not-found",
          "This friend request is no longer available.",
        );
      }
      if (pending.data()?.senderId !== senderId) {
        throw new HttpsError(
          "data-loss",
          "The friend request is not canonical.",
        );
      }

      const timestamp = FieldValue.serverTimestamp();
      await ensureSocialCapacity(
        transaction,
        actorCapacity,
        "pendingIncoming",
      );
      if (sent.exists) {
        await ensureSocialCapacity(
          transaction,
          senderCapacity,
          "pendingOutgoing",
        );
      }
      adjustSocialCapacity(actorCapacity, "pendingIncoming", -1);
      if (sent.exists) {
        adjustSocialCapacity(senderCapacity, "pendingOutgoing", -1);
      }
      persistSocialCapacity(transaction, actorCapacity);
      persistSocialCapacity(transaction, senderCapacity);
      if (!accept) {
        transaction.delete(requestRef);
        transaction.delete(sentRef);
        const pendingNotificationId = storedNotificationId(
          pending.data(),
          `friendRequest_${senderId}`,
        );
        if (pendingNotificationId) {
          transaction.delete(
            notificationReference(auth.uid, pendingNotificationId),
          );
        }
        transaction.delete(legacyRequestNotificationRef);
        return { outcome: "declined", changed: true };
      }

      requireVerified(auth);
      const sender = profileData(senderSnapshot, "The sender's");
      ensureNotRestricted(actorRestriction, "Your");
      ensureNotRestricted(senderRestriction, "The sender's");
      ensureNotBlocked(actorBlock, senderBlock);
      if (myFriend.exists !== senderFriend.exists) {
        throw new HttpsError(
          "data-loss",
          "The friendship mirrors are inconsistent. Please contact support.",
        );
      }
      if (myGuard.exists !== senderGuard.exists) {
        throw new HttpsError(
          "data-loss",
          "The friendship guards are inconsistent. Please contact support.",
        );
      }
      if (myFriend.exists !== myGuard.exists) {
        throw new HttpsError(
          "data-loss",
          "This legacy friendship must be reviewed before it can be used.",
        );
      }
      if (!myFriend.exists) {
        requireCapacity(
          actor,
          "friendCount",
          MAX_FRIENDS,
          "You have reached the friend limit.",
        );
        requireCapacity(
          sender,
          "friendCount",
          MAX_FRIENDS,
          "The sender has reached the friend limit.",
        );
        transaction.create(myFriendRef, {
          userId: senderId,
          acceptanceNotificationId: acceptedNotificationId,
          acceptanceRecipientId: senderId,
          createdAt: timestamp,
        });
        transaction.create(senderFriendRef, {
          userId: auth.uid,
          acceptanceNotificationId: acceptedNotificationId,
          acceptanceRecipientId: senderId,
          createdAt: timestamp,
        });
        transaction.create(
          myGuardRef,
          canonicalFriendshipGuard(auth.uid, senderId, timestamp),
        );
        transaction.create(
          senderGuardRef,
          canonicalFriendshipGuard(senderId, auth.uid, timestamp),
        );
        transaction.update(actorRef, {
          friendCount: countOf(actor, "friendCount") + 1,
        });
        transaction.update(senderRef, {
          friendCount: countOf(sender, "friendCount") + 1,
        });
        transaction.delete(legacyAcceptedNotificationRef);
        transaction.create(
          acceptedNotificationRef,
          canonicalNotificationData({
            actorId: auth.uid,
            actorProfile: actor,
            type: "friendAccepted",
            dedupeKey: acceptedNotificationId,
          }),
        );
      }
      transaction.delete(requestRef);
      transaction.delete(sentRef);
      const pendingNotificationId = storedNotificationId(
        pending.data(),
        `friendRequest_${senderId}`,
      );
      if (pendingNotificationId) {
        transaction.delete(
          notificationReference(auth.uid, pendingNotificationId),
        );
      }
      transaction.delete(legacyRequestNotificationRef);
      return { outcome: "accepted", changed: !myFriend.exists };
    });
  },
);

const cancelFriendRequest = onCall(
  { region: REGION, enforceAppCheck: false },
  async (request) => {
    const auth = requireAuthentication(request);
    await consumeSocialRateLimit(auth.uid, "mutation");
    const targetUserId = targetIdFrom(request);
    if (targetUserId === auth.uid) {
      throw new HttpsError(
        "invalid-argument",
        "You cannot cancel a request to yourself.",
      );
    }
    const requestRef = incomingRequestReference(targetUserId, auth.uid);
    const sentRef = sentRequestReference(auth.uid, targetUserId);
    const actorCapacityRef = socialCapacityReference(auth.uid);
    const targetCapacityRef = socialCapacityReference(targetUserId);
    const legacyRequestNotificationRef = notificationReference(
      targetUserId,
      `friendRequest_${auth.uid}`,
    );
    return db.runTransaction(async (transaction) => {
      const [pending, sent, actorCapacitySnapshot, targetCapacitySnapshot] =
        await transaction.getAll(
        requestRef,
        sentRef,
        actorCapacityRef,
        targetCapacityRef,
      );
      if (!pending.exists && !sent.exists) {
        // A previous partial rollout may have left only the alert behind.
        // Retire it on replay so the recipient never sees an actionable
        // request that no longer exists.
        transaction.delete(legacyRequestNotificationRef);
        return { changed: false };
      }
      if (pending.exists && pending.data()?.senderId !== auth.uid) {
        throw new HttpsError(
          "data-loss",
          "The friend request is not canonical.",
        );
      }
      const requestNotificationId = storedNotificationId(
        pending.exists ? pending.data() : sent.data(),
        `friendRequest_${auth.uid}`,
      );
      const actorCapacity = socialCapacityState(
        auth.uid,
        actorCapacitySnapshot,
      );
      const targetCapacity = socialCapacityState(
        targetUserId,
        targetCapacitySnapshot,
      );
      if (sent.exists) {
        await ensureSocialCapacity(
          transaction,
          actorCapacity,
          "pendingOutgoing",
        );
        adjustSocialCapacity(actorCapacity, "pendingOutgoing", -1);
      }
      if (pending.exists) {
        await ensureSocialCapacity(
          transaction,
          targetCapacity,
          "pendingIncoming",
        );
        adjustSocialCapacity(targetCapacity, "pendingIncoming", -1);
      }
      persistSocialCapacity(transaction, actorCapacity);
      persistSocialCapacity(transaction, targetCapacity);
      transaction.delete(requestRef);
      transaction.delete(sentRef);
      if (requestNotificationId) {
        transaction.delete(
          notificationReference(targetUserId, requestNotificationId),
        );
      }
      transaction.delete(legacyRequestNotificationRef);
      return { changed: true };
    });
  },
);

const removeFriend = onCall(
  { region: REGION, enforceAppCheck: false },
  async (request) => {
    const auth = requireAuthentication(request);
    await consumeSocialRateLimit(auth.uid, "mutation");
    const targetUserId = targetIdFrom(request);
    if (targetUserId === auth.uid) {
      throw new HttpsError("invalid-argument", "You cannot remove yourself.");
    }
    const actorRef = db.doc(`users/${auth.uid}`);
    const targetRef = db.doc(`users/${targetUserId}`);
    const myFriendRef = friendReference(auth.uid, targetUserId);
    const theirFriendRef = friendReference(targetUserId, auth.uid);
    const myGuardRef = friendshipGuardReference(auth.uid, targetUserId);
    const theirGuardRef = friendshipGuardReference(targetUserId, auth.uid);
    const myAcceptedNotificationRef = notificationReference(
      auth.uid,
      `friendAccepted_${targetUserId}`,
    );
    const theirAcceptedNotificationRef = notificationReference(
      targetUserId,
      `friendAccepted_${auth.uid}`,
    );
    return db.runTransaction(async (transaction) => {
      const [actorSnapshot, targetSnapshot, mine, theirs, myGuard, theirGuard] =
        await transaction.getAll(
          actorRef,
          targetRef,
          myFriendRef,
          theirFriendRef,
          myGuardRef,
          theirGuardRef,
        );
      const actor = profileData(actorSnapshot, "Your");
      if (
        !mine.exists &&
        !theirs.exists &&
        !myGuard.exists &&
        !theirGuard.exists
      ) {
        // Idempotent replay also repairs a previous partial lifecycle:
        // no friendship means an old acceptance alert must not survive.
        transaction.delete(myAcceptedNotificationRef);
        transaction.delete(theirAcceptedNotificationRef);
        return { changed: false };
      }
      transaction.delete(myFriendRef);
      transaction.delete(theirFriendRef);
      transaction.delete(myGuardRef);
      transaction.delete(theirGuardRef);
      const acceptance =
        storedAcceptanceNotification(mine.data(), auth.uid, targetUserId) ??
        storedAcceptanceNotification(theirs.data(), auth.uid, targetUserId);
      if (acceptance) {
        transaction.delete(
          notificationReference(
            acceptance.recipientId,
            acceptance.notificationId,
          ),
        );
      }
      // Remove only the retired pair-lifetime ids. New acceptance activity
      // uses a generation-specific id, so a later legitimate re-acceptance
      // is independently created without rewriting its truthful history.
      transaction.delete(myAcceptedNotificationRef);
      transaction.delete(theirAcceptedNotificationRef);
      transaction.update(actorRef, {
        friendCount: Math.max(countOf(actor, "friendCount") - 1, 0),
      });
      if (targetSnapshot.exists) {
        transaction.update(targetRef, {
          friendCount: Math.max(
            countOf(targetSnapshot.data(), "friendCount") - 1,
            0,
          ),
        });
      }
      return { changed: true };
    });
  },
);

const setFollow = onCall(
  { region: REGION, enforceAppCheck: false },
  async (request) => {
    const auth = requireAuthentication(request);
    await consumeSocialRateLimit(auth.uid, "mutation");
    const targetUserId = targetIdFrom(request);
    const following = request.data?.following;
    if (typeof following !== "boolean" || targetUserId === auth.uid) {
      throw new HttpsError(
        "invalid-argument",
        "A valid follow action is required.",
      );
    }
    if (following) requireVerified(auth);

    const actorRef = db.doc(`users/${auth.uid}`);
    const targetRef = db.doc(`users/${targetUserId}`);
    const actorRestrictionRef = db.doc(`restrictions/${auth.uid}`);
    const targetRestrictionRef = db.doc(`restrictions/${targetUserId}`);
    const actorBlockRef = db.doc(`users/${auth.uid}/blocked/${targetUserId}`);
    const targetBlockRef = db.doc(`users/${targetUserId}/blocked/${auth.uid}`);
    const followingRef = followingReference(auth.uid, targetUserId);
    const followerRef = followerReference(targetUserId, auth.uid);
    const followNotificationId = newSocialNotificationId("follow", auth.uid);
    const notificationRef = notificationReference(
      targetUserId,
      followNotificationId,
    );
    const legacyNotificationRef = notificationReference(
      targetUserId,
      `follow_${auth.uid}`,
    );

    return db.runTransaction(async (transaction) => {
      const [
        actorSnapshot,
        targetSnapshot,
        actorRestriction,
        targetRestriction,
        actorBlock,
        targetBlock,
        followingEdge,
        followerEdge,
      ] = await transaction.getAll(
        actorRef,
        targetRef,
        actorRestrictionRef,
        targetRestrictionRef,
        actorBlockRef,
        targetBlockRef,
        followingRef,
        followerRef,
      );
      const actor = profileData(actorSnapshot, "Your");
      if (followingEdge.exists !== followerEdge.exists) {
        throw new HttpsError(
          "data-loss",
          "The follow mirrors are inconsistent. Please contact support.",
        );
      }
      if (following) {
        const target = profileData(targetSnapshot, "The selected");
        ensureNotRestricted(actorRestriction, "Your");
        ensureNotRestricted(targetRestriction, "The selected");
        ensureNotBlocked(actorBlock, targetBlock);
        if (followingEdge.exists) {
          // Opportunistically scrub stale identity snapshots from legacy
          // edges. Identity is resolved from publicProfiles at read time.
          const followedAt =
            followingEdge.data()?.followedAt ?? FieldValue.serverTimestamp();
          const existingNotificationId = storedNotificationId(
            followingEdge.data(),
            `follow_${auth.uid}`,
          );
          transaction.set(followingRef, {
            uid: targetUserId,
            followedAt,
            ...(existingNotificationId
              ? { notificationId: existingNotificationId }
              : {}),
          });
          transaction.set(followerRef, {
            uid: auth.uid,
            followedAt,
            ...(existingNotificationId
              ? { notificationId: existingNotificationId }
              : {}),
          });
          return { changed: false, following: true };
        }
        requireCapacity(
          actor,
          "followingCount",
          MAX_FOLLOWING,
          "You have reached the following limit.",
        );
        const timestamp = FieldValue.serverTimestamp();
        transaction.create(followingRef, {
          uid: targetUserId,
          notificationId: followNotificationId,
          followedAt: timestamp,
        });
        transaction.create(followerRef, {
          uid: auth.uid,
          notificationId: followNotificationId,
          followedAt: timestamp,
        });
        transaction.update(actorRef, {
          followingCount: countOf(actor, "followingCount") + 1,
        });
        transaction.update(targetRef, {
          followerCount: countOf(target, "followerCount") + 1,
        });
        transaction.delete(legacyNotificationRef);
        transaction.create(
          notificationRef,
          canonicalNotificationData({
            actorId: auth.uid,
            actorProfile: actor,
            type: "follow",
            dedupeKey: followNotificationId,
          }),
        );
        return { changed: true, following: true };
      }

      if (!followingEdge.exists) {
        // A previous partial lifecycle may have removed the graph edge but
        // left the legacy deterministic activity row behind. Repair it so
        // a later re-follow is a fresh create and can emit a fresh push.
        transaction.delete(legacyNotificationRef);
        return { changed: false, following: false };
      }
      const currentNotificationId = storedNotificationId(
        followingEdge.data(),
        `follow_${auth.uid}`,
      );
      transaction.delete(followingRef);
      transaction.delete(followerRef);
      if (currentNotificationId) {
        transaction.delete(
          notificationReference(targetUserId, currentNotificationId),
        );
      }
      transaction.delete(legacyNotificationRef);
      transaction.update(actorRef, {
        followingCount: Math.max(countOf(actor, "followingCount") - 1, 0),
      });
      if (targetSnapshot.exists) {
        transaction.update(targetRef, {
          followerCount: Math.max(
            countOf(targetSnapshot.data(), "followerCount") - 1,
            0,
          ),
        });
      }
      return { changed: true, following: false };
    });
  },
);

const setUserBlock = onCall(
  { region: REGION, enforceAppCheck: false },
  async (request) => {
    const auth = requireAuthentication(request);
    await consumeSocialRateLimit(auth.uid, "mutation");
    const targetUserId = targetIdFrom(request);
    const blocked = request.data?.blocked;
    if (typeof blocked !== "boolean" || targetUserId === auth.uid) {
      throw new HttpsError(
        "invalid-argument",
        "A valid block action is required.",
      );
    }
    const actorRef = db.doc(`users/${auth.uid}`);
    const targetRef = db.doc(`users/${targetUserId}`);
    const blockRef = db.doc(`users/${auth.uid}/blocked/${targetUserId}`);
    const actorCapacityRef = socialCapacityReference(auth.uid);
    const targetCapacityRef = socialCapacityReference(targetUserId);
    if (!blocked) {
      return db.runTransaction(async (transaction) => {
        const [actor, existingBlock, actorCapacitySnapshot] =
          await transaction.getAll(actorRef, blockRef, actorCapacityRef);
        profileData(actor, "Your");
        const actorCapacity = socialCapacityState(
          auth.uid,
          actorCapacitySnapshot,
        );
        await ensureSocialCapacity(
          transaction,
          actorCapacity,
          "blocked",
        );
        if (existingBlock.exists) {
          adjustSocialCapacity(actorCapacity, "blocked", -1);
          transaction.delete(blockRef);
        }
        persistSocialCapacity(transaction, actorCapacity);
        return { changed: existingBlock.exists, blocked: false };
      });
    }

    const refs = {
      myFriend: friendReference(auth.uid, targetUserId),
      theirFriend: friendReference(targetUserId, auth.uid),
      myFollowing: followingReference(auth.uid, targetUserId),
      theirFollower: followerReference(targetUserId, auth.uid),
      theirFollowing: followingReference(targetUserId, auth.uid),
      myFollower: followerReference(auth.uid, targetUserId),
      outgoing: incomingRequestReference(targetUserId, auth.uid),
      outgoingMirror: sentRequestReference(auth.uid, targetUserId),
      incoming: incomingRequestReference(auth.uid, targetUserId),
      incomingMirror: sentRequestReference(targetUserId, auth.uid),
      myGuard: friendshipGuardReference(auth.uid, targetUserId),
      theirGuard: friendshipGuardReference(targetUserId, auth.uid),
    };
    const result = await db.runTransaction(async (transaction) => {
      const snapshots = await transaction.getAll(
        actorRef,
        targetRef,
        blockRef,
        ...Object.values(refs),
        actorCapacityRef,
        targetCapacityRef,
      );
      const actor = profileData(snapshots[0], "Your");
      const targetSnapshot = snapshots[1];
      profileData(targetSnapshot, "The selected");
      const existingBlock = snapshots[2];
      const edgeSnapshots = Object.fromEntries(
        Object.keys(refs).map((key, index) => [key, snapshots[index + 3]]),
      );
      const actorCapacity = socialCapacityState(
        auth.uid,
        snapshots[3 + Object.keys(refs).length],
      );
      const targetCapacity = socialCapacityState(
        targetUserId,
        snapshots[4 + Object.keys(refs).length],
      );
      const {
        myFriend,
        theirFriend,
        myFollowing,
        theirFollower,
        theirFollowing,
        myFollower,
        outgoing,
        outgoingMirror,
        incoming,
        incomingMirror,
      } = edgeSnapshots;
      const target = targetSnapshot.data() ?? {};

      await ensureSocialCapacity(transaction, actorCapacity, "blocked");
      if (!existingBlock.exists) {
        if (!socialCapacityHasRoom(actorCapacity, "blocked")) {
          persistSocialCapacity(transaction, actorCapacity);
          return { capacityExceeded: true };
        }
        adjustSocialCapacity(actorCapacity, "blocked", 1);
      }
      if (outgoingMirror.exists) {
        await ensureSocialCapacity(
          transaction,
          actorCapacity,
          "pendingOutgoing",
        );
        adjustSocialCapacity(actorCapacity, "pendingOutgoing", -1);
      }
      if (incoming.exists) {
        await ensureSocialCapacity(
          transaction,
          actorCapacity,
          "pendingIncoming",
        );
        adjustSocialCapacity(actorCapacity, "pendingIncoming", -1);
      }
      if (outgoing.exists) {
        await ensureSocialCapacity(
          transaction,
          targetCapacity,
          "pendingIncoming",
        );
        adjustSocialCapacity(targetCapacity, "pendingIncoming", -1);
      }
      if (incomingMirror.exists) {
        await ensureSocialCapacity(
          transaction,
          targetCapacity,
          "pendingOutgoing",
        );
        adjustSocialCapacity(targetCapacity, "pendingOutgoing", -1);
      }
      persistSocialCapacity(transaction, actorCapacity);
      persistSocialCapacity(transaction, targetCapacity);

      const dynamicNotifications = [
        {
          recipientId: targetUserId,
          notificationId: storedNotificationId(
            outgoing.data(),
            `friendRequest_${auth.uid}`,
          ),
        },
        {
          recipientId: auth.uid,
          notificationId: storedNotificationId(
            incoming.data(),
            `friendRequest_${targetUserId}`,
          ),
        },
        {
          recipientId: targetUserId,
          notificationId: storedNotificationId(
            myFollowing.data(),
            `follow_${auth.uid}`,
          ),
        },
        {
          recipientId: auth.uid,
          notificationId: storedNotificationId(
            theirFollowing.data(),
            `follow_${targetUserId}`,
          ),
        },
        storedAcceptanceNotification(
          myFriend.data(),
          auth.uid,
          targetUserId,
        ) ??
          storedAcceptanceNotification(
            theirFriend.data(),
            auth.uid,
            targetUserId,
          ),
      ].filter((entry) => entry?.notificationId);

      for (const reference of Object.values(refs))
        transaction.delete(reference);
      for (const entry of dynamicNotifications) {
        transaction.delete(
          notificationReference(entry.recipientId, entry.notificationId),
        );
      }
      const actorUpdate = {};
      const targetUpdate = {};
      const hadFriendship = myFriend.exists || theirFriend.exists;
      if (hadFriendship) {
        actorUpdate.friendCount = Math.max(
          countOf(actor, "friendCount") - 1,
          0,
        );
        targetUpdate.friendCount = Math.max(
          countOf(target, "friendCount") - 1,
          0,
        );
      }
      if (myFollowing.exists || theirFollower.exists) {
        actorUpdate.followingCount = Math.max(
          countOf(actor, "followingCount") - 1,
          0,
        );
        targetUpdate.followerCount = Math.max(
          countOf(target, "followerCount") - 1,
          0,
        );
      }
      if (theirFollowing.exists || myFollower.exists) {
        actorUpdate.followerCount = Math.max(
          countOf(actor, "followerCount") - 1,
          0,
        );
        targetUpdate.followingCount = Math.max(
          countOf(target, "followingCount") - 1,
          0,
        );
      }
      if (Object.keys(actorUpdate).length > 0) {
        transaction.update(actorRef, actorUpdate);
      }
      if (Object.keys(targetUpdate).length > 0) {
        transaction.update(targetRef, targetUpdate);
      }
      if (!existingBlock.exists) {
        transaction.create(blockRef, {
          userId: targetUserId,
          createdAt: FieldValue.serverTimestamp(),
        });
      }

      for (const [recipientId, actorId] of [
        [auth.uid, targetUserId],
        [targetUserId, auth.uid],
      ]) {
        for (const type of ["friendRequest", "friendAccepted", "follow"]) {
          transaction.delete(
            notificationReference(recipientId, `${type}_${actorId}`),
          );
        }
      }
      return { changed: !existingBlock.exists, blocked: true };
    });
    if (result.capacityExceeded === true) {
      throw new HttpsError(
        "resource-exhausted",
        "You have reached the block-list safety limit.",
      );
    }
    return result;
  },
);

module.exports = {
  FRIENDSHIP_GUARD_SCHEMA_VERSION,
  SOCIAL_CAPACITY_SCHEMA_VERSION,
  MAX_FRIENDS,
  MAX_FOLLOWING,
  MAX_PENDING_REQUESTS,
  MAX_BLOCKED_USERS,
  MAX_FRIENDS_EXPANDED,
  MAX_FRIENDS_SCANNED_FOR_DISCOVERY,
  MAX_EXPANDED_FRIENDS_PER_SOURCE,
  MAX_SUGGESTION_CANDIDATES,
  MAX_MUTUAL_FRIENDS_SCANNED,
  FRIEND_DISCOVERY_MINUTE_LIMIT,
  FRIEND_DISCOVERY_HOUR_LIMIT,
  FRIEND_DISCOVERY_CACHE_TTL_MS,
  SUGGESTION_GRAPH_READ_BUDGET,
  MUTUAL_GRAPH_READ_BUDGET,
  QUOTA_MINUTE_MS,
  QUOTA_HOUR_MS,
  friendshipGuardReference,
  consumeSocialRateLimit,
  consumeFriendDiscoveryRateLimit,
  friendDiscoveryCacheReference,
  socialCapacityReference,
  getMutualFriends,
  getFriendSuggestions,
  sendFriendRequest,
  respondToFriendRequest,
  cancelFriendRequest,
  removeFriend,
  setFollow,
  setUserBlock,
};
