// THE LIVE-ROOM READ THE STAFF SURFACES SHARE.
//
// `status` IS DELIBERATELY NOT IN THE QUERY — the same decision, for the
// same reason, as `functions/rooms/liveness_sweeper.js`. 25 of the 45
// production rooms carry no `status` field at all, and
// `where("status", "==", "active")` matches only documents where the field
// is PRESENT and equal, so every one of those legacy rooms is dropped. That
// is the defect commit b7c6d99 fixed on the callable side by introducing
// `roomIsActive()`, which reads an ABSENT status as active exactly as
// firestore.rules' own `resource.data.get('status', 'active')` does. The
// aggregates behind the admin dashboard's `liveRooms` figure and the staff
// overview's live-room count and list were not part of that change, and
// went on under-reporting the majority production shape.
//
// WHY THIS IS NOT A `.count()` AGGREGATE ANY MORE. `roomIsActive()` is an
// in-memory predicate, and there is no Firestore filter that spells "absent
// OR equal to active" — a server-side aggregate cannot express the reading
// the rules use, so the documents are read and counted here instead. That is
// affordable precisely because the candidate set is small and bounded by the
// same fact the sweeper relies on: the whole `rooms` collection is ~45
// documents, of which only a handful are ever live at once. A staff-only
// surface reading a handful of documents twice a page load is not a cost
// worth trading a wrong number for.
//
// THE INDEX THIS NOW USES, because dropping a clause changes that. A single
// equality on `isLive` is served by Firestore's AUTOMATIC single-field
// index; the previous two-equality form needed a zigzag merge of two
// single-field indexes (there is no `(status, isLive)` composite in
// firestore.indexes.json, and none is needed now — this removes an index
// dependency rather than adding one). It is also the identical query
// `sweepStrandedLiveRooms` has run in production every five minutes since
// it landed, so it is already proven against the real collection.

const logger = require("firebase-functions/logger");

const { db, roomIsActive } = require("../utils/firestore");

/**
 * The scan bound, and a real one rather than a formality: production holds
 * 45 rooms in total. This matches `MAX_LIVE_ROOM_SCAN` in the sweeper, which
 * is duplicated rather than imported on purpose — importing it would drag
 * the scheduler and the whole LiveKit control plane into two callables that
 * need neither.
 */
const LIVE_ROOM_SCAN_LIMIT = 200;

/**
 * Every room that is live AND active, with an absent `status` read as
 * active.
 *
 * Returns the documents rather than a number because the staff overview
 * needs both the count and the first few rows, and one read should serve
 * both — it previously issued the same query twice.
 *
 * A run that reaches the scan bound reports `truncated: true` and SAYS SO in
 * the log rather than quietly counting a prefix: a silently truncated count
 * is the same under-reporting bug this function exists to fix, arriving by a
 * different route.
 */
async function listLiveActiveRoomDocs({
  maxRooms = LIVE_ROOM_SCAN_LIMIT,
  surface = "unknown",
} = {}) {
  const boundedMax = Math.max(
    1,
    Math.min(Number(maxRooms) || 0, LIVE_ROOM_SCAN_LIMIT),
  );

  const snapshot = await db
    .collection("rooms")
    .where("isLive", "==", true)
    .limit(boundedMax + 1)
    .get();

  const truncated = snapshot.size > boundedMax;

  if (truncated) {
    logger.warn("live room read reached its scan bound; the count is a floor", {
      surface,
      scanned: boundedMax,
    });
  }

  // The in-memory half of the filter the query deliberately gave up, applied
  // exactly as firestore.rules and every callable already read the field.
  const docs = snapshot.docs
    .slice(0, boundedMax)
    .filter((document) => roomIsActive(document.data() ?? {}));

  return { docs, truncated };
}

module.exports = {
  LIVE_ROOM_SCAN_LIMIT,
  listLiveActiveRoomDocs,
};
