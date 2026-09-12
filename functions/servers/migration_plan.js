const crypto = require("node:crypto");
const { isValidOpaqueUid } = require("../achievements/identity");
const { canonicalChannelId, SERVER_TYPES } = require("./contract");
const { isVersionedServer } = require("../utils/server_access");

const MAX_MAPPING_RECORDS = 10000;
const SAFE_ID = /^[A-Za-z0-9_-]{1,128}$/u;
const own = (value, key) => Object.prototype.hasOwnProperty.call(value, key);
const plain = (value) => value !== null && typeof value === "object" &&
  [Object.prototype, null].includes(Object.getPrototypeOf(value));
const compare = (a, b) => a < b ? -1 : a > b ? 1 : 0;
const sha256 = (value) => crypto.createHash("sha256").update(value).digest("hex");

// This is an offline mapping report, NOT an apply manifest or a migration
// runner. In particular, zero participant counters are not proof of idleness.
const REQUIRED_NEXT_GATES = Object.freeze([
  "complete-related-record-and-media-generation-inventory",
  "canonical-owner-membership-ban-and-invitation-validation",
  "reviewed-private-admission-and-channel-access-mapping",
  "shared-free-paid-and-family-allocation-reconciliation",
  "compatible-client-and-idle-session-cutover-gate",
  "transaction-time-source-and-provider-generation-revalidation",
  "reviewed-resumable-apply-and-non-destructive-rollback",
  "separate-production-migration-approval",
]);

function invalid() {
  // Never interpolate supplied keys, paths, URLs or values into an error.
  throw new TypeError("Invalid server migration mapping inventory.");
}

function exact(value, keys) {
  if (!plain(value) || Object.keys(value).some((key) => !keys.includes(key)) ||
      keys.some((key) => !own(value, key))) invalid();
}

function sourceVersion(value) {
  exact(value, ["seconds", "nanoseconds"]);
  if (!Number.isSafeInteger(value.seconds) || value.seconds < 0 ||
      value.seconds > 253402300799 || !Number.isInteger(value.nanoseconds) ||
      value.nanoseconds < 0 || value.nanoseconds >= 1e9) invalid();
  return { seconds: value.seconds, nanoseconds: value.nanoseconds };
}

function indexSnapshots(values, kind) {
  const result = new Map();
  for (const value of values) {
    exact(value, kind === "channel"
      ? ["serverId", "id", "data", "updateTime"]
      : ["id", "data", "updateTime"]);
    if (typeof value.id !== "string" || !SAFE_ID.test(value.id) ||
        !plain(value.data) || (kind === "channel" &&
          (typeof value.serverId !== "string" || !SAFE_ID.test(value.serverId)))) invalid();
    const path = kind === "channel"
      ? `clubs/${value.serverId}/channels/${value.id}`
      : `${kind === "club" ? "clubs" : "rooms"}/${value.id}`;
    if (result.has(path)) invalid();
    const updateTime = sourceVersion(value.updateTime);
    result.set(path, { ...value, path, evidence: {
      path, updateTime,
      versionFingerprint: sha256(JSON.stringify([path, updateTime.seconds, updateTime.nanoseconds])),
    } });
  }
  return result;
}

function standaloneServerId(roomId) {
  if (typeof roomId !== "string" || !SAFE_ID.test(roomId)) invalid();
  // Hash the exact documented bytes; do not use a NUL-delimited digest here.
  return `legacy_room_${sha256(`rooms/${roomId}`).slice(0, 40)}`;
}

function report(source, reasons, values = {}) {
  return { sourcePath: source.path, sourceVersion: source.evidence,
    disposition: reasons.length ? "blocked" : "planned",
    reasons: [...new Set(reasons)].sort(compare), ...values };
}

