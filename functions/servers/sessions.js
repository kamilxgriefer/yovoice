const { HttpsError } = require("firebase-functions/v2/https");
const {
  activeProfile, assertLedgerReplay, assertNotRestricted, consumeRateLimit, fail,
  ledgerData, operationIdentity, rateLimitReference, requireActor, transactionGetAll,
} = require("../integrity/guards");
const { readChannelAccess, readBoundSessionAccess, denied } = require("./authority");
const { canonicalLiveKitRoomName, channelLiveness, MEDIA_KINDS } = require("./contract");
const { createServerOperations } = require("./operations");
const {
  SESSION_TOKEN_ATTEMPT_LIMIT, SESSION_TOKEN_ATTEMPT_SCOPE, SESSION_TOKEN_TTL_SECONDS,
  assertRoomBinding, assertSessionBinding, canonicalSessionId, hasUnresolvedRevocationAttempt, sessionInput,
} = require("./session_contract");
const { readSessionTokenAuthority, requireIssuableRecipient } = require("./session_authority");
const { createServerSessionControlService } = require("./session_control");

const TOKEN_KIND = "server.session.token.v1";

function checkedNow(clock) {
  const nowMs = clock();
  if (!Number.isSafeInteger(nowMs) || nowMs < 0) throw new TypeError("clock must return epoch milliseconds.");
  return nowMs;
}

function authorizedTokenReplay(snapshot, identity, authority, uid, nowMs) {
  const stored = assertLedgerReplay(snapshot, { kind: TOKEN_KIND, uid, inputHash: identity.inputHash });
  if (!stored) return null;
  if (stored.authorityFingerprint !== authority.fingerprint ||
      !authority.recipient || authority.recipient.revocationState !== "active" ||
      hasUnresolvedRevocationAttempt(authority.recipient) ||
      authority.recipient.reconnectAfterMillis > nowMs ||
      stored.tokenEpoch !== authority.recipient.tokenEpoch) denied();
  const result = stored.connection;
  if (!result || Object.entries(authority.binding).some(([key, value]) =>
    !["userId", "livekitRoomName"].includes(key) && result[key] !== value) ||
      result.roomName !== authority.livekitRoomName ||
      typeof result.participantName !== "string" || !result.participantName || result.participantName.length > 120 ||
      result.sessionRole !== authority.participant.role ||
      result.permissions?.canPublish !== authority.grant.canPublish ||
      result.permissions?.canSubscribe !== authority.grant.canSubscribe ||
      result.permissions?.canPublishData !== authority.grant.canPublishData ||
      typeof result.participantToken !== "string" || !result.participantToken ||
      result.token !== result.participantToken || !Number.isSafeInteger(result.expiresAtMillis) ||
      JSON.stringify(result.permittedTrackSources) !== JSON.stringify(authority.grant.permittedTrackSources)) {
    fail("data-loss", "The private media token receipt needs reconciliation.");
  }
  if (result.expiresAtMillis <= nowMs) {
    fail("already-exists", "This token request expired. Use a new connection request.");
  }
  return result;
}

/** Source-only factories. No onCall/index export, held activation, legacy
 * RoomExperience change, provider secret discovery, or billing mutation. */
