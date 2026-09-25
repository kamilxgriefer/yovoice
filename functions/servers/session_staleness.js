const { randomBytes } = require("node:crypto");
const { FieldPath } = require("firebase-admin/firestore");
const { HttpsError } = require("firebase-functions/v2/https");
const { digest, requireSafeInteger, timestampMillis, transactionGetAll } = require("../integrity/guards");
const { canonicalServer } = require("./authority");
const { MAX_SERVER_CHANNELS, canonicalLiveKitRoomName, channelLiveness } = require("./contract");
const { readConvergenceBindings, stageConvergenceSessionEnd } = require("./convergence_lifecycle");
const { isServerRtcRoomName, isVersionedAnchor, resolveRtcBindingForLiveKitRoom } = require("./rtc_binding");
const { SESSION_TOKEN_TTL_SECONDS, assertSessionBinding, tokenRecipientId } = require("./session_contract");

// THE BOUND ON A V1 GENERATION NOBODY IS IN ANY MORE (ADR-180 and its
// amendment for the last-leave grace).
//
// `liveness.isLive` means "a generation is open", and nothing closed a
// generation whose participants all left: the legacy sweeper skips versioned
// anchors by design, so a LIVE badge could persist long after the room
// emptied. This module stages such a generation for end THROUGH THE SAME
// WRITER AND WORKER every authorized end already uses —
// `stageConvergenceSessionEnd` plus the `sessionEnd` outbox job that
// `session_control.js` drains — so there is no second state machine and no
// second teardown path. It decides only WHEN a generation is over, from one
// of two proofs:
//
//   A. THE EMPTY-GENERATION GRACE (release callable, provider `room_finished`,
//      then this sweep). A server-clock observation that the provider room was
//      empty is stored on the private session document
//      (`emptyObservation`). It is recorded only when nobody else is in the
//      room and nobody was admitted in the last ADMISSION_WINDOW_MS, and the
//      generation ends only when, at least EMPTY_GENERATION_GRACE_MS later, the
//      room is STILL empty and nobody was admitted since the observation. A
//      rejoin inside the grace mints a token, which moves
//      `maxTokenExpiresAtMillis` and writes `tokenRecipients.lastIssuedAt`,
//      so the observation no longer describes this generation and nothing
//      ends. No client clock is read anywhere: every instant is this
//      backend's own clock.
//   B. THE ORIGINAL ADR-180 RULE, for a generation nobody observed emptying
//      (an old client and no provider webhook): every token it ever issued
//      expired at least one grace period ago, and the provider reports the
//      room empty or gone. A running observation still wins, so this path
//      cannot cut a reconnect grace short once one was recorded.
//
// Either way the staging transaction re-proves the whole reciprocal graph with
// `readConvergenceBindings` and re-reads `maxTokenExpiresAtMillis`: a token
// minted between the provider reading and the commit moves the bound forward,
// so the commit is refused as `changed`. A provider error or a malformed
// answer is an unknown, and an unknown never ends a generation.
//
// The sweep also repairs PROJECTION DRIFT: a channel whose public
// `liveness.isLive` is still true although no live generation backs it would
// never be seen by the anchor scan above. Only two provably dead shapes are
// written (see classifyChannelProjection); every other shape is counted and
// left alone, and a projection that names a live generation is never touched.

// One token TTL, and the same five minutes as the legacy sweep's
// GRACE_PERIOD_SECONDS: under rule B a generation is not stale until the last
// admission it could have granted has been impossible for a full TTL.
const STALE_GENERATION_GRACE_MS = SESSION_TOKEN_TTL_SECONDS * 1000;
// decisions.md (2026-09-19): the channel session ends when the last
// participant leaves, after a short reconnect grace. A rejoin inside it keeps
// the generation; a room still empty after it ends it.
const EMPTY_GENERATION_GRACE_MS = 60_000;
// A token issued this recently may belong to somebody who is still
// connecting, so an empty provider room is not yet evidence of emptiness.
const ADMISSION_WINDOW_MS = 30_000;
// A public projection that claims a live generation which cannot be proven
// (and whose provider room is empty) is reset after this long.
const MAX_UNPROVEN_LIVE_AGE_MS = 24 * 60 * 60 * 1000;
// The legacy sweep's scan bound, for the same bare `isLive == true` query
// served by the automatic single-field index: no composite index to deploy.
const MAX_LIVE_ANCHOR_SCAN = 200;
// Versioned servers visited per sweep for projection drift, each with one
// single-field `liveness.isLive == true` query on its own channels. No
// collection-group index is needed; a random start spreads a bounded scan.
const MAX_DRIFT_SERVER_SCAN = 200;
const SERVER_PAGE_SIZE = 50;
const EMPTY_OBSERVATION_VERSION = 1;
const EMPTY_OBSERVATION_SOURCES = Object.freeze(["release", "providerFinished", "sweep"]);
const STAGING_KINDS = Object.freeze({ stale: "server.session.stale.v1", empty: "server.session.empty.v1" });
const TERMINAL_SESSION_STATUSES = Object.freeze(["ending", "ended", "failed"]);
const PROJECTION_REPAIRS = Object.freeze(["reset-null-session", "reset-terminal-session", "reset-max-age"]);

