const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { FieldValue } = require("firebase-admin/firestore");
const { getStorage } = require("firebase-admin/storage");

const {
  USER_ROLES,
  ROOM_MANAGEMENT_ROLES,
  PERMANENT_DELETE_ROLES,
} = require("../utils/roles");

const {
  requireVerifiedStaff,
} = require("../utils/auth");

const {
  db,
  timestampToIso,
  normalizeText,
  positiveInteger,
  getDocumentOrThrow,
  deleteDocumentRecursively,
  deleteCollectionInBatches,
  roomIsActive,
} = require("../utils/firestore");

const { writeRoomAuditLog } = require("../utils/audit");
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
const SPEAKING_ROLES = new Set(["host", "speaker"]);

const QUARANTINE_ROLES = new Set([
  USER_ROLES.SUPER_MODERATOR,
  USER_ROLES.SUPER_ADMIN,
]);

async function requireRoomStaff(request) {
  return requireVerifiedStaff(
    request,
    ROOM_MANAGEMENT_ROLES,
    "You do not have permission to manage rooms.",
  );
}

async function requireRoomQuarantineAccess(request) {
  return requireVerifiedStaff(
    request,
    QUARANTINE_ROLES,
    "You do not have permission to quarantine rooms.",
  );
}

async function requireRoomDeleteAccess(request) {
  return requireVerifiedStaff(
    request,
    PERMANENT_DELETE_ROLES,
    "Only an administrator or super moderator can delete any room.",
  );
}

let liveKitControlOverride = null;
let storageBucketOverride = null;

/// Test injection only. Production always resolves the secret-backed client.
function setRoomLiveKitControlForTests(control) {
  liveKitControlOverride = control ?? null;
}

/// Test injection only. Production always resolves the Firebase bucket.
function setRoomStorageBucketForTests(bucket) {
  storageBucketOverride = bucket ?? null;
}

function resolveStorageBucket() {
  return storageBucketOverride ?? getStorage().bucket();
}

function resolveLiveKitControl() {
  if (liveKitControlOverride) return liveKitControlOverride;
  try {
    return getProductionLiveKitControl();
  } catch (error) {
    console.error("LiveKit control-plane is not configured", {
      errorName: error?.name ?? "Error",
    });
    throw new HttpsError(
      "failed-precondition",
      "Live voice moderation is not configured.",
    );
  }
}

function parseSuspended(data) {
  if (typeof data?.suspended === "boolean") return data.suspended;

  const status = normalizeText(data?.status, 40).toLowerCase();
  if (status === "suspended" || status === "quarantined") return true;
  if (status === "active") return false;

  throw new HttpsError(
    "invalid-argument",
    "Status must be active, suspended or quarantined.",
  );
}

function communicationRestrictionIsActive(restriction, now = Date.now()) {
  if (restriction?.type !== "communicationMute") return false;
  if (restriction.expiresAt == null) return true;
  const expiresAt = typeof restriction.expiresAt.toMillis === "function"
    ? restriction.expiresAt.toMillis()
    : new Date(restriction.expiresAt).getTime();
  return Number.isFinite(expiresAt) && expiresAt > now;
}

