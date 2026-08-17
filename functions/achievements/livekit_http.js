const { createHash } = require("node:crypto");

const { logger } = require("firebase-functions/v2");
const { defineSecret } = require("firebase-functions/params");
const { onRequest } = require("firebase-functions/v2/https");

const { isValidOpaqueUid } = require("./identity");
const {
  buildAchievementOutboxRecord,
  normalizeAchievementOutboxRecord,
} = require("./runtime");
const {
  DEFAULT_MAX_SESSION_SECONDS,
  VoiceWebhookValidationError,
  closeVoiceSession,
  planVoiceSessionCredit,
  receiveSignedLiveKitWebhook,
  splitIntervalByUtcDay,
  voiceAchievementEvents,
  voiceSessionFromJoin,
} = require("./voice_webhook");

const REGION = "europe-west1";
// This endpoint is unauthenticated and internet-reachable, so every rejection
// has to be cheaper than the work it declines. A LiveKit voice webhook carries
// one room and at most one participant; observed bodies are well under 4 KiB.
// Anything past this bound is refused before the body is hashed, and 413 is
// deliberately not a 5xx so the sender stops rather than retrying forever.
const MAX_WEBHOOK_BODY_BYTES = 128 * 1024;
// A public endpoint with no App Check in front of it can be driven as hard as
// an attacker likes. Concurrency is capped so a flood costs bounded instances
// and bounded Firestore contention instead of an open-ended bill.
const MAX_WEBHOOK_INSTANCES = 10;
const VOICE_SESSION_SCHEMA_VERSION = 1;
const VOICE_DAY_SCHEMA_VERSION = 1;
const MAX_ROOM_FINISH_SESSIONS = 500;
const AWAITING_JOIN_TTL_MS = 24 * 60 * 60 * 1000;
const SESSION_RETENTION_MS = 30 * 24 * 60 * 60 * 1000;
const SAFE_SEGMENT = /^[A-Za-z0-9_-]{1,128}$/u;
const PARTICIPANT_ROLES = new Set(["host", "speaker", "listener"]);

const livekitAchievementApiKey = defineSecret("LIVEKIT_API_KEY");
const livekitAchievementApiSecret = defineSecret("LIVEKIT_API_SECRET");

class VoiceAchievementStoreError extends Error {
  constructor(message) {
    super(message);
    this.name = "VoiceAchievementStoreError";
  }
}

function safeSegment(value) {
  return typeof value === "string" && SAFE_SEGMENT.test(value) ? value : null;
}

function timestampDate(value) {
  const date = value instanceof Date
    ? value
    : typeof value?.toDate === "function"
      ? value.toDate()
      : null;
  return date instanceof Date && Number.isFinite(date.getTime())
    ? new Date(date.getTime())
    : null;
}

function sessionDocumentId(roomSid, participantSid) {
  if (!safeSegment(roomSid) || !safeSegment(participantSid)) {
    throw new VoiceAchievementStoreError("Canonical LiveKit session ids are required.");
  }
  return `v1_${createHash("sha256")
    .update(`${roomSid}\u0000${participantSid}`, "utf8")
    .digest("hex")}`;
}

function activeProfile(profile) {
  return profile && profile.banned !== true && profile.disabled !== true &&
    profile.deleted !== true && profile.status !== "deleted";
}

function restrictionActive(restriction, occurredAtMs) {
  if (!restriction || restriction.type !== "communicationMute") return false;
  if (restriction.expiresAt === null || restriction.expiresAt === undefined) {
    return true;
  }
  const expiry = timestampDate(restriction.expiresAt);
  return !expiry || expiry.getTime() > occurredAtMs;
}

function snapshotData(snapshot) {
  return snapshot?.exists ? snapshot.data() ?? null : null;
}

function pendingCloseForStorage(webhook) {
  if (!webhook || ![
    "participant_left",
    "participant_connection_aborted",
  ].includes(webhook.type)) {
    throw new VoiceAchievementStoreError("A participant close webhook is required.");
  }
  return Object.freeze({
    type: webhook.type,
    eventId: webhook.eventId,
    roomSid: webhook.roomSid,
    roomName: webhook.roomName,
    createdAtMs: webhook.createdAtMs,
    participantSid: webhook.participantSid,
    participantIdentity: webhook.participantIdentity,
    joinedAtMs: webhook.joinedAtMs ?? null,
  });
}