function versioned(source, kind) {
  const hasBoundary = kind === "club" ? isVersionedServer(source.data)
    : own(source.data, "serverSchemaVersion") || own(source.data, "serverId");
  if (!hasBoundary) return null;
  if (!own(source.data, "serverSchemaVersion")) {
    return report(source, ["partial-versioned-boundary-needs-reconciliation"]);
  }
  return report(source, source.data.serverSchemaVersion === 1
    ? [] : ["unsupported-explicit-schema-version"], {
    disposition: source.data.serverSchemaVersion === 1 ? "already-versioned" : "blocked",
  });
}

function migrationType(source, fallback, privacy, ownerId, overrides, reasons) {
  const override = overrides.get(source.path);
  const serverType = override?.serverType ?? fallback;
  if (override && override.ownerId !== ownerId) reasons.push("owner-override-mismatch");
  if ((fallback === "family") !== (serverType === "family")) {
    reasons.push("family-allocation-conversion-requires-separate-review");
  }
  if ((serverType === "family" && privacy !== "inviteOnly") ||
      (["friends", "company"].includes(serverType) && privacy === "public")) {
    reasons.push("template-incompatible-with-existing-privacy");
  }
  return serverType;
}

function activeRoot(data, reasons) {
  if (data.status !== "active" || data.deletionInProgress === true) {
    reasons.push("source-not-active-or-being-deleted");
  }
}

/**
 * Consume a bounded operator-supplied metadata snapshot, without reading or
 * writing Firestore. The caller must not feed this report to a batch writer.
 * Names, message bodies, artwork URLs, tokens and transient roster identities
 * are intentionally absent from the output. Source IDs are for local review.
 */
