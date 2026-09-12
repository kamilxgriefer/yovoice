const { HttpsError } = require("firebase-functions/v2/https");
const { digest, requireSafeInteger, timestampMillis, transactionGetAll } = require("../integrity/guards");
const { canonicalServer } = require("./authority");
const { readConvergenceBindings, stageConvergenceSessionEnd } = require("./convergence_lifecycle");
const { isVersionedAnchor } = require("./rtc_binding");
const { SESSION_TOKEN_TTL_SECONDS, assertSessionBinding } = require("./session_contract");

// THE BOUND ON A V1 GENERATION WHOSE HOST VANISHED (ADR-180).
//
// `liveness.isLive` means "a generation is open", and nothing closed a
// generation whose starter disconnected without calling
// `endServerChannelSessionV1`: the legacy sweeper skips versioned anchors by
// design, so a LIVE badge could persist forever. This module stages such a
// generation for end THROUGH THE SAME WRITER AND WORKER every authorized end
// already uses — `stageConvergenceSessionEnd` plus the `sessionEnd` outbox
// job that `session_control.js` drains — so there is no second state machine
// and no second teardown path. It decides only WHEN a generation is stale,
// and it does so from two facts, both required:
//
//   1. Nobody can be admitted any more. Every token the generation ever
//      issued has expired (`maxTokenExpiresAtMillis`, kept by token
//      issuance) at least one grace period ago; a generation that never
//      issued one is measured from its own `startedAt`. A JWT is checked at
//      connect time only, so this alone does NOT prove emptiness — an
//      established connection outlives its token — which is why it is only
//      the first condition. It does prove that nobody NEW can arrive, so the
//      second reading cannot be invalidated by a token minted before it.
//   2. Nobody is here. The provider reports the generation's `srv_` room as
//      absent (LiveKit deletes an empty room after its emptyTimeout) or as
//      holding zero participants. A provider error is an unknown, and an
//      unknown never ends a generation.
//
// The staging transaction then re-proves the whole reciprocal graph with
// `readConvergenceBindings` and re-reads `maxTokenExpiresAtMillis`: a token
// minted between the provider reading and the commit moves the bound
// forward, so the commit is refused as `changed` and the next sweep looks
// again. Held anchors are never live and legacy rooms are never versioned,
// so neither is a candidate.

// One token TTL, and the same five minutes as the legacy sweep's
// GRACE_PERIOD_SECONDS: a generation is not stale until the last admission
// it could have granted has been impossible for a full TTL.
const STALE_GENERATION_GRACE_MS = SESSION_TOKEN_TTL_SECONDS * 1000;
// The legacy sweep's scan bound, for the same bare `isLive == true` query
// served by the automatic single-field index: no composite index to deploy.
const MAX_LIVE_ANCHOR_SCAN = 200;

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

function emptyOutcome() {
  return {
    scanned: 0, truncated: false, skippedLegacy: 0, skippedUnbound: 0, skippedYoung: 0,
    skippedOccupied: 0, providerUnavailable: 0, changed: 0, staged: [],
  };
}

/** Internal worker factory only. Registered by servers/registration.js as
 * the stale-generation schedule; no client may reach it. */
function createServerSessionStalenessService({ db, Timestamp, livekit, clock = Date.now }) {
  if (!livekit || !["assertSupported", "roomOccupancy"].every((name) => typeof livekit[name] === "function")) {
    throw new TypeError("An occupancy-capable LiveKit adapter is required.");
  }

  async function stageIfStillStale(anchor, observedMaxTokenExpiresAtMillis, graceMs) {
    return db.runTransaction(async (transaction) => {
      const serverReference = db.doc(`clubs/${anchor.serverId}`);
      const channelReference = serverReference.collection("channels").doc(anchor.channelId);
      const [root, channelSnapshot] = await transactionGetAll(transaction, serverReference, channelReference);
      let item;
      try {
        // The exact consistency every authorized lifecycle writer demands
        // before it may call stageConvergenceSessionEnd. Anything short of
        // it is left alone for the owning worker or an operator.
        const server = canonicalServer(root);
        if (!channelSnapshot.exists) return { outcome: "changed" };
        [item] = await readConvergenceBindings({ db, transaction, serverId: anchor.serverId, server,
          channels: [{ id: anchor.channelId, reference: channelReference, channel: channelSnapshot.data() }] });
      } catch (error) {
        if (error instanceof HttpsError) return { outcome: "changed" };
        throw error;
      }
      if (!item?.session || item.session.status !== "live" || item.session.sessionId !== anchor.sessionId ||
          item.roomReference.id !== anchor.roomId ||
          // A token minted since the provider reading moved the bound; the
          // occupancy read no longer describes this generation.
          item.session.maxTokenExpiresAtMillis !== observedMaxTokenExpiresAtMillis ||
          lastAdmissionMillis(item.session) + graceMs > clock()) return { outcome: "changed" };
      const now = Timestamp.fromMillis(clock());
      // Deterministic per generation: a generation is staged at most once,
      // because staging is what takes it out of `live`.
      const identity = { id: digest("server.session.stale.v1", item.binding) };
      const ending = stageConvergenceSessionEnd({ db, transaction, item, identity, now });
      transaction.update(item.roomReference, { ...ending.roomPatch, updatedAt: now });
      transaction.update(item.reference, { ...ending.channelPatch, revision: item.channel.revision + 1, updatedAt: now });
      return { outcome: "staged", ...item.binding, endOperationId: ending.target.endOperationId };
    });
  }

  async function stageStaleServerChannelSessions({ maxRooms = MAX_LIVE_ANCHOR_SCAN, graceMs = STALE_GENERATION_GRACE_MS } = {}) {
    requireSafeInteger(maxRooms, "maxRooms", { min: 1, max: MAX_LIVE_ANCHOR_SCAN });
    // Never below one token TTL: a shorter grace could end a generation
    // whose newest token is still usable to connect.
    requireSafeInteger(graceMs, "graceMs", { min: STALE_GENERATION_GRACE_MS });
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
      const sessionSnapshot = await db.doc(`clubs/${anchor.serverId}/channels/${anchor.channelId}/channelSessions/${anchor.sessionId}`).get();
      const session = sessionSnapshot.exists ? sessionSnapshot.data() : null;
      let livekitRoomName;
      try {
        livekitRoomName = assertSessionBinding(session, anchor);
      } catch (error) {
        if (!(error instanceof HttpsError)) throw error;
        outcome.skippedUnbound += 1;
        continue;
      }
      if (session.status !== "live") { outcome.skippedUnbound += 1; continue; }
      if (lastAdmissionMillis(session) + graceMs > clock()) { outcome.skippedYoung += 1; continue; }
      let occupancy;
      try {
        occupancy = await livekit.roomOccupancy({ ...anchor, livekitRoomName });
      } catch {
        outcome.providerUnavailable += 1;
        continue;
      }
      if (!occupancy || !Number.isSafeInteger(occupancy.participantCount) || occupancy.participantCount > 0) {
        outcome.skippedOccupied += 1;
        continue;
      }
      const result = await stageIfStillStale(anchor, session.maxTokenExpiresAtMillis, graceMs);
      if (result.outcome === "staged") outcome.staged.push(result);
      else outcome.changed += 1;
    }
    return outcome;
  }

  return { stageStaleServerChannelSessions };
}

module.exports = { MAX_LIVE_ANCHOR_SCAN, STALE_GENERATION_GRACE_MS, createServerSessionStalenessService };
