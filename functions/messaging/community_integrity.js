const {
  activeProfile,
  assertLedgerReplay,
  assertNotRestricted,
  consumeRateLimit,
  digest,
  fail,
  ledgerData,
  normalizeText,
  operationIdentity,
  rateLimitReference,
  requireActor,
  requireExactInput,
  requireId,
  requireRequestId,
  timestampMillis,
  transactionGetAll,
} = require("../integrity/guards");

const DEFAULT_COMMUNITY_LIMITS = Object.freeze({
  roomAttempt: Object.freeze({ maxEvents: 120, windowMs: 60_000 }),
  roomScope: Object.freeze({ maxEvents: 20, windowMs: 10_000 }),
  clubAttempt: Object.freeze({ maxEvents: 120, windowMs: 60_000 }),
  clubScope: Object.freeze({ maxEvents: 20, windowMs: 10_000 }),
});

const ROOM_MEMBER_ROLES = new Set(["owner", "member"]);
const ROOM_PARTICIPANT_ROLES = new Set([
  "host",
  "speaker",
  "listener",
  "moderator",
]);
const CLUB_WRITER_ROLES = new Set([
  "owner",
  "coOwner",
  "admin",
  "moderator",
  "member",
]);
const CLUB_ANNOUNCEMENT_WRITER_ROLES = new Set([
  "owner",
  "coOwner",
  "admin",
  "moderator",
]);
const CLUB_CHANNEL_TYPES = new Set(["chat", "announcement"]);

function exactCanonicalMembership(snapshot, uid, roles) {
  if (!snapshot?.exists) return null;
  const data = snapshot.data() ?? {};
  if (
    data.userId !== uid ||
    data.banned === true ||
    !roles.has(data.role)
  ) {
    return null;
  }
  return data;
}

function canonicalDisplayName(profile) {
  const name = profile?.displayName;
  if (typeof name !== "string" || name.trim().length < 1 || name.length > 120) {
    fail("failed-precondition", "Your canonical display name is unavailable.");
  }
  return name;
}

function activeRoot(snapshot, label, { allowMissingStatus = false } = {}) {
  if (!snapshot?.exists) fail("not-found", `${label} does not exist.`);
  const data = snapshot.data() ?? {};
  if (
    String(allowMissingStatus ? (data.status ?? "active") : data.status) !==
      "active" ||
    data.deletionInProgress === true
  ) {
    fail("failed-precondition", `${label} is not active.`);
  }
  return data;
}

function timeFrom(clock, Timestamp) {
  const nowMs = clock();
  if (!Number.isSafeInteger(nowMs) || nowMs < 0) {
    throw new TypeError("clock must return epoch milliseconds.");
  }
  return { nowMs, now: Timestamp.fromMillis(nowMs) };
}

