const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { FieldValue } = require("firebase-admin/firestore");

const { USER_ROLES, PERMANENT_DELETE_ROLES } = require("../utils/roles");

const {
  requireRole,
  requireRoomManager,
  requireProtectedOwner,
} = require("../utils/auth");

const {
  db,
  timestampToIso,
  normalizeText,
  positiveInteger,
  getDocumentOrThrow,
  deleteDocumentRecursively,
  deleteCollectionInBatches,
} = require("../utils/firestore");

const { writeRoomAuditLog } = require("../utils/audit");

const REGION = "europe-west1";

function mapRoom(document) {
  const data = document.data() ?? {};

  return {
    id: document.id,
    hostId: data.hostId ?? "",
    hostName: data.hostName ?? "YoVoice user",

    name: data.name ?? "Untitled room",
    description: data.description ?? "",
    category: data.category ?? "talk",
    language: data.language ?? "English",
    visibility: data.visibility ?? "public",

    roomType: data.roomType ?? "temporary",
    experience: data.experience ?? "community",
    status: data.status ?? "active",

    isLive: data.isLive === true,

    participantCount: Number(data.participantCount ?? 0),

    memberCount: Number(data.memberCount ?? 0),

    imageUrl: data.imageUrl ?? null,
    clubId: data.clubId ?? null,
    roomKind: data.roomKind ?? null,

    moderationReason: data.moderationReason ?? null,

    moderatedBy: data.moderatedBy ?? null,

    moderatedAt: timestampToIso(data.moderatedAt),

    createdAt: timestampToIso(data.createdAt),

    updatedAt: timestampToIso(data.updatedAt),
  };
}

function roomMatchesSearch(room, search) {
  if (!search) {
    return true;
  }

  const searchable = [
    room.id,
    room.hostId,
    room.hostName,
    room.name,
    room.description,
    room.category,
    room.language,
    room.roomType,
    room.experience,
    room.status,
    room.clubId,
  ]
    .filter(Boolean)
    .join(" ")
    .toLowerCase();

  return searchable.includes(search);
}

const listAdminRooms = onCall(
  {
    region: REGION,
    enforceAppCheck: false,
  },
  async (request) => {
    requireRoomManager(request);

    const limit = positiveInteger(request.data?.limit, 50, 100);

    const search = normalizeText(request.data?.search, 120).toLowerCase();

    const status = normalizeText(request.data?.status, 40);

    const cursorId = normalizeText(request.data?.cursorId, 128);

    let query = db
      .collection("rooms")
      .orderBy("updatedAt", "desc")
      .limit(limit);

    if (status) {
      query = db
        .collection("rooms")
        .where("status", "==", status)
        .orderBy("updatedAt", "desc")
        .limit(limit);
    }

    if (cursorId) {
      const cursorSnapshot = await db.collection("rooms").doc(cursorId).get();

      if (cursorSnapshot.exists) {
        query = query.startAfter(cursorSnapshot);
      }
    }

    const snapshot = await query.get();

    const rooms = snapshot.docs
      .map(mapRoom)
      .filter((room) => roomMatchesSearch(room, search));

    const lastDocument =
      snapshot.docs.length > 0 ? snapshot.docs[snapshot.docs.length - 1] : null;

    return {
      rooms,
      nextCursorId:
        snapshot.docs.length === limit && lastDocument ? lastDocument.id : null,
    };
  },
);

const getAdminRoom = onCall(
  {
    region: REGION,
    enforceAppCheck: false,
  },
  async (request) => {
    requireRoomManager(request);

    const roomId = normalizeText(request.data?.roomId, 128);

    if (!roomId) {
      throw new HttpsError("invalid-argument", "A room id is required.");
    }

    const roomReference = db.collection("rooms").doc(roomId);

    const roomSnapshot = await getDocumentOrThrow(
      roomReference,
      HttpsError,
      "The selected room was not found.",
    );

    const participantsSnapshot = await roomReference
      .collection("participants")
      .limit(200)
      .get();

    const participants = participantsSnapshot.docs.map((document) => {
      const data = document.data() ?? {};

      return {
        id: document.id,
        userId: data.userId ?? document.id,
        displayName: data.displayName ?? data.name ?? "YoVoice user",
        photoUrl: data.photoUrl ?? null,
        role: data.role ?? "listener",
        isSpeaker: data.isSpeaker === true,
        isMuted: data.isMuted === true,
        joinedAt: timestampToIso(data.joinedAt),
      };
    });

    return {
      room: mapRoom(roomSnapshot),
      participants,
    };
  },
);