function planLegacyServerMappings(input) {
  exact(input, ["clubs", "rooms", "channels", "ownerOverrides"]);
  const lists = [input.clubs, input.rooms, input.channels, input.ownerOverrides];
  if (lists.some((list) => !Array.isArray(list)) ||
      lists.reduce((sum, list) => sum + list.length, 0) > MAX_MAPPING_RECORDS) invalid();
  const clubs = indexSnapshots(input.clubs, "club");
  const rooms = indexSnapshots(input.rooms, "room");
  const channels = indexSnapshots(input.channels, "channel");
  const overrides = new Map();
  for (const value of input.ownerOverrides) {
    exact(value, ["sourceKind", "sourceId", "ownerId", "serverType"]);
    if (!["club", "room"].includes(value.sourceKind) ||
        typeof value.sourceId !== "string" || !SAFE_ID.test(value.sourceId) ||
        !isValidOpaqueUid(value.ownerId) || !SERVER_TYPES.includes(value.serverType)) invalid();
    const path = `${value.sourceKind === "club" ? "clubs" : "rooms"}/${value.sourceId}`;
    if (overrides.has(path) || !(value.sourceKind === "club" ? clubs : rooms).has(path)) invalid();
    overrides.set(path, value);
  }

  const mappings = [];
  const clubMappings = new Map();
  const channelsByRoom = new Map();
  const bindingIssues = [];
  for (const channel of channels.values()) {
    const data = channel.data;
    if (!clubs.has(`clubs/${channel.serverId}`)) {
      bindingIssues.push({ sourcePath: channel.path, reason: "missing-parent-server" });
    }
    if (data.roomId === null || data.roomId === undefined) continue;
    if (typeof data.roomId !== "string" || !SAFE_ID.test(data.roomId)) {
      bindingIssues.push({ sourcePath: channel.path, reason: "malformed-room-reference" });
      continue;
    }
    const candidates = channelsByRoom.get(data.roomId) ?? [];
    candidates.push(channel);
    channelsByRoom.set(data.roomId, candidates);
    if (!rooms.has(`rooms/${data.roomId}`)) {
      bindingIssues.push({ sourcePath: channel.path, reason: "missing-referenced-room" });
    }
  }

  for (const club of clubs.values()) {
    const existing = versioned(club, "club");
    if (existing) {
      clubMappings.set(club.id, existing);
      mappings.push(existing);
      continue;
    }
    const data = club.data;
    const reasons = [];
    activeRoot(data, reasons);
    if (!isValidOpaqueUid(data.ownerId)) reasons.push("missing-or-malformed-owner");
    const family = data.type === "family";
    if (data.type !== undefined && !["family", "community"].includes(data.type)) {
      reasons.push("unknown-legacy-server-type");
    }
    if (club.id.startsWith("family_") !== family) reasons.push("family-identity-conflict");
    if (!["public", "private", "inviteOnly"].includes(data.privacy)) reasons.push("unresolved-privacy");
    const serverType = migrationType(club, family ? "family" : "community",
      data.privacy, data.ownerId, overrides, reasons);
    for (const field of ["defaultChatChannelId", "defaultVoiceChannelId", "announcementChannelId"]) {
      const id = data[field];
      if (id === null || id === undefined) continue;
      if (typeof id !== "string" || !SAFE_ID.test(id) ||
          !channels.has(`clubs/${club.id}/channels/${id}`)) reasons.push("unresolved-default-channel");
    }
    if (data.loungeRoomId !== null && data.loungeRoomId !== undefined &&
        (typeof data.loungeRoomId !== "string" || !SAFE_ID.test(data.loungeRoomId) ||
          rooms.get(`rooms/${data.loungeRoomId}`)?.data.clubId !== club.id)) {
      reasons.push("unresolved-lounge-room");
    }
    const mapping = report(club, reasons, { serverId: club.id,
      ownerId: isValidOpaqueUid(data.ownerId) ? data.ownerId : null,
      serverType, privacy: ["public", "private", "inviteOnly"].includes(data.privacy) ? data.privacy : null,
      entitlementPolicyId: family ? "familyFreeV1" : "legacyCommunityPremiumV1",
      provenance: { version: 1, sourceKind: "club", sourceId: club.id },
      memberships: "preserve-canonical-members-after-full-inventory",
    });
    clubMappings.set(club.id, mapping);
    mappings.push(mapping);
  }

  for (const room of rooms.values()) {
    const existing = versioned(room, "room");
    if (existing) { mappings.push(existing); continue; }
    const data = room.data;
    const reasons = [];
    activeRoot(data, reasons);
    if (!isValidOpaqueUid(data.hostId)) reasons.push("missing-or-malformed-owner");
    const experience = data.experience === "podcast" ? "broadcast" : data.experience;
    if (!["community", "broadcast"].includes(experience)) reasons.push("unresolved-experience");
    if (!["public", "private"].includes(data.visibility)) reasons.push("unresolved-privacy");
    if (typeof data.isLive !== "boolean" || !Number.isSafeInteger(data.participantCount) ||
        data.participantCount < 0 || (data.voiceSessionId !== null && data.voiceSessionId !== undefined &&
          (typeof data.voiceSessionId !== "string" || !SAFE_ID.test(data.voiceSessionId)))) {
      reasons.push("unresolved-session-state");
    }
    const live = data.isLive === true || (Number.isSafeInteger(data.participantCount) && data.participantCount > 0);
    const candidates = channelsByRoom.get(room.id) ?? [];
    const bound = data.clubId !== undefined && data.clubId !== null;
    let values;
    if (bound) {
      const parent = typeof data.clubId === "string" && SAFE_ID.test(data.clubId)
        ? clubMappings.get(data.clubId) : null;
      if (!parent) reasons.push("missing-or-malformed-server-binding");
      else if (parent.disposition !== "planned") reasons.push("parent-requires-separate-review");
      if (parent?.ownerId && data.hostId !== parent.ownerId) reasons.push("bound-room-owner-conflict");
      if (overrides.has(room.path)) reasons.push("bound-room-type-is-owned-by-parent-server");
      if (candidates.length > 1 || candidates.some((channel) => channel.serverId !== data.clubId)) {
        reasons.push("ambiguous-reciprocal-channel");
      }
      const channel = candidates.length === 1 && candidates[0].serverId === data.clubId ? candidates[0] : null;
      if (channel && (own(channel.data, "serverSchemaVersion") || channel.data.type !== "voice" ||
          channel.data.isPrivate !== false)) reasons.push("channel-access-mapping-requires-review");
      if (data.channelId !== undefined && data.channelId !== null && data.channelId !== channel?.id) {
        reasons.push("conflicting-room-channel-pointer");
      }
      const channelId = channel?.id ?? (parent?.serverId
        ? canonicalChannelId(parent.serverId, `legacy-room:${room.id}`) : null);
      if (!channel && channelId && channels.has(`clubs/${data.clubId}/channels/${channelId}`)) {
        reasons.push("deterministic-channel-id-collision");
      }
      values = { serverId: parent?.serverId ?? null, channelId,
        serverType: parent?.serverType ?? null, ownerId: parent?.ownerId ?? null,
        bindingAction: channel ? "retain-reciprocal-link" : "review-deterministic-link-repair",
        reciprocalSourceVersion: channel?.evidence ?? null,
      };
    } else {
      if (candidates.length > 0) reasons.push("room-has-channel-reference-without-parent-binding");
      const serverId = standaloneServerId(room.id);
      const collision = clubs.get(`clubs/${serverId}`);
      // An existing target, even with matching provenance, needs a full graph
      // reconciliation. Never overwrite or treat a partial migration as done.
      if (collision) reasons.push("target-already-exists-reconcile-provenance-and-graph");
      if (data.channelId !== undefined && data.channelId !== null) reasons.push("channel-pointer-without-parent-binding");
      const fallbackType = experience === "broadcast" ? "podcast" : experience === "community" ? "community" : null;
      const serverType = migrationType(room, fallbackType,
        data.visibility, data.hostId, overrides, reasons);
      values = { serverId, channelId: "legacy_voice", serverType,
        ownerId: isValidOpaqueUid(data.hostId) ? data.hostId : null,
        privacy: ["public", "private"].includes(data.visibility) ? data.visibility : null,
        entitlementPolicyId: "legacyRoomV1",
        provenance: { version: 1, sourceKind: "room", sourceId: room.id },
        memberships: "owner-and-verified-durable-roomMembers-only",
        transientParticipants: "never-promote-to-durable-members-or-server-roles",
      };
    }
    const mapping = report(room, reasons, { ...values, originalRoomId: room.id,
      roomHistorySource: { kind: "legacyRoomMessages", roomId: room.id },
      preserveRoomMediaAndNotificationIdentity: true,
      sessionEvidence: { isLive: typeof data.isLive === "boolean" ? data.isLive : null,
        participantCount: Number.isSafeInteger(data.participantCount) ? data.participantCount : null,
        voiceSessionId: typeof data.voiceSessionId === "string" && SAFE_ID.test(data.voiceSessionId)
          ? data.voiceSessionId : null },
    });
    if (live) {
      mapping.reasons = [...new Set([...mapping.reasons, "active-session-must-not-be-migrated"])].sort(compare);
      if (mapping.disposition === "planned") mapping.disposition = "deferred";
    }
    mappings.push(mapping);
  }

  mappings.sort((a, b) => compare(a.sourcePath, b.sourcePath));
  bindingIssues.sort((a, b) => compare(a.sourcePath, b.sourcePath) || compare(a.reason, b.reason));
  const body = { reportVersion: 1, scope: "root-and-room-mapping-only", dryRun: true,
    writeCount: 0, applyReady: false, requiredNextGates: [...REQUIRED_NEXT_GATES], mappings, bindingIssues };
  return { ...body, reportDigest: sha256(JSON.stringify(body)) };
}

module.exports = { MAX_MAPPING_RECORDS, REQUIRED_NEXT_GATES, planLegacyServerMappings, standaloneServerId };
