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
  requireBoolean,
  requireExactInput,
  requireId,
  requireRequestId,
  requireSafeInteger,
  timestampMillis,
  transactionGetAll,
} = require("../integrity/guards");

const DEFAULT_ROOM_CREATION_POLICY = Object.freeze({
  maxActiveRooms: 20,
  maxEvents: 6,
  startCooldownMs: 60_000,
  startMaxEvents: 12,
  startWindowMs: 10 * 60_000,
  windowMs: 10 * 60_000,
});

const START_INPUT_FIELDS = Object.freeze([
  "requestId",
  "roomId",
  "sessionId",
]);

const ROOM_CATEGORIES = new Set([
  "business",
  "chill",
  "gaming",
  "music",
  "study",
  "talk",
]);
const ROOM_VISIBILITIES = new Set(["private", "public"]);
const ROOM_TYPES = new Set(["community", "temporary"]);
const ROOM_EXPERIENCES = new Set(["broadcast", "community"]);
const TARGET_AUDIENCES = new Set([
  "enthusiasts",
  "everyone",
  "newcomers",
  "professionals",
]);
const CONVERSATION_STYLES = new Set([
  "casual",
  "focused",
  "networking",
  "supportive",
]);
const SHOW_FORMATS = new Set([
  "interview",
  "openDiscussion",
  "panel",
  "qAndA",
  "solo",
]);

const CREATE_INPUT_FIELDS = Object.freeze([
  "audienceCanSpeak",
  "category",
  "conversationStyle",
  "description",
  "experience",
  "handRaisingEnabled",
  "language",
  "maxParticipants",
  "name",
  "newcomerFriendly",
  "requestId",
  "roomGuidelines",
  "roomType",
  "showFormat",
  "targetAudience",
  "topic",
  "topicTags",
  "visibility",
]);

function timeFrom(clock, Timestamp) {
  const nowMs = clock();
  if (!Number.isSafeInteger(nowMs) || nowMs < 0) {
    throw new TypeError("clock must return epoch milliseconds.");
  }
  return { nowMs, now: Timestamp.fromMillis(nowMs) };
}

function requireEnum(value, allowed, label) {
  if (typeof value !== "string" || !allowed.has(value)) {
    fail("invalid-argument", `${label} is invalid.`);
  }
  return value;
}

function requireNullableEnum(value, allowed, label) {
  if (value === null) return null;
  return requireEnum(value, allowed, label);
}

function normalizedTags(value) {
  if (!Array.isArray(value) || value.length > 3) {
    fail("invalid-argument", "topicTags must contain at most 3 tags.");
  }
  const seen = new Set();
  return value.map((candidate) => {
    const tag = normalizeText(candidate, 24, "topic tag");
    const folded = tag.toLocaleLowerCase("en-US");
    if (seen.has(folded)) {
      fail("invalid-argument", "topicTags must not contain duplicates.");
    }
    seen.add(folded);
    return tag;
  });
}

