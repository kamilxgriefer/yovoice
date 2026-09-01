const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { FieldValue } = require("firebase-admin/firestore");
const { getStorage } = require("firebase-admin/storage");

const { requireAuthentication } = require("../utils/auth");
const {
  db,
  normalizeText,
  deleteDocumentRecursively,
} = require("../utils/firestore");
const { writeClubAuditLog } = require("../utils/audit");
const {
  LIVEKIT_SECRETS,
  getProductionLiveKitControl,
} = require("../livekit/control");
const { ACTIVE_VOICE_SESSIONS } = require("../livekit/sessions");
const {
  cleanupClubMedia,
  cleanupFamilyMedia,
  cleanupRoomMedia,
} = require("../media/cleanup");
const {
  consumeClubActionAttempt,
  lockOwnershipGuards,
  touchOwnershipGuards,
} = require("./quota");

const REGION = "europe-west1";
const SAFE_DOCUMENT_ID = /^[A-Za-z0-9_-]{1,128}$/u;
// Absent means active, matching roomIsActive()/firestore.rules defaulting:
// legacy documents carry no `status` and are not moderated ones. Moderation
// writes an EXPLICIT "suspended", which is the one state refused below.
const DELETABLE_CLUB_STATUSES = new Set(["active", "closed", "archived"]);
const DEFAULT_DELETION_LIMITS = Object.freeze({
  roomsPerRun: 10,
  sessionsPerPage: 250,
  projectionsPerPage: 450,
});

// A club teardown sweeps every bound room plus media; give it the same
// headroom adminDeleteClub gets rather than a single room's 120s.
const CALLABLE_OPTIONS = {
  region: REGION,
  enforceAppCheck: false,
  secrets: LIVEKIT_SECRETS,
  timeoutSeconds: 300,
  memory: "512MiB",
};

async function requireActiveCaller(auth) {
  const profile = await db.collection("users").doc(auth.uid).get();
  if (
    !profile.exists ||
    profile.data()?.banned === true ||
    profile.data()?.disabled === true
  ) {
    throw new HttpsError(
      "permission-denied",
      "An active account is required to delete a Club.",
    );
  }
  return { ...auth, profile: profile.data() ?? {} };
}

function deletionLimits(overrides = {}) {
  const resolved = { ...DEFAULT_DELETION_LIMITS, ...overrides };
  for (const [field, value] of Object.entries(resolved)) {
    if (!Number.isSafeInteger(value) || value < 1 || value > 450) {
      throw new TypeError(`${field} must be an integer between 1 and 450.`);
    }
  }
  return resolved;
}

async function deleteVoiceSessionPage(roomId, pageSize) {
  const snapshot = await db
    .collectionGroup("rooms")
    .where("roomId", "==", roomId)
    .limit(pageSize + 1)
    .get();
  const page = snapshot.docs.slice(0, pageSize);
  for (const document of page) {
    const segments = document.ref.path.split("/");
    const data = document.data() ?? {};
    if (
      segments.length !== 4 ||
      segments[0] !== ACTIVE_VOICE_SESSIONS ||
      segments[2] !== "rooms" ||
      document.id !== roomId ||
      data.roomId !== roomId ||
      data.userId !== segments[1] ||
      data.participantIdentity !== segments[1]
    ) {
      throw new HttpsError(
        "data-loss",
        "A voice-session mirror has an invalid canonical binding.",
      );
    }
  }
  if (page.length > 0) {
    const batch = db.batch();
    for (const document of page) batch.delete(document.ref);
    await batch.commit();
  }
  return snapshot.size <= pageSize;
}

function requireMediaCleanup(outcome, message) {
  const results = Array.isArray(outcome) ? outcome : [outcome];
  if (results.some((result) => result?.deleted !== true)) {
    throw new HttpsError("unavailable", message);
  }
}