function normalizePendingClose(raw, expectedSession = null) {
  if (!raw || ![
    "participant_left",
    "participant_connection_aborted",
  ].includes(raw.type) || !safeSegment(raw.eventId) ||
      !safeSegment(raw.roomSid) || !safeSegment(raw.roomName) ||
      !safeSegment(raw.participantSid) ||
      !isValidOpaqueUid(raw.participantIdentity) ||
      !Number.isSafeInteger(raw.createdAtMs) || raw.createdAtMs <= 0 ||
      (raw.joinedAtMs !== null && raw.joinedAtMs !== undefined &&
       (!Number.isSafeInteger(raw.joinedAtMs) || raw.joinedAtMs <= 0))) {
    throw new VoiceAchievementStoreError("Stored pending voice closure is malformed.");
  }
  const normalized = pendingCloseForStorage(raw);
  if (expectedSession && (
    normalized.roomSid !== expectedSession.roomSid ||
    normalized.roomName !== expectedSession.roomId ||
    normalized.participantSid !== expectedSession.participantSid ||
    normalized.participantIdentity !== expectedSession.userId
  )) {
    throw new VoiceAchievementStoreError(
      "Pending voice closure is not bound to its canonical join.",
    );
  }
  return normalized;
}

function normalizeOpenSession(raw, expectedId) {
  if (!raw || raw.schemaVersion !== VOICE_SESSION_SCHEMA_VERSION ||
      raw.sessionId !== expectedId || raw.status !== "open" ||
      !safeSegment(raw.roomId) || !safeSegment(raw.roomSid) ||
      !safeSegment(raw.participantSid) || !isValidOpaqueUid(raw.userId) ||
      !safeSegment(raw.joinEventId) ||
      !Number.isSafeInteger(raw.joinedAtMs) || raw.joinedAtMs <= 0 ||
      typeof raw.isHost !== "boolean") {
    throw new VoiceAchievementStoreError("Stored voice session is malformed.");
  }
  return Object.freeze({
    roomId: raw.roomId,
    roomSid: raw.roomSid,
    participantSid: raw.participantSid,
    userId: raw.userId,
    joinedAtMs: raw.joinedAtMs,
    isHost: raw.isHost,
    joinEventId: raw.joinEventId,
  });
}

function sessionMatchesJoin(raw, session) {
  return raw?.roomId === session.roomId && raw?.roomSid === session.roomSid &&
    raw?.participantSid === session.participantSid &&
    raw?.userId === session.userId && raw?.joinedAtMs === session.joinedAtMs &&
    raw?.isHost === session.isHost && raw?.joinEventId === session.joinEventId;
}

function intervalSeconds(intervals) {
  if (!Array.isArray(intervals)) return 0;
  return Math.floor(intervals.reduce((total, interval) => {
    if (!Number.isSafeInteger(interval?.startMs) ||
        !Number.isSafeInteger(interval?.endMs) ||
        interval.endMs <= interval.startMs) {
      throw new VoiceAchievementStoreError("Stored voice interval is malformed.");
    }
    return total + interval.endMs - interval.startMs;
  }, 0) / 1000);
}

class FirestoreVoiceAchievementStore {
  constructor({
    db = null,
    maximumSessionSeconds = DEFAULT_MAX_SESSION_SECONDS,
  } = {}) {
    this.db = db;
    this.maximumSessionSeconds = maximumSessionSeconds;
  }

  database() {
    return this.db ?? require("../utils/firestore").db;
  }