function validatedCreationInput(data) {
  const exact = requireExactInput(
    data,
    CREATE_INPUT_FIELDS,
    CREATE_INPUT_FIELDS,
  );
  const requestId = requireRequestId(exact.requestId);
  const name = normalizeText(exact.name, 100, "name");
  if (name.length < 3) {
    fail("invalid-argument", "name must contain 3-100 characters.");
  }
  const description = normalizeText(
    exact.description,
    1000,
    "description",
    { allowEmpty: true },
  );
  const category = requireEnum(exact.category, ROOM_CATEGORIES, "category");
  const visibility = requireEnum(
    exact.visibility,
    ROOM_VISIBILITIES,
    "visibility",
  );
  const language = normalizeText(exact.language, 64, "language");
  const maxParticipants = exact.maxParticipants === null
    ? null
    : requireSafeInteger(exact.maxParticipants, "maxParticipants", {
      min: 2,
      max: 500,
    });
  const roomType = requireEnum(exact.roomType, ROOM_TYPES, "roomType");
  const experience = requireEnum(
    exact.experience,
    ROOM_EXPERIENCES,
    "experience",
  );
  const targetAudience = requireEnum(
    exact.targetAudience,
    TARGET_AUDIENCES,
    "targetAudience",
  );
  const topicTags = normalizedTags(exact.topicTags);
  const roomGuidelines = normalizeText(
    exact.roomGuidelines,
    280,
    "roomGuidelines",
    { allowEmpty: true },
  );
  const conversationStyle = requireNullableEnum(
    exact.conversationStyle,
    CONVERSATION_STYLES,
    "conversationStyle",
  );
  const newcomerFriendly = requireBoolean(
    exact.newcomerFriendly,
    "newcomerFriendly",
  );
  const showFormat = requireNullableEnum(
    exact.showFormat,
    SHOW_FORMATS,
    "showFormat",
  );
  const audienceCanSpeak = requireBoolean(
    exact.audienceCanSpeak,
    "audienceCanSpeak",
  );
  const handRaisingEnabled = requireBoolean(
    exact.handRaisingEnabled,
    "handRaisingEnabled",
  );

  let topic;
  if (experience === "broadcast") {
    topic = normalizeText(exact.topic, 120, "topic");
    if (topic.length < 3 || roomType !== "temporary" ||
        conversationStyle !== null || newcomerFriendly ||
        showFormat === null || audienceCanSpeak) {
      fail("invalid-argument", "The Broadcast room contract is invalid.");
    }
  } else {
    topic = normalizeText(exact.topic, 120, "topic", { allowEmpty: true });
    if (topic !== "" || showFormat !== null || handRaisingEnabled ||
        !audienceCanSpeak) {
      fail("invalid-argument", "The Community room contract is invalid.");
    }
  }

  return Object.freeze({
    audienceCanSpeak,
    category,
    conversationStyle,
    description,
    experience,
    handRaisingEnabled,
    language,
    maxParticipants,
    name,
    newcomerFriendly,
    requestId,
    roomGuidelines,
    roomType,
    showFormat,
    targetAudience,
    topic,
    topicTags,
    visibility,
  });
}

function canonicalRoomId(uid, requestId) {
  return `r_${digest("room-create", uid, requestId).slice(0, 40)}`;
}

function canonicalDisplayName(profile) {
  const name = profile?.displayName;
  if (
    typeof name !== "string" ||
    name !== name.trim() ||
    name.length < 1 ||
    name.length > 120
  ) {
    fail("failed-precondition", "Your canonical display name is unavailable.");
  }
  return name;
}

function validatePolicy(policy) {
  if (!policy || typeof policy !== "object" || Array.isArray(policy)) {
    throw new TypeError("A room-creation policy is required.");
  }
  requireSafeInteger(policy.maxActiveRooms, "maxActiveRooms", {
    min: 1,
    max: 100,
  });
  requireSafeInteger(policy.maxEvents, "maxEvents", { min: 1, max: 100 });
  requireSafeInteger(policy.startCooldownMs, "startCooldownMs", {
    min: 1000,
    max: 24 * 60 * 60_000,
  });
  requireSafeInteger(policy.startMaxEvents, "startMaxEvents", {
    min: 1,
    max: 100,
  });
  requireSafeInteger(policy.startWindowMs, "startWindowMs", { min: 1000 });
  requireSafeInteger(policy.windowMs, "windowMs", { min: 1000 });
  return Object.freeze({ ...policy });
}

function validatedGuardRoomIds(snapshot, uid, maxActiveRooms) {
  if (!snapshot?.exists) return null;
  const data = snapshot.data() ?? {};
  const ids = data.activeRoomIds;
  if (
    ![1, 2].includes(data.schemaVersion) ||
    data.ownerId !== uid ||
    !Array.isArray(ids) ||
    ids.length > maxActiveRooms ||
    new Set(ids).size !== ids.length ||
    ids.some((id) =>
      typeof id !== "string" || !/^[A-Za-z0-9_-]{1,160}$/u.test(id))
  ) {
    fail("data-loss", "The room-capacity guard is malformed.");
  }
  if (
    data.schemaVersion === 2 &&
    typeof data.capacityLocked !== "boolean"
  ) {
    fail("data-loss", "The room-capacity guard is malformed.");
  }
  return {
    activeRoomIds: ids,
    capacityLocked: data.schemaVersion === 2 && data.capacityLocked === true,
  };
}

