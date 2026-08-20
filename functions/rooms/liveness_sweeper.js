const { onSchedule } = require("firebase-functions/v2/scheduler");
const logger = require("firebase-functions/logger");
const { FieldValue, Timestamp } = require("firebase-admin/firestore");

const { db, roomIsActive } = require("../utils/firestore");
const {
  LIVEKIT_SECRETS,
  getProductionLiveKitControl,
} = require("../livekit/control");
const { deleteActiveVoiceSessionsForRoom } = require("../livekit/sessions");

const REGION = "europe-west1";

/**
 * Five minutes. The number is set by the WINDOW IT HAS TO CLEAR, not by how
 * fast a ghost room becomes annoying: `RoomVoiceEntryCoordinator.enter()`
 * writes liveness first and joins second, so between those two calls a room
 * legitimately exists as `isLive: true` with an empty roster. That window is
 * one Firestore round trip on a good connection and a retry-and-timeout on a
 * bad one — seconds, not minutes. Five minutes is two orders of magnitude of
 * headroom on the thing this must never interrupt, and still clears a ghost
 * inside one sweep of the same Home screen the user is looking at.
 */
const GRACE_PERIOD_SECONDS = 300;

/**
 * The scan bound, and it is a real bound rather than a formality: production
 * holds 45 rooms in total, of which only a handful are ever live at once.
 * If this ceiling is ever reached the sweep reports `truncated: true` and
 * says so in the log rather than quietly covering a prefix — the next run
 * picks up the remainder, because closing rooms only ever shrinks the
 * candidate set.
 */
const MAX_LIVE_ROOM_SCAN = 200;

/**
 * THE SWEEP THAT CLOSES A ROOM NOBODY IS IN AND NOBODY WILL COME BACK TO.
 *
 * WHAT IS ACTUALLY BROKEN. `RoomVoiceEntryCoordinator.enter()` performs the
 * liveness write first and the `joinRoom` second, because
 * `createLiveKitToken` refuses a dormant room and `joinRoom` itself refuses
 * one. When the join fails the coordinator returns
 * `RoomVoiceEntryOutcome.failed` and does NOT call `leaveRoomSelf` — there
 * is nothing to leave, the roster row was never written. The room is left
 * `isLive: true, participantCount: 0` with an empty `participants`
 * subcollection, and it keeps advertising itself on `watchLivePublicRooms`
 * (Home and Discover) as a live room nobody is in. A process death between
 * the two calls produces the identical document and cannot be repaired by
 * any client at all.
 *
 * WHY `executeLeaveRoom` DELIBERATELY DOES NOT REPAIR IT. That function
 * returns early when the caller holds no participant row, and extending the
 * repair there would let ANY signed-in account drop `isLive` on a live room
 * during somebody else's start→join window. That is a denial-of-service
 * lever on a public room, small but real, and it is not worth buying this
 * fix with. A schedule has no caller to impersonate, which is the whole
 * reason the repair belongs here and not there.
 *
 * THE ROSTER IS THE AUTHORITY, `participantCount` IS NOT. The counter is a
 * denormalised field with several writers; a stale-LOW value would turn this
 * sweep into an eviction of everyone still talking, because `endRoom()`
 * disconnects the LiveKit room for all of them. Every decision below is made
 * from the `participants` subcollection, and `participantCount` is only ever
 * WRITTEN (repaired to 0), never read to decide anything. This is the same
 * conclusion `executeLeaveRoom` and `executeEndRoomVoice`'s `onlyIfEmpty`
 * branch reached, for the same reason.
 *
 * `updatedAt` IS A SOUND AGE ANCHOR, and that is provable rather than
 * hopeful. Nothing on the server ever writes `isLive: true` — grep the
 * codebase, every server write of that field is `false` — so the client is
 * its only writer, and BOTH client branches that may write it
 * (`roomVoiceStartAllowed()` and `hostRoomUpdateAllowed()`'s start branch in
 * firestore.rules) require `request.resource.data.updatedAt == request.time`
 * and `changed.hasOnly(['isLive', 'endedAt', 'updatedAt'])`. A live room
 * therefore always carries a server-stamped `updatedAt` set at the moment it
 * went live. Every later write to the document — a join, a leave, a host
 * rename — moves it FORWARD, which delays this sweep. The anchor can only
 * ever be too conservative, never too eager, which is the direction a
 * destructive repair must err in.
 *
 * WHAT THIS DOES NOT FIX, stated plainly because the gap is easy to mistake
 * for covered. A client that CRASHES WHILE IN A ROOM leaves its participant
 * row behind. That room's roster is not empty, so this sweep skips it, and
 * it stays live with a ghost on the stage. Repairing that needs per-
 * participant liveness the SFU is the only honest source of — LiveKit's
 * `participant_left` / `participant_connection_aborted` webhook, which
 * `functions/achievements/livekit_http.js` already implements and
 * `functions/index.js` still does not export. docs/DEPLOYMENT.md names that
 * same webhook as the real fix for the `voiceMinutes` and live-presence
 * gaps. This sweep is scoped to the empty-roster case on purpose; it is not
 * a substitute for that work.
 */
