const { fail } = require("../integrity/guards");
const {
  MEDIA_KINDS, accessPolicy, canonicalChannelRoomId, channelLiveness,
  legacyChannelType, serverChannelRefId,
} = require("./contract");
const { grantDocument, policyAllowsMember } = require("./authority");

function canonicalDisplayName(profile) {
  const value = profile?.displayName;
  if (typeof value !== "string" || value !== value.trim() ||
      value.length < 1 || value.length > 120) {
    fail("failed-precondition", "Your canonical display name is unavailable.");
  }
  return value;
}

function memberDocument(uid, profile, role, now, invitedBy = null, authorizationRevision = 1) {
  return {
    userId: uid, displayName: canonicalDisplayName(profile), photoUrl: null,
    role, isOnline: false, joinedAt: now, invitedBy, authorizationRevision,
  };
}

function membershipMirror(serverId, server, member) {
  return {
    clubId: serverId, name: server.name, avatarUrl: server.avatarUrl ?? null,
    role: member.role, joinedAt: member.joinedAt,
  };
}

function channelDocument({ serverId, channelId, input, uid, position, now, roomId = null }) {
  const restricted = input.accessMode === "restricted";
  return {
    serverSchemaVersion: 1, serverId, kind: input.kind,
    name: input.name, type: legacyChannelType(input.kind), position,
    isPrivate: restricted, accessMode: input.accessMode,
    accessPolicy: accessPolicy({
      accessMode: input.accessMode,
      roleIds: restricted ? ["owner"] : [],
      userIds: [],
    }),
    categoryId: input.categoryId, status: "active",
    roomId: MEDIA_KINDS.includes(input.kind)
      ? (roomId ?? canonicalChannelRoomId(serverId, channelId)) : null,
    activeSessionId: null, liveness: channelLiveness(),
    experience: input.experience, mediaMode: input.mediaMode,
    aclRevision: 1, revision: 1,
    historySource: { kind: "channelMessages" },
    ...(input.seedKey ? { seedKey: input.seedKey } : {}),
    createdBy: uid, createdAt: now, updatedAt: now,
  };
}

function channelRoomDocument({ serverId, channelId, server, channel, now }) {
  return {
    serverSchemaVersion: 1, serverId, channelId, clubId: serverId,
    serverActivationState: server.serverActivationState,
    hostId: server.serverActivationState === "held" ? null : server.ownerId,
    serverOwnerId: server.ownerId, hostName: server.ownerName, hostPhotoUrl: null,
    name: channel.name, description: server.description, category: "club",
    visibility: "private", language: server.defaultLanguage,
    maxParticipants: null, participantCount: 0, memberCount: server.memberCount,
    isLive: false, roomType: "community", roomKind: "serverChannel",
    status: server.serverActivationState === "held" ? "preparing" : "active",
    imageUrl: null, approvalRequired: false, slowModeSeconds: 0,
    autoMuteNewUsers: channel.kind === "stage", membersCanStartVoice: true,
    experience: channel.experience, mediaMode: channel.mediaMode,
    voiceSessionId: null, livekitRoomName: null,
    createdAt: now, updatedAt: now,
  };
}

function writeChannelGrant({ db, transaction, serverId, channelId, channel, member, now }) {
  const uid = member.userId;
  const reference = db.doc(`clubs/${serverId}/channels/${channelId}/accessGrants/${uid}`);
  const pointer = db.doc(`users/${uid}/serverChannelRefs/${serverChannelRefId(serverId, channelId)}`);
  if (channel.accessMode === "restricted" && policyAllowsMember(channel, uid, member)) {
    transaction.set(reference, grantDocument({ uid, serverId, channelId, channel, member, now }));
    // No name, last message, HR label or other private preview in discovery.
    transaction.set(pointer, { serverId, channelId });
  } else {
    transaction.delete(reference);
    transaction.delete(pointer);
  }
}

module.exports = {
  canonicalDisplayName, channelDocument, channelRoomDocument,
  memberDocument, membershipMirror, writeChannelGrant,
};