async function applyLiveKitControl({
  caller,
  roomId,
  roomName,
  operation,
  affectedUserId = null,
  action,
}) {
  try {
    return await action();
  } catch (error) {
    // The Firestore authority was intentionally applied first, so new token
    // requests are already blocked. Record the partial outcome and make the
    // caller retry; never report success while an issued session may remain.
    console.error("LiveKit moderation control failed", {
      operation,
      roomId,
      affectedUserId,
      errorName: error?.name ?? "Error",
      errorCode: error?.cause?.code ?? error?.code ?? null,
      errorStatus: error?.cause?.status ?? error?.status ?? null,
    });
    try {
      await writeRoomAuditLog({
        caller,
        action: "livekit_control_failure",
        roomId,
        roomName,
        details: {
          operation,
          affectedUserId,
          stateApplied: true,
          liveKitApplied: false,
        },
      });
    } catch (auditError) {
      console.error("Failed to record LiveKit control failure", {
        operation,
        roomId,
        errorName: auditError?.name ?? "Error",
      });
    }
    throw new HttpsError(
      "unavailable",
      "The room state was secured, but the live voice session could not "
        + "be updated. Retry this action.",
      {
        operation,
        stateApplied: true,
        liveKitApplied: false,
      },
    );
  }
}

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
    await requireRoomStaff(request);

    const limit = positiveInteger(request.data?.limit, 50, 100);

    const search = normalizeText(request.data?.search, 120).toLowerCase();

    const status = normalizeText(request.data?.status, 40);

    const cursorId = normalizeText(request.data?.cursorId, 128);

    // "active" is the one status the browser cannot ask Firestore for.
    // ADR-093: the rules read this field as `.get('status', 'active')`, so an
    // absent `status` IS active, and 25 of the 45 production rooms predate the
    // field entirely. `mapRoom` above already agrees — it reports
    // `data.status ?? "active"` — so the unfiltered list SHOWS those 25 rooms
    // as active and only the query disagreed: `where("status", "==",
    // "active")` matches 9 rooms where the rules and the mapper recognise 34.
    // It does not even return that truncated list, because no
    // `status`+`updatedAt` composite index existed: it threw
    // FAILED_PRECONDITION. Every other value ("closed", "suspended",
    // "archived") is written EXPLICITLY by moderation, so those keep the
    // indexed equality and stay a server-side query.
    const activeFilter = status === "active";

    let query = db.collection("rooms");

    if (status && !activeFilter) {
      query = query.where("status", "==", status);
    }

    query = query.orderBy("updatedAt", "desc").limit(limit);

    if (cursorId) {
      const cursorSnapshot = await db.collection("rooms").doc(cursorId).get();

      if (cursorSnapshot.exists) {
        query = query.startAfter(cursorSnapshot);
      }
    }

    const snapshot = await query.get();

    // Both in-memory filters run AFTER the limit, so a page can return fewer
    // rooms than it scanned — including none. `nextCursorId` below is
    // therefore derived from `snapshot.docs`, the documents scanned, never
    // from `rooms`: it means "there may be more to scan", not "there are more
    // to show". That is the contract `search` has always had; the caller pages
    // until `nextCursorId` is null rather than until a page comes back short.
    const rooms = snapshot.docs
      .map(mapRoom)
      .filter((room) => !activeFilter || roomIsActive(room))
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
    await requireRoomStaff(request);

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
        isMuted: data.isMuted === true || data.serverMuted === true,
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
    secrets: LIVEKIT_SECRETS,
    timeoutSeconds: 120,
    enforceAppCheck: false,
  },
  async (request) => {
    const caller = await requireRoomQuarantineAccess(request);

    const roomId = normalizeText(request.data?.roomId, 128);

    const suspended = parseSuspended(request.data);

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

    const liveKitControl = suspended ? resolveLiveKitControl() : null;

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

    // Validate and mutate in one transaction. A permanent deletion can race
    // a restore request between a standalone read and update; without the
    // transactional precondition that restore could overwrite the secure
    // `deleted` tombstone with `active`.
    const room = await db.runTransaction(async (transaction) => {
      const roomSnapshot = await transaction.get(roomReference);
      if (!roomSnapshot.exists) {
        throw new HttpsError(
          "not-found",
          "The selected room was not found.",
        );
      }
      const currentRoom = roomSnapshot.data() ?? {};
      if (currentRoom.status === "deleted") {
        throw new HttpsError(
          "failed-precondition",
          "A room pending permanent deletion cannot be restored or suspended.",
        );
      }
      if (!suspended && currentRoom.status !== "suspended") {
        throw new HttpsError(
          "failed-precondition",
          "Only a suspended room can be restored.",
        );
      }
      transaction.update(roomReference, updateData);
      return currentRoom;
    });

    if (suspended) {
      await applyLiveKitControl({
        caller,
        roomId,
        roomName: room.name ?? null,
        operation: "suspendRoom",
        action: () => liveKitControl.endRoom(roomId),
      });
      await deleteActiveVoiceSessionsForRoom(roomId);
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
        liveKitControlApplied: suspended,
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
    secrets: LIVEKIT_SECRETS,
    timeoutSeconds: 120,
    enforceAppCheck: false,
  },
  async (request) => {
    const caller = await requireRoomStaff(request);

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

    // A moderator may end a public room only and must always supply the
    // reason promised by the capability matrix. Super moderation may end
    // any room; the owner inherits that tier through the same verified
    // server record.
    if (caller.role === USER_ROLES.MODERATOR) {
      if (room.visibility !== "public") {
        throw new HttpsError(
          "permission-denied",
          "Moderators may end public rooms only.",
        );
      }
      if (!reason) {
        throw new HttpsError(
          "invalid-argument",
          "A reason is required to end a public room.",
        );
      }
    }

    // Resolve secrets/configuration before mutating Firestore. The remote
    // call still runs only after the authoritative state has been closed.
    const liveKitControl = resolveLiveKitControl();

    await roomReference.update({
      isLive: false,
      participantCount: 0,
      forcedEndedBy: caller.uid,
      forcedEndReason: reason || "Administrative action",
      forcedEndedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    await applyLiveKitControl({
      caller,
      roomId,
      roomName: room.name ?? null,
      operation: "forceEndRoom",
      action: () => liveKitControl.endRoom(roomId),
    });

    await deleteActiveVoiceSessionsForRoom(roomId);
    await deleteCollectionInBatches(roomReference.collection("participants"));

    await writeRoomAuditLog({
      caller,
      action: "force_end_room",
      roomId,
      roomName: room.name ?? null,
      details: {
        ownerId: room.hostId ?? null,
        reason: reason || "Administrative action",
        liveKitControlApplied: true,
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
    secrets: LIVEKIT_SECRETS,
    timeoutSeconds: 30,
    enforceAppCheck: false,
  },
  async (request) => {
    const caller = await requireRoomStaff(request);

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
    const liveKitControl = resolveLiveKitControl();

    const participantReference = roomReference
      .collection("participants")
      .doc(userId);

    const removal = await db.runTransaction(async (transaction) => {
      const [currentRoomSnapshot, participantSnapshot] = await Promise.all([
        transaction.get(roomReference),
        transaction.get(participantReference),
      ]);
      if (!currentRoomSnapshot.exists) {
        throw new HttpsError(
          "not-found",
          "The selected room was not found.",
        );
      }
      // Remove the per-user token discovery mirror in the same durable
      // transaction as the roster row. A remote failure can then be retried
      // without leaving future moderation dependent on a stale session index.
      deleteActiveVoiceSession(transaction, userId, roomId);
      if (!participantSnapshot.exists) {
        return { removed: false, participant: {} };
      }

      const currentRoom = currentRoomSnapshot.data() ?? {};
      const currentCount = Number(currentRoom.participantCount ?? 0);
      transaction.delete(participantReference);
      transaction.set(
        roomReference,
        {
          participantCount: Number.isFinite(currentCount)
            ? Math.max(0, currentCount - 1)
            : 0,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      return {
        removed: true,
        participant: participantSnapshot.data() ?? {},
      };
    });

    // Also runs on an idempotent retry where Firestore no longer has the
    // participant: the previous attempt may have secured Firestore and then
    // failed before revoking the already-issued LiveKit token.
    await applyLiveKitControl({
      caller,
      roomId,
      roomName: room.name ?? null,
      operation: "removeParticipant",
      affectedUserId: userId,
      action: () => liveKitControl.revokeParticipant(roomId, userId),
    });

    await writeRoomAuditLog({
      caller,
      action: "remove_room_participant",
      roomId,
      roomName: room.name ?? null,
      details: {
        removedUserId: userId,
        removedUserName:
          removal.participant.displayName ?? removal.participant.name ?? null,
        reason: reason || "Administrative action",
        alreadyRemoved: !removal.removed,
        liveKitControlApplied: true,
      },
    });

    return {
      success: true,
      roomId,
      userId,
      alreadyRemoved: !removal.removed,
    };
  },
);

const setParticipantMute = onCall(
  {
    region: REGION,
    secrets: LIVEKIT_SECRETS,
    timeoutSeconds: 30,
    enforceAppCheck: false,
  },
  async (request) => {
    const caller = await requireRoomStaff(request);

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

    await getDocumentOrThrow(
      roomReference,
      HttpsError,
      "The selected room was not found.",
    );

    const participantReference = roomReference
      .collection("participants")
      .doc(userId);
    const restrictionReference = db.collection("restrictions").doc(userId);

    const liveKitControl = resolveLiveKitControl();

    const state = await db.runTransaction(async (transaction) => {
      const [
        currentRoomSnapshot,
        participantSnapshot,
        restrictionSnapshot,
      ] = await Promise.all([
        transaction.get(roomReference),
        transaction.get(participantReference),
        transaction.get(restrictionReference),
      ]);
      if (!currentRoomSnapshot.exists) {
        throw new HttpsError(
          "not-found",
          "The selected room was not found.",
        );
      }
      if (!participantSnapshot.exists) {
        throw new HttpsError(
          "not-found",
          "The selected participant is not in this room.",
        );
      }

      transaction.update(participantReference, {
        // `isMuted` belongs to the participant's own microphone toggle.
        // Staff moderation has a separate server-only bit so the client can
        // neither clear it nor have its personal preference overwritten.
        serverMuted: muted,
        moderatedBy: caller.uid,
        moderatedAt: FieldValue.serverTimestamp(),
      });
      return {
        room: currentRoomSnapshot.data() ?? {},
        participant: participantSnapshot.data() ?? {},
        restriction: restrictionSnapshot.exists
          ? (restrictionSnapshot.data() ?? {})
          : {},
      };
    });

    const room = state.room;
    const participant = state.participant;
    const communicationMuted = communicationRestrictionIsActive(
      state.restriction,
    );

    const canPublish =
      !muted &&
      room.status === "active" &&
      room.isLive === true &&
      room.deletionInProgress !== true &&
      participant.isMuted !== true &&
      participant.hostMuted !== true &&
      !communicationMuted &&
      (room.hostId === userId || SPEAKING_ROLES.has(participant.role));

    await applyLiveKitControl({
      caller,
      roomId,
      roomName: room.name ?? null,
      operation: muted ? "muteParticipant" : "unmuteParticipant",
      affectedUserId: userId,
      action: () =>
        liveKitControl.setPublishingAllowed(roomId, userId, canPublish),
    });

    await writeRoomAuditLog({
      caller,
      action: muted ? "mute_room_participant" : "unmute_room_participant",
      roomId,
      roomName: room.name ?? null,
      details: {
        userId,
        muted,
        liveKitControlApplied: true,
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
    secrets: LIVEKIT_SECRETS,
  },
  async (request) => {
    const caller = await requireRoomDeleteAccess(request);

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
    const liveKitControl = resolveLiveKitControl();

    // Persist a tombstone state first. If LiveKit is unavailable the room
    // remains non-live and token issuance is blocked; a retry can finish the
    // remote revocation and recursive deletion.
    await roomReference.update({
      status: "deleted",
      isLive: false,
      participantCount: 0,
      moderatedBy: caller.uid,
      moderatedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    await applyLiveKitControl({
      caller,
      roomId,
      roomName: room.name ?? null,
      operation: "deleteRoom",
      action: () => liveKitControl.endRoom(roomId),
    });

    await deleteActiveVoiceSessionsForRoom(roomId);
    const mediaCleanup = await cleanupRoomMedia({
      roomId,
      bucket: resolveStorageBucket(),
    });
    if (mediaCleanup.deleted !== true) {
      throw new HttpsError(
        "unavailable",
        "Room media cleanup did not complete. Retry the deletion.",
      );
    }
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
        liveKitControlApplied: true,
      },
      entryId: `delete_room_${roomId}`,
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
  setRoomLiveKitControlForTests,
  setRoomStorageBucketForTests,
};