const SAFE_ID = /^[A-Za-z0-9_-]{1,128}$/u;
const safeId = (value) => (typeof value === "string" && SAFE_ID.test(value) ? value : null);

function anchorFor(roomId, room) {
  if (room.serverSchemaVersion !== 1 || room.clubId !== room.serverId) return null;
  const serverId = safeId(room.serverId);
  const channelId = safeId(room.channelId);
  const sessionId = safeId(room.voiceSessionId);
  if (!serverId || !channelId || !sessionId) return null;
  return { serverId, channelId, roomId, sessionId };
}

function lastAdmissionMillis(session) {
  return Math.max(timestampMillis(session.startedAt) ?? 0, session.maxTokenExpiresAtMillis);
}

/**
 * The recorded empty-room observation, or null. It describes this generation
 * only while no token was minted since it was taken: the stored bound must
 * equal the session's current `maxTokenExpiresAtMillis`. A malformed value is
 * treated as absent — it can delay an end, never cause one.
 */
function emptyObservation(session) {
  const value = session?.emptyObservation;
  if (!value || typeof value !== "object" || Array.isArray(value) ||
      value.schemaVersion !== EMPTY_OBSERVATION_VERSION ||
      !EMPTY_OBSERVATION_SOURCES.includes(value.source) ||
      !Number.isSafeInteger(value.observedAtMillis) || value.observedAtMillis < 0 ||
      !Number.isSafeInteger(value.maxTokenExpiresAtMillis) ||
      value.maxTokenExpiresAtMillis !== session.maxTokenExpiresAtMillis) return null;
  return value;
}

function graceElapsed(observation, nowMs) {
  return nowMs - observation.observedAtMillis >= EMPTY_GENERATION_GRACE_MS;
}

function remainingGraceMillis(observation, nowMs) {
  return Math.min(EMPTY_GENERATION_GRACE_MS, Math.max(0, observation.observedAtMillis + EMPTY_GENERATION_GRACE_MS - nowMs));
}

/**
 * One provider occupancy reading, fail-closed. `excludeUid` is the leaving
 * caller of the release callable: the provider may still list them for a
 * moment after a clean disconnect, so they do not count as "somebody else".
 * An identity is only excluded when the provider really listed every
 * participant as a string identity; otherwise the raw count stands.
 */
function occupancyVerdict(occupancy, excludeUid = null) {
  const unknown = Object.freeze({ known: false, empty: false, othersEmpty: false, callerPresent: false });
  if (!occupancy || typeof occupancy !== "object" || !Number.isSafeInteger(occupancy.participantCount) ||
      occupancy.participantCount < 0) return unknown;
  const identities = occupancy.participantIdentities;
  // The adapter reports null identities for an answer that was not a list.
  if (identities === null) return unknown;
  const count = occupancy.participantCount;
  if (count === 0) return Object.freeze({ known: true, empty: true, othersEmpty: true, callerPresent: false });
  const listed = Array.isArray(identities) && identities.length === count &&
    identities.every((identity) => typeof identity === "string" && identity.length > 0);
  const callerPresent = listed && excludeUid !== null && identities.includes(excludeUid);
  const others = listed && excludeUid !== null ? identities.filter((identity) => identity !== excludeUid).length : count;
  return Object.freeze({ known: true, empty: false, othersEmpty: others === 0, callerPresent });
}

function stagedEntry(item, endOperationId) {
  return { outcome: "staged", ...item.binding, endOperationId };
}