  async _canonicalJoin(transaction, webhook) {
    const database = this.database();
    const roomId = safeSegment(webhook.roomName);
    if (!roomId || !isValidOpaqueUid(webhook.participantIdentity)) {
      throw new VoiceAchievementStoreError("Webhook identity is not canonical.");
    }
    const roomRef = database.collection("rooms").doc(roomId);
    const roomSnapshot = await transaction.get(roomRef);
    const room = snapshotData(roomSnapshot);
    if (!room || room.status !== "active" || room.isLive !== true ||
        room.deletionInProgress === true ||
        !["community", "temporary"].includes(room.roomType) ||
        !isValidOpaqueUid(room.hostId)) {
      throw new VoiceAchievementStoreError("The canonical room is not active.");
    }

    const uid = webhook.participantIdentity;
    const participantRef = roomRef.collection("participants").doc(uid);
    const userRef = database.collection("users").doc(uid);
    const restrictionRef = database.collection("restrictions").doc(uid);
    const [participantSnapshot, userSnapshot, restrictionSnapshot] =
      typeof transaction.getAll === "function"
        ? await transaction.getAll(participantRef, userRef, restrictionRef)
        : await Promise.all([
            transaction.get(participantRef),
            transaction.get(userRef),
            transaction.get(restrictionRef),
          ]);
    const participant = snapshotData(participantSnapshot);
    const profile = snapshotData(userSnapshot);
    const restriction = snapshotData(restrictionSnapshot);
    if (!participant || participant.userId !== uid || participant.banned === true ||
        !PARTICIPANT_ROLES.has(participant.role) || !activeProfile(profile) ||
        restrictionActive(restriction, webhook.createdAtMs)) {
      throw new VoiceAchievementStoreError(
        "The participant no longer has canonical room authority.",
      );
    }

    const clubId = room.clubId === null || room.clubId === undefined
      ? null
      : safeSegment(room.clubId);
    if (room.clubId && !clubId) {
      throw new VoiceAchievementStoreError("The canonical Club id is malformed.");
    }
    if (clubId) {
      const [clubSnapshot, memberSnapshot] = typeof transaction.getAll === "function"
        ? await transaction.getAll(
            database.collection("clubs").doc(clubId),
            database.collection("clubs").doc(clubId).collection("members").doc(uid),
          )
        : await Promise.all([
            transaction.get(database.collection("clubs").doc(clubId)),
            transaction.get(
              database.collection("clubs").doc(clubId).collection("members").doc(uid),
            ),
          ]);
      const club = snapshotData(clubSnapshot);
      const member = snapshotData(memberSnapshot);
      if (!club || club.status !== "active" || club.deletionInProgress === true ||
          !member || member.userId !== uid || member.banned === true) {
        throw new VoiceAchievementStoreError("Club voice authority is not active.");
      }
    } else if (room.visibility !== "public" && room.hostId !== uid &&
        participant.admittedBy !== room.hostId) {
      throw new VoiceAchievementStoreError(
        "Private-room admission is not canonical.",
      );
    }
    return voiceSessionFromJoin(webhook, { id: roomId, hostId: room.hostId });
  }

  async _closeAuthority(transaction, session, occurredAtMs) {
    const database = this.database();
    const [roomSnapshot, userSnapshot, restrictionSnapshot] =
      typeof transaction.getAll === "function"
        ? await transaction.getAll(
            database.collection("rooms").doc(session.roomId),
            database.collection("users").doc(session.userId),
            database.collection("restrictions").doc(session.userId),
          )
        : await Promise.all([
            transaction.get(database.collection("rooms").doc(session.roomId)),
            transaction.get(database.collection("users").doc(session.userId)),
            transaction.get(database.collection("restrictions").doc(session.userId)),
          ]);
    const room = snapshotData(roomSnapshot);
    const profile = snapshotData(userSnapshot);
    const restriction = snapshotData(restrictionSnapshot);
    return Boolean(room && activeProfile(profile) &&
      isValidOpaqueUid(room.hostId) &&
      (room.hostId === session.userId) === session.isHost &&
      !restrictionActive(restriction, occurredAtMs));
  }