const setRoomModerationStatus = onCall(
  {
    region: REGION,
    enforceAppCheck: false,
  },
  async (request) => {
    const caller = requireRoomManager(request);

    const roomId = normalizeText(request.data?.roomId, 128);

    const suspended = request.data?.suspended === true;

    const reason = normalizeText(request.data?.reason, 500);

    if (!roomId) {
      throw new HttpsError("invalid-argument", "A room id is required.");
    }

    if (suspended && !reason) {
      throw new HttpsError(
        "invalid-argument",
        "A moderation reason is required.",
      );
    }

    const roomReference = db.collection("rooms").doc(roomId);

    const roomSnapshot = await getDocumentOrThrow(
      roomReference,
      HttpsError,
      "The selected room was not found.",
    );

    const room = roomSnapshot.data() ?? {};

    const updateData = {
      status: suspended ? "suspended" : "active",

      moderationReason: suspended ? reason : null,

      moderatedBy: caller.uid,
      moderatedAt: FieldValue.serverTimestamp(),

      updatedAt: FieldValue.serverTimestamp(),
    };

    if (suspended) {
      updateData.isLive = false;
      updateData.participantCount = 0;
    }

    await roomReference.set(updateData, { merge: true });

    if (suspended) {
      await deleteCollectionInBatches(roomReference.collection("participants"));
    }

    await writeRoomAuditLog({
      caller,
      action: suspended ? "suspend_room" : "restore_room",
      roomId,
      roomName: room.name ?? null,
      details: {
        ownerId: room.hostId ?? null,
        previousStatus: room.status ?? null,
        newStatus: suspended ? "suspended" : "active",
        reason: suspended ? reason : null,
      },
    });

    return {
      success: true,
      roomId,
      status: suspended ? "suspended" : "active",
    };
  },
);

