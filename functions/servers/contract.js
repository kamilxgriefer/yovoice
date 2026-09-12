const {
  digest,
  fail,
  normalizeText,
  requireExactInput,
  requireId,
  requireRequestId,
  requireSafeInteger,
  requireUid,
} = require("../integrity/guards");

const SERVER_SCHEMA_VERSION = 1;
const TEMPLATE_VERSION = 1;
const FREE_SERVER_LIMIT = 20;
const MAX_SERVER_CHANNELS = 100;
const MAX_ACCESS_SUBJECTS = 100;
const SERVER_TYPES = Object.freeze([
  "friends", "community", "podcast", "family", "company",
]);
const CHANNEL_KINDS = Object.freeze([
  "text", "voice", "stage", "events", "announcements", "rules", "questions",
  "episodes", "calendar", "memories", "list", "meeting", "whiteboard", "files",
]);
const ROLES = Object.freeze([
  "owner", "coOwner", "admin", "moderator", "member", "guest",
]);
const ROLE_POWER = Object.freeze({
  owner: 60, coOwner: 50, admin: 40, moderator: 30, member: 20, guest: 10,
});
const MEDIA_KINDS = Object.freeze(["voice", "stage", "meeting"]);

function requireEnum(value, values, label) {
  if (typeof value !== "string" || !values.includes(value)) {
    fail("invalid-argument", `${label} is invalid.`);
  }
  return value;
}

