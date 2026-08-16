const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { FieldValue, Timestamp } = require("firebase-admin/firestore");
const { getStorage } = require("firebase-admin/storage");

const { requireAuthentication } = require("../utils/auth");
const { db, normalizeText } = require("../utils/firestore");
const {
  canonicalNotificationData,
  notificationReference,
  restrictionIsActive,
} = require("../notifications/canonical");
const {
  LIVEKIT_SECRETS,
  getProductionLiveKitControl,
} = require("../livekit/control");
const {
  deleteActiveVoiceSession,
  deleteActiveVoiceSessionsForRoom,
} = require("../livekit/sessions");
const { cleanupRoomMedia } = require("../media/cleanup");

const REGION = "europe-west1";
const SAFE_DOCUMENT_ID = /^[A-Za-z0-9_-]{1,128}$/u;
const ROOM_STATUSES = new Set(["active", "closed", "archived"]);

async function requireActiveCaller(request) {
  const auth = requireAuthentication(request);
  const profile = await db.collection("users").doc(auth.uid).get();
  if (
    !profile.exists ||
    profile.data()?.banned === true ||
    profile.data()?.disabled === true
  ) {
    throw new HttpsError(
      "permission-denied",
      "An active account is required for room control.",
    );
  }
  return { ...auth, profile: profile.data() ?? {} };
}

async function requireHostRoom(transaction, roomReference, uid) {
  const snapshot = await transaction.get(roomReference);
  if (!snapshot.exists) {
    throw new HttpsError("not-found", "The room no longer exists.");
  }
  const room = snapshot.data() ?? {};
  if (room.hostId !== uid) {
    throw new HttpsError(
      "permission-denied",
      "Only the room host can manage this room.",
    );
  }
  return room;
}

async function recursiveDelete(reference) {
  if (typeof db.recursiveDelete === "function") {
    await db.recursiveDelete(reference);
    return;
  }
  const snapshot = await reference.limit(250).get();
  if (snapshot.empty) return;
  const batch = db.batch();
  for (const document of snapshot.docs) batch.delete(document.ref);
  await batch.commit();
  if (snapshot.size === 250) await recursiveDelete(reference);
}

/** Host-only participant removal with the roster and counter in one Admin
 * transaction. Rules can verify a self-leave by uid, but cannot discover an
 * arbitrary participant id changed elsewhere in a host batch, so this path is
 * the counter authority for moderation removals. */
async function executeRemoveRoomParticipant(
  request,
  roomControl = null,
) {
    const auth = await requireActiveCaller(request);
    const roomId = normalizeText(request.data?.roomId, 128);
    const participantId = normalizeText(request.data?.participantId, 128);
    if (!SAFE_DOCUMENT_ID.test(roomId) || !SAFE_DOCUMENT_ID.test(participantId)) {
      throw new HttpsError(
        "invalid-argument",
        "Valid roomId and participantId values are required.",
      );
    }
    if (participantId === auth.uid) {
      throw new HttpsError(
        "failed-precondition",
        "Use Leave Room to remove your own participant.",
      );
    }

    const roomReference = db.collection("rooms").doc(roomId);
    const participantReference = roomReference
      .collection("participants")
      .doc(participantId);

    await db.runTransaction(async (transaction) => {
      const [roomSnapshot, participantSnapshot] = await transaction.getAll(
        roomReference,
        participantReference,
      );
      if (!roomSnapshot.exists) {
        throw new HttpsError("not-found", "The room no longer exists.");
      }
      const room = roomSnapshot.data() ?? {};
      if (room.hostId !== auth.uid) {
        throw new HttpsError(
          "permission-denied",
          "Only the room host can remove participants.",
        );
      }
      if (room.status !== "active" || room.isLive !== true ||
          room.deletionInProgress === true) {
        throw new HttpsError(
          "failed-precondition",
          "Participants can only be removed from a live active room.",
        );
      }
      if (!participantSnapshot.exists) return;
      const participant = participantSnapshot.data() ?? {};
      if (participant.userId === room.hostId || participantId === room.hostId) {
        throw new HttpsError(
          "failed-precondition",
          "The room host cannot be removed.",
        );
      }

      transaction.delete(participantReference);
      deleteActiveVoiceSession(transaction, participantId, roomId);
      transaction.update(roomReference, {
        participantCount: Math.max(Number(room.participantCount ?? 0) - 1, 0),
        updatedAt: FieldValue.serverTimestamp(),
      });
    });

    await (roomControl ?? getProductionLiveKitControl())
      .revokeParticipant(roomId, participantId);

    return { success: true, roomId, participantId };
}

