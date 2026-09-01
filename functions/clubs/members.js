const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { FieldPath, FieldValue } = require("firebase-admin/firestore");

const { requireAuthentication } = require("../utils/auth");
const { db, normalizeText } = require("../utils/firestore");
const { digest } = require("../integrity/guards");
const {
  LIVEKIT_SECRETS,
  getProductionLiveKitControl,
} = require("../livekit/control");
const { activeVoiceSessionReference } = require("../livekit/sessions");
const { consumeClubActionAttempt } = require("./quota");

const REGION = "europe-west1";
const ROLE_POWER = Object.freeze({
  owner: 60,
  coOwner: 50,
  admin: 40,
  moderator: 30,
  member: 20,
  guest: 10,
});
const REMOVAL_ROLES = new Set(["owner", "coOwner", "admin", "moderator"]);
const MEMBER_REMOVAL_ROOM_PAGE_SIZE = 25;
let memberLiveKitControlForTests = null;

function setMemberLiveKitControlForTests(control) {
  memberLiveKitControlForTests = control ?? null;
}

function memberRemovalOperationReference(clubId, memberId) {
  return db
    .collection("clubMemberRemovalOperations")
    .doc(digest("club.memberRemoval", clubId, memberId));
}

async function revokeMemberVoicePage({
  clubId,
  memberId,
  operationReference,
  operationGeneration,
  control,
}) {
  const operationSnapshot = await operationReference.get();
  const operation = operationSnapshot.data() ?? {};
  if (
    !operationSnapshot.exists ||
    operation.status === "completed" ||
    operation.generation !== operationGeneration
  ) {
    return { completed: operation.status === "completed", processed: 0 };
  }

  let query = db
    .collection("rooms")
    .where("clubId", "==", clubId)
    .orderBy(FieldPath.documentId());
  if (typeof operation.cursorRoomId === "string" && operation.cursorRoomId) {
    query = query.startAfter(operation.cursorRoomId);
  }
  const roomsSnapshot = await query.limit(MEMBER_REMOVAL_ROOM_PAGE_SIZE + 1).get();
  const roomDocuments = roomsSnapshot.docs.slice(
    0,
    MEMBER_REMOVAL_ROOM_PAGE_SIZE,
  );

  for (const roomDocument of roomDocuments) {
    const participantReference = roomDocument.ref
      .collection("participants")
      .doc(memberId);
    await db.runTransaction(async (transaction) => {
      const [roomSnapshot, participantSnapshot] = await transaction.getAll(
        roomDocument.ref,
        participantReference,
      );
      if (!roomSnapshot.exists || !participantSnapshot.exists) return;
      transaction.delete(participantReference);
      transaction.update(roomDocument.ref, {
        participantCount: Math.max(
          Number(roomSnapshot.data()?.participantCount ?? 0) - 1,
          0,
        ),
        updatedAt: FieldValue.serverTimestamp(),
      });
    });
    await control.revokeParticipant(roomDocument.id, memberId);
    await activeVoiceSessionReference(memberId, roomDocument.id).delete();
  }

  const hasMore = roomsSnapshot.size > MEMBER_REMOVAL_ROOM_PAGE_SIZE;
  const cursorRoomId = roomDocuments.at(-1)?.id ?? operation.cursorRoomId ?? null;
  const targetReference = db
    .collection("clubs")
    .doc(clubId)
    .collection("members")
    .doc(memberId);
  await db.runTransaction(async (transaction) => {
    const [currentOperation, targetSnapshot] = await transaction.getAll(
      operationReference,
      targetReference,
    );
    const current = currentOperation.data() ?? {};
    if (
      !currentOperation.exists ||
      current.generation !== operationGeneration ||
      current.status === "completed"
    ) {
      return;
    }
    if (targetSnapshot.exists) {
      throw new HttpsError(
        "aborted",
        "Club membership changed while voice access was being revoked.",
      );
    }
    transaction.set(
      operationReference,
      {
        cursorRoomId,
        processedRooms: FieldValue.increment(roomDocuments.length),
        status: hasMore ? "pending" : "completed",
        updatedAt: FieldValue.serverTimestamp(),
        ...(hasMore
          ? {}
          : { completedAt: FieldValue.serverTimestamp() }),
      },
      { merge: true },
    );
  });

  return { completed: !hasMore, processed: roomDocuments.length };
}

/**
 * Removes a lower-ranked Club member through one canonical Admin transaction.
 * A direct client root-counter update cannot prove which member disappeared,
 * so Firestore rules deny that old path entirely.
 */
