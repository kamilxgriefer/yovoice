const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { FieldValue } = require("firebase-admin/firestore");
const { getStorage } = require("firebase-admin/storage");

const { ROOM_MANAGEMENT_ROLES } = require("../utils/roles");

const {
  requireActiveSuperAdmin,
  requireVerifiedStaff,
  requireProtectedOwner,
} = require("../utils/auth");

const {
  db,
  normalizeText,
  positiveInteger,
  timestampToIso,
  getDocumentOrThrow,
  deleteCollectionInBatches,
  deleteDocumentRecursively,
} = require("../utils/firestore");

const { writeClubAuditLog } = require("../utils/audit");
const {
  LIVEKIT_SECRETS,
  getProductionLiveKitControl,
} = require("../livekit/control");
const {
  deleteActiveVoiceSessionsForRoom,
} = require("../livekit/sessions");
const {
  finishClubOwnershipVoiceReset,
  revokeClubMemberVoice,
} = require("../clubs/voice");
const {
  lockOwnershipGuards,
  requireCommunityClubCapacity,
  touchOwnershipGuards,
} = require("../clubs/quota");
const {
  cleanupClubMedia,
  cleanupFamilyMedia,
  cleanupRoomMedia,
} = require("../media/cleanup");

const REGION = "europe-west1";
let clubLiveKitControlForTests = null;
let clubStorageBucketForTests = null;

function setClubLiveKitControlForTests(control) {
  clubLiveKitControlForTests = control ?? null;
}

function setClubStorageBucketForTests(bucket) {
  clubStorageBucketForTests = bucket ?? null;
}

function resolveClubStorageBucket() {
  return clubStorageBucketForTests ?? getStorage().bucket();
}

function requireMediaCleanup(outcome, message) {
  const results = Array.isArray(outcome) ? outcome : [outcome];
  if (results.some((result) => result?.deleted !== true)) {
    throw new HttpsError("unavailable", message);
  }
}

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
    await requireVerifiedStaff(
      request,
      ROOM_MANAGEMENT_ROLES,
      "Only active moderation staff can list Clubs.",
    );

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
    await requireVerifiedStaff(
      request,
      ROOM_MANAGEMENT_ROLES,
      "Only active moderation staff can inspect Clubs.",
    );

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
    secrets: LIVEKIT_SECRETS,
    timeoutSeconds: 120,
  },
  async (request) => {
    const caller = await requireVerifiedStaff(
      request,
      ROOM_MANAGEMENT_ROLES,
      "Only active moderation staff can moderate Clubs.",
    );

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

    if (suspended) {
      const liveKitControl =
        clubLiveKitControlForTests ?? getProductionLiveKitControl();
      for (const roomDocument of roomsSnapshot.docs) {
        await liveKitControl.endRoom(roomDocument.id);
        await deleteActiveVoiceSessionsForRoom(roomDocument.id);
        await deleteCollectionInBatches(
          roomDocument.ref.collection("participants"),
        );
      }
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
    secrets: LIVEKIT_SECRETS,
    timeoutSeconds: 120,
  },
  async (request) => {
    const caller = await requireVerifiedStaff(
      request,
      ROOM_MANAGEMENT_ROLES,
      "Only active moderation staff can remove Club members.",
    );

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
    const memberReference = clubReference.collection("members").doc(userId);
    const projectionReference = db
      .collection("users")
      .doc(userId)
      .collection("clubs")
      .doc(clubId);
    let club;
    let member;
    let alreadyRemoved = false;

    await db.runTransaction(async (transaction) => {
      const [clubSnapshot, memberSnapshot] = await transaction.getAll(
        clubReference,
        memberReference,
      );
      if (!clubSnapshot.exists) {
        throw new HttpsError("not-found", "The selected club was not found.");
      }
      club = clubSnapshot.data() ?? {};
      if (club.ownerId === userId) {
        throw new HttpsError(
          "failed-precondition",
          "The club owner cannot be removed from the club.",
        );
      }
      if (!memberSnapshot.exists) {
        alreadyRemoved = true;
        member = {};
        transaction.delete(projectionReference);
        return;
      }
      member = memberSnapshot.data() ?? {};
      if (member.userId !== userId) {
        throw new HttpsError(
          "failed-precondition",
          "The Club membership identity is not canonical.",
        );
      }
      if (member.role === "owner") {
        throw new HttpsError(
          "failed-precondition",
          "The club owner cannot be removed from the club.",
        );
      }
      transaction.delete(memberReference);
      transaction.delete(projectionReference);
      transaction.update(clubReference, {
        memberCount: Math.max(Number(club.memberCount ?? 0) - 1, 0),
        onlineCount: member.isOnline === true
          ? Math.max(Number(club.onlineCount ?? 0) - 1, 0)
          : Math.max(Number(club.onlineCount ?? 0), 0),
        updatedAt: FieldValue.serverTimestamp(),
      });
    });

    await revokeClubMemberVoice({
      clubId,
      userId,
      control: clubLiveKitControlForTests ?? getProductionLiveKitControl(),
    });

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
      alreadyExisted: alreadyRemoved,
      clubId,
      userId,
    };
  },
);

