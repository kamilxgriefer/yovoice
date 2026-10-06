// Removing one page of an account's follow edges, shared by the two
// teardowns that need it:
//
//   * account deletion (account/stages.js, `social` stage): both sides, the
//     account itself is going away;
//   * Page deletion (pages/deletion.js, ADR-236): the `followers` side only,
//     with `survivor: true`, because the ACCOUNT stays and only its Page
//     audience goes.
//
// One edge is ONE transaction, exactly like setFollow: the edge, its mirror
// and the peer's counter move together, so a partial page can never drift a
// counter. With `side: "followers"` the peer's Treści hint
// (pageFollowIndex/{peer}, ADR-234) drops this uid in the same transaction,
// so no follower keeps a hint to a Page that no longer exists.
//
// `survivor: true` additionally retires the "X started following you" bell
// row the follow wrote on the surviving account (the same two ids setFollow's
// unfollow retires), so no row outlives its edge. The surviving account's own
// followerCount is NOT touched per edge: the caller settles it once the
// collection is empty (settleFollowerCount below), which costs one write and
// one publicProfiles re-projection instead of one per follower.
//
// Bounded (`edgePage` edges a call) and idempotent: a re-run finds fewer
// edges. Returns the number of edge documents it consumed.

const { isValidOpaqueUid } = require("../achievements/identity");

const FOLLOW_NOTIFICATION_ID = /^[A-Za-z0-9_-]{1,320}$/u;

function safeCount(value) {
  return Number.isSafeInteger(value) && value > 0 ? value : 0;
}

/// The stored id of the bell row a follow wrote, when it is one this edge
/// could have written (`follow_{follower}_...`); null otherwise.
function storedFollowNotificationId(data, followerId) {
  const candidate = typeof data?.notificationId === "string" ? data.notificationId : "";
  return candidate.startsWith(`follow_${followerId}_`) && FOLLOW_NOTIFICATION_ID.test(candidate)
    ? candidate
    : null;
}

function createFollowEdgeRemover({ db, FieldValue, edgePage }) {
  if (!db || typeof db.collection !== "function" || !FieldValue ||
      !Number.isSafeInteger(edgePage) || edgePage < 1) {
    throw new TypeError("A database, FieldValue and an edge page size are required.");
  }

  return async function removeFollowEdges(uid, { side, survivor = false } = {}) {
    const own = side === "following" ? "following" : "followers";
    const mirror = side === "following" ? "followers" : "following";
    const counter = side === "following" ? "followerCount" : "followingCount";
    // Premium Pages (ADR-234): each follower's Treści hint
    // (pageFollowIndex/{peer}) may name this account, because a live Page
    // follow and the carry-over at Page creation put it there. The hint
    // goes in the same transaction as the edge, so no follower keeps the
    // uid of a deleted account or Page. Loaded lazily, like the Pages stages.
    const pageHints = side === "followers" ? require("../pages/follows") : null;
    const snapshot = await db
      .collection("users").doc(uid).collection(own)
      .limit(edgePage).get();
    for (const document of snapshot.docs) {
      const peer = isValidOpaqueUid(document.id) ? document.id : null;
      if (!peer) {
        await document.ref.delete();
        continue;
      }
      const peerReference = db.collection("users").doc(peer);
      const indexReference = pageHints === null
        ? null
        : pageHints.pageFollowIndexReference(db, peer);
      const bellRows = [];
      if (survivor && side === "followers") {
        const notifications = db.collection("users").doc(uid).collection("notifications");
        const stored = storedFollowNotificationId(document.data(), peer);
        if (stored !== null) bellRows.push(notifications.doc(stored));
        bellRows.push(notifications.doc(`follow_${peer}`));
      }
      await db.runTransaction(async (transaction) => {
        const [peerSnapshot, indexSnapshot] = indexReference === null
          ? [await transaction.get(peerReference), null]
          : await transaction.getAll(peerReference, indexReference);
        transaction.delete(document.ref);
        transaction.delete(peerReference.collection(mirror).doc(uid));
        if (peerSnapshot.exists) {
          const current = safeCount(peerSnapshot.data()?.[counter]);
          transaction.update(peerReference, {
            [counter]: Math.max(0, current - 1),
          });
        }
        if (indexSnapshot?.exists) {
          const index = pageHints.canonicalPageFollowIndex(indexSnapshot, peer);
          if (index.pageIds.includes(uid)) {
            transaction.set(indexReference, pageHints.pageFollowIndexDocument(
              pageHints.pageIdsAfterUnfollow(index.pageIds, uid),
              FieldValue.serverTimestamp(),
            ));
          }
        }
        for (const row of bellRows) transaction.delete(row);
      });
    }
    return snapshot.size;
  };
}

/**
 * Sets users/{uid}.followerCount to 0 once users/{uid}/followers is empty.
 * The emptiness check and the write share one transaction, so a follow that
 * lands in between is never overwritten. Returns true when the collection
 * was empty (the counter is then exact).
 */
async function settleFollowerCount(db, uid) {
  const userReference = db.collection("users").doc(uid);
  return db.runTransaction(async (transaction) => {
    const [userSnapshot, edges] = await Promise.all([
      transaction.get(userReference),
      transaction.get(userReference.collection("followers").limit(1)),
    ]);
    if (!edges.empty) return false;
    if (userSnapshot.exists && safeCount(userSnapshot.data()?.followerCount) !== 0) {
      transaction.update(userReference, { followerCount: 0 });
    }
    return true;
  });
}

module.exports = {
  createFollowEdgeRemover,
  settleFollowerCount,
  storedFollowNotificationId,
};
