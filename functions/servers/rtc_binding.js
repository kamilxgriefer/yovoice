const { HttpsError } = require("firebase-functions/v2/https");

const { canonicalLiveKitRoomName } = require("./contract");

/**
 * Canonical RTC binding resolver for the global consumers that sit outside
 * the V1 session runtime: staff voice enforcement, the legacy active-session
 * mirror cleanup and the achievement webhook.
 *
 * A legacy room uses its own document id as the LiveKit namespace. A V1
 * channel session uses an immutable, generation-specific `srv_` name derived
 * from server, channel and session ids. Authority is never derived from the
 * name alone: every V1 answer is proved through the reciprocal
 * room -> channel -> channelSession binding, exactly the way the reviewed
 * session runtime validates it, and anything that does not prove out is a
 * fail-closed "no live binding" result rather than a legacy fallback.
 *
 * Two levels of answer exist on purpose. `bound: true` means the generation
 * is `live` or `ending` right now and is the only target a provider call may
 * use. `retained` is the structurally proven generation regardless of
 * status: it lets a late provider event (a participant leaving after the
 * session ended) be attributed to its anchor without ever guessing a room,
 * the same way the legacy close path needs existence, not liveness.
 * `pointers` lists every generation id the anchor room or its channel still
 * names (`activeSessionId`, `voiceSessionId`, `serverSessionCleanupId`),
 * proven or not, so a destructive consumer can fence on them even when the
 * graph does not prove out.
 *
 * Every answer is read from one consistent snapshot: a caller that supplies
 * no transaction gets a read-only one, so a start or end committing between
 * the room, channel and session reads can never produce a torn verdict.
 *
 * This module registers nothing and performs no writes. The session-domain
 * validators are required lazily so a legacy-only cold start does not load
 * the server runtime (the same convention as utils/server_access.js).
 */

const SERVER_RTC_ROOM_NAME = /^srv_[a-f0-9]{40}$/u;
const SERVER_RTC_PREFIX = "srv_";
const SAFE_ID = /^[A-Za-z0-9_-]{1,128}$/u;
const SESSION_PATH_LENGTH = 6;
const MAX_NAME_MATCHES = 2;

const RTC_BINDING_KINDS = Object.freeze({ LEGACY: "legacy", V1: "v1" });
const BOUND_SESSION_STATUSES = Object.freeze(["live", "ending"]);
const RTC_BINDING_REASONS = Object.freeze({
  MALFORMED_NAME: "malformed-rtc-name",
  UNKNOWN_NAME: "unknown-rtc-name",
  AMBIGUOUS_NAME: "ambiguous-rtc-name",
  MALFORMED_ANCHOR: "malformed-anchor",
  MISSING_ANCHOR: "missing-anchor",
  CHANNEL_MISMATCH: "channel-mismatch",
  SESSION_MISMATCH: "session-mismatch",
  NO_ACTIVE_SESSION: "no-active-session",
  SESSION_NOT_LIVE: "session-not-live",
  LIVENESS_MISMATCH: "liveness-mismatch",
});

function safeId(value) {
  return typeof value === "string" && SAFE_ID.test(value) ? value : null;
}

/** Whether a LiveKit room name sits in the V1 namespace at all. */
function isServerRtcNamespace(value) {
  return typeof value === "string" && value.startsWith(SERVER_RTC_PREFIX);
}

/** Whether a LiveKit room name is a well-formed V1 generation name. */
function isServerRtcRoomName(value) {
  return typeof value === "string" && SERVER_RTC_ROOM_NAME.test(value);
}

/**
 * The same classification `assertLegacyRoomAccess` applies: any version
 * marker makes the room a versioned boundary, even a malformed one. A
 * malformed versioned anchor is never a legacy room.
 */
function isVersionedAnchor(room) {
  return Boolean(room) && typeof room === "object" &&
    (Object.hasOwn(room, "serverSchemaVersion") || Object.hasOwn(room, "serverId"));
}

