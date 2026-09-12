const {
  digest, fail, requireExactInput, requireId, requireRequestId, requireUid,
} = require("../integrity/guards");
const { canonicalLiveKitRoomName, MEDIA_KINDS } = require("./contract");
const { denied, validRevision } = require("./authority");

const SESSION_TOKEN_TTL_SECONDS = 300;
const SESSION_TOKEN_ATTEMPT_LIMIT = Object.freeze({ maxEvents: 12, windowMs: 60_000 });
const SESSION_TOKEN_ATTEMPT_SCOPE = "server.session.token.attempt.v1";
const SESSION_ROLES = Object.freeze(["host", "guest", "listener"]);

function sessionInput(data, { session = true } = {}) {
  const keys = ["serverId", "channelId", "requestId", ...(session ? ["sessionId"] : [])];
  requireExactInput(data, keys, keys);
  return {
    serverId: requireId(data.serverId, "serverId"),
    channelId: requireId(data.channelId, "channelId"),
    requestId: requireRequestId(data.requestId),
    ...(session ? { sessionId: requireId(data.sessionId, "sessionId") } : {}),
  };
}

function canonicalSessionId(serverId, channelId, uid, requestId) {
  return `ss_${digest("server.session.start.v1", requireId(serverId), requireId(channelId),
    requireUid(uid), requireRequestId(requestId)).slice(0, 40)}`;
}

function tokenRecipientId(uid) {
  return digest("server.session.token.recipient.v1", requireUid(uid));
}

function assertRoomBinding(room, access) {
  if (!MEDIA_KINDS.includes(access.channel.kind) || !room ||
      room.serverSchemaVersion !== 1 || room.serverId !== access.reference.id ||
      room.clubId !== access.reference.id || room.channelId !== access.channelReference.id ||
      room.hostId !== access.server.ownerId || room.serverOwnerId !== access.server.ownerId ||
      room.status !== "active" || room.serverActivationState !== "active" ||
      room.deletionInProgress === true || room.visibility !== "private" ||
      room.experience !== access.channel.experience || room.mediaMode !== access.channel.mediaMode) denied();
}

function assertSessionBinding(session, { serverId, channelId, roomId, sessionId }) {
  const name = canonicalLiveKitRoomName(serverId, channelId, sessionId);
  if (!session || session.serverSchemaVersion !== 1 || session.serverId !== serverId ||
      session.channelId !== channelId || session.roomId !== roomId || session.sessionId !== sessionId ||
      session.livekitRoomName !== name || !validRevision(session.authorizationRevision) ||
      session.sourcePolicyVersion !== 1 || !Number.isSafeInteger(session.maxTokenExpiresAtMillis) ||
      session.maxTokenExpiresAtMillis < 0) denied();
  requireUid(session.startedById, "session host");
  return name;
}

function participantForSession(snapshot, access, uid) {
  const binding = { serverSchemaVersion: 1, serverId: access.reference.id,
    channelId: access.channelReference.id, roomId: access.roomReference.id,
    sessionId: access.session.sessionId, userId: uid };
  const isHost = access.session.startedById === uid;
  if (!snapshot.exists) return {
    ...binding, role: isHost ? "host" : access.channel.experience === "broadcast" ? "listener" : "guest",
    authorizationRevision: 1, hostMuted: false, serverMuted: false, isMuted: true,
    isHandRaised: false, displayName: access.profile.displayName, photoUrl: null,
  };
  const value = snapshot.data();
  if (Object.entries(binding).some(([key, expected]) => value?.[key] !== expected) ||
      !SESSION_ROLES.includes(value.role) || (value.role === "host") !== isHost ||
      !validRevision(value.authorizationRevision) || value.banned === true ||
      typeof value.hostMuted !== "boolean" || typeof value.serverMuted !== "boolean" ||
      typeof value.isMuted !== "boolean") denied();
  return value;
}

function deriveSessionGrant(access, participant) {
  if (!SESSION_ROLES.includes(participant?.role) ||
      !["audio", "video", "meeting"].includes(access?.channel?.mediaMode)) denied();
  const mayPublish = participant.role !== "listener" &&
    participant.hostMuted === false && participant.serverMuted === false;
  // A local mute is a capture state, not a role/permission revocation. Each
  // capture still requires the user's explicit consent in the client.
  const sources = mayPublish ? ["microphone"] : [];
  if (mayPublish && ["video", "meeting"].includes(access.channel.mediaMode)) sources.push("camera");
  // Policy v1 is deliberately narrow; screen sharing is an explicit host
  // capability of a meeting, never a blanket `canPublish` side effect.
  if (mayPublish && access.channel.mediaMode === "meeting" && participant.role === "host") {
    sources.push("screen_share", "screen_share_audio");
  }
  return {
    canPublish: sources.length > 0, canSubscribe: true, canPublishData: true,
    hidden: false, recorder: false, permittedTrackSources: sources,
  };
}

