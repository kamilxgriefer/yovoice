// A hand-seeded, canonical Servers V1 Community server for the channel
// messaging parity suites (reactions, photo/video messages). Every document
// carries exactly the shape authority.js validates, so a refusal in those
// suites is the callable's decision, never a fixture accident. Every fixture
// uses fresh uids and ids, so tests never share rate buckets or ledgers.

const { randomUUID } = require("node:crypto");

const ROLES = Object.freeze(["owner", "coOwner", "admin", "moderator", "member", "guest"]);

function channelDocument(serverId, kind, { restricted = false, roleIds = ["owner"], userIds = [] } = {}) {
  const type = kind === "voice" ? "voice"
    : ["announcements", "rules"].includes(kind) ? "announcement" : "chat";
  return {
    serverSchemaVersion: 1,
    serverId,
    kind,
    type,
    name: kind,
    position: 0,
    revision: 1,
    aclRevision: 1,
    status: "active",
    roomId: kind === "voice" ? `room-${serverId}` : null,
    activeSessionId: null,
    experience: kind === "voice" ? "community" : null,
    mediaMode: kind === "voice" ? "audio" : null,
    isPrivate: restricted,
    accessMode: restricted ? "restricted" : "members",
    accessPolicy: restricted
      ? { accessMode: "restricted", roleIds: [...roleIds].sort(), userIds: [...userIds].sort() }
      : { accessMode: "members", roleIds: [], userIds: [] },
  };
}

function capabilities(kind, role) {
  const member = role !== "guest";
  const moderator = ["owner", "coOwner", "admin", "moderator"].includes(role);
  return {
    read: true,
    write: member && (!["announcements", "rules"].includes(kind) || moderator),
    manage: ["owner", "coOwner", "admin"].includes(role),
    moderate: moderator,
    joinVoice: member && kind === "voice",
    startSession: member && kind === "voice",
  };
}

async function seedServerMessaging(db, Timestamp, { label = "msg", nowMs = 1_900_000_000_000 } = {}) {
  const suffix = randomUUID().slice(0, 8);
  const serverId = `srv-${label}-${suffix}`;
  const uid = (role) => `${label}-${role}-${suffix}`;
  const users = {
    owner: uid("owner"),
    coOwner: uid("coowner"),
    moderator: uid("moderator"),
    member: uid("member"),
    second: uid("second"),
    guest: uid("guest"),
    banned: uid("banned"),
    outsider: uid("outsider"),
    muted: uid("muted"),
    stranger: uid("stranger"),
  };
  const roles = {
    owner: "owner", coOwner: "coOwner", moderator: "moderator", member: "member",
    second: "member", guest: "guest", banned: "member", muted: "member", stranger: "member",
  };
  const now = Timestamp.fromMillis(nowMs);
  for (const [key, id] of Object.entries(users)) {
    await db.doc(`users/${id}`).set({ uid: id, displayName: `Canonical ${key}`, status: "active" });
  }
  await db.doc(`clubs/${serverId}`).set({
    serverSchemaVersion: 1,
    serverType: "community",
    templateVersion: 1,
    type: "community",
    serverActivationState: "active",
    status: "active",
    revision: 1,
    name: "Messaging parity",
    privacy: "inviteOnly",
    ownerId: users.owner,
    memberCount: 9,
  });
  for (const [key, role] of Object.entries(roles)) {
    await db.doc(`clubs/${serverId}/members/${users[key]}`).set({
      userId: users[key],
      displayName: `Canonical ${key}`,
      photoUrl: null,
      role,
      isOnline: false,
      joinedAt: now,
      invitedBy: null,
      authorizationRevision: 1,
      ...(key === "banned" ? { banned: true } : {}),
    });
  }
  await db.doc(`restrictions/${users.muted}`).set({ type: "communicationMute", expiresAt: null });

  const channels = {
    text: `text-${suffix}`,
    announcements: `announcements-${suffix}`,
    rules: `rules-${suffix}`,
    restricted: `restricted-${suffix}`,
    voice: `voice-${suffix}`,
  };
  await db.doc(`clubs/${serverId}/channels/${channels.text}`).set(channelDocument(serverId, "text"));
  await db.doc(`clubs/${serverId}/channels/${channels.announcements}`)
    .set(channelDocument(serverId, "announcements"));
  await db.doc(`clubs/${serverId}/channels/${channels.rules}`).set(channelDocument(serverId, "rules"));
  await db.doc(`clubs/${serverId}/channels/${channels.voice}`).set(channelDocument(serverId, "voice"));
  // Restricted to the owner role plus `member` (with a current grant) and
  // `stranger` (named in the policy, but with no grant at all).
  await db.doc(`clubs/${serverId}/channels/${channels.restricted}`).set(channelDocument(serverId, "text", {
    restricted: true, userIds: [users.member, users.stranger],
  }));
  for (const key of ["owner", "member"]) {
    await db.doc(`clubs/${serverId}/channels/${channels.restricted}/accessGrants/${users[key]}`).set({
      schemaVersion: 1,
      userId: users[key],
      serverId,
      channelId: channels.restricted,
      aclRevision: 1,
      membershipRevision: 1,
      capabilities: capabilities("text", roles[key]),
      updatedAt: now,
    });
  }

  async function message(channelKey, { senderKey = "second", id = `cm_${randomUUID().replaceAll("-", "")}`, ...fields } = {}) {
    const channelId = channels[channelKey];
    const data = {
      clubId: serverId,
      channelId,
      senderId: users[senderKey],
      senderName: `Canonical ${senderKey}`,
      senderPhotoUrl: null,
      content: "hello",
      sentAt: now,
      editedAt: null,
      isDeleted: false,
      ...fields,
    };
    await db.doc(`clubs/${serverId}/channels/${channelId}/messages/${id}`).set(data);
    return { id, channelId, path: `clubs/${serverId}/channels/${channelId}/messages/${id}` };
  }

  return { serverId, users, roles, channels, message, now, nowMs };
}

module.exports = { ROLES, capabilities, channelDocument, seedServerMessaging };
