const {
  activeProfile, fail, requireId, requireUid, transactionGetAll,
} = require("../integrity/guards");
const {
  CHANNEL_KINDS, MEDIA_KINDS, ROLES, SERVER_TYPES, accessPolicy,
  canonicalLiveKitRoomName, legacyChannelType, mediaConfiguration,
} = require("./contract");

const MANAGER_ROLES = Object.freeze(["owner", "coOwner", "admin"]);
const MODERATOR_ROLES = Object.freeze([...MANAGER_ROLES, "moderator"]);

function denied() {
  fail("permission-denied", "You do not have access to this server resource.");
}

function validRevision(value) {
  return Number.isSafeInteger(value) && value > 0 && value < Number.MAX_SAFE_INTEGER;
}

function canonicalMember(snapshot, uid, server) {
  const member = snapshot?.exists ? snapshot.data() : null;
  if (!member || member.userId !== uid || member.banned === true ||
      !ROLES.includes(member.role) || !validRevision(member.authorizationRevision) ||
      ((member.role === "owner") !== (server.ownerId === uid))) denied();
  return member;
}

function canonicalServer(snapshot, { allowHeld = false } = {}) {
  const server = snapshot?.exists ? snapshot.data() : null;
  if (!server || server.serverSchemaVersion !== 1 ||
      !SERVER_TYPES.includes(server.serverType) || server.templateVersion !== 1 ||
      server.type !== (server.serverType === "family" ? "family" : "community") ||
      !((server.serverActivationState === "active" && server.status === "active") ||
        (allowHeld && server.serverActivationState === "held" && server.status === "preparing")) ||
      !validRevision(server.revision) ||
      server.deletionInProgress === true) denied();
  return server;
}

async function readServerAccess({ db, transaction, uid, serverId, allowHeld = false }) {
  requireUid(uid);
  requireId(serverId, "serverId");
  const reference = db.doc(`clubs/${serverId}`);
  const membershipReference = reference.collection("members").doc(uid);
  const [snapshot, membership, profileSnapshot] = await transactionGetAll(
    transaction, reference, membershipReference, db.doc(`users/${uid}`),
  );
  const profile = activeProfile(profileSnapshot, "Your");
  // Missing, private and unsupported targets have the same denial shape.
  const server = canonicalServer(snapshot, { allowHeld });
  const member = canonicalMember(membership, uid, server);
  if (server.serverActivationState === "held" && member.role !== "owner") denied();
  return { reference, membershipReference, snapshot, membership, profile, server, member };
}

function requireServerManager(access, { ownerOnly = false } = {}) {
  if (!(ownerOnly ? ["owner", "coOwner"] : MANAGER_ROLES).includes(access.member.role)) denied();
  return access;
}

function canonicalChannel(snapshot, serverId, { allowArchived = false, allowDeleting = false } = {}) {
  const channel = snapshot?.exists ? snapshot.data() : null;
  if (!channel || channel.serverSchemaVersion !== 1 || channel.serverId !== serverId ||
      !CHANNEL_KINDS.includes(channel.kind) ||
      channel.type !== legacyChannelType(channel.kind) ||
      !validRevision(channel.revision) || !validRevision(channel.aclRevision) ||
      !["active", ...(allowArchived ? ["archived"] : []), ...(allowDeleting ? ["deleting"] : [])].includes(channel.status)) denied();
  try {
    const policy = accessPolicy(channel.accessPolicy);
    if (policy.accessMode !== channel.accessMode ||
        channel.isPrivate !== (policy.accessMode === "restricted")) denied();
    mediaConfiguration(channel.kind, channel.experience, channel.mediaMode);
    if (MEDIA_KINDS.includes(channel.kind)) requireId(channel.roomId, "roomId");
    else if (channel.roomId !== null) denied();
    if (channel.activeSessionId !== null) requireId(channel.activeSessionId, "activeSessionId");
  } catch {
    denied();
  }
  return channel;
}

function policyAllowsMember(channel, uid, member) {
  return channel.accessMode === "members" ||
    channel.accessPolicy.roleIds.includes(member.role) ||
    channel.accessPolicy.userIds.includes(uid);
}

function capabilitiesFor(channel, role) {
  const member = role !== "guest";
  const manager = MANAGER_ROLES.includes(role);
  const moderator = MODERATOR_ROLES.includes(role);
  const media = MEDIA_KINDS.includes(channel.kind);
  return {
    read: true,
    write: member && (!["announcements", "rules"].includes(channel.kind) || moderator),
    manage: manager,
    moderate: moderator,
    joinVoice: member && media,
    startSession: member && media && (channel.kind !== "stage" || moderator),
  };
}