async function sweepStrandedLiveRooms({
  roomControl = null,
  now = () => Timestamp.now(),
  gracePeriodSeconds = GRACE_PERIOD_SECONDS,
  maxRooms = MAX_LIVE_ROOM_SCAN,
} = {}) {
  const boundedGrace = Math.max(60, Number(gracePeriodSeconds) || 0);
  const boundedMax = Math.max(
    1,
    Math.min(Number(maxRooms) || 0, MAX_LIVE_ROOM_SCAN),
  );
  const startedAt = now();
  const cutoffMillis = startedAt.toMillis() - boundedGrace * 1000;

  // A BARE EQUALITY ON ONE FIELD, AND THAT IS THE POINT. Firestore's
  // automatic single-field index on `rooms.isLive` already serves this; no
  // composite is required, so this function cannot fail its first production
  // run with FAILED_PRECONDITION the way the `entitlements` sweep silently
  // did (docs/DEPLOYMENT.md records that Premium never expired for any
  // account because its composite had never been deployed).
  //
  // `status` IS DELIBERATELY NOT IN THE QUERY. 25 of the 45 production rooms
  // carry no `status` field at all, and a `where("status", "==", "active")`
  // clause drops every one of them — the exact defect `roomIsActive()` was
  // written to fix. The filter is applied in memory below, where an absent
  // field reads as active exactly as firestore.rules' own
  // `.get('status', 'active')` does.
  const snapshot = await db
    .collection("rooms")
    .where("isLive", "==", true)
    .limit(boundedMax + 1)
    .get();

  const truncated = snapshot.size > boundedMax;
  const candidates = snapshot.docs.slice(0, boundedMax);

  // Resolved EAGERLY, before the loop, even on a run with nothing to close.
  // `getProductionLiveKitControl()` throws when the LiveKit configuration is
  // incomplete, and a misconfigured deploy should surface on the very next
  // run rather than lying dormant until the first room actually needs
  // closing — which is precisely when the failure costs something.
  const control = roomControl ?? getProductionLiveKitControl();
  const closed = [];
  const failures = [];
  let skippedOccupied = 0;
  let skippedYoung = 0;
  let skippedInactive = 0;
  let skippedUnanchored = 0;

  for (const document of candidates) {
    const room = document.data() ?? {};

    if (!roomIsActive(room) || room.deletionInProgress === true) {
      // Not this function's room to close. `executeDeleteRoom` and
      // `executeSetRoomStatus` own the teardown of a closing or moderated
      // room, and writing `endedAt` underneath either of them would race a
      // teardown that has already committed.
      skippedInactive += 1;
      continue;
    }

    const anchor = ageAnchor(room);
    if (anchor === null) {
      // Unreachable for any room the client made live (see the header), so
      // this is a real anomaly rather than a legacy shape to absorb: refuse
      // to date it, and say so loudly enough to be found.
      skippedUnanchored += 1;
      logger.warn("live room has no usable age anchor; not swept", {
        roomId: document.id,
      });
      continue;
    }
    if (anchor > cutoffMillis) {
      skippedYoung += 1;
      continue;
    }

    try {
      const outcome = await closeIfStillStranded(document.ref, cutoffMillis);
      if (outcome === "occupied") {
        skippedOccupied += 1;
        continue;
      }
      if (outcome === "changed") {
        skippedYoung += 1;
        continue;
      }

      // FIRESTORE FIRST, CONTROL PLANE SECOND — the ordering every other
      // room teardown in this project uses. Firestore is the durable
      // authority, so once `isLive` is false a new token request fails
      // closed; only then is the already-issued LiveKit session revoked.
      // Reversing it would leave a window where the SFU room is gone but
      // the document still invites people to join it.
      await control.endRoom(document.id);
      await deleteActiveVoiceSessionsForRoom(document.id);
      closed.push(document.id);
    } catch (error) {
      // ONE BAD ROOM MUST NOT COST THE OTHERS THEIR SWEEP. The Firestore
      // write for this room may already have committed, which is fine and
      // is why it is safe to continue: the operation is idempotent, and a
      // room whose `isLive` is already false simply stops being a candidate.
      // The failure is re-raised in aggregate at the end so Cloud Scheduler
      // shows it instead of a green run that quietly did nothing.
      failures.push({ roomId: document.id, error });
      // The error is passed as an ARGUMENT rather than folded into the
      // payload. `entryFromArgs` in firebase-functions overwrites a
      // `message` key on the payload object with a synthetic stack unless
      // one of the arguments is a real Error — so `{ message: err.message }`
      // silently loses the only detail worth logging.
      logger.error("stranded room sweep failed for one room", error, {
        roomId: document.id,
      });
    }
  }

  const outcome = {
    scanned: candidates.length,
    closed: closed.length,
    closedRoomIds: closed,
    skippedOccupied,
    skippedYoung,
    skippedInactive,
    skippedUnanchored,
    failed: failures.length,
    truncated,
  };

  if (truncated) {
    logger.warn("stranded room sweep reached its scan bound", outcome);
  }
  if (failures.length > 0) {
    const aggregate = new Error(
      `Stranded room sweep failed for ${failures.length} of ` +
        `${candidates.length} rooms.`,
    );
    aggregate.cause = failures[0].error;
    aggregate.outcome = outcome;
    throw aggregate;
  }

  return outcome;
}

