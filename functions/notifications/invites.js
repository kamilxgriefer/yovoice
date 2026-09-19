const crypto = require("node:crypto");

const {
  onDocumentCreated,
  onDocumentWritten,
} = require("firebase-functions/v2/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { logger } = require("firebase-functions/v2");
const { FieldValue, Timestamp } = require("firebase-admin/firestore");

const { requireAuthentication } = require("../utils/auth");
const { db, normalizeText } = require("../utils/firestore");
const { assertLegacyClubData, isVersionedServer } = require("../utils/server_access");
const {
  consumeRateLimit,
  rateLimitReference,
  transactionGetAll,
} = require("../integrity/guards");
const {
  createNotificationForEvent,
  restrictionIsActive,
} = require("./canonical");
const { isValidOpaqueUid } = require("../achievements/identity");
const {
  SERVER_INVITE_TTL_MS,
  SERVER_TYPES,
  serverInviteRefPath,
} = require("../servers/contract");
const { canInviteToServer } = require("../servers/authority");

const REGION = "europe-west1";
// The LEGACY Club inviter set, used only by `sendClubInvite` and the
// `onClubInviteCreated` validator, both of which refuse a versioned root.
// A V1 server's inviter policy lives in `canInviteToServer` (authority.js)
// and is wider on a publicly joinable server; widening it here instead
// would change the legacy path, which nothing asked for.
const LEGACY_CLUB_INVITER_ROLES = new Set(["owner", "coOwner", "admin", "moderator"]);
const SAFE_ID = /^[A-Za-z0-9_-]{1,128}$/u;
const SERVER_INVITE_SWEEP_LIMIT = 50;
const CLUB_INVITE_ATTEMPT_LIMITS = Object.freeze({
  minute: Object.freeze({ maxEvents: 30, windowMs: 60_000 }),
  hour: Object.freeze({ maxEvents: 200, windowMs: 60 * 60_000 }),
});

function timestampMillis(value) {
  const result = value?.toMillis?.();
  return Number.isSafeInteger(result) ? result : null;
}

function sameTimestamp(left, right) {
  const leftMillis = timestampMillis(left);
  return leftMillis !== null && leftMillis === timestampMillis(right);
}

function exactKeys(value, keys) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const actual = Object.keys(value).sort();
  const expected = [...keys].sort();
  return actual.length === expected.length &&
    actual.every((key, index) => key === expected[index]);
}

function serverInviteNotificationId(serverId, inviteeId, generation) {
  if (!SAFE_ID.test(serverId) || !Number.isSafeInteger(generation) ||
      generation < 1 || generation >= Number.MAX_SAFE_INTEGER) {
    return null;
  }
  try {
    serverInviteRefPath(inviteeId, serverId);
  } catch {
    return null;
  }
  const digest = crypto.createHash("sha256")
    .update(`server.invite.notification.v1\0${serverId}\0${inviteeId}\0${generation}`)
    .digest("hex")
    .slice(0, 40);
  return `serverInvite_${digest}`;
}

function serverInviteIdentity(invite, serverId, inviteeId) {
  if (!invite || invite.serverSchemaVersion !== 1 || invite.serverId !== serverId ||
      invite.inviteeId !== inviteeId || !SAFE_ID.test(serverId) ||
      !isValidOpaqueUid(invite.inviterId) ||
      !Number.isSafeInteger(invite.generation) || invite.generation < 1 ||
      invite.generation >= Number.MAX_SAFE_INTEGER ||
      serverInviteNotificationId(serverId, inviteeId, invite.generation) === null) {
    return null;
  }
  return {
    serverId,
    inviteeId,
    inviterId: invite.inviterId,
    generation: invite.generation,
  };
}