function emptyOutcome() {
  return {
    scanned: 0, truncated: false, skippedLegacy: 0, skippedUnbound: 0, skippedYoung: 0,
    skippedOccupied: 0, providerUnavailable: 0, changed: 0, staged: [],
    stagedEmpty: 0, graceRunning: 0, driftRepaired: 0, driftUnresolved: 0, driftTruncated: false,
  };
}

/**
 * Pure classification of one channel whose public projection says live. Only
 * `reset-null-session` (no generation claims the channel: the exact terminal
 * fence of session_control.js) and `reset-terminal-session` (the claimed
 * generation is ending, ended, failed or missing and the anchor is idle) are
 * provably dead. `max-age-candidate` is a live-looking generation whose
 * anchor is idle, older than MAX_UNPROVEN_LIVE_AGE_MS; it is reset only after
 * the provider reports its room empty. `ok-live` belongs to the anchor scan.
 * Everything else is `unresolved` and is never written.
 */
function classifyChannelProjection({ serverId, channelId, channel, room, session, nowMs }) {
  if (!channel || channel.liveness?.isLive !== true) return "ok-idle";
  if (channel.serverSchemaVersion !== 1 || channel.serverId !== serverId || safeId(channel.roomId) === null) {
    return "unresolved";
  }
  if (room && !(room.serverSchemaVersion === 1 && room.serverId === serverId && room.clubId === serverId &&
      room.channelId === channelId)) return "unresolved";
  if (channel.activeSessionId === null) return "reset-null-session";
  const sessionId = safeId(channel.activeSessionId);
  if (!sessionId) return "unresolved";
  if (room?.isLive === true) {
    // The anchor claims a live generation. Either it is this one and the
    // anchor scan owns it, or the graph disagrees and an operator does.
    return room.voiceSessionId === sessionId && session?.status === "live" &&
      session.sessionId === sessionId ? "ok-live" : "unresolved";
  }
  const anchorIdle = !room || (room.isLive === false && room.voiceSessionId == null && room.livekitRoomName == null);
  if (!anchorIdle) return "unresolved";
  if (!session) return "reset-terminal-session";
  if (session.serverSchemaVersion !== 1 || session.serverId !== serverId || session.channelId !== channelId ||
      session.sessionId !== sessionId) return "unresolved";
  if (TERMINAL_SESSION_STATUSES.includes(session.status)) return "reset-terminal-session";
  const startedAt = timestampMillis(channel.liveness.startedAt);
  if (session.status === "live" && startedAt !== null && nowMs - startedAt >= MAX_UNPROVEN_LIVE_AGE_MS) {
    return "max-age-candidate";
  }
  return "unresolved";
}

/** Internal worker factory only. Registered by servers/registration.js as the
 * stale-generation schedule, and used by the release callable, the
 * `room_finished` webhook path and the repair script; no client reaches it. */
