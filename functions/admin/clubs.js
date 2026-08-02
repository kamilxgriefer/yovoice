const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { FieldValue } = require("firebase-admin/firestore");

const { PERMANENT_DELETE_ROLES } = require("../utils/roles");

const {
  requireRole,
  requireAdminCenterAccess,
  requireRoomManager,
} = require("../utils/auth");

const {
  db,
  normalizeText,
  positiveInteger,
  timestampToIso,
  getDocumentOrThrow,
  deleteDocumentRecursively,
} = require("../utils/firestore");

const { writeClubAuditLog } = require("../utils/audit");

const REGION = "europe-west1";

function mapClub(document) {
  const data = document.data() ?? {};

  return {
    id: document.id,

    name: data.name ?? "Untitled club",
    description: data.description ?? "",
    ownerId: data.ownerId ?? "",
    ownerName: data.ownerName ?? "YoVoice user",

    imageUrl: data.imageUrl ?? null,
    bannerUrl: data.bannerUrl ?? null,

    visibility: data.visibility ?? "public",
    status: data.status ?? "active",
    category: data.category ?? "community",
    language: data.language ?? "English",

    memberCount: Number(data.memberCount ?? 0),

    roomCount: Number(data.roomCount ?? 0),

    moderationReason: data.moderationReason ?? null,

    moderatedBy: data.moderatedBy ?? null,

    moderatedAt: timestampToIso(data.moderatedAt),

    createdAt: timestampToIso(data.createdAt),

    updatedAt: timestampToIso(data.updatedAt),
  };
}

function clubMatchesSearch(club, search) {
  if (!search) {
    return true;
  }

  const searchable = [
    club.id,
    club.name,
    club.description,
    club.ownerId,
    club.ownerName,
    club.visibility,
    club.status,
    club.category,
    club.language,
  ]
    .filter(Boolean)
    .join(" ")
    .toLowerCase();

  return searchable.includes(search);
}

function mapClubMember(document) {
  const data = document.data() ?? {};

  return {
    id: document.id,
    userId: data.userId ?? document.id,

    displayName: data.displayName ?? data.name ?? "YoVoice user",

    username: data.username ?? "",

    photoUrl: data.photoUrl ?? null,

    role: data.role ?? "member",

    muted: data.muted === true,

    banned: data.banned === true,

    joinedAt: timestampToIso(data.joinedAt),

    updatedAt: timestampToIso(data.updatedAt),
  };
}

const listAdminClubs = onCall(
  {
    region: REGION,
    enforceAppCheck: false,
  },
  async (request) => {
    requireAdminCenterAccess(request);

    const limit = positiveInteger(request.data?.limit, 50, 100);

    const search = normalizeText(request.data?.search, 160).toLowerCase();

    const status = normalizeText(request.data?.status, 40);

    const cursorId = normalizeText(request.data?.cursorId, 128);

    let query = db
      .collection("clubs")
      .orderBy("updatedAt", "desc")
      .limit(limit);

    if (status) {
      query = db
        .collection("clubs")
        .where("status", "==", status)
        .orderBy("updatedAt", "desc")
        .limit(limit);
    }

    if (cursorId) {
      const cursorSnapshot = await db.collection("clubs").doc(cursorId).get();

      if (cursorSnapshot.exists) {
        query = query.startAfter(cursorSnapshot);
      }
    }

    const snapshot = await query.get();

    const clubs = snapshot.docs
      .map(mapClub)
      .filter((club) => clubMatchesSearch(club, search));

    const lastDocument =
      snapshot.docs.length > 0 ? snapshot.docs[snapshot.docs.length - 1] : null;

    return {
      clubs,

      nextCursorId:
        snapshot.docs.length === limit && lastDocument ? lastDocument.id : null,
    };
  },
);

const getAdminClub = onCall(
  {
    region: REGION,
    enforceAppCheck: false,
  },
  async (request) => {
    requireAdminCenterAccess(request);

    const clubId = normalizeText(request.data?.clubId, 128);

    if (!clubId) {
      throw new HttpsError("invalid-argument", "A club id is required.");
    }

    const clubReference = db.collection("clubs").doc(clubId);

    const clubSnapshot = await getDocumentOrThrow(
      clubReference,
      HttpsError,
      "The selected club was not found.",
    );

    const membersSnapshot = await clubReference
      .collection("members")
      .limit(250)
      .get();

    const roomsSnapshot = await db
      .collection("rooms")
      .where("clubId", "==", clubId)
      .limit(100)
      .get();

    return {
      club: mapClub(clubSnapshot),

      members: membersSnapshot.docs.map(mapClubMember),

      rooms: roomsSnapshot.docs.map((document) => {
        const data = document.data() ?? {};

        return {
          id: document.id,
          name: data.name ?? "Untitled room",
          status: data.status ?? "active",
          isLive: data.isLive === true,
          participantCount: Number(data.participantCount ?? 0),
          createdAt: timestampToIso(data.createdAt),
          updatedAt: timestampToIso(data.updatedAt),
        };
      }),
    };
  },
);