/**
 * Owner-initiated permanent Club deletion — the "Club lifecycle" that
 * executeDeleteRoom's lounge refusal points at. The club owner deletes their
 * whole club: the club document tree (members, invites, channels and their
 * messages, moments, checkIns), the lounge room tree, every private
 * users/{uid}/clubs projection, the marketing consent, LiveKit state and
 * Storage media. adminDeleteClub remains the staff-side equivalent; this is
 * the self-service one, authorized purely by the club document's `ownerId`.
 *
 * Shape mirrors executeDeleteRoom: one transaction FIRST (reads before
 * writes — the Admin SDK refuses a read after a write) marks the club
 * `deletionInProgress` and closes the lounge document, then every side
 * effect runs after the commit. Rules refuse invite acceptance and metadata
 * edits once `deletionInProgress` is visible, so the post-commit sweep works
 * against a stable membership snapshot.
 *
 * REPEAT/CONCURRENT DELETION SEMANTICS (pinned by tests): a club already
 * marked `deletionInProgress: true` is NOT refused — the owner's repeat call
 * resumes the idempotent teardown and returns { success: true, clubId }.
 * Refusing would permanently wedge a club whose first attempt died after the
 * mark (media cleanup throws `unavailable` exactly so a retry can finish the
 * job). Once the club document is gone, a repeat call gets `not-found`.
 *
 * PENDING OWNERSHIP TRANSFER (`ownershipVoiceResetPending: true`): the
 * transfer transaction has already committed by the time that flag exists,
 * so `ownerId` is the RECIPIENT. The recipient may delete: deletion is a
 * strict superset of the pending voice reset (endRoom, session-mirror
 * cleanup, roster deletion — and then the room and club themselves), so an
 * interrupted transfer can never leave a club undeletable. The previous
 * owner is an ordinary non-owner by then and gets `permission-denied`.
 */
