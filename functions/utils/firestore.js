const { getFirestore, Timestamp } = require("firebase-admin/firestore");

const db = getFirestore();

function timestampToIso(value) {
  if (!value) {
    return null;
  }

  if (value instanceof Timestamp) {
    return value.toDate().toISOString();
  }

  if (typeof value.toDate === "function") {
    return value.toDate().toISOString();
  }

  if (value instanceof Date) {
    return value.toISOString();
  }

  return null;
}

function normalizeText(value, maxLength = 500) {
  return String(value ?? "")
    .trim()
    .slice(0, maxLength);
}

function normalizeOptionalText(value, maxLength = 500) {
  const normalized = normalizeText(value, maxLength);
  return normalized || null;
}

function positiveInteger(value, fallback, maximum) {
  const parsed = Number.parseInt(String(value ?? ""), 10);

  if (!Number.isFinite(parsed) || parsed <= 0) {
    return fallback;
  }

  return Math.min(parsed, maximum);
}

async function getDocumentOrThrow(
  reference,
  HttpsError,
  notFoundMessage = "The selected document was not found.",
) {
  const snapshot = await reference.get();

  if (!snapshot.exists) {
    throw new HttpsError("not-found", notFoundMessage);
  }

  return snapshot;
}

async function deleteCollectionInBatches(collectionReference, batchSize = 250) {
  while (true) {
    const snapshot = await collectionReference.limit(batchSize).get();

    if (snapshot.empty) {
      break;
    }

    const batch = db.batch();

    for (const document of snapshot.docs) {
      batch.delete(document.ref);
    }

    await batch.commit();
  }
}

async function deleteDocumentRecursively(documentReference) {
  if (typeof db.recursiveDelete === "function") {
    await db.recursiveDelete(documentReference);
    return;
  }

  const subcollections = await documentReference.listCollections();

  for (const collection of subcollections) {
    await deleteCollectionInBatches(collection);
  }

  await documentReference.delete();
}


/**
 * "Is this room active?" — the ONE reading of `status`, shared by every
 * callable that gates on it.
 *
 * ABSENT MEANS ACTIVE, because that is what the deployed ruleset already
 * decides. `firestore.rules` reads this field as
 * `resource.data.get('status', 'active')` throughout, and 25 of the 45 rooms
 * in production carry no `status` field at all — they predate it. A bare
 * `room.status !== "active"` therefore DISAGREES WITH THE RULES on the
 * majority production shape: the rules authorise the client's `isLive: true`
 * write, and then the callable refuses the LiveKit token for the same room
 * with "This room is not currently live." That mismatch is what left a room
 * flipped live with nobody able to connect and no way to turn it off, since
 * `executeEndRoomVoice` read the field the same bare way.
 *
 * A legacy document is not a suspended one. Moderation writes an EXPLICIT
 * "suspended"/"closed"/"archived" value, so every genuinely inactive room
 * has the field — which is exactly why defaulting the absent case to active
 * loosens nothing that moderation relies on.
 */
function roomIsActive(room) {
  return String(room?.status ?? "active") === "active";
}

module.exports = {
  db,
  timestampToIso,
  normalizeText,
  normalizeOptionalText,
  positiveInteger,
  getDocumentOrThrow,
  deleteCollectionInBatches,
  deleteDocumentRecursively,
  roomIsActive,
};