const removeClubMemberSelf = onCall(
  {
    region: REGION,
    enforceAppCheck: false,
    secrets: LIVEKIT_SECRETS,
    timeoutSeconds: 120,
  },
  async (request) => {
    const auth = requireAuthentication(request);
    const clubId = normalizeText(request.data?.clubId, 128);
    const memberId = normalizeText(request.data?.memberId, 128);
    if (!clubId || !memberId) {
      throw new HttpsError(
        "invalid-argument",
        "Both clubId and memberId are required.",
      );
    }
    if (memberId === auth.uid) {
      throw new HttpsError(
        "failed-precondition",
        "You cannot remove your own membership.",
      );
    }
    await consumeClubActionAttempt(auth.uid, "removeClubMember");

    const clubReference = db.collection("clubs").doc(clubId);
    const actorReference = clubReference.collection("members").doc(auth.uid);
    const targetReference = clubReference.collection("members").doc(memberId);
    const targetProjection = db
      .collection("users")
      .doc(memberId)
      .collection("clubs")
      .doc(clubId);
    const actorProfileReference = db.collection("users").doc(auth.uid);
    const operationReference = memberRemovalOperationReference(clubId, memberId);
    let alreadyRemoved = false;
    let operationGeneration = null;
    let revocationCompleted = false;

    await db.runTransaction(async (transaction) => {
      const [
        clubSnapshot,
        actorSnapshot,
        targetSnapshot,
        actorProfile,
        operationSnapshot,
      ] =
        await transaction.getAll(
          clubReference,
          actorReference,
          targetReference,
          actorProfileReference,
          operationReference,
        );
      if (!clubSnapshot.exists) {
        throw new HttpsError("not-found", "The Club no longer exists.");
      }
      if (!actorSnapshot.exists || !actorProfile.exists) {
        throw new HttpsError(
          "failed-precondition",
          "The acting account must be an active Club member.",
        );
      }

      const club = clubSnapshot.data() ?? {};
      const actor = actorSnapshot.data() ?? {};
      const profile = actorProfile.data() ?? {};
      if (
        club.status !== "active" ||
        club.deletionInProgress === true ||
        actor.userId !== auth.uid ||
        actor.banned === true ||
        profile.banned === true ||
        profile.disabled === true
      ) {
        throw new HttpsError(
          "permission-denied",
          "Only an active Club manager can remove members.",
        );
      }
      const priorOperation = operationSnapshot.exists
        ? (operationSnapshot.data() ?? {})
        : {};
      if (!targetSnapshot.exists) {
        alreadyRemoved = true;
        transaction.delete(targetProjection);
        if (priorOperation.status === "completed") {
          revocationCompleted = true;
          return;
        }
        operationGeneration = Number.isSafeInteger(priorOperation.generation)
          ? priorOperation.generation
          : 1;
        transaction.set(
          operationReference,
          {
            schemaVersion: 1,
            clubId,
            memberId,
            generation: operationGeneration,
            status: "pending",
            cursorRoomId: priorOperation.cursorRoomId ?? null,
            processedRooms: Number.isSafeInteger(priorOperation.processedRooms)
              ? priorOperation.processedRooms
              : 0,
            requestedBy: priorOperation.requestedBy ?? auth.uid,
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        return;
      }
      const target = targetSnapshot.data() ?? {};
      const actorRole = String(actor.role ?? "member");
      const targetRole = String(target.role ?? "member");
      if (
        target.userId !== memberId ||
        ((actorRole === "owner") !== (club.ownerId === auth.uid))
      ) {
        throw new HttpsError(
          "failed-precondition",
          "Club membership authority is not canonical.",
        );
      }
      if (
        !REMOVAL_ROLES.has(actorRole) ||
        targetRole === "owner" ||
        (ROLE_POWER[actorRole] ?? 0) <= (ROLE_POWER[targetRole] ?? 0)
      ) {
        throw new HttpsError(
          "permission-denied",
          "Your Club role cannot remove this member.",
        );
      }
      if (club.ownerId === memberId) {
        throw new HttpsError(
          "failed-precondition",
          "The Club owner cannot be removed.",
        );
      }

      const memberCount = Math.max(Number(club.memberCount ?? 0) - 1, 0);
      const onlineCount = target.isOnline === true
        ? Math.max(Number(club.onlineCount ?? 0) - 1, 0)
        : Math.max(Number(club.onlineCount ?? 0), 0);
      operationGeneration = Number.isSafeInteger(priorOperation.generation)
        ? priorOperation.generation + 1
        : 1;
      transaction.delete(targetReference);
      transaction.delete(targetProjection);
      transaction.update(clubReference, {
        memberCount,
        onlineCount,
        updatedAt: FieldValue.serverTimestamp(),
      });
      transaction.set(operationReference, {
        schemaVersion: 1,
        clubId,
        memberId,
        generation: operationGeneration,
        status: "pending",
        cursorRoomId: null,
        processedRooms: 0,
        requestedBy: auth.uid,
        requestedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    });

    if (!revocationCompleted) {
      const lifecycle = await revokeMemberVoicePage({
        clubId,
        memberId,
        operationReference,
        operationGeneration,
        control:
          memberLiveKitControlForTests ?? getProductionLiveKitControl(),
      });
      if (!lifecycle.completed) {
        throw new HttpsError(
          "unavailable",
          "Club voice cleanup is still in progress. Retry this action.",
        );
      }
    }

    return { success: true, alreadyExisted: alreadyRemoved, clubId, memberId };
  },
);

module.exports = {
  removeClubMemberSelf,
  ROLE_POWER,
  REMOVAL_ROLES,
  MEMBER_REMOVAL_ROOM_PAGE_SIZE,
  memberRemovalOperationReference,
  setMemberLiveKitControlForTests,
};