  async _closeInTransaction(transaction, reference, session, closeWebhook) {
    const interval = closeVoiceSession(session, closeWebhook, {
      maximumSessionSeconds: this.maximumSessionSeconds,
    });
    if (!interval) {
      throw new VoiceAchievementStoreError("Voice closure does not match its join.");
    }
    const parts = splitIntervalByUtcDay(interval);
    const database = this.database();
    const dayRefs = parts.map((part) => database
      .collection("achievementVoiceDays")
      .doc(session.userId)
      .collection("days")
      .doc(part.day));
    const daySnapshots = typeof transaction.getAll === "function"
      ? await transaction.getAll(...dayRefs)
      : await Promise.all(dayRefs.map((dayRef) => transaction.get(dayRef)));
    const voiceIntervalsByDay = {};
    const hostIntervalsByDay = {};
    for (let index = 0; index < parts.length; index += 1) {
      const stored = snapshotData(daySnapshots[index]);
      if (stored && (stored.schemaVersion !== VOICE_DAY_SCHEMA_VERSION ||
          stored.userId !== session.userId || stored.day !== parts[index].day)) {
        throw new VoiceAchievementStoreError("Stored voice day is not canonical.");
      }
      voiceIntervalsByDay[parts[index].day] = stored?.voiceIntervals ?? [];
      hostIntervalsByDay[parts[index].day] = stored?.hostIntervals ?? [];
    }
    const plan = planVoiceSessionCredit({
      session,
      closeWebhook,
      voiceIntervalsByDay,
      hostIntervalsByDay,
      maximumSessionSeconds: this.maximumSessionSeconds,
    });
    const achievementEvents = voiceAchievementEvents(session, plan);
    const createdAt = new Date(closeWebhook.createdAtMs);
    const outboxRecords = achievementEvents.map((event) =>
      buildAchievementOutboxRecord(event, createdAt));
    const outboxRefs = outboxRecords.map((record) =>
      database.collection("achievementOutbox").doc(record.eventId));
    const outboxSnapshots = outboxRefs.length === 0
      ? []
      : typeof transaction.getAll === "function"
        ? await transaction.getAll(...outboxRefs)
        : await Promise.all(outboxRefs.map((outboxRef) => transaction.get(outboxRef)));
    for (let index = 0; index < outboxRecords.length; index += 1) {
      const existing = snapshotData(outboxSnapshots[index]);
      if (existing) normalizeAchievementOutboxRecord(
        existing,
        outboxRecords[index].eventId,
      );
    }

    for (let index = 0; index < parts.length; index += 1) {
      const day = parts[index].day;
      const voiceIntervals = plan.voiceIntervalsByDay[day] ?? [];
      const hostIntervals = plan.hostIntervalsByDay[day] ?? [];
      transaction.set(dayRefs[index], {
        schemaVersion: VOICE_DAY_SCHEMA_VERSION,
        userId: session.userId,
        day,
        voiceIntervals,
        hostIntervals,
        voiceSeconds: intervalSeconds(voiceIntervals),
        hostSeconds: intervalSeconds(hostIntervals),
        updatedAt: createdAt,
      });
    }
    for (let index = 0; index < outboxRecords.length; index += 1) {
      if (!outboxSnapshots[index]?.exists) {
        transaction.create(outboxRefs[index], outboxRecords[index]);
      }
    }
    transaction.set(reference, {
      schemaVersion: VOICE_SESSION_SCHEMA_VERSION,
      sessionId: reference.id,
      status: "closed",
      ...session,
      closeEventId: closeWebhook.eventId,
      endedAtMs: plan.interval.endMs,
      capped: plan.interval.capped,
      creditedVoiceSeconds: plan.voiceSecondsAdded,
      creditedHostSeconds: plan.hostSecondsAdded,
      outboxIds: outboxRecords.map((record) => record.eventId),
      closedAt: createdAt,
      updatedAt: createdAt,
      expiresAt: new Date(createdAt.getTime() + SESSION_RETENTION_MS),
    });
    return {
      outcome: "closed",
      sessionId: reference.id,
      voiceSecondsAdded: plan.voiceSecondsAdded,
      hostSecondsAdded: plan.hostSecondsAdded,
      outboxIds: outboxRecords.map((record) => record.eventId),
    };
  }

