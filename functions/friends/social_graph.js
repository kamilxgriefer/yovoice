const { onCall, HttpsError } = require("firebase-functions/v2/https");

const { requireAuthentication } = require("../utils/auth");
const { db, normalizeText } = require("../utils/firestore");

const REGION = "europe-west1";

// friends/{id} subcollection reads are owner-only in firestore.rules — by
// design, friend lists are private. Mutual-friend/suggestion computation
// needs to read OTHER users' friend lists, which only the Admin SDK
// (running here, server-side) can do without weakening that rule for every
// client. Neither callable exposes anyone's friend list directly — only
// aggregate counts and the resulting candidate profiles.

async function friendIdsOf(userId) {
  const snapshot = await db
    .collection("users")
    .doc(userId)
    .collection("friends")
    .get();
  return snapshot.docs.map((doc) => doc.id);
}

async function profileSummaries(userIds) {
  if (userIds.length === 0) return new Map();
  const refs = userIds.map((id) => db.collection("users").doc(id));
  const snapshots = await db.getAll(...refs);
  const result = new Map();
  for (const snapshot of snapshots) {
    if (!snapshot.exists) continue;
    const data = snapshot.data() ?? {};
    result.set(snapshot.id, {
      uid: snapshot.id,
      displayName: normalizeText(
        data.displayName || data.username || data.email?.split("@")[0] || "YoVoice user",
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
    const targetUserId = normalizeText(request.data?.targetUserId, 128);

    if (!targetUserId) {
      throw new HttpsError("invalid-argument", "targetUserId is required.");
    }
    if (targetUserId === auth.uid) {
      return { count: 0, sample: [] };
    }

    const [mine, theirs] = await Promise.all([
      friendIdsOf(auth.uid),
      friendIdsOf(targetUserId),
    ]);
    const theirSet = new Set(theirs);
    const mutualIds = mine.filter((id) => theirSet.has(id));

    const sampleIds = mutualIds.slice(0, 6);
    const profiles = await profileSummaries(sampleIds);

    return {
      count: mutualIds.length,
      sample: sampleIds.map((id) => profiles.get(id)).filter(Boolean),
    };
  },
);

const MAX_FRIENDS_EXPANDED = 40;
const DEFAULT_SUGGESTION_LIMIT = 10;
const MAX_SUGGESTION_LIMIT = 25;

const getFriendSuggestions = onCall(
  { region: REGION, enforceAppCheck: false },
  async (request) => {
    const auth = requireAuthentication(request);
    const limit = Math.min(
      Math.max(Number.parseInt(request.data?.limit, 10) || DEFAULT_SUGGESTION_LIMIT, 1),
      MAX_SUGGESTION_LIMIT,
    );

    const userRef = db.collection("users").doc(auth.uid);
    const [
      myFriendsSnapshot,
      blockedSnapshot,
      incomingRequestsSnapshot,
      outgoingRequestsSnapshot,
    ] = await Promise.all([
      userRef.collection("friends").get(),
      userRef.collection("blocked").get(),
      userRef.collection("friendRequests").get(),
      userRef.collection("sentFriendRequests").get(),
    ]);

    const myFriendIds = myFriendsSnapshot.docs.map((doc) => doc.id);
    const exclude = new Set([
      auth.uid,
      ...myFriendIds,
      ...blockedSnapshot.docs.map((doc) => doc.id),
      ...incomingRequestsSnapshot.docs.map((doc) => doc.id),
      ...outgoingRequestsSnapshot.docs.map((doc) => doc.id),
    ]);

    if (myFriendIds.length === 0) {
      return { suggestions: [] };
    }

    const expandIds = myFriendIds.slice(0, MAX_FRIENDS_EXPANDED);
    const theirFriendLists = await Promise.all(expandIds.map(friendIdsOf));

    const mutualCounts = new Map();
    for (const list of theirFriendLists) {
      for (const candidateId of list) {
        if (exclude.has(candidateId)) continue;
        mutualCounts.set(candidateId, (mutualCounts.get(candidateId) ?? 0) + 1);
      }
    }

    const ranked = [...mutualCounts.entries()]
      .sort((a, b) => b[1] - a[1])
      .slice(0, limit);

    const profiles = await profileSummaries(ranked.map(([id]) => id));

    return {
      suggestions: ranked
        .map(([id, mutualCount]) => {
          const profile = profiles.get(id);
          if (!profile) return null;
          return { ...profile, mutualCount };
        })
        .filter(Boolean),
    };
  },
);

module.exports = {
  getMutualFriends,
  getFriendSuggestions,
};
