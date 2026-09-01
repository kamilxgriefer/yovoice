const { FieldPath } = require("firebase-admin/firestore");

const { fail } = require("../integrity/guards");

const SNAPSHOT_TARGETS = Object.freeze({
  conversations: Object.freeze({ collection: "conversations", group: false }),
  rooms: Object.freeze({ collection: "rooms", group: false }),
  friendRequests: Object.freeze({ collection: "friendRequests", group: true }),
  notifications: Object.freeze({ collection: "notifications", group: true }),
  participants: Object.freeze({ collection: "participants", group: true }),
  roomMembers: Object.freeze({ collection: "roomMembers", group: true }),
  members: Object.freeze({ collection: "members", group: true }),
  messages: Object.freeze({ collection: "messages", group: true }),
  checkIns: Object.freeze({ collection: "checkIns", group: true }),
  handRequests: Object.freeze({ collection: "handRequests", group: true }),
  moments: Object.freeze({ collection: "moments", group: false }),
});

function scrubUpdate(target, data) {
  const update = {};
  if (target === "conversations") {
    const ids = Array.isArray(data.participantIds) ? data.participantIds : [];
    if (ids.length === 2 && data.participantPhotoUrls &&
        typeof data.participantPhotoUrls === "object" &&
        !Array.isArray(data.participantPhotoUrls)) {
      const sanitized = Object.fromEntries(ids.map((uid) => [uid, ""]));
      if (ids.some((uid) => data.participantPhotoUrls[uid] !== "") ||
          Object.keys(data.participantPhotoUrls).length !== ids.length) {
        update.participantPhotoUrls = sanitized;
      }
    }
    return update;
  }
  const fields = {
    rooms: ["hostPhotoUrl"],
    friendRequests: ["senderPhotoUrl"],
    notifications: ["actorPhotoUrl"],
    participants: ["photoUrl"],
    roomMembers: ["photoUrl"],
    members: ["photoUrl"],
    messages: ["senderPhotoUrl"],
    checkIns: ["photoUrl"],
    handRequests: ["photoUrl"],
    moments: ["authorPhotoUrl"],
  }[target] ?? [];
  for (const field of fields) {
    if (Object.prototype.hasOwnProperty.call(data, field) &&
        data[field] !== null) {
      update[field] = null;
    }
  }
  return update;
}

function createProfileIdentitySnapshotMigration({ db }) {
  if (!db?.collection || !db?.collectionGroup) {
    throw new TypeError("A Firestore database is required.");
  }

  async function scrub({ target, cursor = null, limit = 100, dryRun }) {
    const definition = SNAPSHOT_TARGETS[target];
    if (!definition ||
        (cursor !== null &&
          (typeof cursor !== "string" || cursor.length > 1500)) ||
        !Number.isSafeInteger(limit) || limit < 1 || limit > 200 ||
        typeof dryRun !== "boolean") {
      fail("invalid-argument", "The identity snapshot sweep input is invalid.");
    }
    let query = (definition.group
      ? db.collectionGroup(definition.collection)
      : db.collection(definition.collection))
      .orderBy(FieldPath.documentId())
      .limit(limit);
    if (cursor !== null) query = query.startAfter(db.doc(cursor));
    const page = await query.get();
    const writes = [];
    for (const document of page.docs) {
      const update = scrubUpdate(target, document.data() ?? {});
      if (Object.keys(update).length > 0) writes.push({ document, update });
    }
    if (!dryRun && writes.length > 0) {
      const batch = db.batch();
      for (const row of writes) batch.update(row.document.ref, row.update);
      await batch.commit();
    }
    return {
      target,
      dryRun,
      scanned: page.size,
      scrubbed: writes.length,
      nextCursor: page.empty ? null : page.docs.at(-1).ref.path,
      hasMore: page.size === limit,
    };
  }

  return Object.freeze({ scrub });
}

module.exports = {
  SNAPSHOT_TARGETS,
  createProfileIdentitySnapshotMigration,
  scrubUpdate,
};