function isActiveOrdinaryRoom(snapshot, uid) {
  if (!snapshot?.exists) return false;
  const room = snapshot.data() ?? {};
  return room.hostId === uid &&
    room.status === "active" &&
    !room.clubId &&
    room.roomKind !== "clubLounge" &&
    ROOM_TYPES.has(room.roomType);
}

function boundedLegacyRoomQuery(db, uid, maxActiveRooms) {
  return db.collection("rooms")
    .where("hostId", "==", uid)
    .where("status", "==", "active")
    .limit(maxActiveRooms + 1);
}

function roomDocument(input, uid, hostName, now) {
  const communityMembership = input.roomType === "community";
  const broadcast = input.experience === "broadcast";
  return {
    hostId: uid,
    hostName,
    hostPhotoUrl: null,
    name: input.name,
    description: input.description,
    category: input.category,
    visibility: input.visibility,
    language: input.language,
    maxParticipants: input.maxParticipants,
    participantCount: communityMembership ? 0 : 1,
    memberCount: communityMembership ? 1 : 0,
    isLive: !communityMembership,
    roomType: input.roomType,
    status: "active",
    imageUrl: null,
    targetAudience: input.targetAudience,
    topicTags: input.topicTags,
    roomGuidelines: input.roomGuidelines,
    ...(input.conversationStyle === null
      ? {}
      : { conversationStyle: input.conversationStyle }),
    ...(input.newcomerFriendly ? { newcomerFriendly: true } : {}),
    ...(input.showFormat === null ? {} : { showFormat: input.showFormat }),
    experience: input.experience,
    topic: input.topic,
    audienceCanSpeak: input.audienceCanSpeak,
    handRaisingEnabled: input.handRaisingEnabled,
    stageLimit: broadcast ? 8 : null,
    approvalRequired: false,
    slowModeSeconds: 0,
    autoMuteNewUsers: broadcast,
    membersCanStartVoice: false,
    createdAt: now,
    updatedAt: now,
  };
}

function validatedStartInput(data) {
  const exact = requireExactInput(
    data,
    START_INPUT_FIELDS,
    START_INPUT_FIELDS,
  );
  return Object.freeze({
    requestId: requireRequestId(exact.requestId),
    roomId: requireId(exact.roomId, "roomId"),
    sessionId: requireRequestId(exact.sessionId),
  });
}

function voiceStartGuardReference(db, hostId, roomId) {
  return db.doc(
    `privateRoomVoiceStartGuards/${digest("room-voice-start", hostId, roomId)}`,
  );
}

async function canStartRoomVoice({
  auth,
  db,
  room,
  roomId,
  transaction,
}) {
  if (room.hostId === auth.uid) return true;
  const clubId = room.clubId;
  if (typeof clubId === "string" && clubId.length > 0) {
    requireId(clubId, "clubId");
    const [club, membership] = await transactionGetAll(
      transaction,
      db.doc(`clubs/${clubId}`),
      db.doc(`clubs/${clubId}/members/${auth.uid}`),
    );
    const member = membership.exists ? (membership.data() ?? {}) : null;
    if (
      club.exists &&
      club.data()?.status === "active" &&
      club.data()?.deletionInProgress !== true &&
      member?.userId === auth.uid &&
      member.banned !== true &&
      ["owner", "coOwner", "admin", "moderator", "member"].includes(
        member.role ?? "guest",
      )
    ) {
      return true;
    }
    return false;
  }
  if (room.membersCanStartVoice === true) {
    const membership = await transaction.get(
      db.doc(`rooms/${roomId}/roomMembers/${auth.uid}`),
    );
    if (
      membership.exists &&
      membership.data()?.userId === auth.uid &&
      membership.data()?.banned !== true
    ) {
      return true;
    }
  }
  return false;
}

function commitVoiceStartDenial({
  attemptRef,
  code,
  identity,
  input,
  ledgerRef,
  message,
  now,
  transaction,
}) {
  const result = {
    schemaVersion: 1,
    denied: { code, message },
    roomId: input.roomId,
  };
  transaction.create(ledgerRef, ledgerData({
    kind: "room.voice.start",
    uid: identity.uid ?? null,
    requestId: input.requestId,
    inputHash: identity.inputHash,
    result,
    now,
  }));
  transaction.delete(attemptRef);
  return result;
}