async function executeDeleteClubSelf(
  request,
  clubControl = null,
  storageBucket = null,
  limitOverrides = {},
) {
  const authentication = requireAuthentication(request);
  const clubId = normalizeText(request.data?.clubId, 128);
  if (!SAFE_DOCUMENT_ID.test(clubId)) {
    throw new HttpsError("invalid-argument", "A valid Club is required.");
  }
  // This commit is deliberately independent of the caller-selected Club.
  // Missing, foreign and moderated targets consume the same actor budget as
  // successful deletion attempts and cannot roll it back.
  await consumeClubActionAttempt(authentication.uid, "deleteClub");
  const auth = await requireActiveCaller(authentication);
  const limits = deletionLimits(limitOverrides);

  const clubReference = db.collection("clubs").doc(clubId);
  let club;

  await db.runTransaction(async (transaction) => {
    // Lock order: owner guards before Club roots, matching
    // createCommunityClub, both ownership transfers and adminDeleteClub.
    // The caller's guard is locked unconditionally (the owner is only known
    // after the club read, and reads must all precede writes); it is only
    // TOUCHED below for a community club, because family clubs never count
    // toward the community ownership quota the guards serialize.
    const guardReferences = await lockOwnershipGuards(transaction, [auth.uid]);
    const clubSnapshot = await transaction.get(clubReference);
    if (!clubSnapshot.exists) {
      throw new HttpsError("not-found", "The selected Club no longer exists.");
    }
    club = clubSnapshot.data() ?? {};
    if (club.ownerId !== auth.uid) {
      throw new HttpsError(
        "permission-denied",
        "Only the Club owner can delete this Club.",
      );
    }
    if (!DELETABLE_CLUB_STATUSES.has(String(club.status ?? "active"))) {
      throw new HttpsError(
        "failed-precondition",
        "A moderated Club cannot be deleted by its owner.",
      );
    }

    // The lounge is closed inside the SAME transaction that plants the
    // deletion mark, exactly like executeDeleteRoom closes an ordinary room,
    // so no join/voice-start can race the teardown. It is closed only when
    // its `clubId` field binds it to THIS club — `loungeRoomId` is
    // client-written on family clubs, and a forged pointer at somebody
    // else's room must not close that room. Lounges are created lazily
    // (ensureClubLounge), so a club with no lounge document is a real state
    // and simply skips this write.
    const loungeCandidate = normalizeText(club.loungeRoomId, 128);
    const loungeRoomId = SAFE_DOCUMENT_ID.test(loungeCandidate)
      ? loungeCandidate
      : `club_lounge_${clubId}`;
    const loungeReference = db.collection("rooms").doc(loungeRoomId);
    const loungeSnapshot = await transaction.get(loungeReference);

    transaction.set(
      clubReference,
      {
        deletionInProgress: true,
        deletionRequestedBy: auth.uid,
        deletionRequestedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    if (loungeSnapshot.exists && loungeSnapshot.data()?.clubId === clubId) {
      transaction.update(loungeReference, {
        status: "closed",
        isLive: false,
        participantCount: 0,
        deletionInProgress: true,
        endedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    if (club.type !== "family") {
      touchOwnershipGuards(transaction, guardReferences);
    }
  });

  // Side effects strictly after the commit, mirroring executeDeleteRoom.
  // Any failure below leaves the marked club retryable: the repeat call
  // resumes here and re-runs the idempotent sweep.
  const control = clubControl ?? getProductionLiveKitControl();
  const bucket = storageBucket ?? getStorage().bucket();

  // Rooms are bound to the club by their `clubId` FIELD, never by an id
  // prefix — same authority adminDeleteClub and the rules use. This sweeps
  // the lounge and any other room the club ever owns.
  const roomsSnapshot = await db
    .collection("rooms")
    .where("clubId", "==", clubId)
    .limit(limits.roomsPerRun + 1)
    .get();
  const roomDocuments = roomsSnapshot.docs.slice(0, limits.roomsPerRun);
  for (const roomDocument of roomDocuments) {
    await control.endRoom(roomDocument.id);
    if (
      !(await deleteVoiceSessionPage(
        roomDocument.id,
        limits.sessionsPerPage,
      ))
    ) {
      throw new HttpsError(
        "unavailable",
        "Club voice-session cleanup is still in progress. Retry the deletion.",
      );
    }
    requireMediaCleanup(
      await cleanupRoomMedia({ roomId: roomDocument.id, bucket }),
      "Club room media cleanup did not complete. Retry the deletion.",
    );
    await deleteDocumentRecursively(roomDocument.ref);
  }
  if (roomsSnapshot.size > limits.roomsPerRun) {
    throw new HttpsError(
      "unavailable",
      "Club room cleanup is still in progress. Retry the deletion.",
    );
  }

  if (club.deletionMediaCleaned !== true) {
    requireMediaCleanup(
      await cleanupClubMedia({ clubId, club, bucket }),
      "Club media cleanup did not complete. Retry the deletion.",
    );
    if (club.type === "family") {
      requireMediaCleanup(
        await cleanupFamilyMedia({ clubId, bucket }),
        "Family media cleanup did not complete. Retry the deletion.",
      );
    }
    await clubReference.set(
      {
        deletionMediaCleaned: true,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }

  // Root deletion does not cascade to the private users/{uid}/clubs index.
  // Remove every projection BEFORE the root, so an interruption never leaves
  // ghost projections behind a vanished member list (same invariant as
  // adminDeleteClub; the collectionGroup query is exercised by the emulator
  // tests — ADR-007).
  const projectionsSnapshot = await db
    .collectionGroup("clubs")
    .where("clubId", "==", clubId)
    .limit(limits.projectionsPerPage + 1)
    .get();
  const projectionPage = projectionsSnapshot.docs.slice(
    0,
    limits.projectionsPerPage,
  );
  for (let offset = 0; offset < projectionPage.length; offset += 450) {
    const batch = db.batch();
    for (const projection of projectionPage.slice(
      offset,
      offset + 450,
    )) {
      batch.delete(projection.ref);
    }
    await batch.commit();
  }
  if (projectionsSnapshot.size > limits.projectionsPerPage) {
    throw new HttpsError(
      "unavailable",
      "Club membership-index cleanup is still in progress. Retry the deletion.",
    );
  }

  await writeClubAuditLog({
    caller: { uid: auth.uid, role: "owner" },
    action: "delete_club_self",
    clubId,
    clubName: club.name ?? null,
    details: {
      ownerId: club.ownerId ?? null,
      clubType: club.type ?? "community",
      memberCount: Number(club.memberCount ?? 0),
      deletedRooms: roomDocuments.length,
    },
    entryId: `delete_club_self_${clubId}`,
  });

  // The marketing grant is tied to this exact Club lifecycle: remove it
  // before the canonical root so it cannot orphan or silently reactivate if
  // the same document id is ever recreated.
  await db.collection("clubMarketingConsents").doc(clubId).delete();
  await deleteDocumentRecursively(clubReference);

  return { success: true, clubId };
}

// firebase-functions v2 invokes every onCall handler as handler(request,
// responseProxy); a multi-parameter execute* function must never be
// registered directly (see functions/rooms/participants.js and the
// callable_invocation_contract tests). Register the one-argument wrapper.
const deleteClubSelf = onCall(CALLABLE_OPTIONS, (request) =>
  executeDeleteClubSelf(request),
);

module.exports = {
  DEFAULT_DELETION_LIMITS,
  deleteClubSelf,
  deleteVoiceSessionPage,
  deletionLimits,
  executeDeleteClubSelf,
};