function canonicalPendingServerInvite(invite, serverId, inviteeId, nowMs) {
  const identity = serverInviteIdentity(invite, serverId, inviteeId);
  const expiresAtMillis = timestampMillis(invite?.expiresAt);
  const createdAtMillis = timestampMillis(invite?.createdAt);
  const updatedAtMillis = timestampMillis(invite?.updatedAt);
  if (!identity || !exactKeys(invite, [
    "serverSchemaVersion", "serverId", "inviteeId", "inviterId",
    "inviterAuthorizationRevision", "status", "generation", "expiresAt",
    "serverName", "inviterName", "createdAt", "updatedAt",
  ]) || invite.status !== "pending" ||
      !Number.isSafeInteger(invite.inviterAuthorizationRevision) ||
      invite.inviterAuthorizationRevision < 1 ||
      invite.inviterAuthorizationRevision >= Number.MAX_SAFE_INTEGER ||
      expiresAtMillis === null || expiresAtMillis <= nowMs ||
      createdAtMillis === null || updatedAtMillis === null ||
      updatedAtMillis !== createdAtMillis ||
      expiresAtMillis - createdAtMillis !== SERVER_INVITE_TTL_MS ||
      typeof invite.serverName !== "string" || invite.serverName.length < 1 ||
      invite.serverName.length > 120 || invite.serverName !== invite.serverName.trim() ||
      typeof invite.inviterName !== "string" || invite.inviterName.length < 1 ||
      invite.inviterName.length > 120 || invite.inviterName !== invite.inviterName.trim()) {
    return null;
  }
  return { ...identity, invite };
}

function canonicalServerRootForInvite(server, serverId) {
  return Boolean(server) && server.serverSchemaVersion === 1 &&
    server.templateVersion === 1 && SERVER_TYPES.includes(server.serverType) &&
    server.type === (server.serverType === "family" ? "family" : "community") &&
    server.status === "active" && server.serverActivationState === "active" &&
    server.deletionInProgress !== true && isValidOpaqueUid(server.ownerId) &&
    Number.isSafeInteger(server.revision) && server.revision > 0 &&
    server.revision < Number.MAX_SAFE_INTEGER && SAFE_ID.test(serverId);
}

function canonicalInviterMembership(member, invite, server) {
  return Boolean(member) && member.userId === invite.inviterId &&
    member.banned !== true && canInviteToServer(server, member) &&
    Number.isSafeInteger(member.authorizationRevision) &&
    member.authorizationRevision > 0 &&
    member.authorizationRevision < Number.MAX_SAFE_INTEGER &&
    member.authorizationRevision === invite.inviterAuthorizationRevision &&
    ((member.role === "owner") === (server.ownerId === invite.inviterId));
}

function canonicalFriendshipGuard(snapshot, ownerId, friendId) {
  const value = snapshot?.exists ? (snapshot.data() ?? {}) : null;
  return exactKeys(value, ["ownerId", "friendId", "schemaVersion", "establishedAt"]) &&
    value.ownerId === ownerId && value.friendId === friendId &&
    value.schemaVersion === 1 && timestampMillis(value.establishedAt) !== null;
}

function activeServerInviteParty(snapshot) {
  const value = snapshot?.exists ? (snapshot.data() ?? {}) : null;
  return Boolean(value) && value.banned !== true && value.disabled !== true &&
    value.deleted !== true && value.status !== "deleted" &&
    (value.authDeletedAt === null || value.authDeletedAt === undefined);
}

function canonicalInvitePointer(snapshot, invite) {
  const value = snapshot?.exists ? (snapshot.data() ?? {}) : null;
  return exactKeys(value, ["serverId", "generation", "expiresAt"]) &&
    value.serverId === invite.serverId && value.generation === invite.generation &&
    sameTimestamp(value.expiresAt, invite.expiresAt);
}

