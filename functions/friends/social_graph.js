const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { createHash } = require("node:crypto");
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

const REGION = "europe-west1";
const SAFE_ID = /^[A-Za-z0-9_-]{1,128}$/u;
const FRIENDSHIP_GUARD_SCHEMA_VERSION = 1;
const MAX_FRIENDS = 500;
const MAX_FOLLOWING = 1000;
const MAX_PENDING_REQUESTS = 200;
const MAX_BLOCKED_USERS = 1000;
const MAX_FRIENDS_EXPANDED = 40;
const MAX_EXPANDED_FRIENDS_PER_SOURCE = 100;
const MAX_SUGGESTION_CANDIDATES = 125;
const DEFAULT_SUGGESTION_LIMIT = 10;
const MAX_SUGGESTION_LIMIT = 25;
const SOCIAL_READ_MINUTE_LIMIT = 30;
const SOCIAL_READ_HOUR_LIMIT = 300;
const SOCIAL_MUTATION_MINUTE_LIMIT = 60;
const SOCIAL_MUTATION_HOUR_LIMIT = 600;
const QUOTA_MINUTE_MS = 60 * 1000;
const QUOTA_HOUR_MS = 60 * 60 * 1000;

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

async function requireActiveProfile(uid, label = "The account") {
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

function canonicalName(profile) {
  return (
    normalizeText(profile.displayName || profile.username, 80) ||
    "YO Voice user"
  );
}

function canonicalPhoto(profile) {
  return typeof profile.photoUrl === "string" ? profile.photoUrl : null;
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

async function boundedIds(query, maximum, label, { failOnOverflow = true } = {}) {
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
    { failOnOverflow },
  );
}

async function profileSummaries(userIds) {
  if (userIds.length === 0) return new Map();
  const [snapshots, sources] = await Promise.all([
    db.getAll(...userIds.map((id) => db.collection("publicProfiles").doc(id))),
    // A retrying projection can be briefly stale. Re-check the private
    // authority so a deleted, banned or disabled account is never disclosed.
    db.getAll(...userIds.map((id) => db.collection("users").doc(id))),
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
      sourceData.disabled === true
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
      photoUrl: data.photoUrl ?? null,
    });
  }
  return result;
}

const getMutualFriends = onCall(
  { region: REGION, enforceAppCheck: false },
  async (request) => {
    const auth = requireAuthentication(request);
    await consumeSocialRateLimit(auth.uid, "read");
    const targetUserId = normalizeText(request.data?.targetUserId, 128);

    if (!SAFE_ID.test(targetUserId)) {
      throw new HttpsError("invalid-argument", "targetUserId is required.");
    }
    if (targetUserId === auth.uid) {
      return { count: 0, sample: [] };
    }

    await Promise.all([
      requireActiveProfile(auth.uid, "Your"),
      requireActiveProfile(targetUserId, "The selected"),
      requireVisiblePair(auth.uid, targetUserId),
    ]);

    const [mine, theirs] = await Promise.all([
      friendIdsOf(auth.uid),
      friendIdsOf(targetUserId),
    ]);
    const theirSet = new Set(theirs);
    const mutualIds = mine.filter((id) => theirSet.has(id));

    const profiles = await profileSummaries(mutualIds);
    const visibleMutualIds = mutualIds.filter((id) => profiles.has(id));
    const sampleIds = visibleMutualIds.slice(0, 6);

    return {
      count: visibleMutualIds.length,
      sample: sampleIds.map((id) => profiles.get(id)).filter(Boolean),
    };
  },
);