function text(value, maxLength, label, minLength = 0) {
  const result = normalizeText(value, maxLength, label, { allowEmpty: minLength === 0 });
  if (result.length < minLength || /[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/u.test(result)) {
    fail("invalid-argument", `${label} is invalid.`);
  }
  return result;
}

function canonicalServerId(uid, requestId, serverType) {
  requireUid(uid);
  requireRequestId(requestId);
  requireEnum(serverType, SERVER_TYPES, "serverType");
  if (serverType === "family") {
    // Retain the historical family ID. UIDs that cannot fit that historical
    // path are rejected rather than silently inventing a second identity.
    return requireId(`family_${uid}`, "family server id");
  }
  return `srv_${digest("server.create.v1", uid, requestId).slice(0, 40)}`;
}

function canonicalChannelId(serverId, identity) {
  requireId(serverId, "serverId");
  return `ch_${digest("server.channel.v1", serverId, identity).slice(0, 40)}`;
}

function canonicalChannelRoomId(serverId, channelId) {
  return `sr_${digest("server.channel.room.v1", requireId(serverId), requireId(channelId)).slice(0, 40)}`;
}

function serverChannelRefId(serverId, channelId) {
  return digest("server.channel.ref.v1", requireId(serverId), requireId(channelId));
}

// A V1 invitation lives for seven days. Long enough to be answered across a
// weekend, short enough that a forgotten invitation cannot become a standing
// admission capability; a manager re-issues one (new generation) after that.
const SERVER_INVITE_TTL_MS = 7 * 24 * 60 * 60_000;

/**
 * The invitee's private discovery pointer for one server's invitation, the
 * exact posture of `users/{uid}/serverChannelRefs`: server-authored, opaque
 * ids only, owner-readable, never client-writable, never authority. One
 * invitation exists per (server, invitee), so the server id is the key.
 */
function serverInviteRefPath(inviteeId, serverId) {
  return `users/${requireUid(inviteeId, "inviteeId")}/serverInviteRefs/${requireId(serverId, "serverId")}`;
}

function canonicalLiveKitRoomName(serverId, channelId, sessionId) {
  return `srv_${digest("server.session.v1", requireId(serverId), requireId(channelId), requireId(sessionId)).slice(0, 40)}`;
}

function validatedPrivacy(privacy, serverType) {
  requireEnum(privacy, ["public", "private", "inviteOnly"], "privacy");
  if (serverType === "family" && privacy !== "inviteOnly") {
    fail("invalid-argument", "Family servers require invitations.");
  }
  if (["friends", "company"].includes(serverType) && privacy === "public") {
    fail("invalid-argument", "This template requires a private server.");
  }
  return privacy;
}

function creationInput(data) {
  const fields = ["requestId", "serverType", "templateVersion", "name", "description", "privacy", "defaultLanguage"];
  const exact = requireExactInput(data, fields, fields);
  const serverType = requireEnum(exact.serverType, SERVER_TYPES, "serverType");
  if (exact.templateVersion !== TEMPLATE_VERSION) {
    fail("invalid-argument", "This template version is unsupported.");
  }
  return Object.freeze({
    requestId: requireRequestId(exact.requestId),
    serverType,
    templateVersion: TEMPLATE_VERSION,
    name: text(exact.name, 40, "name", 3),
    description: text(exact.description, 220, "description"),
    privacy: validatedPrivacy(exact.privacy, serverType),
    defaultLanguage: text(exact.defaultLanguage, 64, "defaultLanguage", 1),
  });
}

function sortedSubjects(values, validate, label) {
  if (!Array.isArray(values) || values.length > MAX_ACCESS_SUBJECTS) {
    fail("invalid-argument", `${label} is invalid.`);
  }
  const result = values.map((value) => validate(value, label));
  if (new Set(result).size !== result.length) fail("invalid-argument", `${label} contains duplicates.`);
  return result.sort();
}

function accessPolicy(value) {
  requireExactInput(value, ["accessMode", "roleIds", "userIds"], ["accessMode", "roleIds", "userIds"]);
  const mode = requireEnum(value.accessMode, ["members", "restricted"], "accessMode");
  const roleIds = sortedSubjects(value.roleIds, (role) => requireEnum(role, ROLES, "role"), "roleIds");
  const userIds = sortedSubjects(value.userIds, requireUid, "userIds");
  if (mode === "members" && (roleIds.length > 0 || userIds.length > 0)) {
    fail("invalid-argument", "A member channel does not accept access subjects.");
  }
  if (mode === "restricted" && !roleIds.includes("owner")) {
    fail("invalid-argument", "Restricted channels must explicitly retain owner access.");
  }
  return Object.freeze({ accessMode: mode, roleIds, userIds });
}

function categoryId(value) {
  return value === null ? null : requireId(value, "categoryId");
}

function mediaConfiguration(kind, experience, mediaMode) {
  if (!MEDIA_KINDS.includes(kind)) {
    if (experience !== null || mediaMode !== null) fail("invalid-argument", "This channel is not a media channel.");
    return { experience: null, mediaMode: null };
  }
  const expected = kind === "stage" ? "broadcast" : "community";
  if (experience !== expected || (kind === "voice" && mediaMode !== "audio") ||
      (kind === "meeting" && mediaMode !== "meeting") ||
      (kind === "stage" && !["audio", "video"].includes(mediaMode))) {
    fail("invalid-argument", "The channel media configuration is invalid.");
  }
  return { experience, mediaMode };
}

function channelCreationInput(data) {
  const required = ["serverId", "requestId", "kind", "name", "categoryId", "accessMode"];
  requireExactInput(data, [...required, "experience", "mediaMode"], required);
  const kind = requireEnum(data.kind, CHANNEL_KINDS, "kind");
  return Object.freeze({
    serverId: requireId(data.serverId, "serverId"),
    requestId: requireRequestId(data.requestId),
    kind,
    name: text(data.name, 80, "name", 1),
    categoryId: categoryId(data.categoryId),
    accessMode: requireEnum(data.accessMode, ["members", "restricted"], "accessMode"),
    ...mediaConfiguration(kind, data.experience ?? null, data.mediaMode ?? null),
  });
}

const CHANNEL_LIVENESS_VERSION = 1;

/**
 * The client-visible projection of a private session generation onto the
 * already-ACL-governed channel document: the grant that reveals the channel
 * reveals its liveness, so `channelSessions` and the V1 room anchor stay
 * closed. A live projection always carries the instant it started and an idle
 * one never does, so "live at an unknown time" cannot be represented.
 *
 * There is deliberately NO participantCount. Token admission is not
 * provider-connected presence (see createServerChannelTokenV1), so no honest
 * writer for a count exists until a verified presence webhook does. Rendering
 * "live, count unknown" is correct; deriving a count from token issuance is
 * not, and this shape makes that impossible rather than merely discouraged.
 */
function channelLiveness(startedAt = null) {
  return { schemaVersion: CHANNEL_LIVENESS_VERSION, isLive: startedAt !== null, startedAt };
}

function legacyChannelType(kind) {
  if (MEDIA_KINDS.includes(kind)) return "voice";
  return ["announcements", "rules"].includes(kind) ? "announcement" : "chat";
}

function revision(value, label = "revision") {
  return requireSafeInteger(value, label, { min: 1, max: Number.MAX_SAFE_INTEGER - 1 });
}

module.exports = {
  CHANNEL_KINDS, CHANNEL_LIVENESS_VERSION, FREE_SERVER_LIMIT, MAX_ACCESS_SUBJECTS,
  MAX_SERVER_CHANNELS, MEDIA_KINDS, ROLE_POWER, ROLES, SERVER_INVITE_TTL_MS, SERVER_SCHEMA_VERSION,
  SERVER_TYPES, TEMPLATE_VERSION, accessPolicy, canonicalChannelId, canonicalChannelRoomId,
  canonicalLiveKitRoomName, canonicalServerId, categoryId, channelCreationInput,
  channelLiveness, creationInput, legacyChannelType, mediaConfiguration, requireEnum,
  revision, serverChannelRefId, serverInviteRefPath, text, validatedPrivacy,
};
