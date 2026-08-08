const { onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { FieldPath } = require("firebase-admin/firestore");
const { logger } = require("firebase-functions/v2");

const { db } = require("../utils/firestore");

const REGION = "europe-west1";

// Firestore batch hard limit is 500 writes; stay under it.
const BATCH_LIMIT = 450;

/**
 * Fans a profile identity change (photoUrl / displayName) out to the
 * places that keep denormalized copies of it.
 *
 * users/{uid}.photoUrl is the canonical avatar (ProfileService owns it),
 * but three surfaces snapshot identity at write time and were never
 * updated afterward — so everyone else kept seeing your old avatar/name
 * forever:
 *
 *  - conversations.participantPhotoUrls.{uid} / participantNames.{uid}
 *    (the Chats list both people see)
 *  - clubs/{clubId}/members/{uid}.photoUrl / displayName
 *    (club member lists; memberships enumerated via the
 *    users/{uid}/clubs mirror, so no collectionGroup query — this
 *    project has been bitten by collectionGroup+rules before, ADR-007)
 *  - voice_moments.authorPhotoUrl / authorName (the Home feed)
 *
 * Room participant docs are deliberately NOT touched: they're deleted
 * when the user leaves the room, so they're short-lived enough that a
 * stale avatar for the remainder of one session isn't worth the writes.
 *
 * Friends lists never needed this — friend_service.watchFriends()
 * subscribes to the real users/{id} documents.
 */
const onProfileIdentityChanged = onDocumentUpdated(
  {
    document: "users/{uid}",
    region: REGION,
  },
  async (event) => {
    const before = event.data?.before.data() ?? {};
    const after = event.data?.after.data() ?? {};
    const uid = event.params.uid;

    const photoChanged = (before.photoUrl ?? null) !== (after.photoUrl ?? null);
    const nameChanged =
      (before.displayName ?? null) !== (after.displayName ?? null);

    if (!photoChanged && !nameChanged) {
      return;
    }

    const photoUrl = after.photoUrl ?? null;
    const displayName = after.displayName ?? null;

    let batch = db.batch();
    let pending = 0;
    let total = 0;

    const commitIfFull = async () => {
      if (pending >= BATCH_LIMIT) {
        await batch.commit();
        total += pending;
        batch = db.batch();
        pending = 0;
      }
    };

    // Chats: both sides' conversation list rows.
    const conversations = await db
      .collection("conversations")
      .where("participantIds", "array-contains", uid)
      .get();
    for (const doc of conversations.docs) {
      const update = {};
      if (photoChanged) {
        update[new FieldPath("participantPhotoUrls", uid)] = photoUrl ?? "";
      }
      if (nameChanged && displayName) {
        update[new FieldPath("participantNames", uid)] = displayName;
      }
      if (Object.keys(update).length > 0) {
        batch.update(doc.ref, update);
        pending += 1;
        await commitIfFull();
      }
    }

    // Club member rows, via the user's own membership mirror.
    const memberships = await db
      .collection("users")
      .doc(uid)
      .collection("clubs")
      .get();
    for (const membership of memberships.docs) {
      const clubId = membership.data().clubId ?? membership.id;
      const update = {};
      if (photoChanged) update.photoUrl = photoUrl;
      if (nameChanged && displayName) update.displayName = displayName;
      batch.set(
        db.collection("clubs").doc(clubId).collection("members").doc(uid),
        update,
        { merge: true },
      );
      pending += 1;
      await commitIfFull();
    }

    // Voice Moments authored by this user (Home feed cards).
    const moments = await db
      .collection("voice_moments")
      .where("authorId", "==", uid)
      .get();
    for (const doc of moments.docs) {
      const update = {};
      if (photoChanged) update.authorPhotoUrl = photoUrl;
      if (nameChanged && displayName) update.authorName = displayName;
      batch.update(doc.ref, update);
      pending += 1;
      await commitIfFull();
    }

    if (pending > 0) {
      await batch.commit();
      total += pending;
    }

    logger.info("profile identity fan-out", {
      uid,
      photoChanged,
      nameChanged,
      conversations: conversations.size,
      clubMemberships: memberships.size,
      moments: moments.size,
      writes: total,
    });
  },
);

module.exports = { onProfileIdentityChanged };