const forceEndRoom = onCall(
  {
    region: REGION,
    enforceAppCheck: false,
  },
  async (request) => {
    const caller = requireRoomManager(request);

    const roomId = normalizeText(request.data?.roomId, 128);

    const reason = normalizeText(request.data?.reason, 500);

    if (!roomId) {
      throw new HttpsError("invalid-argument", "A room id is required.");
    }

    const roomReference = db.collection("rooms").doc(roomId);

    const roomSnapshot = await getDocumentOrThrow(
      roomReference,
      HttpsError,
      "The selected room was not found.",
    );

    const room = roomSnapshot.data() ?? {};

    await roomReference.set(
      {
        isLive: false,
        participantCount: 0,
        forcedEndedBy: caller.uid,
        forcedEndReason: reason || "Administrative action",
        forcedEndedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    await deleteCollectionInBatches(roomReference.collection("participants"));

    await writeRoomAuditLog({
      caller,
      action: "force_end_room",
      roomId,
      roomName: room.name ?? null,
      details: {
        ownerId: room.hostId ?? null,
        reason: reason || "Administrative action",
      },
    });

    return {
      success: true,
      roomId,
      isLive: false,
    };
  },
);

const removeRoomParticipant = onCall(
  {
    region: REGION,
    enforceAppCheck: false,
  },
  async (request) => {
    const caller = requireRoomManager(request);

    const roomId = normalizeText(request.data?.roomId, 128);

    const userId = normalizeText(request.data?.userId, 128);

    const reason = normalizeText(request.data?.reason, 500);

    if (!roomId || !userId) {
      throw new HttpsError(
        "invalid-argument",
        "Both roomId and userId are required.",
      );
    }

    const roomReference = db.collection("rooms").doc(roomId);

    const roomSnapshot = await getDocumentOrThrow(
      roomReference,
      HttpsError,
      "The selected room was not found.",
    );

    const room = roomSnapshot.data() ?? {};

    const participantReference = roomReference
      .collection("participants")
      .doc(userId);

    const participantSnapshot = await participantReference.get();

    if (!participantSnapshot.exists) {
      throw new HttpsError(
        "not-found",
        "The selected participant is not in this room.",
      );
    }

    const participant = participantSnapshot.data() ?? {};

    await participantReference.delete();

    await roomReference.set(
      {
        participantCount: FieldValue.increment(-1),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    await writeRoomAuditLog({
      caller,
      action: "remove_room_participant",
      roomId,
      roomName: room.name ?? null,
      details: {
        removedUserId: userId,
        removedUserName: participant.displayName ?? participant.name ?? null,
        reason: reason || "Administrative action",
      },
    });

    return {
      success: true,
      roomId,
      userId,
    };
  },
);

const setParticipantMute = onCall(
  {
    region: REGION,
    enforceAppCheck: false,
  },
  async (request) => {
    const caller = requireRoomManager(request);

    const roomId = normalizeText(request.data?.roomId, 128);

    const userId = normalizeText(request.data?.userId, 128);

    const muted = request.data?.muted === true;

    if (!roomId || !userId) {
      throw new HttpsError(
        "invalid-argument",
        "Both roomId and userId are required.",
      );
    }

    const roomReference = db.collection("rooms").doc(roomId);

    const roomSnapshot = await getDocumentOrThrow(
      roomReference,
      HttpsError,
      "The selected room was not found.",
    );

    const participantReference = roomReference
      .collection("participants")
      .doc(userId);

    await getDocumentOrThrow(
      participantReference,
      HttpsError,
      "The selected participant is not in this room.",
    );

    await participantReference.set(
      {
        isMuted: muted,
        moderatedBy: caller.uid,
        moderatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    const room = roomSnapshot.data() ?? {};

    await writeRoomAuditLog({
      caller,
      action: muted ? "mute_room_participant" : "unmute_room_participant",
      roomId,
      roomName: room.name ?? null,
      details: {
        userId,
        muted,
      },
    });

    return {
      success: true,
      roomId,
      userId,
      muted,
    };
  },
);

const adminDeleteRoom = onCall(
  {
    region: REGION,
    enforceAppCheck: false,
    timeoutSeconds: 120,
    memory: "512MiB",
    // Permanent deletion is an OWNERSHIP capability: the uid must match
    // the protected-owner secret, not merely carry superAdmin.
    secrets: ["YOVOICE_PROTECTED_OWNER_UID"],
  },
  async (request) => {
    const caller = await requireProtectedOwner(request);

    const roomId = normalizeText(request.data?.roomId, 128);

    const reason = normalizeText(request.data?.reason, 500);

    const confirmation = normalizeText(request.data?.confirmation, 128);

    if (!roomId) {
      throw new HttpsError("invalid-argument", "A room id is required.");
    }

    if (!reason) {
      throw new HttpsError(
        "invalid-argument",
        "A deletion reason is required.",
      );
    }

    if (confirmation !== roomId) {
      throw new HttpsError(
        "failed-precondition",
        "Confirm permanent deletion by providing the exact room id.",
      );
    }

    const roomReference = db.collection("rooms").doc(roomId);

    const roomSnapshot = await getDocumentOrThrow(
      roomReference,
      HttpsError,
      "The selected room was not found.",
    );

    const room = roomSnapshot.data() ?? {};

    await writeRoomAuditLog({
      caller,
      action: "delete_room",
      roomId,
      roomName: room.name ?? null,
      details: {
        ownerId: room.hostId ?? null,
        ownerName: room.hostName ?? null,
        reason,
        roomType: room.roomType ?? null,
        experience: room.experience ?? null,
        clubId: room.clubId ?? null,
      },
    });

    await deleteDocumentRecursively(roomReference);

    return {
      success: true,
      roomId,
      message: "The room was permanently deleted.",
    };
  },
);

module.exports = {
  listAdminRooms,
  getAdminRoom,
  setRoomModerationStatus,
  forceEndRoom,
  removeRoomParticipant,
  setParticipantMute,
  adminDeleteRoom,
};