async function retireServerInviteNotification({
  serverId,
  inviteeId,
  generation,
  database = db,
}) {
  const notificationId = serverInviteNotificationId(serverId, inviteeId, generation);
  if (!notificationId) return "skipped:invalid-source";
  const reference = database.doc(`users/${inviteeId}/notifications/${notificationId}`);
  return database.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    if (!snapshot.exists) return "skipped:absent";
    const notification = snapshot.data() ?? {};
    if (notification.type !== "clubInvite" || notification.targetId !== serverId ||
        notification.sourceGeneration !== String(generation) ||
        notification.sourcePath !== `clubs/${serverId}/invites/${inviteeId}`) {
      return "skipped:mismatch";
    }
    transaction.delete(reference);
    return "deleted";
  });
}

function serverInvitePointerIdentity(reference, value) {
  const userReference = reference?.parent?.parent;
  const inviteeId = userReference?.parent?.id === "users" ? userReference.id : null;
  const serverId = reference?.parent?.id === "serverInviteRefs" ? reference.id : null;
  const expiresAtMillis = timestampMillis(value?.expiresAt);
  if (!isValidOpaqueUid(inviteeId) || !SAFE_ID.test(serverId ?? "") ||
      expiresAtMillis === null) {
    return null;
  }
  const canonical = exactKeys(value, ["serverId", "generation", "expiresAt"]) &&
    value.serverId === serverId && Number.isSafeInteger(value.generation) &&
    value.generation > 0 && value.generation < Number.MAX_SAFE_INTEGER &&
    serverInviteNotificationId(serverId, inviteeId, value.generation) !== null;
  return {
    inviteeId,
    serverId,
    expiresAtMillis,
    generation: canonical ? value.generation : null,
    canonical,
  };
}

async function serverInviteNotificationSourceIsCurrent({
  recipientId,
  notificationId,
  notification,
  firestore = db,
  reader = null,
  nowMs = Date.now(),
}) {
  const serverId = notification?.targetId;
  const inviterId = notification?.actorId;
  const generationText = notification?.sourceGeneration;
  const generation = Number(generationText);
  const sourcePath = `clubs/${serverId}/invites/${recipientId}`;
  if (!Number.isSafeInteger(nowMs) || nowMs < 0 ||
      !SAFE_ID.test(serverId ?? "") || !isValidOpaqueUid(recipientId) ||
      !isValidOpaqueUid(inviterId) || !Number.isSafeInteger(generation) ||
      generation < 1 || generation >= Number.MAX_SAFE_INTEGER ||
      String(generation) !== generationText ||
      notificationId !== serverInviteNotificationId(serverId, recipientId, generation) ||
      notification?.type !== "clubInvite" || notification?.sourcePath !== sourcePath ||
      notification?.dedupeKey !== notificationId) {
    return false;
  }

  const serverReference = firestore.doc(`clubs/${serverId}`);
  const inviteReference = firestore.doc(sourcePath);
  const inviterMembershipReference = serverReference.collection("members").doc(inviterId);
  const inviteeMembershipReference = serverReference.collection("members").doc(recipientId);
  const pointerReference = firestore.doc(serverInviteRefPath(recipientId, serverId));
  const forwardFriendship = firestore.doc(
    `friendshipGuards/${inviterId}/friends/${recipientId}`,
  );
  const reverseFriendship = firestore.doc(
    `friendshipGuards/${recipientId}/friends/${inviterId}`,
  );
  const inviterProfile = firestore.doc(`users/${inviterId}`);
  const inviteeProfile = firestore.doc(`users/${recipientId}`);
  const inviterRestriction = firestore.doc(`restrictions/${inviterId}`);
  const inviteeRestriction = firestore.doc(`restrictions/${recipientId}`);
  const inviterBlock = firestore.doc(`users/${inviterId}/blocked/${recipientId}`);
  const inviteeBlock = firestore.doc(`users/${recipientId}/blocked/${inviterId}`);
  const sourceReader = reader ?? firestore;
  const [serverSnapshot, inviterMembership, currentInvite, inviteeMembership,
    pointer, forwardGuard, reverseGuard, inviterProfileSnapshot,
    inviteeProfileSnapshot, inviterRestrictionSnapshot,
    inviteeRestrictionSnapshot, inviterBlockSnapshot, inviteeBlockSnapshot] =
    await sourceReader.getAll(
    serverReference,
    inviterMembershipReference,
    inviteReference,
    inviteeMembershipReference,
    pointerReference,
    forwardFriendship,
    reverseFriendship,
    inviterProfile,
    inviteeProfile,
    inviterRestriction,
    inviteeRestriction,
    inviterBlock,
    inviteeBlock,
  );
  const server = serverSnapshot.exists ? (serverSnapshot.data() ?? {}) : null;
  const invite = canonicalPendingServerInvite(
    currentInvite.exists ? (currentInvite.data() ?? {}) : null,
    serverId,
    recipientId,
    nowMs,
  );
  return Boolean(invite) && invite.generation === generation &&
    invite.inviterId === inviterId &&
    notification.targetLabel === invite.invite.serverName &&
    canonicalServerRootForInvite(server, serverId) &&
    canonicalInviterMembership(
      inviterMembership.exists ? (inviterMembership.data() ?? {}) : null,
      invite.invite,
      server,
    ) &&
    !inviteeMembership.exists &&
    canonicalInvitePointer(pointer, invite.invite) &&
    activeServerInviteParty(inviterProfileSnapshot) &&
    activeServerInviteParty(inviteeProfileSnapshot) &&
    !restrictionIsActive(inviterRestrictionSnapshot.data(), nowMs) &&
    !restrictionIsActive(inviteeRestrictionSnapshot.data(), nowMs) &&
    !inviterBlockSnapshot.exists && !inviteeBlockSnapshot.exists &&
    canonicalFriendshipGuard(forwardGuard, inviterId, recipientId) &&
    canonicalFriendshipGuard(reverseGuard, recipientId, inviterId);
}