function createServerSessionStalenessService({
  db, Timestamp, livekit, clock = Date.now,
  random = () => `srv_${randomBytes(20).toString("hex")}`,
}) {
  if (!livekit || !["assertSupported", "roomOccupancy"].every((name) => typeof livekit[name] === "function")) {
    throw new TypeError("An occupancy-capable LiveKit adapter is required.");
  }
  if (typeof random !== "function") throw new TypeError("random must be a function.");

  function checkedNow() {
    const nowMs = clock();
    if (!Number.isSafeInteger(nowMs) || nowMs < 0) throw new TypeError("clock must return epoch milliseconds.");
    return nowMs;
  }

  /**
   * Whether somebody other than `excludeUid` was issued a token for this
   * generation after `sinceMillis`. Served by the automatic single-field
   * index on `tokenRecipients.lastIssuedAt`; read inside the caller's
   * transaction, so a concurrent issuance conflicts with the decision.
   */
  async function recentAdmission(transaction, sessionReference, sinceMillis, excludeUid = null) {
    const query = sessionReference.collection("tokenRecipients")
      .where("lastIssuedAt", ">", Timestamp.fromMillis(Math.max(0, sinceMillis))).limit(2);
    const snapshot = transaction ? await transaction.get(query) : await query.get();
    const excluded = excludeUid === null ? null : tokenRecipientId(excludeUid);
    return snapshot.docs.some((document) => document.id !== excluded);
  }

  /** The anchor's generation, re-proved inside a transaction exactly as
   * every authorized lifecycle writer demands before it may call
   * stageConvergenceSessionEnd, or null when anything short of that holds. */
  async function readBoundGeneration(transaction, anchor) {
    const serverReference = db.doc(`clubs/${anchor.serverId}`);
    const channelReference = serverReference.collection("channels").doc(anchor.channelId);
    const [root, channelSnapshot] = await transactionGetAll(transaction, serverReference, channelReference);
    let item;
    try {
      const server = canonicalServer(root);
      if (!channelSnapshot.exists) return null;
      [item] = await readConvergenceBindings({ db, transaction, serverId: anchor.serverId, server,
        channels: [{ id: anchor.channelId, reference: channelReference, channel: channelSnapshot.data() }] });
    } catch (error) {
      if (error instanceof HttpsError) return null;
      throw error;
    }
    if (!item?.session || item.session.status !== "live" || item.session.sessionId !== anchor.sessionId ||
        item.roomReference.id !== anchor.roomId) return null;
    return item;
  }

  function stageItem(transaction, item, reason, nowMs) {
    const now = Timestamp.fromMillis(nowMs);
    // Deterministic per generation and reason: a generation is staged at
    // most once, because staging is what takes it out of `live`.
    const identity = { id: digest(STAGING_KINDS[reason], item.binding) };
    const ending = stageConvergenceSessionEnd({ db, transaction, item, identity, now });
    transaction.update(item.roomReference, { ...ending.roomPatch, updatedAt: now });
    transaction.update(item.reference, { ...ending.channelPatch, revision: item.channel.revision + 1, updatedAt: now });
    return stagedEntry(item, ending.target.endOperationId);
  }

  /**
   * The shared staging step. `admissionCheck({transaction, item, nowMs})`
   * decides whether nobody can still be arriving; it may read (inside the
   * transaction) but never write. Runs in the caller's transaction when one is
   * supplied.
   */
  async function stageEmptyGeneration({
    anchor, observedMaxTokenExpiresAtMillis, reason = "empty", admissionCheck = null, transaction = null,
  }) {
    if (!Object.hasOwn(STAGING_KINDS, reason)) throw new TypeError("Unsupported staging reason.");
    const work = async (current) => {
      const item = await readBoundGeneration(current, anchor);
      // A token minted since the provider reading moved the bound; the
      // occupancy read no longer describes this generation.
      if (!item || item.session.maxTokenExpiresAtMillis !== observedMaxTokenExpiresAtMillis) return { outcome: "changed" };
      const nowMs = checkedNow();
      if (admissionCheck && !(await admissionCheck({ transaction: current, item, nowMs }))) return { outcome: "changed" };
      return stageItem(current, item, reason, nowMs);
    };
    return transaction ? work(transaction) : db.runTransaction(work);
  }

  /**
   * The empty-generation grace, one decision inside one transaction:
   *   - an observation at least EMPTY_GENERATION_GRACE_MS old, a provider
   *     room with nobody in it at all and no admission since the observation
   *     end the generation (`ended`);
   *   - somebody else present clears any observation (`occupied`);
   *   - a running observation is kept, never extended (`pending`);
   *   - otherwise a fresh observation is recorded (`pending`), unless a token
   *     was issued within the admission window (`occupied`).
   * `verdict` is the occupancy reading taken after
   * `observedMaxTokenExpiresAtMillis` was read.
   */
  async function settleEmptyGenerationWithin(transaction, {
    anchor, observedMaxTokenExpiresAtMillis, verdict, source, excludeUid = null, admissionSinceMillis = null,
  }) {
    if (!EMPTY_OBSERVATION_SOURCES.includes(source)) throw new TypeError("Unsupported observation source.");
    const item = await readBoundGeneration(transaction, anchor);
    if (!item || item.session.maxTokenExpiresAtMillis !== observedMaxTokenExpiresAtMillis) {
      return { outcome: "changed", recheckAfterMillis: 0 };
    }
    if (!verdict?.known) return { outcome: "occupied", recheckAfterMillis: 0 };
    const nowMs = checkedNow();
    const recorded = emptyObservation(item.session);
    // Every read happens before the first write.
    const admittedSinceObservation = recorded
      ? await recentAdmission(transaction, item.sessionReference, recorded.observedAtMillis) : false;
    const windowStart = Math.min(admissionSinceMillis ?? Number.MAX_SAFE_INTEGER, nowMs) - ADMISSION_WINDOW_MS;
    const admittedRecently = await recentAdmission(transaction, item.sessionReference, windowStart, excludeUid);
    const observation = recorded && !admittedSinceObservation ? recorded : null;
    if (observation && verdict.empty && graceElapsed(observation, nowMs)) {
      return { outcome: "ended", recheckAfterMillis: 0, staged: stageItem(transaction, item, "empty", nowMs) };
    }
    if (!verdict.othersEmpty) {
      // Somebody is here: the observed emptiness no longer holds.
      if (item.session.emptyObservation != null) transaction.update(item.sessionReference, { emptyObservation: null });
      return { outcome: "occupied", recheckAfterMillis: 0 };
    }
    if (observation) {
      // Running grace, or an elapsed one whose leaving caller the provider
      // still lists. Never extended: a later leaver does not buy more time.
      return { outcome: "pending", recheckAfterMillis: verdict.callerPresent ? 0 : remainingGraceMillis(observation, nowMs) };
    }
    if (admittedRecently) return { outcome: "occupied", recheckAfterMillis: 0 };
    transaction.update(item.sessionReference, { emptyObservation: {
      schemaVersion: EMPTY_OBSERVATION_VERSION, source, observedAtMillis: nowMs,
      maxTokenExpiresAtMillis: item.session.maxTokenExpiresAtMillis,
    } });
    return { outcome: "pending", recheckAfterMillis: EMPTY_GENERATION_GRACE_MS };
  }

  function settleEmptyGeneration(parameters) {
    return db.runTransaction((transaction) => settleEmptyGenerationWithin(transaction, parameters));
  }

  async function readSession(anchor) {
    const snapshot = await db.doc(`clubs/${anchor.serverId}/channels/${anchor.channelId}/channelSessions/${anchor.sessionId}`).get();
    return snapshot.exists ? snapshot.data() : null;
  }

  /**
   * The provider path: LiveKit sends `room_finished` once a room has been
   * empty for its departure timeout. It records (or completes) the same
   * grace the release callable does, so a crashed or killed client clears
   * without an app update. The provider's own timestamp only ever widens the
   * admission window; it can never shorten the grace.
   */
  async function stageFinishedProviderRoom({ livekitRoomName, finishedAtMs }) {
    if (!isServerRtcRoomName(livekitRoomName) || !Number.isSafeInteger(finishedAtMs) || finishedAtMs <= 0) {
      return { outcome: "skipped" };
    }
    livekit.assertSupported();
    const binding = await resolveRtcBindingForLiveKitRoom({ db, livekitRoomName });
    if (binding.bound !== true) return { outcome: "unbound" };
    if (binding.status !== "live") return { outcome: "not-live" };
    const anchor = { serverId: binding.serverId, channelId: binding.channelId, roomId: binding.roomId,
      sessionId: binding.sessionId };
    const session = await readSession(anchor);
    if (!session || session.status !== "live" || !Number.isSafeInteger(session.maxTokenExpiresAtMillis)) {
      return { outcome: "changed" };
    }
    let occupancy;
    try {
      occupancy = await livekit.roomOccupancy({ ...anchor, livekitRoomName: binding.livekitRoomName });
    } catch {
      return { outcome: "unknown" };
    }
    const verdict = occupancyVerdict(occupancy);
    if (!verdict.known || !verdict.empty) return { outcome: "occupied" };
    const settled = await settleEmptyGeneration({ anchor, observedMaxTokenExpiresAtMillis: session.maxTokenExpiresAtMillis,
      verdict, source: "providerFinished", admissionSinceMillis: finishedAtMs });
    return { outcome: settled.outcome };
  }

  /**
   * The provider half of a stale raised hand: LiveKit says `participantIdentity`
   * left (or its connection aborted) a `srv_` generation at `leftAtMs`. A hand
   * that person raised before leaving is lowered with `handDecision:
   * "lowered"`, so the host's queue never offers somebody who is not there
   * and the person reads why their request ended.
   *
   * Nothing is lowered while the provider still lists the identity (a
   * reconnect under a new participant SID, or a second device), when the
   * provider cannot say, for a hand raised after the departure instant, or
   * for any other generation. A hand is a request, not authority: no
   * revision moves and nothing is revoked. Replays converge on "unchanged".
   */
  async function lowerDepartedHand({ livekitRoomName, participantIdentity, leftAtMs }) {
    if (!isServerRtcRoomName(livekitRoomName) || typeof participantIdentity !== "string" ||
        participantIdentity.length === 0 || participantIdentity.length > 128 || participantIdentity.includes("/") ||
        !Number.isSafeInteger(leftAtMs) || leftAtMs <= 0) {
      return { outcome: "skipped" };
    }
    livekit.assertSupported();
    const binding = await resolveRtcBindingForLiveKitRoom({ db, livekitRoomName });
    if (binding.bound !== true) return { outcome: "unbound" };
    if (binding.status !== "live") return { outcome: "not-live" };
    const anchor = { serverId: binding.serverId, channelId: binding.channelId, roomId: binding.roomId,
      sessionId: binding.sessionId };
    const reference = db.doc(`rooms/${anchor.roomId}/participants/${participantIdentity}`);
    const raisedBefore = (value) => value?.serverSchemaVersion === 1 && value.serverId === anchor.serverId &&
      value.channelId === anchor.channelId && value.roomId === anchor.roomId &&
      value.sessionId === anchor.sessionId && value.userId === participantIdentity &&
      value.isHandRaised === true && (timestampMillis(value.handRaisedAt) ?? Number.MAX_SAFE_INTEGER) <= leftAtMs;
    const first = await reference.get();
    if (!first.exists || !raisedBefore(first.data())) return { outcome: "unchanged" };
    let occupancy;
    try {
      occupancy = await livekit.roomOccupancy({ ...anchor, livekitRoomName: binding.livekitRoomName });
    } catch {
      return { outcome: "unknown" };
    }
    const verdict = occupancyVerdict(occupancy, participantIdentity);
    if (!verdict.known) return { outcome: "unknown" };
    if (!verdict.empty) {
      // An empty room is an answer by itself; an occupied one is an answer
      // only when every listed identity can be compared with this one.
      const identities = occupancy.participantIdentities;
      if (!Array.isArray(identities) || identities.length !== occupancy.participantCount ||
          identities.some((identity) => typeof identity !== "string" || identity.length === 0)) {
        return { outcome: "unknown" };
      }
      if (identities.includes(participantIdentity)) return { outcome: "present" };
    }
    return db.runTransaction(async (transaction) => {
      const sessionReference = db.doc(
        `clubs/${anchor.serverId}/channels/${anchor.channelId}/channelSessions/${anchor.sessionId}`);
      const [snapshot, sessionSnapshot] = await transactionGetAll(transaction, reference, sessionReference);
      if (sessionSnapshot.data()?.status !== "live") return { outcome: "not-live" };
      if (!snapshot.exists || !raisedBefore(snapshot.data())) return { outcome: "unchanged" };
      const now = Timestamp.fromMillis(checkedNow());
      transaction.update(reference, {
        isHandRaised: false, handRaisedAt: null,
        handDecision: "lowered", handDecidedAt: now, handDecidedById: null, updatedAt: now,
      });
      return { outcome: "lowered" };
    });
  }

  async function readProjection(transaction, serverId, channelId) {
    const channelReference = db.doc(`clubs/${serverId}/channels/${channelId}`);
    const channelSnapshot = await transaction.get(channelReference);
    const channel = channelSnapshot.exists ? channelSnapshot.data() : null;
    const roomId = safeId(channel?.roomId);
    const sessionId = safeId(channel?.activeSessionId);
    const references = [
      ...(roomId ? [db.doc(`rooms/${roomId}`)] : []),
      ...(sessionId ? [channelReference.collection("channelSessions").doc(sessionId)] : []),
    ];
    const snapshots = references.length ? await transactionGetAll(transaction, ...references) : [];
    const room = roomId && snapshots[0].exists ? snapshots[0].data() : null;
    const sessionSnapshot = sessionId ? snapshots[roomId ? 1 : 0] : null;
    const session = sessionSnapshot?.exists ? sessionSnapshot.data() : null;
    const classification = classifyChannelProjection({ serverId, channelId, channel, room, session, nowMs: checkedNow() });
    return { classification, channelReference, channel, roomId, sessionId, session };
  }

  /**
   * Classifies one channel projection and, with `apply`, repairs it when it
   * is provably dead. The write re-reads channel, anchor and session in its
   * own transaction and applies only when the classification AND the named
   * generation are unchanged, so a projection that names a newer live
   * generation is never cleared. `useProvider: false` (the repair script,
   * which holds no provider credential) never resets a max-age candidate.
   */
  async function repairChannelProjection({ serverId, channelId, apply = false, useProvider = true }) {
    const first = await db.runTransaction((transaction) => readProjection(transaction, serverId, channelId),
      { readOnly: true });
    let classification = first.classification;
    if (classification === "max-age-candidate") {
      if (!useProvider) return { classification: "unresolved", maxAge: true, applied: false };
      let verdict;
      try {
        verdict = occupancyVerdict(await livekit.roomOccupancy({ serverId, channelId, roomId: first.roomId,
          sessionId: first.sessionId, livekitRoomName: canonicalLiveKitRoomName(serverId, channelId, first.sessionId) }));
      } catch {
        verdict = occupancyVerdict(null);
      }
      if (!verdict.known || !verdict.empty) return { classification: "unresolved", maxAge: true, applied: false };
      classification = "reset-max-age";
    }
    if (!PROJECTION_REPAIRS.includes(classification) || !apply) return { classification, applied: false };
    return db.runTransaction(async (transaction) => {
      const current = await readProjection(transaction, serverId, channelId);
      const expected = classification === "reset-max-age" ? "max-age-candidate" : classification;
      if (current.classification !== expected || current.sessionId !== first.sessionId ||
          current.channel?.revision !== first.channel?.revision) return { classification: "changed", applied: false };
      const now = Timestamp.fromMillis(checkedNow());
      if (classification === "reset-terminal-session") {
        if (!Number.isSafeInteger(current.channel.revision) || current.channel.revision < 1 ||
            current.channel.revision >= Number.MAX_SAFE_INTEGER - 1) return { classification: "unresolved", applied: false };
        // Retiring the pointer is what every end writer does, so it moves
        // the revision exactly as they do.
        transaction.update(current.channelReference, { activeSessionId: null, liveness: channelLiveness(),
          revision: current.channel.revision + 1, updatedAt: now });
      } else {
        // The projection alone: the exact fence session_control.js applies
        // on a late terminal ACK. A max-age reset leaves the private graph to
        // an operator.
        transaction.update(current.channelReference, { liveness: channelLiveness(), updatedAt: now });
      }
      return { classification, applied: true };
    });
  }

  /**
   * Visits versioned servers (`clubs where serverSchemaVersion == 1`, by
   * document id) from `start`, wrapping once, at most `maxServers` of them.
   */
  async function forEachVersionedServer({ maxServers, start = null }, visit) {
    const base = db.collection("clubs").where("serverSchemaVersion", "==", 1).orderBy(FieldPath.documentId());
    let cursor = start;
    let wrapped = start === null;
    let visited = 0;
    let truncated = false;
    scan: for (;;) {
      let query = base;
      if (cursor !== null) query = query.startAfter(cursor);
      const page = await query.limit(SERVER_PAGE_SIZE).get();
      for (const document of page.docs) {
        if (wrapped && start !== null && document.id > start) break scan;
        if (visited >= maxServers) { truncated = true; break scan; }
        visited += 1;
        await visit(document);
      }
      if (page.size < SERVER_PAGE_SIZE) {
        if (wrapped) break;
        wrapped = true;
        cursor = null;
      } else {
        cursor = page.docs.at(-1).id;
      }
    }
    return { visited, truncated };
  }

  /** Every channel of one versioned server whose projection says live. */
  async function liveProjectionIds(serverId) {
    const snapshot = await db.collection(`clubs/${serverId}/channels`)
      .where("liveness.isLive", "==", true).limit(MAX_SERVER_CHANNELS).get();
    return snapshot.docs.map((document) => document.id);
  }

  async function sweepProjectionDrift(outcome, maxServers) {
    const start = String(random());
    if (!SAFE_ID.test(start)) throw new TypeError("random must return a document id.");
    const { truncated } = await forEachVersionedServer({ maxServers, start }, async (server) => {
      for (const channelId of await liveProjectionIds(server.id)) {
        const result = await repairChannelProjection({ serverId: server.id, channelId, apply: true });
        if (result.applied) outcome.driftRepaired += 1;
        else if (result.classification === "unresolved" || result.classification === "changed") outcome.driftUnresolved += 1;
      }
    });
    outcome.driftTruncated = truncated;
  }

  async function stageStaleServerChannelSessions({
    maxRooms = MAX_LIVE_ANCHOR_SCAN, graceMs = STALE_GENERATION_GRACE_MS, maxServers = MAX_DRIFT_SERVER_SCAN,
  } = {}) {
    requireSafeInteger(maxRooms, "maxRooms", { min: 1, max: MAX_LIVE_ANCHOR_SCAN });
    // Never below one token TTL: a shorter grace could end a generation
    // whose newest token is still usable to connect.
    requireSafeInteger(graceMs, "graceMs", { min: STALE_GENERATION_GRACE_MS });
    requireSafeInteger(maxServers, "maxServers", { min: 1, max: MAX_DRIFT_SERVER_SCAN });
    // Resolved before the scan, exactly as the legacy sweep resolves its
    // control: a misconfigured deploy surfaces on the next run, not on the
    // first generation that needs closing.
    livekit.assertSupported();
    const outcome = emptyOutcome();
    const snapshot = await db.collection("rooms").where("isLive", "==", true).limit(maxRooms + 1).get();
    outcome.truncated = snapshot.size > maxRooms;
    for (const document of snapshot.docs.slice(0, maxRooms)) {
      const room = document.data() ?? {};
      if (!isVersionedAnchor(room)) { outcome.skippedLegacy += 1; continue; }
      outcome.scanned += 1;
      const anchor = anchorFor(document.id, room);
      if (!anchor) { outcome.skippedUnbound += 1; continue; }
      const session = await readSession(anchor);
      let livekitRoomName;
      try {
        livekitRoomName = assertSessionBinding(session, anchor);
      } catch (error) {
        if (!(error instanceof HttpsError)) throw error;
        outcome.skippedUnbound += 1;
        continue;
      }
      if (session.status !== "live") { outcome.skippedUnbound += 1; continue; }
      const nowMs = checkedNow();
      const observation = emptyObservation(session);
      // A running reconnect grace is never cut short, not even by rule B.
      if (observation && !graceElapsed(observation, nowMs)) { outcome.graceRunning += 1; continue; }
      if (!observation && lastAdmissionMillis(session) + graceMs > nowMs) { outcome.skippedYoung += 1; continue; }
      let occupancy;
      try {
        occupancy = await livekit.roomOccupancy({ ...anchor, livekitRoomName });
      } catch {
        outcome.providerUnavailable += 1;
        continue;
      }
      const verdict = occupancyVerdict(occupancy);
      if (observation) {
        if (!verdict.known) { outcome.skippedOccupied += 1; continue; }
        const result = await settleEmptyGeneration({ anchor, observedMaxTokenExpiresAtMillis: session.maxTokenExpiresAtMillis,
          verdict, source: "sweep" });
        if (result.outcome === "ended") { outcome.stagedEmpty += 1; outcome.staged.push(result.staged); }
        else if (result.outcome === "occupied") outcome.skippedOccupied += 1;
        else if (result.outcome === "pending") outcome.graceRunning += 1;
        else outcome.changed += 1;
        continue;
      }
      if (!verdict.known || !verdict.empty) {
        outcome.skippedOccupied += 1;
        continue;
      }
      const result = await stageEmptyGeneration({ anchor, observedMaxTokenExpiresAtMillis: session.maxTokenExpiresAtMillis,
        reason: "stale", admissionCheck: ({ item, nowMs: stagingNowMs }) => {
          const running = emptyObservation(item.session);
          return lastAdmissionMillis(item.session) + graceMs <= stagingNowMs &&
            !(running && !graceElapsed(running, stagingNowMs));
        } });
      if (result.outcome === "staged") outcome.staged.push(result);
      else outcome.changed += 1;
    }
    await sweepProjectionDrift(outcome, maxServers);
    return outcome;
  }

  return {
    classifyChannelProjection, forEachVersionedServer, liveProjectionIds, lowerDepartedHand, recentAdmission,
    repairChannelProjection, settleEmptyGeneration, settleEmptyGenerationWithin, stageEmptyGeneration,
    stageFinishedProviderRoom, stageStaleServerChannelSessions,
  };
}

module.exports = {
  ADMISSION_WINDOW_MS, EMPTY_GENERATION_GRACE_MS, MAX_DRIFT_SERVER_SCAN, MAX_LIVE_ANCHOR_SCAN,
  MAX_UNPROVEN_LIVE_AGE_MS, PROJECTION_REPAIRS, STALE_GENERATION_GRACE_MS,
  classifyChannelProjection, createServerSessionStalenessService, emptyObservation, occupancyVerdict,
};