/** The canonical V1 RTC name, or null when any id is not a safe segment. */
function serverRtcRoomNameFor(serverId, channelId, sessionId) {
  if (!safeId(serverId) || !safeId(channelId) || !safeId(sessionId)) return null;
  return canonicalLiveKitRoomName(serverId, channelId, sessionId);
}

/**
 * Whether an activeVoiceSessions mirror belongs to exactly this resolved
 * generation for this identity: the reviewed runtime's `mirrorBelongsTo`
 * seam, applied to a consumer-side binding.
 */
function mirrorBindsToSession(mirror, binding, userId) {
  if (!mirror || typeof mirror !== "object" || !binding || binding.kind !== RTC_BINDING_KINDS.V1 ||
      binding.bound !== true || !safeId(userId)) return false;
  const { mirrorBelongsTo } = require("./session_control");
  return mirrorBelongsTo(mirror, {
    serverId: binding.serverId, channelId: binding.channelId, roomId: binding.roomId,
    sessionId: binding.sessionId, livekitRoomName: binding.livekitRoomName,
    userId, participantIdentity: userId,
  });
}

/**
 * Whether an activeVoiceSessions mirror is a V1 mirror of this anchor at all,
 * for any generation. Used by cleanup to tell "a generation of this anchor"
 * from a legacy-shaped or foreign document before applying a generation fence.
 */
function mirrorIsVersionedForAnchor(mirror, anchor, userId) {
  return Boolean(mirror) && typeof mirror === "object" && mirror.serverSchemaVersion === 1 &&
    Boolean(anchor) && mirror.serverId === anchor.serverId && mirror.channelId === anchor.channelId &&
    mirror.roomId === anchor.roomId && mirror.userId === userId && mirror.participantIdentity === userId &&
    safeId(mirror.sessionId) !== null &&
    mirror.livekitRoomName === serverRtcRoomNameFor(anchor.serverId, anchor.channelId, mirror.sessionId);
}

/**
 * Whether a V1 answer failed to bind while its structurally proven
 * generation is still `live` or `ending`: media may be connected under that
 * generation's `srv_` name although the graph does not prove liveness. A
 * consumer must neither treat that as "nothing to do" nor destroy the
 * generation's state on the strength of the anchor id.
 */
function hasUnboundLiveGeneration(binding) {
  return Boolean(binding) && binding.kind === RTC_BINDING_KINDS.V1 && binding.bound === false &&
    Boolean(binding.retained) && BOUND_SESSION_STATUSES.includes(binding.retained.status);
}

const NO_POINTERS = Object.freeze([]);

function legacyBinding(roomId) {
  return Object.freeze({
    kind: RTC_BINDING_KINDS.LEGACY, bound: true, roomId, livekitRoomName: roomId, reason: null,
    anchor: null, retained: null, pointers: NO_POINTERS,
  });
}

function unbound(reason, { anchor = null, retained = null, pointers = NO_POINTERS } = {}) {
  return Object.freeze({
    kind: RTC_BINDING_KINDS.V1, bound: false, reason, anchor, retained, pointers,
  });
}

/** The generation ids the anchor and its channel still name, proven or not. */
function generationPointers(room, channel) {
  const ids = [channel?.activeSessionId, room?.voiceSessionId, room?.serverSessionCleanupId]
    .map(safeId)
    .filter((value) => value !== null);
  return Object.freeze([...new Set(ids)]);
}

function anchorIdentity(roomId, room) {
  if (room.serverSchemaVersion !== 1 || room.clubId !== room.serverId) return null;
  const serverId = safeId(room.serverId);
  const channelId = safeId(room.channelId);
  if (!serverId || !channelId) return null;
  return Object.freeze({ roomId, serverId, channelId });
}

async function readDocument(db, transaction, path) {
  const reference = db.doc(path);
  const snapshot = transaction ? await transaction.get(reference) : await reference.get();
  return snapshot.exists ? snapshot.data() ?? null : null;
}

function channelBindsAnchor(channel, anchor) {
  return Boolean(channel) && channel.serverSchemaVersion === 1 &&
    channel.serverId === anchor.serverId && channel.roomId === anchor.roomId;
}