function createCommunityMessagingService({
  db,
  Timestamp,
  clock = () => Date.now(),
  limits = DEFAULT_COMMUNITY_LIMITS,
} = {}) {
  if (!db || !Timestamp?.fromMillis) {
    throw new TypeError("db and Timestamp are required.");
  }

  function ledgerReference(identity) {
    return db.doc(`integrityOperationLedgers/${identity.id}`);
  }

  function rateReference(scope, uid) {
    return rateLimitReference(db, scope, uid);
  }

  function consume(transaction, snapshot, reference, configName, scope, uid, timing) {
    const config = limits[configName];
    if (!config) throw new TypeError(`Missing ${configName} rate limit.`);
    consumeRateLimit(transaction, snapshot, {
      reference,
      scope,
      uid,
      ...timing,
      ...config,
    });
  }

  // Invalid room/channel identifiers and denied memberships are still paid
  // Firestore reads. A quota written in the same transaction as those reads
  // rolls back with the denial and therefore protects nothing. Charge a
  // target-independent attempt bucket first, in its own committed
  // transaction. A completed operation ledger short-circuits without a
  // second charge, preserving cheap idempotent retries.
  async function consumeAttempt({ auth, configName, identity, kind, scope, timing }) {
    const ledgerRef = ledgerReference(identity);
    const attemptRef = rateReference(scope, auth.uid);
    return db.runTransaction(async (transaction) => {
      const [ledger, attempt] = await transactionGetAll(
        transaction,
        ledgerRef,
        attemptRef,
      );
      const replay = assertLedgerReplay(ledger, {
        kind,
        uid: auth.uid,
        inputHash: identity.inputHash,
      });
      if (replay) return replay;
      consume(
        transaction,
        attempt,
        attemptRef,
        configName,
        scope,
        auth.uid,
        timing,
      );
      return null;
    });
  }

  async function sendRoomMessage(request) {
    const auth = requireActor(request);
    const data = requireExactInput(
      request.data,
      ["requestId", "roomId", "text"],
      ["requestId", "roomId", "text"],
    );
    const roomId = requireId(data.roomId, "roomId");
    const requestId = requireRequestId(data.requestId);
    const text = normalizeText(data.text, 500, "text");
    const input = { roomId, text };
    const identity = operationIdentity("room.message.send", auth.uid, requestId, input);
    const messageId = `rm_${digest(
      "room-message",
      roomId,
      auth.uid,
      requestId,
    ).slice(0, 40)}`;
    const timing = timeFrom(clock, Timestamp);

    const preflightReplay = await consumeAttempt({
      auth,
      configName: "roomAttempt",
      identity,
      kind: "room.message.send",
      scope: "room.message.send.attempt",
      timing,
    });
    if (preflightReplay) return preflightReplay;

    return db.runTransaction(async (transaction) => {
      const roomRef = db.doc(`rooms/${roomId}`);
      const participantRef = roomRef.collection("participants").doc(auth.uid);
      const roomMemberRef = roomRef.collection("roomMembers").doc(auth.uid);
      const profileRef = db.doc(`users/${auth.uid}`);
      const restrictionRef = db.doc(`restrictions/${auth.uid}`);
      const ledgerRef = ledgerReference(identity);
      const scopeName = `room.message.send.${roomId}`;
      const scopeRateRef = rateReference(scopeName, auth.uid);
      const cooldownRef = db.doc(
        `privateRoomMessageCooldowns/${digest("room-cooldown", roomId, auth.uid)}`,
      );
      const messageRef = roomRef.collection("messages").doc(messageId);
      const [
        ledger,
        scopeRate,
        roomSnapshot,
        participantSnapshot,
        roomMemberSnapshot,
        profileSnapshot,
        restrictionSnapshot,
        cooldownSnapshot,
        existingMessage,
      ] = await transactionGetAll(
        transaction,
        ledgerRef,
        scopeRateRef,
        roomRef,
        participantRef,
        roomMemberRef,
        profileRef,
        restrictionRef,
        cooldownRef,
        messageRef,
      );

      const replay = assertLedgerReplay(ledger, {
        kind: "room.message.send",
        uid: auth.uid,
        inputHash: identity.inputHash,
      });
      if (replay) return replay;

      const room = activeRoot(roomSnapshot, "The room", {
        allowMissingStatus: true,
      });
      const profile = activeProfile(profileSnapshot, "Your");
      assertNotRestricted(restrictionSnapshot, "Your", timing.nowMs);
      const participant = exactCanonicalMembership(
        participantSnapshot,
        auth.uid,
        ROOM_PARTICIPANT_ROLES,
      );
      const roomMember = exactCanonicalMembership(
        roomMemberSnapshot,
        auth.uid,
        ROOM_MEMBER_ROLES,
      );
      const isHost = room.hostId === auth.uid;
      const clubId = typeof room.clubId === "string" ? room.clubId : "";

      let activeClubMember = true;
      if (clubId) {
        requireId(clubId, "room clubId");
        const [clubSnapshot, clubMemberSnapshot] = await transactionGetAll(
          transaction,
          db.doc(`clubs/${clubId}`),
          db.doc(`clubs/${clubId}/members/${auth.uid}`),
        );
        const club = activeRoot(clubSnapshot, "The Club");
        activeClubMember = Boolean(
          club && exactCanonicalMembership(
            clubMemberSnapshot,
            auth.uid,
            CLUB_WRITER_ROLES,
          ),
        );
      }

      const participantMayEnter = Boolean(participant) && (
        room.visibility === "public" ||
        isHost ||
        clubId.length > 0 ||
        participant.admittedBy === room.hostId
      );
      if (
        (!isHost && !roomMember && !participantMayEnter) ||
        (clubId && !activeClubMember)
      ) {
        fail("permission-denied", "You cannot post in this room.");
      }
      if (existingMessage.exists) {
        fail("data-loss", "A room message exists without its operation ledger.");
      }

      const slowModeSeconds = Number(room.slowModeSeconds ?? 0);
      if (
        !Number.isSafeInteger(slowModeSeconds) ||
        slowModeSeconds < 0 ||
        slowModeSeconds > 3600
      ) {
        fail("data-loss", "The room slow-mode setting is invalid.");
      }
      if (!isHost && slowModeSeconds > 0 && cooldownSnapshot.exists) {
        const cooldown = cooldownSnapshot.data() ?? {};
        const lastMessageAt = timestampMillis(cooldown.lastMessageAt);
        if (
          cooldown.ownerId !== auth.uid ||
          cooldown.roomId !== roomId ||
          lastMessageAt === null
        ) {
          fail("data-loss", "The room slow-mode state is invalid.");
        }
        if (timing.nowMs - lastMessageAt < slowModeSeconds * 1000) {
          fail("resource-exhausted", "Room slow mode is active. Try again shortly.");
        }
      }

      consume(
        transaction,
        scopeRate,
        scopeRateRef,
        "roomScope",
        scopeName,
        auth.uid,
        timing,
      );
      transaction.create(messageRef, {
        senderId: auth.uid,
        senderName: canonicalDisplayName(profile),
        senderPhotoUrl: null,
        text,
        createdAt: timing.now,
        reactions: {},
      });
      transaction.set(cooldownRef, {
        schemaVersion: 1,
        ownerId: auth.uid,
        roomId,
        messageId,
        lastMessageAt: timing.now,
      });
      transaction.update(roomRef, { updatedAt: timing.now });
      const result = { messageId, roomId };
      transaction.create(ledgerRef, ledgerData({
        kind: "room.message.send",
        uid: auth.uid,
        requestId,
        inputHash: identity.inputHash,
        result,
        now: timing.now,
      }));
      return result;
    });
  }

  async function sendClubMessage(request) {
    const auth = requireActor(request);
    const data = requireExactInput(
      request.data,
      ["channelId", "clubId", "requestId", "text"],
      ["channelId", "clubId", "requestId", "text"],
    );
    const clubId = requireId(data.clubId, "clubId");
    const channelId = requireId(data.channelId, "channelId");
    const requestId = requireRequestId(data.requestId);
    const text = normalizeText(data.text, 2000, "text");
    const input = { channelId, clubId, text };
    const identity = operationIdentity("club.message.send", auth.uid, requestId, input);
    const messageId = `cm_${digest(
      "club-message",
      clubId,
      channelId,
      auth.uid,
      requestId,
    ).slice(0, 40)}`;
    const timing = timeFrom(clock, Timestamp);

    const preflightReplay = await consumeAttempt({
      auth,
      configName: "clubAttempt",
      identity,
      kind: "club.message.send",
      scope: "club.message.send.attempt",
      timing,
    });
    if (preflightReplay) return preflightReplay;

    return db.runTransaction(async (transaction) => {
      const clubRef = db.doc(`clubs/${clubId}`);
      const memberRef = clubRef.collection("members").doc(auth.uid);
      const channelRef = clubRef.collection("channels").doc(channelId);
      const messageRef = channelRef.collection("messages").doc(messageId);
      const profileRef = db.doc(`users/${auth.uid}`);
      const restrictionRef = db.doc(`restrictions/${auth.uid}`);
      const ledgerRef = ledgerReference(identity);
      const scopeName = `club.message.send.${clubId}.${channelId}`;
      const scopeRateRef = rateReference(scopeName, auth.uid);
      const [
        ledger,
        scopeRate,
        clubSnapshot,
        memberSnapshot,
        channelSnapshot,
        profileSnapshot,
        restrictionSnapshot,
        existingMessage,
      ] = await transactionGetAll(
        transaction,
        ledgerRef,
        scopeRateRef,
        clubRef,
        memberRef,
        channelRef,
        profileRef,
        restrictionRef,
        messageRef,
      );

      const replay = assertLedgerReplay(ledger, {
        kind: "club.message.send",
        uid: auth.uid,
        inputHash: identity.inputHash,
      });
      if (replay) return replay;

      activeRoot(clubSnapshot, "The Club");
      if (!channelSnapshot.exists) {
        fail("not-found", "The Club channel does not exist.");
      }
      const channel = channelSnapshot.data() ?? {};
      if (!CLUB_CHANNEL_TYPES.has(channel.type)) {
        fail("failed-precondition", "This Club channel does not accept text messages.");
      }
      const allowedRoles = channel.type === "announcement"
        ? CLUB_ANNOUNCEMENT_WRITER_ROLES
        : CLUB_WRITER_ROLES;
      const member = exactCanonicalMembership(
        memberSnapshot,
        auth.uid,
        allowedRoles,
      );
      if (!member) {
        fail("permission-denied", "Your Club role cannot send to this channel.");
      }
      const profile = activeProfile(profileSnapshot, "Your");
      assertNotRestricted(restrictionSnapshot, "Your", timing.nowMs);
      if (existingMessage.exists) {
        fail("data-loss", "A Club message exists without its operation ledger.");
      }

      consume(
        transaction,
        scopeRate,
        scopeRateRef,
        "clubScope",
        scopeName,
        auth.uid,
        timing,
      );
      transaction.create(messageRef, {
        clubId,
        channelId,
        senderId: auth.uid,
        senderName: canonicalDisplayName(profile),
        senderPhotoUrl: null,
        content: text,
        sentAt: timing.now,
        editedAt: null,
        isDeleted: false,
      });
      const result = { channelId, clubId, messageId };
      transaction.create(ledgerRef, ledgerData({
        kind: "club.message.send",
        uid: auth.uid,
        requestId,
        inputHash: identity.inputHash,
        result,
        now: timing.now,
      }));
      return result;
    });
  }

  return Object.freeze({ sendClubMessage, sendRoomMessage });
}

module.exports = {
  DEFAULT_COMMUNITY_LIMITS,
  createCommunityMessagingService,
};