  async recordJoin(webhook) {
    if (webhook?.type !== "participant_joined") {
      throw new VoiceAchievementStoreError("A signed participant join is required.");
    }
    const database = this.database();
    const sessionId = sessionDocumentId(webhook.roomSid, webhook.participantSid);
    const reference = database.collection("achievementVoiceSessions").doc(sessionId);
    return database.runTransaction(async (transaction) => {
      const existingSnapshot = await transaction.get(reference);
      const existing = snapshotData(existingSnapshot);
      const session = await this._canonicalJoin(transaction, webhook);
      if (existing?.status === "open" || existing?.status === "closed") {
        if (!sessionMatchesJoin(existing, session)) {
          throw new VoiceAchievementStoreError("LiveKit session identity collision.");
        }
        return { outcome: "replayed", sessionId };
      }
      let pendingClose = null;
      if (existing) {
        if (existing.schemaVersion !== VOICE_SESSION_SCHEMA_VERSION ||
            existing.sessionId !== sessionId || existing.status !== "awaitingJoin" ||
            existing.roomId !== session.roomId ||
            existing.roomSid !== session.roomSid ||
            existing.participantSid !== session.participantSid ||
            existing.userId !== session.userId) {
          throw new VoiceAchievementStoreError("Pending voice session is malformed.");
        }
        pendingClose = normalizePendingClose(existing.pendingClose, session);
      }
      const createdAt = new Date(webhook.createdAtMs);
      if (pendingClose) {
        return this._closeInTransaction(transaction, reference, session, pendingClose);
      }
      transaction.set(reference, {
        schemaVersion: VOICE_SESSION_SCHEMA_VERSION,
        sessionId,
        status: "open",
        ...session,
        authorityCheckedAt: createdAt,
        createdAt,
        updatedAt: createdAt,
        expiresAt: new Date(
          session.joinedAtMs + this.maximumSessionSeconds * 1000 +
          SESSION_RETENTION_MS,
        ),
      });
      return { outcome: "opened", sessionId };
    });
  }