/**
 * Proves one retained channelSession against its anchor room and channel and
 * classifies its generation. Only `live` and `ending` are bound; a retained
 * generation in any other status is reported without provider authority.
 */
function evaluateSession({ anchor, room, channel, session, sessionId }) {
  const { assertSessionBinding } = require("./session_contract");
  const pointers = generationPointers(room, channel);
  const binding = { serverId: anchor.serverId, channelId: anchor.channelId, roomId: anchor.roomId, sessionId };
  let livekitRoomName;
  try {
    livekitRoomName = assertSessionBinding(session, binding);
  } catch (error) {
    if (!(error instanceof HttpsError)) throw error;
    return unbound(RTC_BINDING_REASONS.SESSION_MISMATCH, { anchor, pointers });
  }
  const retained = Object.freeze({
    ...binding, livekitRoomName, status: session.status, startedById: session.startedById,
  });
  if (!BOUND_SESSION_STATUSES.includes(session.status)) {
    return unbound(RTC_BINDING_REASONS.SESSION_NOT_LIVE, { anchor, retained, pointers });
  }
  const consistent = session.status === "live"
    ? channel.activeSessionId === sessionId && room.isLive === true &&
      room.voiceSessionId === sessionId && room.livekitRoomName === livekitRoomName &&
      room.serverSessionCleanupId == null
    : channel.activeSessionId === null && room.isLive === false &&
      room.voiceSessionId === null && room.livekitRoomName === null &&
      room.serverSessionCleanupId === sessionId && typeof session.endOperationId === "string";
  if (!consistent) return unbound(RTC_BINDING_REASONS.LIVENESS_MISMATCH, { anchor, retained, pointers });
  return Object.freeze({
    kind: RTC_BINDING_KINDS.V1, bound: true, ...binding, livekitRoomName,
    status: session.status, authorizationRevision: session.authorizationRevision,
    startedById: session.startedById, anchor, retained, pointers, reason: null,
  });
}

async function resolveVersionedAnchor({ db, transaction, roomId, room }) {
  const anchor = anchorIdentity(roomId, room);
  if (!anchor) return unbound(RTC_BINDING_REASONS.MALFORMED_ANCHOR);
  const channel = await readDocument(db, transaction, `clubs/${anchor.serverId}/channels/${anchor.channelId}`);
  const pointers = generationPointers(room, channel);
  if (!channelBindsAnchor(channel, anchor)) {
    return unbound(RTC_BINDING_REASONS.CHANNEL_MISMATCH, { anchor, pointers });
  }
  // The active pointer names the live generation; an ending generation keeps
  // only the anchor's cleanup barrier while the worker drains it.
  const sessionId = safeId(channel.activeSessionId) ?? safeId(room.serverSessionCleanupId);
  if (!sessionId) return unbound(RTC_BINDING_REASONS.NO_ACTIVE_SESSION, { anchor, pointers });
  const session = await readDocument(db, transaction,
    `clubs/${anchor.serverId}/channels/${anchor.channelId}/channelSessions/${sessionId}`);
  if (!session) return unbound(RTC_BINDING_REASONS.SESSION_MISMATCH, { anchor, pointers });
  return evaluateSession({ anchor, room, channel, session, sessionId });
}

/**
 * Runs a multi-document resolution on one consistent snapshot. A caller's
 * own transaction is used as is; otherwise a read-only transaction is opened
 * so the room, channel and session reads can never straddle a commit.
 */
function withSnapshot(db, transaction, resolve) {
  if (transaction) return resolve(transaction);
  if (typeof db.runTransaction !== "function") throw new TypeError("A Firestore database is required.");
  return db.runTransaction(resolve, { readOnly: true });
}

async function resolveRoomIn(db, transaction, id) {
  const room = await readDocument(db, transaction, `rooms/${id}`);
  if (!isVersionedAnchor(room)) return legacyBinding(id);
  return resolveVersionedAnchor({ db, transaction, roomId: id, room });
}