/**
 * A V1 invitation is rewritten for every answer, revocation and re-issue.
 * The legacy on-create trigger deliberately rejects these documents, so this
 * generation-aware writer owns the V1 notification lifecycle. A generation
 * can create at most one inbox row and any transition away from that exact
 * pending generation removes only the row it created.
 */
async function handleServerInviteWritten(event, { nowMs = Date.now() } = {}) {
  if (!Number.isSafeInteger(nowMs) || nowMs < 0) {
    throw new TypeError("nowMs must be epoch milliseconds.");
  }
  const serverId = event?.params?.clubId;
  const inviteeId = event?.params?.inviteeId;
  if (!SAFE_ID.test(serverId ?? "") || !isValidOpaqueUid(inviteeId)) {
    return "skipped:invalid-path";
  }
  const before = event?.data?.before;
  const after = event?.data?.after;
  const beforeData = before?.exists ? (before.data() ?? {}) : null;
  const afterData = after?.exists ? (after.data() ?? {}) : null;
  const beforeIdentity = serverInviteIdentity(beforeData, serverId, inviteeId);
  const afterIdentity = serverInviteIdentity(afterData, serverId, inviteeId);
  const afterPending = canonicalPendingServerInvite(
    afterData,
    serverId,
    inviteeId,
    nowMs,
  );

  const retirements = [];
  if (beforeIdentity &&
      (!afterPending || afterPending.generation !== beforeIdentity.generation)) {
    retirements.push(await retireServerInviteNotification(beforeIdentity));
  }
  if (!afterPending) {
    if (afterIdentity && (!beforeIdentity ||
        beforeIdentity.generation !== afterIdentity.generation)) {
      retirements.push(await retireServerInviteNotification(afterIdentity));
    }
    const outcome = retirements.includes("deleted")
      ? "deleted"
      : "skipped:not-pending";
    logger.info("Server invite notification", { serverId, inviteeId, outcome });
    return outcome;
  }

  const beforePending = canonicalPendingServerInvite(
    beforeData,
    serverId,
    inviteeId,
    nowMs,
  );
  if (beforePending?.generation === afterPending.generation) {
    return "skipped:unchanged-generation";
  }

  const notificationId = serverInviteNotificationId(
    serverId,
    inviteeId,
    afterPending.generation,
  );
  const sourcePath = `clubs/${serverId}/invites/${inviteeId}`;
  const eventId = `${String(event?.id ?? "")}:server-invite:${afterPending.generation}`;
  const outcome = await createNotificationForEvent({
    eventId,
    recipientId: inviteeId,
    actorId: afterPending.inviterId,
    type: "clubInvite",
    notificationId,
    targetId: serverId,
    targetLabel: afterPending.invite.serverName,
    sourcePath,
    sourceGeneration: String(afterPending.generation),
    validate: (transaction) => serverInviteNotificationSourceIsCurrent({
      recipientId: inviteeId,
      notificationId,
      notification: {
        type: "clubInvite",
        actorId: afterPending.inviterId,
        targetId: serverId,
        targetLabel: afterPending.invite.serverName,
        sourcePath,
        sourceGeneration: String(afterPending.generation),
        dedupeKey: notificationId,
        bellSuppressed: false,
      },
      firestore: db,
      reader: transaction,
      nowMs,
    }),
  });
  logger.info("Server invite notification", {
    serverId,
    inviteeId,
    generation: afterPending.generation,
    outcome,
  });
  return outcome;
}