/**
 * The moment this room's current liveness began, in epoch milliseconds, or
 * null when the document carries nothing datable.
 *
 * `updatedAt` leads because the start write sets it (see the header) and
 * every subsequent write moves it forward. `createdAt` is the fallback for a
 * room whose start predates the field, and is equally conservative: it can
 * only be older, and an older anchor makes the room MORE eligible only once
 * it has also sat with an empty roster past the grace period.
 */
function ageAnchor(room) {
  for (const value of [room?.updatedAt, room?.createdAt]) {
    if (value instanceof Timestamp) return value.toMillis();
    if (value && typeof value.toMillis === "function") return value.toMillis();
    if (value instanceof Date) return value.getTime();
  }
  return null;
}

/**
 * Re-decides the whole question inside a transaction and writes only if the
 * answer still holds.
 *
 * THE SCAN ABOVE IS A HINT, NOT A VERDICT. Between the query and this
 * transaction somebody can join the room, the host can end it, or a teardown
 * can start. Re-reading the roster here is what makes this safe rather than
 * merely likely to be safe — it is the same defence `executeEndRoomVoice`'s
 * `onlyIfEmpty` branch uses, and without it this function would be exactly
 * the eviction bug that branch exists to prevent.
 *
 * Both reads happen before the write because the Admin SDK refuses a read
 * that follows one inside a transaction.
 */
async function closeIfStillStranded(roomReference, cutoffMillis) {
  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(roomReference);
    if (!snapshot.exists) return "changed";

    const room = snapshot.data() ?? {};
    if (
      room.isLive !== true ||
      !roomIsActive(room) ||
      room.deletionInProgress === true
    ) {
      return "changed";
    }

    // Re-dated inside the transaction so a room that was closed and started
    // again between the scan and now is measured from its NEW start, not the
    // stale one the scan read.
    const anchor = ageAnchor(room);
    if (anchor === null || anchor > cutoffMillis) return "changed";

    // limit(1) answers the only question there is. Unlike the leave path
    // there is no caller whose own row has to be discounted: this sweep acts
    // for nobody, so a single surviving participant of any identity means
    // the room is occupied and is left exactly as it is.
    const roster = await transaction.get(
      roomReference.collection("participants").limit(1),
    );
    if (!roster.empty) return "occupied";

    transaction.update(roomReference, {
      isLive: false,
      // The roster is empty, so zero is not an assumption — it is the
      // repair. A stranded room usually already reads 0 here; a room whose
      // counter drifted high is corrected by the same write.
      participantCount: 0,
      endedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return "closed";
  });
}

/**
 * Every 5 minutes, matching the grace period: a ghost room is visible on
 * Home for at most one grace period plus one cadence, and the cadence costs
 * one indexed query returning a handful of documents. `maxInstances: 1`
 * keeps two runs from racing each other onto the same room — the transaction
 * would make that correct anyway, but not free.
 */
const sweepStrandedLiveRoomsSchedule = onSchedule(
  {
    region: REGION,
    schedule: "every 5 minutes",
    timeZone: "UTC",
    maxInstances: 1,
    timeoutSeconds: 300,
    secrets: LIVEKIT_SECRETS,
  },
  async () => {
    const outcome = await sweepStrandedLiveRooms();
    if (outcome.closed > 0) {
      logger.info("stranded live rooms closed", outcome);
    }
  },
);

module.exports = {
  GRACE_PERIOD_SECONDS,
  MAX_LIVE_ROOM_SCAN,
  REGION,
  ageAnchor,
  sweepStrandedLiveRooms,
  sweepStrandedLiveRoomsSchedule,
};