const CALLABLE_OPTIONS = {
  region: REGION,
  enforceAppCheck: false,
  secrets: LIVEKIT_SECRETS,
  timeoutSeconds: 120,
};

const removeRoomParticipantSelf = onCall(
  CALLABLE_OPTIONS,
  executeRemoveRoomParticipant,
);

/**
 * Participant self-leave is server-authoritative so deleting the Firestore
 * row cannot leave an already-issued LiveKit identity connected. The roster,
 * root counter and active-session mirror move atomically; control-plane
 * revocation happens immediately afterwards and is safe to retry.
 */
async function executeLeaveRoom(request, roomControl = null) {
  const auth = await requireActiveCaller(request);
  const roomId = normalizeText(request.data?.roomId, 128);
  if (!SAFE_DOCUMENT_ID.test(roomId)) {
    throw new HttpsError("invalid-argument", "A valid room is required.");
  }
  const roomReference = db.collection("rooms").doc(roomId);
  const participantReference = roomReference
    .collection("participants")
    .doc(auth.uid);
  let endedLounge = false;

  await db.runTransaction(async (transaction) => {
    const [roomSnapshot, participantSnapshot] = await transaction.getAll(
      roomReference,
      participantReference,
    );
    if (!roomSnapshot.exists) {
      deleteActiveVoiceSession(transaction, auth.uid, roomId);
      return;
    }
    const room = roomSnapshot.data() ?? {};
    if (
      room.hostId === auth.uid &&
      room.roomType === "temporary" &&
      !room.clubId
    ) {
      throw new HttpsError(
        "failed-precondition",
        "A temporary-room host must end the room for everyone.",
      );
    }

    deleteActiveVoiceSession(transaction, auth.uid, roomId);
    if (!participantSnapshot.exists) return;
    const participant = participantSnapshot.data() ?? {};
    if (participant.userId !== auth.uid) {
      throw new HttpsError(
        "permission-denied",
        "The participant identity is not canonical.",
      );
    }

    const currentCount = Math.max(Number(room.participantCount ?? 0), 0);
    const nextCount = Math.max(currentCount - 1, 0);
    const isClubLounge = room.roomKind === "clubLounge" && !!room.clubId;
    endedLounge = isClubLounge && nextCount === 0;
    transaction.delete(participantReference);
    transaction.update(roomReference, {
      participantCount: nextCount,
      ...(endedLounge
        ? {
            isLive: false,
            endedAt: FieldValue.serverTimestamp(),
          }
        : {}),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });

  const control = roomControl ?? getProductionLiveKitControl();
  if (endedLounge) {
    await control.endRoom(roomId);
    await deleteActiveVoiceSessionsForRoom(roomId);
  } else {
    await control.revokeParticipant(roomId, auth.uid);
  }
  return { success: true, roomId };
}

const leaveRoomSelf = onCall(CALLABLE_OPTIONS, executeLeaveRoom);

async function executeSetRoomStatus(
  request,
  roomControl = null,
) {
  const auth = await requireActiveCaller(request);
  const roomId = normalizeText(request.data?.roomId, 128);
  const status = normalizeText(request.data?.status, 32);
  if (!SAFE_DOCUMENT_ID.test(roomId) || !ROOM_STATUSES.has(status)) {
    throw new HttpsError("invalid-argument", "A valid room and status are required.");
  }
  const roomReference = db.collection("rooms").doc(roomId);
  await db.runTransaction(async (transaction) => {
    const room = await requireHostRoom(
      transaction,
      roomReference,
      auth.uid,
    );
    if (!ROOM_STATUSES.has(String(room.status ?? "active")) ||
        room.deletionInProgress === true) {
      throw new HttpsError(
        "failed-precondition",
        "A moderated or deleting room cannot be restored by its host.",
      );
    }
    transaction.update(roomReference, {
      status,
      ...(status === "active"
        ? {}
        : {
            isLive: false,
            participantCount: 0,
            endedAt: FieldValue.serverTimestamp(),
          }),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  if (status !== "active") {
    await (roomControl ?? getProductionLiveKitControl()).endRoom(roomId);
    await deleteActiveVoiceSessionsForRoom(roomId);
    await recursiveDelete(roomReference.collection("participants"));
  }
  return { success: true, roomId, status };
}

const setRoomStatusSelf = onCall(CALLABLE_OPTIONS, executeSetRoomStatus);

async function executeEndRoomVoice(
  request,
  roomControl = null,
) {
  const auth = await requireActiveCaller(request);
  const roomId = normalizeText(request.data?.roomId, 128);
  if (!SAFE_DOCUMENT_ID.test(roomId)) {
    throw new HttpsError("invalid-argument", "A valid room is required.");
  }
  const roomReference = db.collection("rooms").doc(roomId);
  await db.runTransaction(async (transaction) => {
    const room = await requireHostRoom(transaction, roomReference, auth.uid);
    if (room.status !== "active" || room.deletionInProgress === true) {
      throw new HttpsError(
        "failed-precondition",
        "Only an active room can end its voice session.",
      );
    }
    transaction.update(roomReference, {
      isLive: false,
      participantCount: 0,
      endedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  await (roomControl ?? getProductionLiveKitControl()).endRoom(roomId);
  await deleteActiveVoiceSessionsForRoom(roomId);
  await recursiveDelete(roomReference.collection("participants"));
  return { success: true, roomId };
}

const endRoomVoiceSelf = onCall(CALLABLE_OPTIONS, executeEndRoomVoice);

async function executeDeleteRoom(
  request,
  roomControl = null,
  storageBucket = null,
) {
  const auth = await requireActiveCaller(request);
  const roomId = normalizeText(request.data?.roomId, 128);
  if (!SAFE_DOCUMENT_ID.test(roomId)) {
    throw new HttpsError("invalid-argument", "A valid room is required.");
  }
  const roomReference = db.collection("rooms").doc(roomId);
  await db.runTransaction(async (transaction) => {
    const room = await requireHostRoom(transaction, roomReference, auth.uid);
    if (room.roomKind === "clubLounge" || room.clubId) {
      throw new HttpsError(
        "failed-precondition",
        "A Club Lounge is deleted through the Club lifecycle.",
      );
    }
    if (!ROOM_STATUSES.has(String(room.status ?? "active"))) {
      throw new HttpsError(
        "failed-precondition",
        "A moderated room cannot be deleted by its host.",
      );
    }
    transaction.update(roomReference, {
      status: "closed",
      isLive: false,
      participantCount: 0,
      deletionInProgress: true,
      endedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  await (roomControl ?? getProductionLiveKitControl()).endRoom(roomId);
  await deleteActiveVoiceSessionsForRoom(roomId);
  const mediaCleanup = await cleanupRoomMedia({
    roomId,
    bucket: storageBucket ?? getStorage().bucket(),
  });
  if (mediaCleanup.deleted !== true) {
    throw new HttpsError(
      "unavailable",
      "Room media cleanup did not complete. Retry the deletion.",
    );
  }
  await recursiveDelete(roomReference);
  return { success: true, roomId };
}

const deleteRoomSelf = onCall(CALLABLE_OPTIONS, executeDeleteRoom);

async function executeModerateRoomParticipant(
  request,
  roomControl = null,
) {
  const auth = await requireActiveCaller(request);
  const roomId = normalizeText(request.data?.roomId, 128);
  const participantId = normalizeText(request.data?.participantId, 128);
  const hasMuted = typeof request.data?.isMuted === "boolean";
  const hasSpeaker = typeof request.data?.isSpeaker === "boolean";
  const lowerHand = request.data?.lowerHand === true;
  if (
    !SAFE_DOCUMENT_ID.test(roomId) ||
    !SAFE_DOCUMENT_ID.test(participantId) ||
    (!hasMuted && !hasSpeaker && !lowerHand)
  ) {
    throw new HttpsError(
      "invalid-argument",
      "A room, participant and moderation action are required.",
    );
  }
  const roomReference = db.collection("rooms").doc(roomId);
  const participantReference = roomReference
    .collection("participants")
    .doc(participantId);
  const restrictionReference = db.collection("restrictions").doc(participantId);
  let resulting = null;
  await db.runTransaction(async (transaction) => {
    const [room, participantSnapshot, restrictionSnapshot] =
      await Promise.all([
        requireHostRoom(transaction, roomReference, auth.uid),
        transaction.get(participantReference),
        transaction.get(restrictionReference),
      ]);
    if (!participantSnapshot.exists) {
      throw new HttpsError("not-found", "The participant is no longer here.");
    }
    if (room.status !== "active" || room.isLive !== true ||
        room.deletionInProgress === true) {
      throw new HttpsError(
        "failed-precondition",
        "Only a live active room can be moderated by its host.",
      );
    }
    if (participantId === room.hostId &&
        ((hasMuted && request.data.isMuted) ||
         (hasSpeaker && !request.data.isSpeaker))) {
      throw new HttpsError(
        "failed-precondition",
        "The room host must remain on stage and cannot be moderator-muted.",
      );
    }
    const participant = participantSnapshot.data() ?? {};
    const restriction = restrictionSnapshot.exists
      ? (restrictionSnapshot.data() ?? {})
      : {};
    const expiresAt = restriction.expiresAt;
    const communicationMuted = restriction.type === "communicationMute" &&
      (expiresAt == null ||
       (expiresAt instanceof Timestamp && expiresAt.toMillis() > Date.now()));
    const promotingToSpeaker = hasSpeaker &&
      request.data.isSpeaker === true &&
      participant.isSpeaker !== true &&
      participant.role !== "speaker" &&
      participant.role !== "host" &&
      participantId !== room.hostId;
    if (promotingToSpeaker) {
      const targetProfileReference = db.doc(`users/${participantId}`);
      const hostRestrictionReference = db.doc(`restrictions/${auth.uid}`);
      const hostBlockReference = db.doc(
        `users/${auth.uid}/blocked/${participantId}`,
      );
      const participantBlockReference = db.doc(
        `users/${participantId}/blocked/${auth.uid}`,
      );
      const notificationType = room.experience === "broadcast"
        ? "broadcastInvite"
        : "roomInvite";
      const inviteNotificationReference = notificationReference(
        participantId,
        `${notificationType}_${roomId}_${participantId}`,
      );
      const [
        targetProfile,
        hostRestriction,
        hostBlock,
        participantBlock,
        notification,
      ] =
        await transaction.getAll(
          targetProfileReference,
          hostRestrictionReference,
          hostBlockReference,
          participantBlockReference,
          inviteNotificationReference,
        );
      const target = targetProfile.exists ? (targetProfile.data() ?? {}) : {};
      if (
        !targetProfile.exists ||
        target.banned === true ||
        target.disabled === true ||
        restrictionIsActive(hostRestriction.data()) ||
        communicationMuted ||
        hostBlock.exists ||
        participantBlock.exists
      ) {
        throw new HttpsError(
          "failed-precondition",
          "This participant cannot be invited to the stage.",
        );
      }
      if (!notification.exists) {
        transaction.set(
          inviteNotificationReference,
          canonicalNotificationData({
            actorId: auth.uid,
            actorProfile: auth.profile,
            type: notificationType,
            targetId: roomId,
            targetLabel:
              typeof room.name === "string" ? room.name : "Voice room",
            dedupeKey: `${notificationType}_${roomId}_${participantId}`,
          }),
        );
      }
    }
    const update = { updatedAt: FieldValue.serverTimestamp() };
    if (hasMuted) {
      update.hostMuted = request.data.isMuted;
    }
    if (hasSpeaker) {
      update.role = participantId === room.hostId
        ? "host"
        : (request.data.isSpeaker ? "speaker" : "listener");
      update.isSpeaker = request.data.isSpeaker;
      update.isHandRaised = false;
    }
    if (lowerHand) update.isHandRaised = false;
    transaction.update(participantReference, update);

    const role = update.role ?? participant.role ?? "listener";
    const isMuted = update.isMuted ?? (participant.isMuted === true);
    const hostMuted = update.hostMuted ?? (participant.hostMuted === true);
    const serverMuted = participant.serverMuted === true;
    resulting = {
      canPublish: (role === "host" || role === "speaker") &&
        !isMuted && !hostMuted && !serverMuted && !communicationMuted,
      canPublishData: !communicationMuted,
    };
  });

  const control = roomControl ?? getProductionLiveKitControl();
  if (typeof control.setParticipantPermissions === "function") {
    await control.setParticipantPermissions(roomId, participantId, resulting);
  } else {
    await control.setPublishingAllowed(
      roomId,
      participantId,
      resulting.canPublish,
    );
  }
  return { success: true, roomId, participantId };
}

const moderateRoomParticipantSelf = onCall(
  CALLABLE_OPTIONS,
  executeModerateRoomParticipant,
);

async function executeSetOwnParticipantMute(
  request,
  roomControl = null,
) {
  const auth = await requireActiveCaller(request);
  const roomId = normalizeText(request.data?.roomId, 128);
  const isMuted = request.data?.isMuted;
  if (!SAFE_DOCUMENT_ID.test(roomId) || typeof isMuted !== "boolean") {
    throw new HttpsError(
      "invalid-argument",
      "A valid room and mute state are required.",
    );
  }
  const roomReference = db.collection("rooms").doc(roomId);
  const participantReference = roomReference
    .collection("participants")
    .doc(auth.uid);
  const restrictionReference = db.collection("restrictions").doc(auth.uid);
  let resulting = null;
  await db.runTransaction(async (transaction) => {
    const [roomSnapshot, participantSnapshot, restrictionSnapshot] =
      await transaction.getAll(
        roomReference,
        participantReference,
        restrictionReference,
      );
    if (!roomSnapshot.exists || !participantSnapshot.exists) {
      throw new HttpsError("not-found", "The room participant no longer exists.");
    }
    const room = roomSnapshot.data() ?? {};
    const participant = participantSnapshot.data() ?? {};
    if (room.status !== "active" || room.isLive !== true ||
        room.deletionInProgress === true || participant.userId !== auth.uid) {
      throw new HttpsError(
        "failed-precondition",
        "Mute can only change for your active voice participant.",
      );
    }
    transaction.update(participantReference, {
      isMuted,
      updatedAt: FieldValue.serverTimestamp(),
    });
    const restriction = restrictionSnapshot.exists
      ? (restrictionSnapshot.data() ?? {})
      : {};
    const expiresAt = restriction.expiresAt;
    const communicationMuted = restriction.type === "communicationMute" &&
      (expiresAt == null ||
       (expiresAt instanceof Timestamp && expiresAt.toMillis() > Date.now()));
    const role = String(participant.role ?? "listener");
    resulting = {
      canPublish: (role === "host" || role === "speaker") &&
        !isMuted && participant.hostMuted !== true &&
        participant.serverMuted !== true && !communicationMuted,
      canPublishData: !communicationMuted,
    };
  });
  await (roomControl ?? getProductionLiveKitControl())
    .setParticipantPermissions(roomId, auth.uid, resulting);
  return { success: true, roomId, isMuted };
}

const setOwnRoomParticipantMute = onCall(
  CALLABLE_OPTIONS,
  executeSetOwnParticipantMute,
);

module.exports = {
  deleteRoomSelf,
  endRoomVoiceSelf,
  executeDeleteRoom,
  executeEndRoomVoice,
  executeLeaveRoom,
  executeModerateRoomParticipant,
  executeRemoveRoomParticipant,
  executeSetOwnParticipantMute,
  executeSetRoomStatus,
  moderateRoomParticipantSelf,
  requireActiveCaller,
  leaveRoomSelf,
  removeRoomParticipantSelf,
  setOwnRoomParticipantMute,
  setRoomStatusSelf,
};