const onServerInviteWritten = onDocumentWritten(
  {
    document: "clubs/{clubId}/invites/{inviteeId}",
    region: REGION,
    retry: true,
    maxInstances: 50,
  },
  handleServerInviteWritten,
);

/**
 * Expiry does not rewrite the invitation, so no Firestore event can retract
 * its bell row or discovery pointer. This transaction deletes the expired
 * pointer and only the notification carrying the same canonical generation;
 * the invitation history remains for generation fencing and auditability.
 */
async function cleanupExpiredServerInvitePointer(reference, {
  database = db,
  now = Timestamp.now(),
} = {}) {
  const nowMs = timestampMillis(now);
  if (nowMs === null) throw new TypeError("A Firestore Timestamp is required.");
  return database.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    if (!snapshot.exists) {
      return { pointer: "absent", notification: "untouched" };
    }
    const identity = serverInvitePointerIdentity(reference, snapshot.data() ?? {});
    if (!identity || identity.expiresAtMillis > nowMs) {
      return { pointer: "current", notification: "untouched" };
    }
    let notificationReference = null;
    let notification = null;
    if (identity.canonical) {
      notificationReference = database.doc(
        `users/${identity.inviteeId}/notifications/${serverInviteNotificationId(
          identity.serverId,
          identity.inviteeId,
          identity.generation,
        )}`,
      );
      notification = await transaction.get(notificationReference);
    }
    transaction.delete(reference);
    let notificationOutcome = "untouched";
    if (notification?.exists) {
      const value = notification.data() ?? {};
      if (value.type === "clubInvite" && value.targetId === identity.serverId &&
          value.sourceGeneration === String(identity.generation) &&
          value.sourcePath ===
            `clubs/${identity.serverId}/invites/${identity.inviteeId}`) {
        transaction.delete(notificationReference);
        notificationOutcome = "deleted";
      } else {
        notificationOutcome = "mismatch";
      }
    } else if (identity.canonical) {
      notificationOutcome = "absent";
    }
    return { pointer: "deleted", notification: notificationOutcome };
  });
}