function grantDocument({ uid, serverId, channelId, member, channel, now }) {
  return {
    schemaVersion: 1, userId: uid, serverId, channelId,
    aclRevision: channel.aclRevision,
    membershipRevision: member.authorizationRevision,
    capabilities: capabilitiesFor(channel, member.role),
    updatedAt: now,
  };
}

function grantMatches(grant, { uid, serverId, channelId, member, channel }) {
  if (!grant || grant.schemaVersion !== 1 || grant.userId !== uid ||
      grant.serverId !== serverId || grant.channelId !== channelId ||
      grant.aclRevision !== channel.aclRevision ||
      grant.membershipRevision !== member.authorizationRevision) return false;
  const expected = capabilitiesFor(channel, member.role);
  return grant.capabilities &&
    Object.keys(grant.capabilities).length === Object.keys(expected).length &&
    Object.entries(expected).every(([key, value]) => grant.capabilities[key] === value);
}

async function readChannelAccess({
  db, transaction, uid, serverId, channelId, capability = "read",
  allowHeld = false, allowArchived = false, allowDeleting = false, serverAccess = null,
}) {
  requireId(channelId, "channelId");
  const parent = serverAccess ?? await readServerAccess({ db, transaction, uid, serverId, allowHeld });
  const reference = parent.reference.collection("channels").doc(channelId);
  const snapshot = await transaction.get(reference);
  const channel = canonicalChannel(snapshot, serverId, { allowArchived, allowDeleting });
  if (!policyAllowsMember(channel, uid, parent.member)) denied();
  const capabilities = capabilitiesFor(channel, parent.member.role);
  if (channel.accessMode === "restricted") {
    const grant = await transaction.get(reference.collection("accessGrants").doc(uid));
    if (!grantMatches(grant.exists ? grant.data() : null, {
      uid, serverId, channelId, member: parent.member, channel,
    })) denied();
  }
  if (capabilities[capability] !== true) denied();
  return { ...parent, channelReference: reference, channelSnapshot: snapshot, channel, capabilities };
}

async function readBoundSessionAccess({ db, transaction, uid, serverId, channelId, sessionId, capability = "joinVoice" }) {
  requireId(sessionId, "sessionId");
  const access = await readChannelAccess({ db, transaction, uid, serverId, channelId, capability });
  if (!MEDIA_KINDS.includes(access.channel.kind) || access.channel.activeSessionId !== sessionId) denied();
  const [roomSnapshot, sessionSnapshot] = await transactionGetAll(
    transaction,
    db.doc(`rooms/${access.channel.roomId}`),
    access.channelReference.collection("channelSessions").doc(sessionId),
  );
  const room = roomSnapshot.exists ? roomSnapshot.data() : null;
  const session = sessionSnapshot.exists ? sessionSnapshot.data() : null;
  const rtcName = canonicalLiveKitRoomName(serverId, channelId, sessionId);
  if (!room || !session || room.serverSchemaVersion !== 1 || room.serverId !== serverId ||
      room.clubId !== serverId || room.channelId !== channelId || room.isLive !== true ||
      room.hostId !== access.server.ownerId || room.serverOwnerId !== access.server.ownerId ||
      room.serverActivationState !== "active" || session.serverSchemaVersion !== 1 ||
      room.status !== "active" || room.deletionInProgress === true ||
      room.voiceSessionId !== sessionId || room.livekitRoomName !== rtcName ||
      session.serverId !== serverId || session.channelId !== channelId ||
      session.roomId !== roomSnapshot.id || session.sessionId !== sessionId ||
      session.status !== "live" || session.livekitRoomName !== rtcName ||
      room.experience !== access.channel.experience || session.experience !== access.channel.experience ||
      room.mediaMode !== access.channel.mediaMode || session.mediaMode !== access.channel.mediaMode) denied();
  return { ...access, roomReference: roomSnapshot.ref, room, sessionReference: sessionSnapshot.ref, session, livekitRoomName: rtcName };
}

module.exports = {
  MANAGER_ROLES, MODERATOR_ROLES, canonicalChannel, canonicalMember,
  canonicalServer, capabilitiesFor, denied, grantDocument, grantMatches,
  policyAllowsMember, readBoundSessionAccess, readChannelAccess,
  readServerAccess, requireServerManager, validRevision,
};