const getFriendSuggestions = onCall(
  { region: REGION, enforceAppCheck: false },
  async (request) => {
    const auth = requireAuthentication(request);
    await consumeSocialRateLimit(auth.uid, "read");
    const limit = Math.min(
      Math.max(
        Number.parseInt(request.data?.limit, 10) || DEFAULT_SUGGESTION_LIMIT,
        1,
      ),
      MAX_SUGGESTION_LIMIT,
    );

    await requireActiveProfile(auth.uid, "Your");

    const userRef = db.collection("users").doc(auth.uid);
    const [myFriendIds, blockedIds, incomingIds, outgoingIds] =
      await Promise.all([
        friendIdsOf(auth.uid),
        boundedIds(
          userRef.collection("blocked").orderBy(FieldPath.documentId()),
          MAX_BLOCKED_USERS,
          "The block list",
        ),
        boundedIds(
          userRef.collection("friendRequests").orderBy(FieldPath.documentId()),
          MAX_PENDING_REQUESTS,
          "The incoming request list",
        ),
        boundedIds(
          userRef
            .collection("sentFriendRequests")
            .orderBy(FieldPath.documentId()),
          MAX_PENDING_REQUESTS,
          "The outgoing request list",
        ),
      ]);
    const exclude = new Set([
      auth.uid,
      ...myFriendIds,
      ...blockedIds,
      ...incomingIds,
      ...outgoingIds,
    ]);

    if (myFriendIds.length === 0) {
      return { suggestions: [] };
    }

    const expandIds = myFriendIds.slice(0, MAX_FRIENDS_EXPANDED);
    const theirFriendLists = await Promise.all(
      expandIds.map((userId) =>
        friendIdsOf(userId, {
          maximum: MAX_EXPANDED_FRIENDS_PER_SOURCE,
          failOnOverflow: false,
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

    const ranked = [...mutualCounts.entries()]
      .sort((a, b) => b[1] - a[1])
      .slice(0, Math.min(mutualCounts.size, limit * 5));

    const profiles = await profileSummaries(ranked.map(([id]) => id));
    const reverseBlocks =
      ranked.length === 0
        ? []
        : await db.getAll(
            ...ranked.map(([id]) => db.doc(`users/${id}/blocked/${auth.uid}`)),
          );
    const hidden = new Set(
      reverseBlocks
        .filter((snapshot) => snapshot.exists)
        .map((snapshot) => snapshot.ref.parent.parent.id),
    );

    return {
      suggestions: ranked
        .map(([id, mutualCount]) => {
          const profile = profiles.get(id);
          if (!profile || hidden.has(id)) return null;
          return { ...profile, mutualCount };
        })
        .filter(Boolean)
        .slice(0, limit),
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
    const targetNotificationRef = notificationReference(
      targetUserId,
      `friendRequest_${auth.uid}`,
    );
    const acceptedNotificationRef = notificationReference(
      targetUserId,
      `friendAccepted_${auth.uid}`,
    );
    const actorRequestNotificationRef = notificationReference(
      auth.uid,
      `friendRequest_${targetUserId}`,
    );

    return db.runTransaction(async (transaction) => {
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
        actorRequestNotification,
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
        actorRequestNotificationRef,
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
          transaction.set(outgoingMirrorRef, {
            receiverId: targetUserId,
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
        transaction.create(myFriendRef, {
          userId: targetUserId,
          createdAt: timestamp,
        });
        transaction.create(theirFriendRef, {
          userId: auth.uid,
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
        transaction.set(
          acceptedNotificationRef,
          canonicalNotificationData({
            actorId: auth.uid,
            actorProfile: actor,
            type: "friendAccepted",
            dedupeKey: `friendAccepted_${auth.uid}`,
          }),
        );
        if (actorRequestNotification.exists) {
          transaction.update(actorRequestNotificationRef, {
            isRead: true,
            readAt: timestamp,
          });
        }
        return { outcome: "accepted", changed: true };
      }

      const [actorOutgoing, targetIncoming] = await Promise.all([
        transaction.get(
          actorRef
            .collection("sentFriendRequests")
            .limit(MAX_PENDING_REQUESTS + 1),
        ),
        transaction.get(
          targetRef
            .collection("friendRequests")
            .limit(MAX_PENDING_REQUESTS + 1),
        ),
      ]);
      if (
        actorOutgoing.size >= MAX_PENDING_REQUESTS ||
        targetIncoming.size >= MAX_PENDING_REQUESTS
      ) {
        throw new HttpsError(
          "resource-exhausted",
          "The pending friend-request limit has been reached.",
        );
      }
      const timestamp = FieldValue.serverTimestamp();
      transaction.create(outgoingRef, {
        senderId: auth.uid,
        senderName: canonicalName(actor),
        senderPhotoUrl: canonicalPhoto(actor),
        createdAt: timestamp,
      });
      transaction.create(outgoingMirrorRef, {
        receiverId: targetUserId,
        createdAt: timestamp,
      });
      transaction.set(
        targetNotificationRef,
        canonicalNotificationData({
          actorId: auth.uid,
          actorProfile: actor,
          type: "friendRequest",
          dedupeKey: `friendRequest_${auth.uid}`,
        }),
      );
      return { outcome: "requested", changed: true };
    });
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
    const myFriendRef = friendReference(auth.uid, senderId);
    const senderFriendRef = friendReference(senderId, auth.uid);
    const myGuardRef = friendshipGuardReference(auth.uid, senderId);
    const senderGuardRef = friendshipGuardReference(senderId, auth.uid);
    const requestNotificationRef = notificationReference(
      auth.uid,
      `friendRequest_${senderId}`,
    );
    const acceptedNotificationRef = notificationReference(
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
        myFriend,
        senderFriend,
        myGuard,
        senderGuard,
        requestNotification,
      ] = await transaction.getAll(
        actorRef,
        senderRef,
        actorRestrictionRef,
        senderRestrictionRef,
        actorBlockRef,
        senderBlockRef,
        requestRef,
        myFriendRef,
        senderFriendRef,
        myGuardRef,
        senderGuardRef,
        requestNotificationRef,
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
          return { outcome: "alreadyAccepted", changed: false };
        }
        if (!accept) return { outcome: "alreadyResolved", changed: false };
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
      if (!accept) {
        transaction.delete(requestRef);
        transaction.delete(sentRef);
        if (requestNotification.exists) {
          transaction.update(requestNotificationRef, {
            isRead: true,
            readAt: timestamp,
          });
        }
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
          createdAt: timestamp,
        });
        transaction.create(senderFriendRef, {
          userId: auth.uid,
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
        transaction.set(
          acceptedNotificationRef,
          canonicalNotificationData({
            actorId: auth.uid,
            actorProfile: actor,
            type: "friendAccepted",
            dedupeKey: `friendAccepted_${auth.uid}`,
          }),
        );
      }
      transaction.delete(requestRef);
      transaction.delete(sentRef);
      if (requestNotification.exists) {
        transaction.update(requestNotificationRef, {
          isRead: true,
          readAt: timestamp,
        });
      }
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
    return db.runTransaction(async (transaction) => {
      const [pending, sent] = await transaction.getAll(requestRef, sentRef);
      if (!pending.exists && !sent.exists) return { changed: false };
      if (pending.exists && pending.data()?.senderId !== auth.uid) {
        throw new HttpsError(
          "data-loss",
          "The friend request is not canonical.",
        );
      }
      transaction.delete(requestRef);
      transaction.delete(sentRef);
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
        return { changed: false };
      }
      transaction.delete(myFriendRef);
      transaction.delete(theirFriendRef);
      transaction.delete(myGuardRef);
      transaction.delete(theirGuardRef);
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
    const notificationRef = notificationReference(
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
          transaction.set(followingRef, { uid: targetUserId, followedAt });
          transaction.set(followerRef, { uid: auth.uid, followedAt });
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
          followedAt: timestamp,
        });
        transaction.create(followerRef, {
          uid: auth.uid,
          followedAt: timestamp,
        });
        transaction.update(actorRef, {
          followingCount: countOf(actor, "followingCount") + 1,
        });
        transaction.update(targetRef, {
          followerCount: countOf(target, "followerCount") + 1,
        });
        transaction.set(
          notificationRef,
          canonicalNotificationData({
            actorId: auth.uid,
            actorProfile: actor,
            type: "follow",
            dedupeKey: `follow_${auth.uid}`,
          }),
        );
        return { changed: true, following: true };
      }

      if (!followingEdge.exists) return { changed: false, following: false };
      transaction.delete(followingRef);
      transaction.delete(followerRef);
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
    if (!blocked) {
      const actor = await actorRef.get();
      profileData(actor, "Your");
      const existed = (await blockRef.get()).exists;
      if (existed) await blockRef.delete();
      return { changed: existed, blocked: false };
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
    return db.runTransaction(async (transaction) => {
      const snapshots = await transaction.getAll(
        actorRef,
        targetRef,
        blockRef,
        ...Object.values(refs),
      );
      const actor = profileData(snapshots[0], "Your");
      const targetSnapshot = snapshots[1];
      profileData(targetSnapshot, "The selected");
      const existingBlock = snapshots[2];
      const [
        myFriend,
        theirFriend,
        myFollowing,
        theirFollower,
        theirFollowing,
        myFollower,
      ] = snapshots.slice(3, 9);
      const target = targetSnapshot.data() ?? {};

      if (!existingBlock.exists) {
        const blockList = await transaction.get(
          actorRef.collection("blocked").limit(MAX_BLOCKED_USERS + 1),
        );
        if (blockList.size >= MAX_BLOCKED_USERS) {
          throw new HttpsError(
            "resource-exhausted",
            "You have reached the block-list safety limit.",
          );
        }
      }

      for (const reference of Object.values(refs))
        transaction.delete(reference);
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
  },
);

module.exports = {
  FRIENDSHIP_GUARD_SCHEMA_VERSION,
  MAX_FRIENDS,
  MAX_FOLLOWING,
  MAX_PENDING_REQUESTS,
  MAX_BLOCKED_USERS,
  QUOTA_MINUTE_MS,
  QUOTA_HOUR_MS,
  friendshipGuardReference,
  consumeSocialRateLimit,
  getMutualFriends,
  getFriendSuggestions,
  sendFriendRequest,
  respondToFriendRequest,
  cancelFriendRequest,
  removeFriend,
  setFollow,
  setUserBlock,
};