function createServerSessionService(dependencies) {
  const { db, Timestamp, livekit, clock = Date.now } = dependencies;
  if (!livekit || !["assertSupported", "mintToken", "revokeParticipant", "endRoom"]
    .every((name) => typeof livekit[name] === "function")) throw new TypeError("A revocation-capable LiveKit adapter is required.");
  const operations = createServerOperations(dependencies);
  const control = createServerSessionControlService(dependencies);

  async function startServerChannelSessionV1(request) {
    const input = sessionInput(request.data, { session: false });
    return operations.execute(request, "server.session.start.v1", input,
      async ({ transaction, auth, prior, now }) => {
        const access = await readChannelAccess({ db, transaction, uid: auth.uid, ...input, capability: "startSession" });
        if (!MEDIA_KINDS.includes(access.channel.kind)) denied();
        const roomReference = db.doc(`rooms/${access.channel.roomId}`);
        const roomSnapshot = await transaction.get(roomReference);
        const room = roomSnapshot.exists ? roomSnapshot.data() : null;
        assertRoomBinding(room, access);
        livekit.assertSupported();
        if (prior) {
          if (prior.roomId !== roomReference.id) denied();
          const previous = await transaction.get(access.channelReference.collection("channelSessions").doc(prior.sessionId));
          assertSessionBinding(previous.exists ? previous.data() : null, { ...input, ...prior });
          // A replay acknowledges its original generation, even after it ended;
          // it never restarts it or joins a newer session implicitly.
          return prior;
        }
        if (access.channel.activeSessionId !== null) {
          const current = await readBoundSessionAccess({ db, transaction, uid: auth.uid,
            ...input, sessionId: access.channel.activeSessionId, capability: "startSession" });
          assertSessionBinding(current.session, { ...input, roomId: roomReference.id, sessionId: access.channel.activeSessionId });
          if (room.serverSessionCleanupId != null) fail("failed-precondition", "Media cleanup is still pending.");
          return { roomId: roomReference.id, sessionId: access.channel.activeSessionId };
        }
        if (room.isLive !== false || room.voiceSessionId !== null || room.livekitRoomName !== null ||
            room.serverSessionCleanupId != null) fail("failed-precondition", "Media cleanup is still pending.");
        // Covers an orphaned ending generation left by another canonical
        // lifecycle writer (for example ownership transfer). No legacy start
        // path may silently bypass its cleanup barrier.
        const nonterminal = await transaction.get(access.channelReference.collection("channelSessions")
          .where("status", "in", ["starting", "live", "ending"]).limit(1));
        if (!nonterminal.empty) fail("failed-precondition", "The previous media session needs cleanup.");
        const sessionId = canonicalSessionId(input.serverId, input.channelId, auth.uid, input.requestId);
        const sessionReference = access.channelReference.collection("channelSessions").doc(sessionId);
        if ((await transaction.get(sessionReference)).exists) fail("data-loss", "The media generation already exists without its receipt.");
        const livekitRoomName = canonicalLiveKitRoomName(input.serverId, input.channelId, sessionId);
        transaction.create(sessionReference, {
          serverSchemaVersion: 1, serverId: input.serverId, channelId: input.channelId,
          roomId: roomReference.id, sessionId, livekitRoomName,
          experience: access.channel.experience, mediaMode: access.channel.mediaMode,
          sourcePolicyVersion: 1, authorizationRevision: 1,
          startedById: auth.uid, startedAt: now, endedAt: null,
          status: "live", updatedAt: now, maxTokenExpiresAtMillis: 0,
        });
        // The channel's own ACL governs this projection, so a member learns a
        // channel is live without any read on the private session or anchor.
        transaction.update(access.channelReference, {
          activeSessionId: sessionId, liveness: channelLiveness(now),
          revision: access.channel.revision + 1, updatedAt: now,
        });
        transaction.update(roomReference, {
          isLive: true, voiceSessionId: sessionId, livekitRoomName,
          serverSessionCleanupId: null, voiceStartedAt: now, updatedAt: now,
        });
        // Intentionally no participants, membership/presence mirror or token.
        return { roomId: roomReference.id, sessionId };
      });
  }

  async function createServerChannelTokenV1(request) {
    const input = sessionInput(request.data);
    const auth = requireActor(request);
    const nowMs = checkedNow(clock);
    const now = Timestamp.fromMillis(nowMs);
    const { requestId, ...operationInput } = input;
    const identity = operationIdentity(TOKEN_KIND, auth.uid, requestId, operationInput);
    const ledgerReference = db.doc(`integrityOperationLedgers/${identity.id}`);
    const rateReference = rateLimitReference(db, SESSION_TOKEN_ATTEMPT_SCOPE, auth.uid);
    // Every replay/denial consumes the same actor-only budget before looking
    // at any target or token receipt. No free existence-oracle/cache path.
    await db.runTransaction(async (transaction) => {
      const [profile, restriction, rate] = await transactionGetAll(transaction,
        db.doc(`users/${auth.uid}`), db.doc(`restrictions/${auth.uid}`), rateReference);
      activeProfile(profile, "Your"); assertNotRestricted(restriction, "Your", nowMs);
      consumeRateLimit(transaction, rate, { reference: rateReference, scope: SESSION_TOKEN_ATTEMPT_SCOPE,
        uid: auth.uid, nowMs, now, ...SESSION_TOKEN_ATTEMPT_LIMIT });
    });
    const preflight = await db.runTransaction(async (transaction) => {
      const ledger = await transaction.get(ledgerReference);
      const authority = await readSessionTokenAuthority({ db, transaction, uid: auth.uid, input, nowMs: checkedNow(clock) });
      livekit.assertSupported();
      const replay = authorizedTokenReplay(ledger, identity, authority, auth.uid, checkedNow(clock));
      return { authority, replay, tokenEpoch: requireIssuableRecipient(authority, checkedNow(clock)) };
    });
    if (preflight.replay) return preflight.replay;
    let connection;
    try {
      connection = await livekit.mintToken({ uid: auth.uid, participantName: preflight.authority.participantName,
        binding: preflight.authority.binding, sessionRole: preflight.authority.participant.role,
        grant: preflight.authority.grant });
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      fail("unavailable", "Media access could not be issued. Retry this request.");
    }
    // Signing is local provider SDK work, outside the transaction. The JWT is
    // not disclosed until this transaction re-reads every mutable authority.
    // A later revocation sees the durable recipient and generation mirror.
    return db.runTransaction(async (transaction) => {
      const finalMs = checkedNow(clock);
      const finalNow = Timestamp.fromMillis(finalMs);
      const ledger = await transaction.get(ledgerReference);
      const authority = await readSessionTokenAuthority({ db, transaction, uid: auth.uid, input, nowMs: finalMs });
      const replay = authorizedTokenReplay(ledger, identity, authority, auth.uid, finalMs);
      if (replay) return replay;
      const tokenEpoch = requireIssuableRecipient(authority, finalMs);
      if (authority.fingerprint !== preflight.authority.fingerprint || tokenEpoch !== preflight.tokenEpoch) {
        fail("aborted", "Media authority changed during token issuance. Retry after cleanup.");
      }
      if (!connection || Object.entries(authority.binding).some(([key, value]) =>
        !["userId", "livekitRoomName"].includes(key) && connection[key] !== value) ||
          connection.roomName !== authority.livekitRoomName ||
          connection.participantIdentity !== auth.uid || connection.token !== connection.participantToken ||
          connection.participantName !== authority.participantName ||
          connection.sessionRole !== authority.participant.role ||
          connection.permissions?.canPublish !== authority.grant.canPublish ||
          connection.permissions?.canSubscribe !== authority.grant.canSubscribe ||
          connection.permissions?.canPublishData !== authority.grant.canPublishData ||
          typeof connection.participantToken !== "string" || !connection.participantToken ||
          !Number.isSafeInteger(connection.expiresAtMillis) || connection.expiresAtMillis <= finalMs ||
          connection.expiresAtMillis > finalMs + SESSION_TOKEN_TTL_SECONDS * 1000 ||
          JSON.stringify(connection.permittedTrackSources) !== JSON.stringify(authority.grant.permittedTrackSources)) {
        fail("unavailable", "The media token could not be validated.");
      }
      const mirrorReference = db.doc(`activeVoiceSessions/${auth.uid}/rooms/${authority.roomReference.id}`);
      const mirror = await transaction.get(mirrorReference);
      if (mirror.exists && (mirror.data()?.serverSchemaVersion !== 1 ||
          mirror.data()?.sessionId !== input.sessionId || mirror.data()?.serverId !== input.serverId ||
          mirror.data()?.channelId !== input.channelId)) fail("failed-precondition", "Previous media cleanup is incomplete.");
      const expiresAtMillis = Math.max(connection.expiresAtMillis, authority.recipient?.expiresAtMillis ?? 0);
      transaction.set(authority.recipientReference, {
        schemaVersion: 1, ...authority.binding, authorityFingerprint: authority.fingerprint,
        tokenEpoch, revocationState: "active", reconnectAfterMillis: 0,
        expiresAtMillis, firstIssuedAt: authority.recipient?.firstIssuedAt ?? finalNow,
        lastIssuedAt: finalNow, updatedAt: finalNow,
      });
      transaction.set(authority.participantReference, {
        ...authority.participant, displayName: authority.participantName, photoUrl: null,
        tokenAuthorityFingerprint: authority.fingerprint,
        joinedAt: authority.participant.joinedAt ?? finalNow, updatedAt: finalNow,
      });
      transaction.set(mirrorReference, {
        serverSchemaVersion: 1, ...authority.binding, clubId: input.serverId, roomKind: "serverChannel",
        authorityFingerprint: authority.fingerprint, tokenEpoch,
        expiresAt: Timestamp.fromMillis(expiresAtMillis), issuedAt: finalNow, updatedAt: finalNow,
      });
      transaction.update(authority.sessionReference, {
        maxTokenExpiresAtMillis: Math.max(authority.session.maxTokenExpiresAtMillis ?? 0, expiresAtMillis),
        updatedAt: finalNow,
      });
      transaction.create(ledgerReference, ledgerData({ kind: TOKEN_KIND, uid: auth.uid, requestId,
        inputHash: identity.inputHash, result: { authorityFingerprint: authority.fingerprint, tokenEpoch, connection }, now: finalNow }));
      // Token admission is not provider-connected presence: isOnline and the
      // online/participant counters await a verified provider event adapter.
      return connection;
    });
  }

  async function endServerChannelSessionV1(request) {
    const input = sessionInput(request.data);
    const receipt = await operations.execute(request, "server.session.end.v1", input,
      async ({ transaction, auth, prior, now, identity }) => {
        const access = await readChannelAccess({ db, transaction, uid: auth.uid, ...input, capability: "joinVoice" });
        const roomReference = db.doc(`rooms/${access.channel.roomId}`);
        const sessionReference = access.channelReference.collection("channelSessions").doc(input.sessionId);
        const [roomSnapshot, sessionSnapshot] = await transactionGetAll(transaction, roomReference, sessionReference);
        const room = roomSnapshot.exists ? roomSnapshot.data() : null;
        const session = sessionSnapshot.exists ? sessionSnapshot.data() : null;
        assertRoomBinding(room, access);
        const livekitRoomName = assertSessionBinding(session, { ...input, roomId: roomReference.id });
        if (session.startedById !== auth.uid && access.capabilities.moderate !== true) denied();
        livekit.assertSupported();
        if (prior) return prior;
        if (["ending", "ended"].includes(session.status)) {
          if (typeof session.endOperationId !== "string") fail("failed-precondition", "The session is already closing through another lifecycle operation.");
          return { roomId: roomReference.id, sessionId: input.sessionId, operationId: session.endOperationId };
        }
        if (session.status !== "live" || access.channel.activeSessionId !== input.sessionId ||
            room.isLive !== true || room.voiceSessionId !== input.sessionId ||
            room.livekitRoomName !== livekitRoomName || room.serverSessionCleanupId != null) denied();
        if (session.authorizationRevision >= Number.MAX_SAFE_INTEGER - 1) fail("data-loss", "The session authorization revision is exhausted.");
        transaction.update(sessionReference, { status: "ending", endedAt: now,
          endOperationId: identity.id, authorizationRevision: session.authorizationRevision + 1, updatedAt: now });
        transaction.update(access.channelReference, { activeSessionId: null,
          liveness: channelLiveness(), revision: access.channel.revision + 1, updatedAt: now });
        transaction.update(roomReference, { isLive: false, voiceSessionId: null,
          livekitRoomName: null, serverSessionCleanupId: input.sessionId, updatedAt: now });
        transaction.create(db.doc(`serverControlOutbox/${identity.id}`), {
          schemaVersion: 1, kind: "sessionEnd", operationId: identity.id,
          serverId: input.serverId, channelId: input.channelId,
          roomId: roomReference.id, sessionId: input.sessionId, livekitRoomName,
          status: "pending", cursor: null, leaseId: null, leaseExpiresAtMillis: 0,
          maxTokenExpiresAtMillis: session.maxTokenExpiresAtMillis ?? 0,
          createdAt: now, updatedAt: now,
        });
        return { roomId: roomReference.id, sessionId: input.sessionId, operationId: identity.id };
      }, { verified: false, allowRestricted: true });
    // One bounded page eagerly attempts teardown. Partial failure is truthful
    // and durable, not an instruction for the caller to issue a new end ID.
    try {
      const outcome = await control.processServerSessionEndPage({ operationId: receipt.operationId });
      return { ...receipt, status: outcome.cleanupPending ? "ending" : "ended", cleanupPending: outcome.cleanupPending };
    } catch {
      return { ...receipt, status: "ending", cleanupPending: true };
    }
  }

  return { startServerChannelSessionV1, createServerChannelTokenV1, endServerChannelSessionV1 };
}

module.exports = { TOKEN_KIND, authorizedTokenReplay, createServerSessionService };