async function sweepExpiredServerInvites({
  database = db,
  now = Timestamp.now(),
  limit = SERVER_INVITE_SWEEP_LIMIT,
} = {}) {
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > SERVER_INVITE_SWEEP_LIMIT) {
    throw new TypeError(`limit must be 1-${SERVER_INVITE_SWEEP_LIMIT}.`);
  }
  const nowMs = timestampMillis(now);
  if (nowMs === null) throw new TypeError("A Firestore Timestamp is required.");
  const snapshot = await database.collectionGroup("serverInviteRefs")
    .where("expiresAt", "<=", now)
    .limit(limit)
    .get();
  let pointersDeleted = 0;
  let notificationsDeleted = 0;
  const failures = [];
  for (const document of snapshot.docs) {
    try {
      const outcome = await cleanupExpiredServerInvitePointer(document.ref, {
        database,
        now,
      });
      if (outcome.pointer === "deleted") pointersDeleted += 1;
      if (outcome.notification === "deleted") notificationsDeleted += 1;
    } catch (error) {
      failures.push({ path: document.ref.path, code: error?.code ?? "unknown" });
    }
  }
  return {
    scanned: snapshot.size,
    pointersDeleted,
    notificationsDeleted,
    failed: failures.length,
    failures,
    hasMore: snapshot.size === limit,
    nowMs,
  };
}

const sweepExpiredServerInvitesSchedule = onSchedule(
  {
    region: REGION,
    schedule: "every 15 minutes",
    timeZone: "UTC",
    maxInstances: 1,
    timeoutSeconds: 300,
    memory: "256MiB",
  },
  async () => {
    const outcome = await sweepExpiredServerInvites();
    logger.info("Expired Server invite references swept", outcome);
  },
);

async function consumeClubInviteAttempt(uid, nowMs = Date.now()) {
  const now = Timestamp.fromMillis(nowMs);
  const minuteScope = "club.invite.send.minute";
  const hourScope = "club.invite.send.hour";
  const minuteRef = rateLimitReference(db, minuteScope, uid);
  const hourRef = rateLimitReference(db, hourScope, uid);
  await db.runTransaction(async (transaction) => {
    const [minute, hour] = await transactionGetAll(
      transaction,
      minuteRef,
      hourRef,
    );
    consumeRateLimit(transaction, minute, {
      reference: minuteRef,
      scope: minuteScope,
      uid,
      nowMs,
      now,
      ...CLUB_INVITE_ATTEMPT_LIMITS.minute,
    });
    consumeRateLimit(transaction, hour, {
      reference: hourRef,
      scope: hourScope,
      uid,
      nowMs,
      now,
      ...CLUB_INVITE_ATTEMPT_LIMITS.hour,
    });
  });
}

