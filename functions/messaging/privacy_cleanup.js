const { isValidOpaqueUid } = require("../achievements/identity");
const { db } = require("../utils/firestore");

const DEFAULT_PAGE_SIZE = 200;
const DEFAULT_MAX_PAGES = 5;
const OWNER_INDEXED_COLLECTIONS = Object.freeze([
  "directPrivateReadStates",
  "directConversationUnreadStates",
]);

async function deleteOwnerPage(database, collectionName, ownerId, pageSize) {
  const snapshot = await database
    .collection(collectionName)
    .where("ownerId", "==", ownerId)
    .limit(pageSize)
    .get();
  if (snapshot.empty) return 0;
  const batch = database.batch();
  for (const document of snapshot.docs) batch.delete(document.ref);
  await batch.commit();
  return snapshot.size;
}

/**
 * Erases server-owned Premium messaging privacy data after Auth deletion.
 *
 * Every invocation performs a fixed maximum number of bounded pages. If an
 * account exceeds that budget, the handler throws after committing progress;
 * the trigger's failure policy retries the same idempotent deletion until no
 * owner-indexed state remains.
 */
async function cleanupPremiumMessagingPrivacyForDeletedUser(
  ownerId,
  {
    database = db,
    pageSize = DEFAULT_PAGE_SIZE,
    maxPages = DEFAULT_MAX_PAGES,
  } = {},
) {
  if (!isValidOpaqueUid(ownerId)) {
    throw new TypeError("A canonical deleted-user uid is required.");
  }
  if (!Number.isSafeInteger(pageSize) || pageSize < 1 || pageSize > 400 ||
      !Number.isSafeInteger(maxPages) || maxPages < 1 || maxPages > 20) {
    throw new TypeError("Privacy cleanup bounds are invalid.");
  }

  await database.collection("directPrivacyPreferences").doc(ownerId).delete();
  const deleted = Object.fromEntries(
    OWNER_INDEXED_COLLECTIONS.map((name) => [name, 0]),
  );
  for (const collectionName of OWNER_INDEXED_COLLECTIONS) {
    for (let page = 0; page < maxPages; page += 1) {
      const count = await deleteOwnerPage(
        database,
        collectionName,
        ownerId,
        pageSize,
      );
      deleted[collectionName] += count;
      if (count < pageSize) break;
    }
  }

  const remaining = await Promise.all(OWNER_INDEXED_COLLECTIONS.map(
    (collectionName) => database
      .collection(collectionName)
      .where("ownerId", "==", ownerId)
      .limit(1)
      .get(),
  ));
  if (remaining.some((snapshot) => !snapshot.empty)) {
    const error = new Error(
      "Premium messaging privacy cleanup requires another bounded retry.",
    );
    error.code = "cleanup-incomplete";
    throw error;
  }
  return { ownerId, deleted };
}

module.exports = {
  DEFAULT_MAX_PAGES,
  DEFAULT_PAGE_SIZE,
  OWNER_INDEXED_COLLECTIONS,
  cleanupPremiumMessagingPrivacyForDeletedUser,
};
