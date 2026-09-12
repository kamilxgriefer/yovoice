const { createHash } = require("node:crypto");

const { logger } = require("firebase-functions/v2");
const { defineSecret } = require("firebase-functions/params");
const { onRequest } = require("firebase-functions/v2/https");

const { isValidOpaqueUid } = require("./identity");
const {
  RTC_BINDING_KINDS,
  isServerRtcNamespace,
  isVersionedAnchor,
  resolveRtcBindingForLiveKitRoom,
} = require("../servers/rtc_binding");
const {
  AchievementOutboxValidationError,
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
// A V1 channel session's participant row carries the session roles of the
// reviewed server runtime, not the legacy speaker vocabulary.
const SERVER_SESSION_ROLES = new Set(["host", "guest", "listener"]);
// A `srv_` room name that does not prove out reciprocally is acknowledged
// and dropped: no attribution to a guessed room, no retry storm from LiveKit.
const SKIPPED_UNBOUND_RTC_NAME = "skipped:unbound-rtc-name";

const livekitAchievementApiKey = defineSecret("LIVEKIT_API_KEY");
const livekitAchievementApiSecret = defineSecret("LIVEKIT_API_SECRET");

class VoiceAchievementStoreError extends Error {
  constructor(message) {
    super(message);
    this.name = "VoiceAchievementStoreError";
  }
}

/**
 * Internal control-flow signal for a `srv_` name with no proven binding.
 * `reason` is one of the closed-set resolver constants, never event data.
 */
class UnboundServerRtcNameError extends Error {
  constructor(reason) {
    super("The LiveKit room name is not bound to a server channel session.");
    this.name = "UnboundServerRtcNameError";
    this.reason = reason;
  }
}

function skippedUnboundRtcName(eventType, reason, sessionId = null) {
  logger.warn("livekit achievement webhook skipped an unbound server rtc name", {
    eventType,
    reason,
  });
  return { outcome: SKIPPED_UNBOUND_RTC_NAME, reason, sessionId };
}

function storedRtcBinding(binding) {
  return Object.freeze({
    kind: RTC_BINDING_KINDS.V1,
    serverId: binding.serverId,
    channelId: binding.channelId,
    sessionId: binding.sessionId,
  });
}

function validStoredRtcBinding(value) {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value) &&
    value.kind === RTC_BINDING_KINDS.V1 && Boolean(safeSegment(value.serverId)) &&
    Boolean(safeSegment(value.channelId)) && Boolean(safeSegment(value.sessionId));
}

function participantBindsSession(participant, uid, binding) {
  return participant.serverSchemaVersion === 1 &&
    participant.serverId === binding.serverId &&
    participant.channelId === binding.channelId &&
    participant.roomId === binding.roomId &&
    participant.sessionId === binding.sessionId &&
    participant.userId === uid &&
    SERVER_SESSION_ROLES.has(participant.role);
}

function safeSegment(value) {
  return typeof value === "string" && SAFE_SEGMENT.test(value) ? value : null;
}

/**
 * Distinguishes "this delivery will never succeed" from "try again later".
 *
 * The distinction is load-bearing twice over. At the HTTP edge a permanent
 * failure must not be answered 503, or LiveKit retries a hopeless delivery
 * until its budget is exhausted. Inside `closeRoom` it decides whether one
 * session's failure may be skipped past — a deterministic failure will fail
 * identically on every retry, so skipping it is the only way the other
 * participants in the room ever get credited, whereas a transient failure
 * genuinely deserves the whole request to be retried.
 */
