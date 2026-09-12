const { digest, fail, requireId, requireUid, transactionGetAll } = require("../integrity/guards");
const { MAX_SERVER_CHANNELS, MEDIA_KINDS, canonicalLiveKitRoomName } = require("./contract");
const { canonicalChannel } = require("./authority");
const { assertSessionBinding } = require("./session_contract");

function inconsistent() { fail("failed-precondition", "The server media graph needs reconciliation."); }

function sessionBinding(serverId, item, session) {
  return { serverId, channelId: item.id, roomId: item.channel.roomId,
    sessionId: session.sessionId,
    livekitRoomName: canonicalLiveKitRoomName(serverId, item.id, session.sessionId) };
}

function validateEndJob(job, binding, operationId) {
  if (!job || job.schemaVersion !== 1 || job.kind !== "sessionEnd" ||
      job.operationId !== operationId || !["pending", "completed"].includes(job.status) ||
      Object.entries(binding).some(([key, value]) => job[key] !== value)) inconsistent();
  return job;
}

/** Read before any mutation writes. The bounded nonterminal query detects an
 * orphan even when an earlier writer lost both public liveness pointers. */
async function readConvergenceBindings({ db, transaction, serverId, server, channels }) {
  requireId(serverId, "serverId");
  if (!Array.isArray(channels) || channels.length > MAX_SERVER_CHANNELS) inconsistent();
  const media = [];
  for (const item of channels) {
    requireId(item.id, "channelId");
    const channel = canonicalChannel({ exists: true, data: () => item.channel }, serverId,
      { allowArchived: true, allowDeleting: true });
    if (item.reference.path !== `clubs/${serverId}/channels/${item.id}`) inconsistent();
    if (MEDIA_KINDS.includes(channel.kind)) media.push({ ...item, channel });
    else if (channel.activeSessionId !== null) inconsistent();
  }
  if (media.length === 0) return [];
  const rooms = await transactionGetAll(transaction, ...media.map((item) => db.doc(`rooms/${item.channel.roomId}`)));
  const sessions = await Promise.all(media.map((item) => transaction.get(item.reference.collection("channelSessions")
    .where("status", "in", ["starting", "live", "ending"]).limit(2))));
  const result = [];
  for (let index = 0; index < media.length; index += 1) {
    const item = media[index]; const roomSnapshot = rooms[index];
    const room = roomSnapshot.exists ? roomSnapshot.data() : null;
    const expectedStatus = item.channel.status === "active"
      ? (server.serverActivationState === "held" ? "preparing" : "active") : item.channel.status;
    if (!room || room.serverSchemaVersion !== 1 || room.serverId !== serverId || room.clubId !== serverId ||
        room.channelId !== item.id || room.serverOwnerId !== server.ownerId ||
        room.hostId !== (server.serverActivationState === "held" ? null : server.ownerId) ||
        room.serverActivationState !== server.serverActivationState || room.visibility !== "private" ||
        room.status !== expectedStatus || room.experience !== item.channel.experience || room.mediaMode !== item.channel.mediaMode ||
        sessions[index].size > 1) inconsistent();
    const base = { ...item, roomReference: roomSnapshot.ref, room, session: null, sessionReference: null };
    if (sessions[index].empty) {
      if (item.channel.activeSessionId !== null || room.isLive !== false || room.voiceSessionId !== null ||
          room.livekitRoomName !== null || room.serverSessionCleanupId != null) inconsistent();
      result.push(base); continue;
    }
    const sessionSnapshot = sessions[index].docs[0]; const session = sessionSnapshot.data();
    const binding = sessionBinding(serverId, item, session);
    if (sessionSnapshot.id !== session.sessionId || session.experience !== item.channel.experience ||
        session.mediaMode !== item.channel.mediaMode) inconsistent();
    assertSessionBinding(session, binding);
    if (session.status === "live") {
      if (server.serverActivationState !== "active" || item.channel.status !== "active" ||
          item.channel.activeSessionId !== session.sessionId || room.isLive !== true ||
          room.voiceSessionId !== session.sessionId || room.livekitRoomName !== binding.livekitRoomName ||
          room.serverSessionCleanupId != null) inconsistent();
    } else if (session.status === "ending") {
      if (item.channel.activeSessionId !== null || room.isLive !== false || room.voiceSessionId !== null ||
          room.livekitRoomName !== null || room.serverSessionCleanupId !== session.sessionId) inconsistent();
      requireId(session.endOperationId, "endOperationId");
    } else inconsistent();
    result.push({ ...base, session, sessionReference: sessionSnapshot.ref, binding });
  }
  const ending = result.filter((item) => item.session?.status === "ending");
  if (ending.length) {
    const jobs = await transactionGetAll(transaction, ...ending.map((item) => db.doc(`serverControlOutbox/${item.session.endOperationId}`)));
    ending.forEach((item, index) => {
      const job = validateEndJob(jobs[index].exists ? jobs[index].data() : null, item.binding, item.session.endOperationId);
      if (job.status !== "pending") inconsistent();
    });
  }
  return result;
}

function capturedRecipientTargets(bindings, userId = null) {
  if (userId !== null) requireUid(userId);
  return bindings.filter((item) => item.session).map((item) => ({ ...item.binding,
    mode: userId === null ? "recipients" : "recipient", ...(userId === null ? {} : { userId }) }));
}

function convergenceState(rtcTargets, { grantsComplete = true, contentCleanupPending = false } = {}) {
  return { convergenceVersion: 1, rtcTargets,
    grantStatus: grantsComplete ? "completed" : "pending", grantCursor: null,
    rtcStatus: rtcTargets.length ? "pending" : "completed", rtcTargetIndex: 0, rtcRecipientCursor: null,
    bridgeLeaseId: null, bridgeLeaseExpiresAtMillis: 0, retryAfterMillis: 0, lastErrorCode: null,
    contentCleanupPending };
}

/** Only an already-authorized archive/delete/transfer transaction may call
 * this writer. A recipient convergence failure never grants end authority.
 * Caller merges the returned patches into its one room/channel write. */
function stageConvergenceSessionEnd({ db, transaction, item, identity, now }) {
  if (!item.session) return { target: null, roomPatch: {}, channelPatch: {} };
  const { session, binding } = item;
  let endOperationId = session.endOperationId;
  if (session.status === "live") {
    if (session.authorizationRevision >= Number.MAX_SAFE_INTEGER - 1) inconsistent();
    endOperationId = digest("server.convergence.session.end.v1", identity.id, binding);
    transaction.update(item.sessionReference, { status: "ending", endedAt: now, endOperationId,
      authorizationRevision: session.authorizationRevision + 1, updatedAt: now });
    transaction.create(db.doc(`serverControlOutbox/${endOperationId}`), {
      schemaVersion: 1, kind: "sessionEnd", operationId: endOperationId, parentOperationId: identity.id,
      ...binding, status: "pending", cursor: null, leaseId: null, leaseExpiresAtMillis: 0,
      maxTokenExpiresAtMillis: session.maxTokenExpiresAtMillis, createdAt: now, updatedAt: now,
    });
  } else if (session.status !== "ending") inconsistent();
  return { target: { ...binding, mode: "sessionEnd", endOperationId },
    roomPatch: { isLive: false, voiceSessionId: null, livekitRoomName: null, serverSessionCleanupId: session.sessionId },
    channelPatch: { activeSessionId: null } };
}

module.exports = { capturedRecipientTargets, convergenceState, readConvergenceBindings,
  stageConvergenceSessionEnd, validateEndJob };