const sendClubInvite = onCall(
  { region: REGION, enforceAppCheck: false, maxInstances: 20 },
  async (request) => {
    const auth = requireAuthentication(request);
    if (auth.token?.email_verified !== true) {
      throw new HttpsError(
        "failed-precondition",
        "Verify your email before sending invitations.",
      );
    }
    const clubId = normalizeText(request.data?.clubId, 128);
    const inviteeId = normalizeText(request.data?.inviteeId, 128);
    if (
      !SAFE_ID.test(clubId) ||
      !SAFE_ID.test(inviteeId) ||
      inviteeId === auth.uid
    ) {
      throw new HttpsError("invalid-argument", "A valid Club and invitee are required.");
    }

    // Commit the actor-wide attempt quota before any target/member graph
    // reads. Denials and deterministic invite replays must not roll the
    // throttle back and become a 12-read denial-of-wallet loop.
    await consumeClubInviteAttempt(auth.uid);

    const clubReference = db.doc(`clubs/${clubId}`);
    const inviterReference = db.doc(`users/${auth.uid}`);
    const inviteeReference = db.doc(`users/${inviteeId}`);
    const membershipReference = db.doc(`clubs/${clubId}/members/${auth.uid}`);
    const memberReference = db.doc(`clubs/${clubId}/members/${inviteeId}`);
    const inviteReference = db.doc(`clubs/${clubId}/invites/${inviteeId}`);
    const inviterRestrictionReference = db.doc(`restrictions/${auth.uid}`);
    const inviteeRestrictionReference = db.doc(`restrictions/${inviteeId}`);
    const inviterBlockReference = db.doc(`users/${auth.uid}/blocked/${inviteeId}`);
    const inviteeBlockReference = db.doc(`users/${inviteeId}/blocked/${auth.uid}`);
    const inviterFriendReference = db.doc(`users/${auth.uid}/friends/${inviteeId}`);
    const inviteeFriendReference = db.doc(`users/${inviteeId}/friends/${auth.uid}`);

    return db.runTransaction(async (transaction) => {
      const [
        club,
        inviter,
        invitee,
        membership,
        member,
        invite,
        inviterRestriction,
        inviteeRestriction,
        inviterBlock,
        inviteeBlock,
        inviterFriend,
        inviteeFriend,
      ] = await transaction.getAll(
        clubReference,
        inviterReference,
        inviteeReference,
        membershipReference,
        memberReference,
        inviteReference,
        inviterRestrictionReference,
        inviteeRestrictionReference,
        inviterBlockReference,
        inviteeBlockReference,
        inviterFriendReference,
        inviteeFriendReference,
      );
      if (!club.exists || !inviter.exists || !invitee.exists || !membership.exists) {
        throw new HttpsError("not-found", "The Club or selected account no longer exists.");
      }
      const clubData = club.data() ?? {};
      assertLegacyClubData(clubData);
      const inviterData = inviter.data() ?? {};
      const inviteeData = invitee.data() ?? {};
      if (
        clubData.status !== "active" ||
        clubData.deletionInProgress === true ||
        inviterData.banned === true ||
        inviterData.disabled === true ||
        inviteeData.banned === true ||
        inviteeData.disabled === true ||
        membership.data()?.userId !== auth.uid ||
        membership.data()?.banned === true ||
        !LEGACY_CLUB_INVITER_ROLES.has(membership.data()?.role) ||
        restrictionIsActive(inviterRestriction.data()) ||
        restrictionIsActive(inviteeRestriction.data()) ||
        inviterBlock.exists ||
        inviteeBlock.exists ||
        !inviterFriend.exists ||
        !inviteeFriend.exists
      ) {
        throw new HttpsError(
          "permission-denied",
          "This Club invitation is not permitted.",
        );
      }
      if (member.exists) {
        throw new HttpsError("already-exists", "This person is already a Club member.");
      }
      if (invite.exists) return { changed: false, clubId, inviteeId };

      transaction.create(inviteReference, {
        clubId,
        clubName: normalizeText(clubData.name, 120) || "YO Voice server",
        clubAvatarUrl:
          typeof clubData.avatarUrl === "string" ? clubData.avatarUrl : null,
        inviteeId,
        inviterId: auth.uid,
        inviterName:
          normalizeText(inviterData.displayName || inviterData.username, 80) ||
          "YO Voice user",
        status: "pending",
        createdAt: FieldValue.serverTimestamp(),
      });
      return { changed: true, clubId, inviteeId };
    });
  },
);