  async _closeKnownSession(reference, closeWebhook) {
    const database = this.database();
    return database.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(reference);
      const raw = snapshotData(snapshot);
      if (!raw) return { outcome: "skipped:missing-join", sessionId: reference.id };
      if (raw.status === "closed") {
        return { outcome: "replayed", sessionId: reference.id };
      }
      const session = normalizeOpenSession(raw, reference.id);
      const authorized = await this._closeAuthority(
        transaction,
        session,
        closeWebhook.createdAtMs,
      );
      if (!authorized) {
        const closedAt = new Date(closeWebhook.createdAtMs);
        transaction.set(reference, {
          ...raw,
          status: "closed",
          closeEventId: closeWebhook.eventId,
          creditedVoiceSeconds: 0,
          creditedHostSeconds: 0,
          outboxIds: [],
          closeOutcome: "rejected:authority",
          closedAt,
          updatedAt: closedAt,
          expiresAt: new Date(closedAt.getTime() + SESSION_RETENTION_MS),
        });
        return { outcome: "rejected:authority", sessionId: reference.id };
      }
      return this._closeInTransaction(transaction, reference, session, closeWebhook);
    });
  }

  async closeParticipant(webhook) {
    const close = pendingCloseForStorage(webhook);
    const database = this.database();
    const sessionId = sessionDocumentId(close.roomSid, close.participantSid);
    const reference = database.collection("achievementVoiceSessions").doc(sessionId);
    return database.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(reference);
      const current = snapshotData(snapshot);
      if (current?.status === "open") {
        const session = normalizeOpenSession(current, reference.id);
        const authorized = await this._closeAuthority(
          transaction,
          session,
          close.createdAtMs,
        );
        if (!authorized) {
          const closedAt = new Date(close.createdAtMs);
          transaction.set(reference, {
            ...current,
            status: "closed",
            closeEventId: close.eventId,
            creditedVoiceSeconds: 0,
            creditedHostSeconds: 0,
            outboxIds: [],
            closeOutcome: "rejected:authority",
            closedAt,
            updatedAt: closedAt,
            expiresAt: new Date(closedAt.getTime() + SESSION_RETENTION_MS),
          });
          return { outcome: "rejected:authority", sessionId };
        }
        return this._closeInTransaction(transaction, reference, session, close);
      }
      if (current?.status === "closed") {
        return { outcome: "replayed", sessionId };
      }
      if (current) {
        if (current.status === "awaitingJoin") {
          const stored = normalizePendingClose(current.pendingClose);
          if (stored.roomSid !== close.roomSid ||
              stored.participantSid !== close.participantSid ||
              stored.participantIdentity !== close.participantIdentity) {
            throw new VoiceAchievementStoreError("Pending close identity collision.");
          }
          return { outcome: "replayed:awaiting-join", sessionId };
        }
        throw new VoiceAchievementStoreError("Stored voice session is malformed.");
      }
      const createdAt = new Date(close.createdAtMs);
      transaction.create(reference, {
        schemaVersion: VOICE_SESSION_SCHEMA_VERSION,
        sessionId,
        status: "awaitingJoin",
        roomId: close.roomName,
        roomSid: close.roomSid,
        participantSid: close.participantSid,
        userId: close.participantIdentity,
        pendingClose: close,
        createdAt,
        updatedAt: createdAt,
        expiresAt: new Date(createdAt.getTime() + AWAITING_JOIN_TTL_MS),
      });
      return { outcome: "awaiting-join", sessionId };
    });
  }

  async closeRoom(webhook) {
    if (webhook?.type !== "room_finished" || !safeSegment(webhook.roomSid) ||
        !safeSegment(webhook.roomName)) {
      throw new VoiceAchievementStoreError("A signed room finish is required.");
    }
    const snapshot = await this.database()
      .collection("achievementVoiceSessions")
      .where("roomSid", "==", webhook.roomSid)
      .limit(MAX_ROOM_FINISH_SESSIONS + 1)
      .get();
    if (snapshot.size > MAX_ROOM_FINISH_SESSIONS) {
      throw new VoiceAchievementStoreError(
        "Room finish exceeds the bounded session reconciliation limit.",
      );
    }
    const results = [];
    for (const document of snapshot.docs) {
      const raw = document.data() ?? {};
      if (raw.roomId !== webhook.roomName || raw.roomSid !== webhook.roomSid) {
        throw new VoiceAchievementStoreError("Room finish session is not canonical.");
      }
      if (raw.status !== "open") continue;
      results.push(await this._closeKnownSession(document.ref, webhook));
    }
    return { outcome: "room-closed", sessionCount: results.length, results };
  }

  async handle(webhook) {
    if (webhook?.type === "participant_joined") return this.recordJoin(webhook);
    if (["participant_left", "participant_connection_aborted"].includes(
      webhook?.type,
    )) return this.closeParticipant(webhook);
    if (webhook?.type === "room_finished") return this.closeRoom(webhook);
    return { outcome: "skipped:unsupported" };
  }
}

function authorizationHeader(request) {
  if (typeof request?.get === "function") return request.get("authorization") ?? "";
  const value = request?.headers?.authorization;
  return Array.isArray(value) ? value[0] ?? "" : value ?? "";
}

function rawBodyByteLength(rawBody) {
  if (Buffer.isBuffer(rawBody)) return rawBody.byteLength;
  if (typeof rawBody === "string") return Buffer.byteLength(rawBody, "utf8");
  return null;
}