/**
 * Resolves the binding for a media anchor room id (a `rooms/{roomId}`
 * document). Legacy rooms, including unknown ids, keep their id as the RTC
 * namespace; a versioned anchor must prove a live or ending generation.
 */
async function resolveRtcBindingForRoom({ db, transaction = null, roomId }) {
  if (!db || typeof db.doc !== "function") throw new TypeError("A Firestore database is required.");
  const id = safeId(roomId);
  if (!id) return legacyBinding(roomId);
  return withSnapshot(db, transaction, (current) => resolveRoomIn(db, current, id));
}

async function resolveLiveKitRoomIn(db, transaction, livekitRoomName) {
  const query = db.collectionGroup("channelSessions")
    .where("livekitRoomName", "==", livekitRoomName)
    .limit(MAX_NAME_MATCHES);
  const matches = await transaction.get(query);
  if (matches.empty) return unbound(RTC_BINDING_REASONS.UNKNOWN_NAME);
  if (matches.size > 1) return unbound(RTC_BINDING_REASONS.AMBIGUOUS_NAME);
  const document = matches.docs[0];
  const segments = document.ref.path.split("/");
  const session = document.data() ?? {};
  if (segments.length !== SESSION_PATH_LENGTH || segments[0] !== "clubs" ||
      segments[2] !== "channels" || segments[4] !== "channelSessions" ||
      session.serverId !== segments[1] || session.channelId !== segments[3] ||
      session.sessionId !== segments[5] ||
      serverRtcRoomNameFor(segments[1], segments[3], segments[5]) !== livekitRoomName) {
    return unbound(RTC_BINDING_REASONS.SESSION_MISMATCH);
  }
  const roomId = safeId(session.roomId);
  if (!roomId) return unbound(RTC_BINDING_REASONS.SESSION_MISMATCH);
  const room = await readDocument(db, transaction, `rooms/${roomId}`);
  if (!room) return unbound(RTC_BINDING_REASONS.MISSING_ANCHOR);
  const anchor = isVersionedAnchor(room) ? anchorIdentity(roomId, room) : null;
  if (!anchor || anchor.serverId !== segments[1] || anchor.channelId !== segments[3]) {
    return unbound(RTC_BINDING_REASONS.MALFORMED_ANCHOR);
  }
  const channel = await readDocument(db, transaction, `clubs/${anchor.serverId}/channels/${anchor.channelId}`);
  if (!channelBindsAnchor(channel, anchor)) {
    return unbound(RTC_BINDING_REASONS.CHANNEL_MISMATCH, { anchor, pointers: generationPointers(room, channel) });
  }
  return evaluateSession({ anchor, room, channel, session, sessionId: segments[5] });
}

/**
 * Resolves the binding for a LiveKit room name. Names outside the `srv_`
 * namespace are the legacy room id. A `srv_` name is located through a
 * bounded collectionGroup('channelSessions') query on `livekitRoomName`
 * (a COLLECTION_GROUP field index is required in production) and then
 * proved reciprocally: the session document's path, its stored ids, the
 * canonical name derivation, its anchor room and its channel must all agree.
 */
async function resolveRtcBindingForLiveKitRoom({ db, transaction = null, livekitRoomName }) {
  if (!db || typeof db.collectionGroup !== "function") throw new TypeError("A Firestore database is required.");
  if (!isServerRtcNamespace(livekitRoomName)) return legacyBinding(livekitRoomName);
  if (!isServerRtcRoomName(livekitRoomName)) return unbound(RTC_BINDING_REASONS.MALFORMED_NAME);
  return withSnapshot(db, transaction, (current) => resolveLiveKitRoomIn(db, current, livekitRoomName));
}

module.exports = {
  BOUND_SESSION_STATUSES,
  RTC_BINDING_KINDS,
  RTC_BINDING_REASONS,
  hasUnboundLiveGeneration,
  isServerRtcNamespace,
  isServerRtcRoomName,
  isVersionedAnchor,
  mirrorBindsToSession,
  mirrorIsVersionedForAnchor,
  resolveRtcBindingForLiveKitRoom,
  resolveRtcBindingForRoom,
  serverRtcRoomNameFor,
};