const setClubModerationStatus = onCall(
  {
    region: REGION,
    enforceAppCheck: false,
  },
  async (request) => {
    const caller = requireRoomManager(request);

    const clubId = normalizeText(request.data?.clubId, 128);

    const suspended = request.data?.suspended === true;

    const reason = normalizeText(request.data?.reason, 500);

    if (!clubId) {
      throw new HttpsError("invalid-argument", "A club id is required.");
    }

    if (suspended && !reason) {
      throw new HttpsError(
        "invalid-argument",
        "A moderation reason is required.",
      );
    }

    const clubReference = db.collection("clubs").doc(clubId);

    const clubSnapshot = await getDocumentOrThrow(
      clubReference,
      HttpsError,
      "The selected club was not found.",
    );

    const club = clubSnapshot.data() ?? {};

    await clubReference.set(
      {
        status: suspended ? "suspended" : "active",

        moderationReason: suspended ? reason : null,

        moderatedBy: caller.uid,

        moderatedAt: FieldValue.serverTimestamp(),

        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    const roomsSnapshot = await db
      .collection("rooms")
      .where("clubId", "==", clubId)
      .get();

    if (!roomsSnapshot.empty) {
      const batch = db.batch();

      for (const document of roomsSnapshot.docs) {
        batch.set(
          document.ref,
          {
            status: suspended ? "suspended" : "active",

            moderationReason: suspended ? reason : null,

            moderatedBy: caller.uid,

            moderatedAt: FieldValue.serverTimestamp(),

            isLive: suspended ? false : document.data()?.isLive === true,

            participantCount: suspended
              ? 0
              : Number(document.data()?.participantCount ?? 0),

            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      }

      await batch.commit();
    }

    await writeClubAuditLog({
      caller,

      action: suspended ? "suspend_club" : "restore_club",

      clubId,

      clubName: club.name ?? null,

      details: {
        ownerId: club.ownerId ?? null,

        previousStatus: club.status ?? null,

        newStatus: suspended ? "suspended" : "active",

        reason: suspended ? reason : null,

        affectedRooms: roomsSnapshot.size,
      },
    });

    return {
      success: true,
      clubId,
      status: suspended ? "suspended" : "active",
      affectedRooms: roomsSnapshot.size,
    };
  },
);

const removeClubMember = onCall(
  {
    region: REGION,
    enforceAppCheck: false,
  },
  async (request) => {
    const caller = requireRoomManager(request);

    const clubId = normalizeText(request.data?.clubId, 128);

    const userId = normalizeText(request.data?.userId, 128);

    const reason = normalizeText(request.data?.reason, 500);

    if (!clubId || !userId) {
      throw new HttpsError(
        "invalid-argument",
        "Both clubId and userId are required.",
      );
    }

    const clubReference = db.collection("clubs").doc(clubId);

    const clubSnapshot = await getDocumentOrThrow(
      clubReference,
      HttpsError,
      "The selected club was not found.",
    );

    const club = clubSnapshot.data() ?? {};

    if (club.ownerId === userId) {
      throw new HttpsError(
        "failed-precondition",
        "The club owner cannot be removed from the club.",
      );
    }

    const memberReference = clubReference.collection("members").doc(userId);

    const memberSnapshot = await getDocumentOrThrow(
      memberReference,
      HttpsError,
      "The selected user is not a member of this club.",
    );

    const member = memberSnapshot.data() ?? {};

    const batch = db.batch();

    batch.delete(memberReference);

    batch.set(
      clubReference,
      {
        memberCount: FieldValue.increment(-1),

        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    await batch.commit();

    await writeClubAuditLog({
      caller,
      action: "remove_club_member",
      clubId,
      clubName: club.name ?? null,

      details: {
        removedUserId: userId,

        removedUserName: member.displayName ?? member.name ?? null,

        reason: reason || "Administrative action",
      },
    });

    return {
      success: true,
      clubId,
      userId,
    };
  },
);

const setClubMemberBan = onCall(
  {
    region: REGION,
    enforceAppCheck: false,
  },
  async (request) => {
    const caller = requireRoomManager(request);

    const clubId = normalizeText(request.data?.clubId, 128);

    const userId = normalizeText(request.data?.userId, 128);

    const banned = request.data?.banned === true;

    const reason = normalizeText(request.data?.reason, 500);

    if (!clubId || !userId) {
      throw new HttpsError(
        "invalid-argument",
        "Both clubId and userId are required.",
      );
    }

    const clubReference = db.collection("clubs").doc(clubId);

    const clubSnapshot = await getDocumentOrThrow(
      clubReference,
      HttpsError,
      "The selected club was not found.",
    );

    const club = clubSnapshot.data() ?? {};

    if (club.ownerId === userId) {
      throw new HttpsError(
        "failed-precondition",
        "The club owner cannot be banned from their own club.",
      );
    }

    const memberReference = clubReference.collection("members").doc(userId);

    await getDocumentOrThrow(
      memberReference,
      HttpsError,
      "The selected user is not a member of this club.",
    );

    await memberReference.set(
      {
        banned,

        banReason: banned ? reason || "Administrative action" : null,

        bannedBy: banned ? caller.uid : null,

        bannedAt: banned ? FieldValue.serverTimestamp() : null,

        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    await writeClubAuditLog({
      caller,

      action: banned ? "ban_club_member" : "unban_club_member",

      clubId,

      clubName: club.name ?? null,

      details: {
        userId,
        banned,

        reason: banned ? reason || "Administrative action" : null,
      },
    });

    return {
      success: true,
      clubId,
      userId,
      banned,
    };
  },
);

const transferClubOwnership = onCall(
  {
    region: REGION,
    enforceAppCheck: false,
  },
  async (request) => {
    const caller = requireRole(
      request,
      PERMANENT_DELETE_ROLES,
      "Only an administrator can transfer club ownership.",
    );

    const clubId = normalizeText(request.data?.clubId, 128);

    const newOwnerId = normalizeText(request.data?.newOwnerId, 128);

    const reason = normalizeText(request.data?.reason, 500);

    if (!clubId || !newOwnerId) {
      throw new HttpsError(
        "invalid-argument",
        "Both clubId and newOwnerId are required.",
      );
    }

    if (!reason) {
      throw new HttpsError(
        "invalid-argument",
        "A transfer reason is required.",
      );
    }

    const clubReference = db.collection("clubs").doc(clubId);

    const clubSnapshot = await getDocumentOrThrow(
      clubReference,
      HttpsError,
      "The selected club was not found.",
    );

    const club = clubSnapshot.data() ?? {};

    if (club.ownerId === newOwnerId) {
      throw new HttpsError(
        "failed-precondition",
        "The selected user is already the club owner.",
      );
    }

    const newOwnerReference = clubReference
      .collection("members")
      .doc(newOwnerId);

    const newOwnerSnapshot = await getDocumentOrThrow(
      newOwnerReference,
      HttpsError,
      "The new owner must already be a member of the club.",
    );

    const newOwner = newOwnerSnapshot.data() ?? {};

    const batch = db.batch();

    if (club.ownerId) {
      batch.set(
        clubReference.collection("members").doc(club.ownerId),
        {
          role: "member",
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }

    batch.set(
      newOwnerReference,
      {
        role: "owner",
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    batch.set(
      clubReference,
      {
        ownerId: newOwnerId,

        ownerName: newOwner.displayName ?? newOwner.name ?? "YoVoice user",

        ownershipTransferredBy: caller.uid,

        ownershipTransferredAt: FieldValue.serverTimestamp(),

        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    await batch.commit();

    await writeClubAuditLog({
      caller,
      action: "transfer_club_ownership",
      clubId,
      clubName: club.name ?? null,

      details: {
        previousOwnerId: club.ownerId ?? null,

        newOwnerId,

        newOwnerName: newOwner.displayName ?? newOwner.name ?? null,

        reason,
      },
    });

    return {
      success: true,
      clubId,
      previousOwnerId: club.ownerId ?? null,
      newOwnerId,
    };
  },
);

const adminDeleteClub = onCall(
  {
    region: REGION,
    enforceAppCheck: false,
    timeoutSeconds: 180,
    memory: "512MiB",
  },
  async (request) => {
    const caller = requireRole(
      request,
      PERMANENT_DELETE_ROLES,
      "Only an administrator can permanently delete clubs.",
    );

    const clubId = normalizeText(request.data?.clubId, 128);

    const reason = normalizeText(request.data?.reason, 500);

    const confirmation = normalizeText(request.data?.confirmation, 128);

    if (!clubId) {
      throw new HttpsError("invalid-argument", "A club id is required.");
    }

    if (!reason) {
      throw new HttpsError(
        "invalid-argument",
        "A deletion reason is required.",
      );
    }

    if (confirmation !== clubId) {
      throw new HttpsError(
        "failed-precondition",
        "Confirm permanent deletion by providing the exact club id.",
      );
    }

    const clubReference = db.collection("clubs").doc(clubId);

    const clubSnapshot = await getDocumentOrThrow(
      clubReference,
      HttpsError,
      "The selected club was not found.",
    );

    const club = clubSnapshot.data() ?? {};

    const roomsSnapshot = await db
      .collection("rooms")
      .where("clubId", "==", clubId)
      .get();

    await writeClubAuditLog({
      caller,
      action: "delete_club",
      clubId,
      clubName: club.name ?? null,

      details: {
        ownerId: club.ownerId ?? null,

        ownerName: club.ownerName ?? null,

        reason,

        memberCount: Number(club.memberCount ?? 0),

        roomCount: roomsSnapshot.size,
      },
    });

    for (const roomDocument of roomsSnapshot.docs) {
      await deleteDocumentRecursively(roomDocument.ref);
    }

    await deleteDocumentRecursively(clubReference);

    return {
      success: true,
      clubId,
      deletedRooms: roomsSnapshot.size,

      message: "The club and its associated rooms were permanently deleted.",
    };
  },
);

module.exports = {
  listAdminClubs,
  getAdminClub,
  setClubModerationStatus,
  removeClubMember,
  setClubMemberBan,
  transferClubOwnership,
  adminDeleteClub,
};