function createLiveKitAchievementWebhookHandler({
  apiKeyProvider,
  apiSecretProvider,
  receiver = null,
  store = new FirestoreVoiceAchievementStore(),
} = {}) {
  if (typeof apiKeyProvider !== "function" ||
      typeof apiSecretProvider !== "function" ||
      !store || typeof store.handle !== "function") {
    throw new TypeError("Webhook secrets and a voice achievement store are required.");
  }
  return async function liveKitAchievementWebhook(request, response) {
    if (request?.method !== "POST") {
      response.set("Allow", "POST");
      response.status(405).send("Method Not Allowed");
      return;
    }
    const bodyBytes = rawBodyByteLength(request?.rawBody);
    if (bodyBytes !== null && bodyBytes > MAX_WEBHOOK_BODY_BYTES) {
      // Refused before the SHA-256 over the body and before any signature
      // work, so an oversized payload cannot buy CPU from an anonymous caller.
      response.status(413).json({ accepted: false, error: "payload-too-large" });
      return;
    }
    let webhook;
    try {
      webhook = await receiveSignedLiveKitWebhook({
        apiKey: apiKeyProvider(),
        apiSecret: apiSecretProvider(),
        rawBody: request.rawBody,
        authorization: authorizationHeader(request),
        receiver,
      });
    } catch (error) {
      if (error instanceof VoiceWebhookValidationError) {
        response.status(400).json({ accepted: false, error: "invalid-webhook" });
        return;
      }
      // The SDK deliberately owns signature parsing. Its errors are mapped to
      // one non-oracular response and never include the Authorization token.
      response.status(401).json({ accepted: false, error: "invalid-signature" });
      return;
    }
    if (!webhook) {
      response.status(204).send("");
      return;
    }
    try {
      const result = await store.handle(webhook);
      // `type` and `outcome` are both closed sets of server-authored constants.
      // No uid, room id, room/participant SID, event id or session id is ever
      // logged: this endpoint's observability must not become a second copy of
      // the participant list.
      logger.info("livekit achievement webhook accepted", {
        eventType: webhook.type,
        outcome: result.outcome,
      });
      response.status(202).json({ accepted: true, outcome: result.outcome });
    } catch (error) {
      if (error instanceof VoiceAchievementStoreError ||
          error instanceof VoiceWebhookValidationError) {
        // Both classes carry static, non-interpolated messages by
        // construction, so the message names the failed invariant without
        // naming the account or room it failed for.
        logger.warn("livekit achievement webhook rejected a signed event", {
          eventType: webhook.type,
          reason: error.message,
        });
        response.status(400).json({ accepted: false, error: "invalid-source" });
        return;
      }
      // A transient persistence failure must remain retryable for LiveKit.
      // Only the error's class and code are logged — a Firestore error message
      // can quote a document path, and those paths contain uids.
      logger.error("livekit achievement webhook could not persist", {
        eventType: webhook.type,
        errorName: error?.name ?? null,
        errorCode: error?.code ?? null,
      });
      response.status(503).json({ accepted: false, error: "temporarily-unavailable" });
    }
  };
}

// Deliberately public: LiveKit's SFU signs each delivery with the shared API
// secret and cannot present a Firebase ID token or an App Check token. The
// HMAC over the exact raw body IS the authentication boundary here — see
// receiveSignedLiveKitWebhook — so `invoker` is stated rather than inherited.
const receiveLiveKitAchievementWebhook = onRequest({
  region: REGION,
  cors: false,
  invoker: "public",
  maxInstances: MAX_WEBHOOK_INSTANCES,
  timeoutSeconds: 60,
  secrets: [livekitAchievementApiKey, livekitAchievementApiSecret],
}, createLiveKitAchievementWebhookHandler({
  apiKeyProvider: () => livekitAchievementApiKey.value(),
  apiSecretProvider: () => livekitAchievementApiSecret.value(),
}));

module.exports = {
  AWAITING_JOIN_TTL_MS,
  FirestoreVoiceAchievementStore,
  MAX_ROOM_FINISH_SESSIONS,
  MAX_WEBHOOK_BODY_BYTES,
  MAX_WEBHOOK_INSTANCES,
  REGION,
  SESSION_RETENTION_MS,
  VOICE_DAY_SCHEMA_VERSION,
  VOICE_SESSION_SCHEMA_VERSION,
  VoiceAchievementStoreError,
  authorizationHeader,
  createLiveKitAchievementWebhookHandler,
  livekitAchievementApiKey,
  livekitAchievementApiSecret,
  normalizeOpenSession,
  normalizePendingClose,
  pendingCloseForStorage,
  receiveLiveKitAchievementWebhook,
  sessionDocumentId,
};