function returnVoiceStartOutcome(outcome) {
  if (outcome?.denied) {
    fail(outcome.denied.code, outcome.denied.message);
  }
  return outcome;
}

function createRoomCreationService({
  db,
  FieldValue,
  Timestamp,
  clock = () => Date.now(),
  policy = DEFAULT_ROOM_CREATION_POLICY,
} = {}) {
  if (!db || !FieldValue?.delete || !Timestamp?.fromMillis) {
    throw new TypeError("db, FieldValue and Timestamp are required.");
  }
  const creationPolicy = validatePolicy(policy);

  async function createRoom(request) {
    const auth = requireActor(request);
    const input = validatedCreationInput(request.data);
    const operationInput = Object.fromEntries(
      Object.entries(input).filter(([key]) => key !== "requestId"),
    );
    const identity = operationIdentity(
      "room.create",
      auth.uid,
      input.requestId,
      operationInput,
    );
    const roomId = canonicalRoomId(auth.uid, input.requestId);
    const timing = timeFrom(clock, Timestamp);
    const ledgerRef = db.doc(`integrityOperationLedgers/${identity.id}`);
    const attemptRef = db.doc(`privateRoomCreationAttempts/${identity.id}`);
    const rateRef = rateLimitReference(db, "room.create.global", auth.uid);
    const profileRef = db.doc(`users/${auth.uid}`);
    const restrictionRef = db.doc(`restrictions/${auth.uid}`);

    // Commit the global attempt budget before touching the room graph. A
    // capacity attacker can therefore cause only N bounded graph reads per
    // window, not an unlimited series of rolled-back scans. The attempt row
    // makes a retry with the same requestId free and resumable after a lost
    // function acknowledgement.
    const admission = await db.runTransaction(async (transaction) => {
      const [ledger, attempt, rate, profile, restriction] =
        await transactionGetAll(
          transaction,
          ledgerRef,
          attemptRef,
          rateRef,
          profileRef,
          restrictionRef,
        );
      const replay = assertLedgerReplay(ledger, {
        kind: "room.create",
        uid: auth.uid,
        inputHash: identity.inputHash,
      });
      if (replay) return { replay };
      activeProfile(profile, "Your");
      assertNotRestricted(restriction, "Your", timing.nowMs);
      if (attempt.exists) {
        const prior = attempt.data() ?? {};
        if (
          prior.schemaVersion !== 1 ||
          prior.kind !== "room.create" ||
          prior.ownerId !== auth.uid ||
          prior.inputHash !== identity.inputHash ||
          prior.requestId !== input.requestId
        ) {
          fail("already-exists", "requestId was already used for another operation.");
        }
        return { admitted: true };
      }
      consumeRateLimit(transaction, rate, {
        reference: rateRef,
        scope: "room.create.global",
        uid: auth.uid,
        ...timing,
        maxEvents: creationPolicy.maxEvents,
        windowMs: creationPolicy.windowMs,
      });
      transaction.create(attemptRef, {
        schemaVersion: 1,
        kind: "room.create",
        ownerId: auth.uid,
        requestId: input.requestId,
        inputHash: identity.inputHash,
        createdAt: timing.now,
      });
      return { admitted: true };
    });
    if (admission.replay) {
      if (admission.replay.denied === "capacity") {
        fail(
          "resource-exhausted",
          `You can keep up to ${creationPolicy.maxActiveRooms} active rooms.`,
        );
      }
      return admission.replay;
    }

    const outcome = await db.runTransaction(async (transaction) => {
      const guardRef = db.doc(`privateRoomHostGuards/${auth.uid}`);
      const roomRef = db.doc(`rooms/${roomId}`);
      const [ledger, attempt, guard, profileSnapshot, restriction, existingRoom] =
        await transactionGetAll(
          transaction,
          ledgerRef,
          attemptRef,
          guardRef,
          profileRef,
          restrictionRef,
          roomRef,
        );

      const replay = assertLedgerReplay(ledger, {
        kind: "room.create",
        uid: auth.uid,
        inputHash: identity.inputHash,
      });
      if (replay) return replay;

      const profile = activeProfile(profileSnapshot, "Your");
      assertNotRestricted(restriction, "Your", timing.nowMs);
      const hostName = canonicalDisplayName(profile);
      const admitted = attempt.exists ? (attempt.data() ?? {}) : {};
      if (
        admitted.schemaVersion !== 1 ||
        admitted.kind !== "room.create" ||
        admitted.ownerId !== auth.uid ||
        admitted.requestId !== input.requestId ||
        admitted.inputHash !== identity.inputHash
      ) {
        fail("data-loss", "The room-creation admission is missing or malformed.");
      }
      if (existingRoom.exists) {
        fail("data-loss", "A room exists without its idempotency ledger.");
      }

      const guardState = validatedGuardRoomIds(
        guard,
        auth.uid,
        creationPolicy.maxActiveRooms,
      );
      let activeRoomIds;
      let capacityLocked = guardState?.capacityLocked === true;
      if (guardState === null) {
        // A legacy account can contain an attacker-sized room collection.
        // Never scan it. `limit(cap + 1)` proves either that the result is
        // exhaustive, or that capacity cannot safely be established. The
        // latter becomes a fail-closed guard, so subsequent attempts do not
        // repeat even this bounded bootstrap read until an admin migration
        // reconciles the account.
        const query = boundedLegacyRoomQuery(
          db,
          auth.uid,
          creationPolicy.maxActiveRooms,
        );
        const activeSnapshot = await transaction.get(query);
        activeRoomIds = activeSnapshot.docs
          .filter((document) => isActiveOrdinaryRoom(document, auth.uid))
          .map((document) => document.id)
          .slice(0, creationPolicy.maxActiveRooms);
        capacityLocked = activeSnapshot.size > creationPolicy.maxActiveRooms;
      } else if (capacityLocked) {
        activeRoomIds = guardState.activeRoomIds;
      } else {
        const guardedIds = guardState.activeRoomIds;
        const snapshots = guardedIds.length === 0
          ? []
          : await transactionGetAll(
            transaction,
            ...guardedIds.map((id) => db.doc(`rooms/${id}`)),
          );
        activeRoomIds = snapshots
          .filter((snapshot) => isActiveOrdinaryRoom(snapshot, auth.uid))
          .map((snapshot) => snapshot.id);
      }
      activeRoomIds = [...new Set(activeRoomIds)].sort();

      if (
        capacityLocked ||
        activeRoomIds.length >= creationPolicy.maxActiveRooms
      ) {
        const result = {
          schemaVersion: 1,
          denied: "capacity",
        };
        transaction.set(guardRef, {
          schemaVersion: 2,
          ownerId: auth.uid,
          activeRoomIds,
          capacityLocked,
          updatedAt: timing.now,
        });
        transaction.create(ledgerRef, ledgerData({
          kind: "room.create",
          uid: auth.uid,
          requestId: input.requestId,
          inputHash: identity.inputHash,
          result,
          now: timing.now,
        }));
        transaction.delete(attemptRef);
        return result;
      }
      transaction.create(roomRef, roomDocument(input, auth.uid, hostName, timing.now));
      if (input.roomType === "community") {
        transaction.create(roomRef.collection("roomMembers").doc(auth.uid), {
          userId: auth.uid,
          displayName: hostName,
          photoUrl: null,
          role: "owner",
          joinedAt: timing.now,
        });
      } else {
        transaction.create(roomRef.collection("participants").doc(auth.uid), {
          userId: auth.uid,
          displayName: hostName,
          photoUrl: null,
          role: "host",
          isMuted: false,
          isSpeaker: true,
          isHandRaised: false,
          joinedAt: timing.now,
          updatedAt: timing.now,
        });
      }
      transaction.set(guardRef, {
        schemaVersion: 2,
        ownerId: auth.uid,
        activeRoomIds: [...activeRoomIds, roomId].sort(),
        capacityLocked: false,
        updatedAt: timing.now,
      });
      const result = {
        schemaVersion: 1,
        roomId,
        created: true,
      };
      transaction.create(ledgerRef, ledgerData({
        kind: "room.create",
        uid: auth.uid,
        requestId: input.requestId,
        inputHash: identity.inputHash,
        result,
        now: timing.now,
      }));
      transaction.delete(attemptRef);
      return result;
    });
    if (outcome?.denied === "capacity") {
      fail(
        "resource-exhausted",
        `You can keep up to ${creationPolicy.maxActiveRooms} active rooms.`,
      );
    }
    return outcome;
  }

  async function startRoomVoice(request) {
    const auth = requireActor(request);
    const input = validatedStartInput(request.data);
    const operationInput = {
      roomId: input.roomId,
      sessionId: input.sessionId,
    };
    const identity = {
      ...operationIdentity(
        "room.voice.start",
        auth.uid,
        input.requestId,
        operationInput,
      ),
      uid: auth.uid,
    };
    const timing = timeFrom(clock, Timestamp);
    const ledgerRef = db.doc(`integrityOperationLedgers/${identity.id}`);
    const attemptRef = db.doc(`privateRoomVoiceStartAttempts/${identity.id}`);
    const rateRef = rateLimitReference(
      db,
      "room.voice.start.global",
      auth.uid,
    );
    const profileRef = db.doc(`users/${auth.uid}`);
    const restrictionRef = db.doc(`restrictions/${auth.uid}`);

    // Charge the actor-wide budget before reading a caller-selected room id.
    // A random-id or unauthorized-target probe is therefore N/N+1 bounded,
    // while a retry of the exact same operation resumes for free.
    const admission = await db.runTransaction(async (transaction) => {
      const [ledger, attempt, rate, profile, restriction] =
        await transactionGetAll(
          transaction,
          ledgerRef,
          attemptRef,
          rateRef,
          profileRef,
          restrictionRef,
        );
      const replay = assertLedgerReplay(ledger, {
        kind: "room.voice.start",
        uid: auth.uid,
        inputHash: identity.inputHash,
      });
      if (replay) return { replay };
      activeProfile(profile, "Your");
      assertNotRestricted(restriction, "Your", timing.nowMs);
      if (attempt.exists) {
        const prior = attempt.data() ?? {};
        if (
          prior.schemaVersion !== 1 ||
          prior.kind !== "room.voice.start" ||
          prior.ownerId !== auth.uid ||
          prior.requestId !== input.requestId ||
          prior.inputHash !== identity.inputHash
        ) {
          fail("already-exists", "requestId was already used for another operation.");
        }
        return { admitted: true };
      }
      consumeRateLimit(transaction, rate, {
        reference: rateRef,
        scope: "room.voice.start.global",
        uid: auth.uid,
        ...timing,
        maxEvents: creationPolicy.startMaxEvents,
        windowMs: creationPolicy.startWindowMs,
      });
      transaction.create(attemptRef, {
        schemaVersion: 1,
        kind: "room.voice.start",
        ownerId: auth.uid,
        requestId: input.requestId,
        inputHash: identity.inputHash,
        createdAt: timing.now,
      });
      return { admitted: true };
    });
    if (admission.replay) return returnVoiceStartOutcome(admission.replay);

    const outcome = await db.runTransaction(async (transaction) => {
      const roomRef = db.doc(`rooms/${input.roomId}`);
      const [ledger, attempt, profile, restriction, roomSnapshot] =
        await transactionGetAll(
          transaction,
          ledgerRef,
          attemptRef,
          profileRef,
          restrictionRef,
          roomRef,
        );
      const replay = assertLedgerReplay(ledger, {
        kind: "room.voice.start",
        uid: auth.uid,
        inputHash: identity.inputHash,
      });
      if (replay) return replay;

      activeProfile(profile, "Your");
      assertNotRestricted(restriction, "Your", timing.nowMs);
      const admitted = attempt.exists ? (attempt.data() ?? {}) : {};
      if (
        admitted.schemaVersion !== 1 ||
        admitted.kind !== "room.voice.start" ||
        admitted.ownerId !== auth.uid ||
        admitted.requestId !== input.requestId ||
        admitted.inputHash !== identity.inputHash
      ) {
        fail("data-loss", "The voice-start admission is missing or malformed.");
      }
      if (!roomSnapshot.exists) {
        return commitVoiceStartDenial({
          transaction,
          attemptRef,
          ledgerRef,
          identity,
          input,
          now: timing.now,
          code: "not-found",
          message: "The room does not exist.",
        });
      }
      const room = roomSnapshot.data() ?? {};
      if (
        typeof room.hostId !== "string" ||
        !/^[A-Za-z0-9_-]{1,160}$/u.test(room.hostId) ||
        room.status !== "active" ||
        room.deletionInProgress === true
      ) {
        return commitVoiceStartDenial({
          transaction,
          attemptRef,
          ledgerRef,
          identity,
          input,
          now: timing.now,
          code: "failed-precondition",
          message: "This room cannot start voice.",
        });
      }
      if (room.isLive === true) {
        return commitVoiceStartDenial({
          transaction,
          attemptRef,
          ledgerRef,
          identity,
          input,
          now: timing.now,
          code: "failed-precondition",
          message: "Voice is already live in this room.",
        });
      }
      if (!await canStartRoomVoice({
        auth,
        db,
        room,
        roomId: input.roomId,
        transaction,
      })) {
        return commitVoiceStartDenial({
          transaction,
          attemptRef,
          ledgerRef,
          identity,
          input,
          now: timing.now,
          code: "permission-denied",
          message: "You cannot start voice in this room.",
        });
      }

      // Cooldown is scoped to the immutable room host + room identity, not
      // the caller. Otherwise two authorized Club/Community members could
      // alternate calls and bypass it with distinct actor-scoped guards.
      const startGuardRef = voiceStartGuardReference(
        db,
        room.hostId,
        input.roomId,
      );
      const startGuard = await transaction.get(startGuardRef);
      const guard = startGuard.exists ? (startGuard.data() ?? {}) : {};
      const lastStartedMs = timestampMillis(guard.lastStartedAt);
      if (
        startGuard.exists &&
        (
          guard.schemaVersion !== 1 ||
          guard.ownerId !== room.hostId ||
          guard.roomId !== input.roomId ||
          lastStartedMs === null ||
          timing.nowMs < lastStartedMs
        )
      ) {
        fail("data-loss", "The room voice-start guard is malformed.");
      }

      if (
        lastStartedMs !== null &&
        timing.nowMs - lastStartedMs < creationPolicy.startCooldownMs
      ) {
        return commitVoiceStartDenial({
          transaction,
          attemptRef,
          ledgerRef,
          identity,
          input,
          now: timing.now,
          code: "resource-exhausted",
          message: "Voice was started too recently. Please wait before starting again.",
        });
      }

      transaction.update(roomRef, {
        isLive: true,
        updatedAt: timing.now,
        endedAt: FieldValue.delete(),
        voiceSessionId: input.sessionId,
        voiceStartedAt: timing.now,
      });
      transaction.set(startGuardRef, {
        schemaVersion: 1,
        ownerId: room.hostId,
        roomId: input.roomId,
        startedById: auth.uid,
        lastSessionId: input.sessionId,
        lastStartedAt: timing.now,
        updatedAt: timing.now,
      });
      const result = {
        schemaVersion: 1,
        roomId: input.roomId,
        sessionId: input.sessionId,
        started: true,
      };
      transaction.create(ledgerRef, ledgerData({
        kind: "room.voice.start",
        uid: auth.uid,
        requestId: input.requestId,
        inputHash: identity.inputHash,
        result,
        now: timing.now,
      }));
      transaction.delete(attemptRef);
      return result;
    });
    return returnVoiceStartOutcome(outcome);
  }

  return Object.freeze({ createRoom, startRoomVoice });
}

module.exports = {
  CREATE_INPUT_FIELDS,
  DEFAULT_ROOM_CREATION_POLICY,
  START_INPUT_FIELDS,
  boundedLegacyRoomQuery,
  canonicalRoomId,
  createRoomCreationService,
  validatedStartInput,
  validatedCreationInput,
  voiceStartGuardReference,
};