const onClubInviteCreated = onDocumentCreated(
  {
    document: "clubs/{clubId}/invites/{inviteeId}",
    region: REGION,
  },
  async (event) => {
    const source = event.data;
    if (!source?.exists) return;
    const invite = source.data() ?? {};
    const { clubId, inviteeId } = event.params;
    const inviterId = invite.inviterId;
    // V1 invitations have their own generation-aware on-write lifecycle.
    // Returning here also avoids recording this CloudEvent as a rejected
    // legacy delivery before that lifecycle validates the source.
    if (invite.serverSchemaVersion === 1) return;
    if (
      invite.status !== "pending" ||
      invite.inviteeId !== inviteeId ||
      typeof inviterId !== "string" ||
      !inviterId
    ) {
      logger.warn("Ignoring non-canonical Club invite", { clubId, inviteeId });
      return;
    }

    const clubReference = db.doc(`clubs/${clubId}`);
    const inviterMembership = db.doc(
      `clubs/${clubId}/members/${inviterId}`,
    );
    const clubSnapshot = await clubReference.get();
    const clubLabel = typeof clubSnapshot.data()?.name === "string"
      ? clubSnapshot.data().name.trim().slice(0, 120)
      : "YO Voice server";
    const outcome = await createNotificationForEvent({
      eventId: event.id,
      recipientId: inviteeId,
      actorId: inviterId,
      type: "clubInvite",
      notificationId: `clubInvite_${clubId}_${inviteeId}`,
      targetId: clubId,
      targetLabel: clubLabel || "YO Voice server",
      sourcePath: source.ref.path,
      validate: async (transaction) => {
        const [club, membership, currentInvite, member] =
          await transaction.getAll(
            clubReference,
            inviterMembership,
            source.ref,
            db.doc(`clubs/${clubId}/members/${inviteeId}`),
          );
        if (!club.exists || !membership.exists || !currentInvite.exists) {
          return false;
        }
        const clubData = club.data() ?? {};
        const role = membership.data()?.role;
        if (
          isVersionedServer(clubData) ||
          clubData.status !== "active" ||
          clubData.deletionInProgress === true ||
          membership.data()?.userId !== inviterId ||
          membership.data()?.banned === true ||
          !LEGACY_CLUB_INVITER_ROLES.has(role) ||
          member.exists
        ) {
          return false;
        }
        return true;
      },
    });
    logger.info("Club invite notification", { clubId, inviteeId, outcome });
  },
);

const onClubMemberCreated = onDocumentCreated(
  {
    document: "clubs/{clubId}/members/{memberId}",
    region: REGION,
  },
  async (event) => {
    const source = event.data;
    if (!source?.exists) return;
    const member = source.data() ?? {};
    const { clubId, memberId } = event.params;
    const inviterId = member.invitedBy;
    if (
      member.userId !== memberId ||
      member.role !== "member" ||
      typeof inviterId !== "string" ||
      !inviterId
    ) {
      return;
    }

    const clubReference = db.doc(`clubs/${clubId}`);
    const club = await clubReference.get();
    const label = typeof club.data()?.name === "string"
      ? club.data().name.trim().slice(0, 120)
      : "YO Voice server";
    const outcome = await createNotificationForEvent({
      eventId: event.id,
      recipientId: inviterId,
      actorId: memberId,
      type: "clubInviteAccepted",
      notificationId: `clubInviteAccepted_${clubId}_${memberId}`,
      targetId: clubId,
      targetLabel: label || "YO Voice server",
      sourcePath: source.ref.path,
      validate: async (transaction) => {
        const [canonicalClub, canonicalMember, outstandingInvite] =
          await transaction.getAll(
            clubReference,
            source.ref,
            db.doc(`clubs/${clubId}/invites/${memberId}`),
          );
        return canonicalClub.exists &&
          !isVersionedServer(canonicalClub.data()) &&
          canonicalClub.data()?.status === "active" &&
          canonicalClub.data()?.deletionInProgress !== true &&
          canonicalMember.exists &&
          canonicalMember.data()?.userId === memberId &&
          canonicalMember.data()?.invitedBy === inviterId &&
          !outstandingInvite.exists;
      },
    });
    logger.info("Club invite acceptance notification", {
      clubId,
      memberId,
      inviterId,
      outcome,
    });
  },
);

module.exports = {
  CLUB_INVITE_ATTEMPT_LIMITS,
  SERVER_INVITE_SWEEP_LIMIT,
  canonicalPendingServerInvite,
  cleanupExpiredServerInvitePointer,
  consumeClubInviteAttempt,
  handleServerInviteWritten,
  onServerInviteWritten,
  retireServerInviteNotification,
  sendClubInvite,
  serverInviteNotificationId,
  serverInviteNotificationSourceIsCurrent,
  sweepExpiredServerInvites,
  sweepExpiredServerInvitesSchedule,
  onClubInviteCreated,
  onClubMemberCreated,
};