const setClubMemberBan = onCall(
  {
    region: REGION,
    enforceAppCheck: false,
    secrets: LIVEKIT_SECRETS,
    timeoutSeconds: 120,
  },
  async (request) => {
    const caller = await requireVerifiedStaff(
      request,
      ROOM_MANAGEMENT_ROLES,
      "Only active moderation staff can ban Club members.",
    );

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

    if (banned) {
      await revokeClubMemberVoice({
        clubId,
        userId,
        control: clubLiveKitControlForTests ?? getProductionLiveKitControl(),
      });
    }

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
    secrets: LIVEKIT_SECRETS,
    timeoutSeconds: 120,
  },
  async (request) => {
    // Ownership transfer is stronger than ordinary moderation. Check both
    // the signed claim and the live server role record so a revoked or banned
    // super admin cannot keep using a stale ID token for this operation.
    const caller = await requireActiveSuperAdmin(request);

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
    const preflightSnapshot = await getDocumentOrThrow(
      clubReference,
      HttpsError,
      "The selected club was not found.",
    );
    const preflightClub = preflightSnapshot.data() ?? {};
    if (!preflightClub.ownerId) {
      throw new HttpsError(
        "failed-precondition",
        "The Club does not have a valid current owner.",
      );
    }
    if (preflightClub.type === "family") {
      throw new HttpsError(
        "failed-precondition",
        "Family Room ownership cannot be transferred.",
      );
    }
    if (preflightClub.deletionInProgress === true) {
      throw new HttpsError(
        "failed-precondition",
        "A Club being deleted cannot transfer ownership.",
      );
    }
    if (preflightClub.ownerId === newOwnerId) {
      if (preflightClub.ownershipVoiceResetPending === true) {
        await finishClubOwnershipVoiceReset({
          clubId,
          loungeRoomId:
            preflightClub.loungeRoomId ?? `club_lounge_${clubId}`,
          newOwnerId,
          control:
            clubLiveKitControlForTests ?? getProductionLiveKitControl(),
        });
      }
      return {
        success: true,
        alreadyExisted: true,
        clubId,
        previousOwnerId:
          preflightClub.ownershipTransferredFrom ?? newOwnerId,
        newOwnerId,
      };
    }
    if (preflightClub.status !== "active") {
      throw new HttpsError(
        "failed-precondition",
        "Only an active Club can transfer ownership.",
      );
    }
    if (preflightClub.ownershipVoiceResetPending === true) {
      throw new HttpsError(
        "failed-precondition",
        "A previous ownership voice reset is still in progress.",
      );
    }

    let club;
    let newOwner;
    let alreadyExisted = false;

    await db.runTransaction(async (transaction) => {
      const guardReferences = await lockOwnershipGuards(transaction, [
        preflightClub.ownerId,
        newOwnerId,
      ]);
      const clubSnapshot = await transaction.get(clubReference);
      if (!clubSnapshot.exists) {
        throw new HttpsError("not-found", "The selected club was not found.");
      }
      club = clubSnapshot.data() ?? {};

      if (club.ownerId === newOwnerId) {
        alreadyExisted = true;
        return;
      }
      if (!club.ownerId) {
        throw new HttpsError(
          "failed-precondition",
          "The Club does not have a valid current owner.",
        );
      }
      if (
        club.ownerId !== preflightClub.ownerId ||
        club.type === "family" ||
        club.deletionInProgress === true ||
        club.status !== "active" ||
        club.ownershipVoiceResetPending === true
      ) {
        throw new HttpsError(
          "aborted",
          "Club ownership changed while the transfer was being prepared.",
        );
      }

      const currentOwnerReference = clubReference
        .collection("members")
        .doc(club.ownerId);
      const newOwnerReference = clubReference
        .collection("members")
        .doc(newOwnerId);
      const [currentOwnerSnapshot, newOwnerSnapshot] =
        await transaction.getAll(currentOwnerReference, newOwnerReference);

      if (!currentOwnerSnapshot.exists || !newOwnerSnapshot.exists) {
        throw new HttpsError(
          "failed-precondition",
          "Both owners must have canonical Club memberships.",
        );
      }
      const currentOwner = currentOwnerSnapshot.data() ?? {};
      newOwner = newOwnerSnapshot.data() ?? {};
      if (
        currentOwner.userId !== club.ownerId ||
        currentOwner.role !== "owner" ||
        newOwner.userId !== newOwnerId ||
        newOwner.role === "owner"
      ) {
        throw new HttpsError(
          "failed-precondition",
          "Club ownership memberships are not canonical.",
        );
      }
      if (newOwner.banned === true) {
        throw new HttpsError(
          "permission-denied",
          "A banned Club member cannot receive ownership.",
        );
      }

      await requireCommunityClubCapacity(transaction, newOwnerId);
      const loungeReference = db.collection("rooms").doc(
        club.loungeRoomId ?? `club_lounge_${clubId}`,
      );
      const loungeSnapshot = await transaction.get(loungeReference);

      transaction.set(
        currentOwnerReference,
        { role: "member", updatedAt: FieldValue.serverTimestamp() },
        { merge: true },
      );
      transaction.set(
        newOwnerReference,
        { role: "owner", updatedAt: FieldValue.serverTimestamp() },
        { merge: true },
      );
      transaction.set(
        db
          .collection("users")
          .doc(club.ownerId)
          .collection("clubs")
          .doc(clubId),
        {
          clubId,
          name: club.name ?? "Untitled club",
          avatarUrl: club.avatarUrl ?? null,
          role: "member",
          joinedAt:
            currentOwner.joinedAt ?? FieldValue.serverTimestamp(),
        },
      );
      transaction.set(
        db
          .collection("users")
          .doc(newOwnerId)
          .collection("clubs")
          .doc(clubId),
        {
          clubId,
          name: club.name ?? "Untitled club",
          avatarUrl: club.avatarUrl ?? null,
          role: "owner",
          joinedAt: newOwner.joinedAt ?? FieldValue.serverTimestamp(),
        },
      );
      transaction.set(
        clubReference,
        {
          ownerId: newOwnerId,
          ownerName:
            newOwner.displayName ?? newOwner.name ?? "YO Voice user",
          ownershipTransferredBy: caller.uid,
          ownershipTransferredFrom: club.ownerId,
          ownershipTransferredAt: FieldValue.serverTimestamp(),
          ownershipVoiceResetPending: true,
          ownershipVoiceResetForOwner: newOwnerId,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      if (loungeSnapshot.exists) {
        transaction.update(loungeReference, {
          hostId: newOwnerId,
          hostName:
            newOwner.displayName ?? newOwner.name ?? "YO Voice user",
          hostPhotoUrl: newOwner.photoUrl ?? null,
          isLive: false,
          participantCount: 0,
          endedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
      // Public marketing consent is owner-specific and cannot survive a
      // transfer performed by staff on the owner's behalf.
      transaction.delete(
        db.collection("clubMarketingConsents").doc(clubId),
      );
      touchOwnershipGuards(transaction, guardReferences);
    });

    if (alreadyExisted) {
      const latest = await clubReference.get();
      if (latest.data()?.ownershipVoiceResetPending === true) {
        await finishClubOwnershipVoiceReset({
          clubId,
          loungeRoomId:
            latest.data()?.loungeRoomId ?? `club_lounge_${clubId}`,
          newOwnerId,
          control:
            clubLiveKitControlForTests ?? getProductionLiveKitControl(),
        });
      }
      return {
        success: true,
        alreadyExisted: true,
        clubId,
        previousOwnerId: preflightClub.ownerId,
        newOwnerId,
      };
    }

    await finishClubOwnershipVoiceReset({
      clubId,
      loungeRoomId: club?.loungeRoomId ?? `club_lounge_${clubId}`,
      newOwnerId,
      control: clubLiveKitControlForTests ?? getProductionLiveKitControl(),
    });

    await writeClubAuditLog({
      caller,
      action: "transfer_club_ownership",
      clubId,
      clubName: club?.name ?? null,

      details: {
        previousOwnerId: club?.ownerId ?? null,

        newOwnerId,

        newOwnerName: newOwner?.displayName ?? newOwner?.name ?? null,

        reason,
      },
    });

    return {
      success: true,
      alreadyExisted: false,
      clubId,
      previousOwnerId: club?.ownerId ?? null,
      newOwnerId,
    };
  },
);

const adminDeleteClub = onCall(
  {
    region: REGION,
    enforceAppCheck: false,
    timeoutSeconds: 540,
    memory: "512MiB",
    // Permanent deletion is an OWNERSHIP capability: the uid must match
    // the protected-owner secret, not merely carry superAdmin.
    secrets: ["YOVOICE_PROTECTED_OWNER_UID", ...LIVEKIT_SECRETS],
  },
  async (request) => {
    const caller = await requireProtectedOwner(request);

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

    const preflightSnapshot = await getDocumentOrThrow(
      clubReference,
      HttpsError,
      "The selected club was not found.",
    );
    const preflightClub = preflightSnapshot.data() ?? {};
    let club;

    // Mark first and serialize with community ownership changes. Rules refuse
    // new invite acceptance once this flag is visible, so the membership
    // snapshot below is stable and every private projection can be removed
    // before the canonical root disappears.
    await db.runTransaction(async (transaction) => {
      const guardReferences =
        preflightClub.ownerId && preflightClub.type !== "family"
          ? await lockOwnershipGuards(transaction, [preflightClub.ownerId])
          : [];
      const latestSnapshot = await transaction.get(clubReference);
      if (!latestSnapshot.exists) {
        throw new HttpsError("not-found", "The selected club was not found.");
      }
      club = latestSnapshot.data() ?? {};
      if (club.ownerId !== preflightClub.ownerId) {
        throw new HttpsError(
          "aborted",
          "Club ownership changed while deletion was being prepared.",
        );
      }
      transaction.set(
        clubReference,
        {
          deletionInProgress: true,
          deletionRequestedBy: caller.uid,
          deletionRequestedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      touchOwnershipGuards(transaction, guardReferences);
    });

    const roomsSnapshot = await db
      .collection("rooms")
      .where("clubId", "==", clubId)
      .get();

    const membersSnapshot = await clubReference.collection("members").get();
    const projectionsSnapshot = await db
      .collectionGroup("clubs")
      .where("clubId", "==", clubId)
      .get();

    const liveKitControl =
      clubLiveKitControlForTests ?? getProductionLiveKitControl();
    const storageBucket = resolveClubStorageBucket();
    for (let offset = 0; offset < roomsSnapshot.docs.length; offset += 5) {
      await Promise.all(
        roomsSnapshot.docs.slice(offset, offset + 5).map(async (roomDocument) => {
          await liveKitControl.endRoom(roomDocument.id);
          requireMediaCleanup(
            await cleanupRoomMedia({
              roomId: roomDocument.id,
              bucket: storageBucket,
            }),
            "Club room media cleanup did not complete. Retry the deletion.",
          );
          await deleteDocumentRecursively(roomDocument.ref);
        }),
      );
    }

    requireMediaCleanup(
      await cleanupClubMedia({
        clubId,
        club,
        bucket: storageBucket,
      }),
      "Club media cleanup did not complete. Retry the deletion.",
    );
    if (club.type === "family") {
      requireMediaCleanup(
        await cleanupFamilyMedia({ clubId, bucket: storageBucket }),
        "Family media cleanup did not complete. Retry the deletion.",
      );
    }

    // Root deletion does not cascade to the private users/{uid}/clubs index.
    // Remove every projection BEFORE the root. If a process interruption
    // occurs, the marked Club remains retryable; there is never a point where
    // the only member list is gone but ghost projections remain.
    for (let offset = 0; offset < projectionsSnapshot.docs.length; offset += 450) {
      const batch = db.batch();
      for (const projection of projectionsSnapshot.docs.slice(
        offset,
        offset + 450,
      )) {
        batch.delete(projection.ref);
      }
      await batch.commit();
    }

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
      entryId: `delete_club_${clubId}`,
    });

    // A marketing grant is tied to this exact Club lifecycle. Delete it
    // before the canonical root so it cannot become an orphan or silently
    // reactivate if the same document id is ever recreated.
    await db.collection("clubMarketingConsents").doc(clubId).delete();
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
  setClubLiveKitControlForTests,
  setClubStorageBucketForTests,
};