function authorityFingerprint(access, participant, grant) {
  return digest("server.session.authority.v1", {
    serverId: access.reference.id, serverSchemaVersion: access.server.serverSchemaVersion,
    serverOwnerId: access.server.ownerId, serverType: access.server.serverType,
    serverStatus: access.server.status, serverActivationState: access.server.serverActivationState,
    channelId: access.channelReference.id, channelKind: access.channel.kind,
    experience: access.channel.experience, mediaMode: access.channel.mediaMode,
    aclRevision: access.channel.aclRevision,
    membershipRevision: access.member.authorizationRevision, memberRole: access.member.role,
    roomId: access.roomReference.id, sessionId: access.session.sessionId,
    sessionRevision: access.session.authorizationRevision,
    sourcePolicyVersion: access.session.sourcePolicyVersion,
    participantRevision: participant.authorizationRevision, participantRole: participant.role,
    hostMuted: participant.hostMuted, serverMuted: participant.serverMuted,
    grant,
  });
}

function validateRecipient(recipient, binding) {
  if (!recipient || recipient.schemaVersion !== 1 ||
      Object.entries(binding).some(([key, expected]) => recipient[key] !== expected) ||
      !validRevision(recipient.tokenEpoch) ||
      !["active", "revoking", "revoked"].includes(recipient.revocationState) ||
      typeof recipient.authorityFingerprint !== "string" || !/^[a-f0-9]{64}$/u.test(recipient.authorityFingerprint) ||
      !Number.isSafeInteger(recipient.expiresAtMillis) || recipient.expiresAtMillis <= 0 ||
      !Number.isSafeInteger(recipient.reconnectAfterMillis) || recipient.reconnectAfterMillis < 0) {
    fail("data-loss", "The private session token record needs reconciliation.");
  }
  const attempt = recipient.revocationAttempt;
  if (attempt !== undefined && (attempt === null || typeof attempt !== "object" || Array.isArray(attempt) ||
      attempt.schemaVersion !== 1 || typeof attempt.id !== "string" || !/^[A-Za-z0-9_-]{8,128}$/u.test(attempt.id) ||
      attempt.tokenEpoch !== recipient.tokenEpoch ||
      !["pending", "uncertain", "acknowledged"].includes(attempt.state) ||
      !Number.isSafeInteger(attempt.startedAtMillis) || attempt.startedAtMillis < 0 ||
      !Number.isSafeInteger(attempt.leaseExpiresAtMillis) || attempt.leaseExpiresAtMillis <= attempt.startedAtMillis ||
      (attempt.state === "acknowledged" &&
        (!Number.isSafeInteger(attempt.revokedBeforeMillis) || attempt.revokedBeforeMillis <= 0 ||
         !Number.isSafeInteger(attempt.acknowledgedAtMillis) || attempt.acknowledgedAtMillis < 0)))) {
    fail("data-loss", "The private revocation attempt needs reconciliation.");
  }
  return recipient;
}

function hasUnresolvedRevocationAttempt(recipient) {
  return recipient?.revocationAttempt !== undefined && recipient.revocationAttempt?.state !== "acknowledged";
}

function recipientBinding(access, uid) {
  return { serverId: access.reference.id, channelId: access.channelReference.id,
    roomId: access.roomReference.id, sessionId: access.session.sessionId,
    livekitRoomName: access.livekitRoomName, userId: uid, participantIdentity: uid };
}

module.exports = {
  SESSION_ROLES, SESSION_TOKEN_ATTEMPT_LIMIT, SESSION_TOKEN_ATTEMPT_SCOPE,
  SESSION_TOKEN_TTL_SECONDS, assertRoomBinding, assertSessionBinding,
  authorityFingerprint, canonicalSessionId, deriveSessionGrant, participantForSession,
  hasUnresolvedRevocationAttempt, recipientBinding, sessionInput, tokenRecipientId, validateRecipient,
};