function isPermanentFailure(error) {
  return error instanceof VoiceAchievementStoreError ||
    error instanceof VoiceWebhookValidationError ||
    error instanceof AchievementOutboxValidationError ||
    error instanceof RangeError ||
    error instanceof TypeError;
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
  // A V1 session's provider name is its `srv_` generation, not the anchor
  // room id the session is attributed to; a legacy session's name is its id.
  if (expectedSession && (
    normalized.roomSid !== expectedSession.roomSid ||
    normalized.roomName !== (expectedSession.livekitRoomName ?? expectedSession.roomId) ||
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
  // A legacy session stores neither field. A V1 session stores both, and
  // they must agree with each other and with the anchor-based attribution.
  const versioned = raw.livekitRoomName !== undefined || raw.rtcBinding !== undefined;
  if (versioned && (!safeSegment(raw.livekitRoomName) ||
      !isServerRtcNamespace(raw.livekitRoomName) || !validStoredRtcBinding(raw.rtcBinding))) {
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
    ...(versioned
      ? { livekitRoomName: raw.livekitRoomName, rtcBinding: storedRtcBinding(raw.rtcBinding) }
      : {}),
  });
}

function sessionMatchesJoin(raw, session) {
  return raw?.roomId === session.roomId && raw?.roomSid === session.roomSid &&
    raw?.participantSid === session.participantSid &&
    raw?.userId === session.userId && raw?.joinedAtMs === session.joinedAtMs &&
    raw?.isHost === session.isHost && raw?.joinEventId === session.joinEventId &&
    (raw?.livekitRoomName ?? null) === (session.livekitRoomName ?? null);
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

  /**
   * Resolves a `srv_` room name to its server channel session. `live` demands
   * a currently bound (`live`/`ending`) generation, which a join needs; a
   * close only needs the structurally proven generation, the way the legacy
   * close path needs the room to exist rather than to be live. Authority is
   * never taken from the name: the resolver proves the reciprocal
   * room -> channel -> channelSession binding or the event is skipped.
   */
  async _serverRtcBinding(transaction, roomName, { live }) {
    const binding = await resolveRtcBindingForLiveKitRoom({
      db: this.database(),
      transaction,
      livekitRoomName: roomName,
    });
    const generation = binding.retained;
    if (!generation || (live && !binding.bound)) {
      throw new UnboundServerRtcNameError(binding.reason ?? "session-not-live");
    }
    return Object.freeze({
      roomId: generation.roomId,
      serverId: generation.serverId,
      channelId: generation.channelId,
      sessionId: generation.sessionId,
      livekitRoomName: generation.livekitRoomName,
      startedById: generation.startedById,
    });
  }

  async _canonicalJoin(transaction, webhook) {
    const database = this.database();
    const roomName = safeSegment(webhook.roomName);
    if (!roomName || !isValidOpaqueUid(webhook.participantIdentity)) {
      throw new VoiceAchievementStoreError("Webhook identity is not canonical.");
    }
    const binding = isServerRtcNamespace(roomName)
      ? await this._serverRtcBinding(transaction, roomName, { live: true })
      : null;
    const roomId = binding ? binding.roomId : roomName;
    const roomRef = database.collection("rooms").doc(roomId);
    const roomSnapshot = await transaction.get(roomRef);
    const room = snapshotData(roomSnapshot);
    // A legacy-namespace name reaches legacy rooms only. A versioned anchor's
    // media lives solely under its generation's `srv_` name, so a provider
    // room that merely shares the anchor id carries no authority over it.
    if (!binding && isVersionedAnchor(room)) {
      throw new VoiceAchievementStoreError("A versioned room has no legacy media namespace.");
    }
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
    // A V1 participant row is bound to one generation; it must name the
    // resolved session, not merely sit under the anchor room.
    const participantAuthorized = Boolean(participant) && participant.banned !== true && (
      binding
        ? participantBindsSession(participant, uid, binding)
        : participant.userId === uid && PARTICIPANT_ROLES.has(participant.role)
    );
    if (!participantAuthorized || !activeProfile(profile) ||
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
    if (!binding) {
      return voiceSessionFromJoin(webhook, { id: roomId, hostId: room.hostId });
    }
    // The session is attributed to its anchor room exactly like a legacy
    // event for that room; the provider name is retained so later closes
    // for the same `srv_` generation bind to this join. The session host is
    // the generation's starter, which is what the V1 participant role means.
    const session = voiceSessionFromJoin(
      { ...webhook, roomName: roomId },
      { id: roomId, hostId: binding.startedById },
    );
    return Object.freeze({
      ...session,
      livekitRoomName: binding.livekitRoomName,
      rtcBinding: storedRtcBinding(binding),
    });
  }

  async _closeAuthority(transaction, session, occurredAtMs) {
    const database = this.database();
    const references = [
      database.collection("rooms").doc(session.roomId),
      database.collection("users").doc(session.userId),
      database.collection("restrictions").doc(session.userId),
    ];
    // A V1 session's host is its generation's starter, so the retained
    // channelSession, not the anchor's owner field, re-proves the host claim.
    if (session.rtcBinding) {
      references.push(database.collection("clubs").doc(session.rtcBinding.serverId)
        .collection("channels").doc(session.rtcBinding.channelId)
        .collection("channelSessions").doc(session.rtcBinding.sessionId));
    }
    const [roomSnapshot, userSnapshot, restrictionSnapshot, generationSnapshot] =
      typeof transaction.getAll === "function"
        ? await transaction.getAll(...references)
        : await Promise.all(references.map((reference) => transaction.get(reference)));
    const room = snapshotData(roomSnapshot);
    const profile = snapshotData(userSnapshot);
    const restriction = snapshotData(restrictionSnapshot);
    let hostAuthority;
    if (session.rtcBinding) {
      const generation = snapshotData(generationSnapshot);
      hostAuthority = Boolean(generation) && generation.serverSchemaVersion === 1 &&
        generation.serverId === session.rtcBinding.serverId &&
        generation.channelId === session.rtcBinding.channelId &&
        generation.roomId === session.roomId &&
        generation.sessionId === session.rtcBinding.sessionId &&
        generation.livekitRoomName === session.livekitRoomName &&
        isValidOpaqueUid(generation.startedById) &&
        (generation.startedById === session.userId) === session.isHost;
    } else {
      hostAuthority = Boolean(room) && isValidOpaqueUid(room.hostId) &&
        (room.hostId === session.userId) === session.isHost;
    }
    return Boolean(room && activeProfile(profile) && hostAuthority &&
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
      // The day's ledger was already full, so this session earned nothing.
      // It still closes — the alternative was a permanently open document.
      saturated: plan.saturated === true,
      creditedVoiceSeconds: plan.voiceSecondsAdded,
      creditedHostSeconds: plan.hostSecondsAdded,
      outboxIds: outboxRecords.map((record) => record.eventId),
      closedAt: createdAt,
      updatedAt: createdAt,
      expiresAt: new Date(createdAt.getTime() + SESSION_RETENTION_MS),
    });
    return {
      outcome: plan.saturated === true ? "closed:ledger-saturated" : "closed",
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
      let session;
      try {
        session = await this._canonicalJoin(transaction, webhook);
      } catch (error) {
        if (!(error instanceof UnboundServerRtcNameError)) throw error;
        return skippedUnboundRtcName(webhook.type, error.reason, sessionId);
      }
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
            (existing.livekitRoomName ?? null) !== (session.livekitRoomName ?? null) ||
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
      // A close for a room or an account this project has never heard of must
      // not mint a permanent document. Before this check, `recordJoin`
      // re-derived everything through `_canonicalJoin` while this path took
      // roomId, roomSid, participantSid and userId verbatim from the event and
      // wrote them — so any join that failed validation for any reason still
      // got its close, and that close became an orphan row that nothing ever
      // collects.
      //
      // Deliberately an EXISTENCE check and nothing more. By the time a close
      // arrives the room has usually ended and the participant row is gone, so
      // requiring `status`/`isLive`/membership here — the way the join path
      // rightly does — would reject the ordinary case. Two documents, one
      // round trip: this path must not become as expensive as the join path.
      const closeRoomName = safeSegment(close.roomName);
      if (!closeRoomName) return { outcome: "skipped:unknown-session", sessionId };
      // A `srv_` name is attributed to its proven anchor, live or not: the
      // generation has usually ended by the time its last close arrives.
      let closeBinding = null;
      if (isServerRtcNamespace(closeRoomName)) {
        try {
          closeBinding = await this._serverRtcBinding(transaction, closeRoomName, { live: false });
        } catch (error) {
          if (!(error instanceof UnboundServerRtcNameError)) throw error;
          return skippedUnboundRtcName(close.type, error.reason, sessionId);
        }
      }
      const closeRoomId = closeBinding ? closeBinding.roomId : closeRoomName;
      const [roomSnapshot, profileSnapshot] =
        typeof transaction.getAll === "function"
          ? await transaction.getAll(
              database.collection("rooms").doc(closeRoomId),
              database.collection("users").doc(close.participantIdentity),
            )
          : await Promise.all([
              transaction.get(database.collection("rooms").doc(closeRoomId)),
              transaction.get(
                database.collection("users").doc(close.participantIdentity),
              ),
            ]);
      const closeRoom = snapshotData(roomSnapshot);
      // A legacy-namespace close names a legacy room only; a versioned anchor
      // that shares the id is not that room, so no awaiting-join row is kept
      // for a join the legacy path would reject anyway.
      if (!closeRoom || !snapshotData(profileSnapshot) ||
          (!closeBinding && isVersionedAnchor(closeRoom))) {
        return { outcome: "skipped:unknown-session", sessionId };
      }
      const createdAt = new Date(close.createdAtMs);
      transaction.create(reference, {
        schemaVersion: VOICE_SESSION_SCHEMA_VERSION,
        sessionId,
        status: "awaitingJoin",
        roomId: closeRoomId,
        ...(closeBinding
          ? { livekitRoomName: closeRoomName, rtcBinding: storedRtcBinding(closeBinding) }
          : {}),
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
    // PER-SESSION ISOLATION. This loop used to let the first failing session
    // propagate out, which became a 400 — so every co-participant ordered
    // after it in `__name__` was never reached, was never credited, and was
    // left with an open session document, while the 400 told LiveKit not to
    // retry. One account's private ledger state must never decide whether a
    // different account gets credited for talking, however narrow the victim
    // set is. Deterministic failures are therefore skipped and counted;
    // transient ones still abort so the whole delivery is retried, which is
    // safe because closed sessions are skipped on re-entry and each retry
    // makes monotone progress.
    const results = [];
    const failures = [];
    for (const document of snapshot.docs) {
      const raw = document.data() ?? {};
      // A V1 session finishes under its `srv_` generation name; a legacy
      // session finishes under the room id it stores.
      if ((raw.livekitRoomName ?? raw.roomId) !== webhook.roomName ||
          raw.roomSid !== webhook.roomSid) {
        failures.push("not-canonical");
        continue;
      }
      if (raw.status !== "open") continue;
      try {
        results.push(await this._closeKnownSession(document.ref, webhook));
      } catch (error) {
        if (!isPermanentFailure(error)) throw error;
        failures.push(error.name);
      }
    }
    return {
      outcome: failures.length > 0 ? "room-closed:partial" : "room-closed",
      sessionCount: results.length,
      failureCount: failures.length,
      results,
    };
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
  now = () => Date.now(),
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
        now,
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
      // Permanent means permanent: a RangeError from a counter overflow, a
      // TypeError from a malformed effect and a poisoned outbox record all
      // fail identically on every retry, so answering 503 would only spend
      // LiveKit's retry budget on a delivery that can never succeed. Only
      // genuinely transient faults — Firestore UNAVAILABLE, ABORTED, deadline
      // — are worth retrying.
      if (isPermanentFailure(error)) {
        // The two voice error classes carry static, non-interpolated messages
        // by construction. The others may not, so only their class is logged:
        // a Firestore or engine message can quote a document path, and those
        // paths contain uids.
        const staticReason = error instanceof VoiceAchievementStoreError ||
          error instanceof VoiceWebhookValidationError;
        logger.warn("livekit achievement webhook rejected a signed event", {
          eventType: webhook.type,
          errorName: error?.name ?? null,
          reason: staticReason ? error.message : null,
        });
        response.status(400).json({ accepted: false, error: "invalid-source" });
        return;
      }
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
  SKIPPED_UNBOUND_RTC_NAME,
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
