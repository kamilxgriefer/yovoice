const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const { test } = require("node:test");
const { canonicalChannelId } = require("../servers/contract");
const { MAX_MAPPING_RECORDS, planLegacyServerMappings, standaloneServerId } = require("../servers/migration_plan");

const stamp = () => ({ seconds: 1700000000, nanoseconds: 123456789 });
function room(id = "room_a", patch = {}) {
  return { id, updateTime: stamp(), data: { hostId: "owner_a", status: "active",
    visibility: "public", experience: "community", isLive: false, participantCount: 0, ...patch } };
}
function club(id = "club_a", patch = {}) {
  return { id, updateTime: stamp(), data: { ownerId: "owner_a", status: "active",
    privacy: "public", type: "community", ...patch } };
}
function channel(id = "voice_a", patch = {}, serverId = "club_a") {
  return { id, serverId, updateTime: stamp(), data: { type: "voice", isPrivate: false,
    roomId: "room_a", ...patch } };
}
function inventory(patch = {}) {
  return { clubs: [], rooms: [], channels: [], ownerOverrides: [], ...patch };
}
function find(plan, sourcePath) { return plan.mappings.find((row) => row.sourcePath === sourcePath); }

test("mapping report is always dry-run, never an apply grant, including an empty inventory", () => {
  for (const input of [inventory(), inventory({ rooms: [room()] })]) {
    const plan = planLegacyServerMappings(input);
    assert.equal(plan.writeCount, 0);
    assert.equal(plan.applyReady, false);
    assert.equal(plan.dryRun, true);
    assert.equal(plan.scope, "root-and-room-mapping-only");
    assert.ok(plan.requiredNextGates.includes("separate-production-migration-approval"));
    assert.ok(plan.requiredNextGates.includes("transaction-time-source-and-provider-generation-revalidation"));
  }
});

test("standalone ID hashes exact source bytes and retains room, history and quota provenance", () => {
  const digest = crypto.createHash("sha256").update("rooms/room_a").digest("hex").slice(0, 40);
  const mapping = find(planLegacyServerMappings(inventory({ rooms: [room()] })), "rooms/room_a");
  assert.equal(mapping.disposition, "planned");
  assert.equal(mapping.serverId, `legacy_room_${digest}`);
  assert.equal(mapping.channelId, "legacy_voice");
  assert.equal(mapping.originalRoomId, "room_a");
  assert.deepEqual(mapping.roomHistorySource, { kind: "legacyRoomMessages", roomId: "room_a" });
  assert.equal(mapping.entitlementPolicyId, "legacyRoomV1");
  assert.deepEqual(mapping.provenance, { version: 1, sourceKind: "room", sourceId: "room_a" });
  assert.notEqual(standaloneServerId("room_a"), standaloneServerId("ROOM_a"));
});

test("experience mapping preserves Broadcast/podcast distinction and does not guess unknown values", () => {
  for (const [experience, expected] of [["broadcast", "podcast"], ["podcast", "podcast"], ["community", "community"]]) {
    const mapping = find(planLegacyServerMappings(inventory({ rooms: [room("room_a", { experience })] })), "rooms/room_a");
    assert.equal(mapping.serverType, expected);
    assert.equal(mapping.disposition, "planned");
  }
  for (const experience of [undefined, null, "purple"]) {
    const mapping = find(planLegacyServerMappings(inventory({ rooms: [room("room_a", { experience })] })), "rooms/room_a");
    assert.equal(mapping.disposition, "blocked");
    assert.equal(mapping.serverType, null);
    assert.ok(mapping.reasons.includes("unresolved-experience"));
  }
});

test("ordinary Club and transferred Family keep original IDs and separate allocations", () => {
  const plan = planLegacyServerMappings(inventory({ clubs: [club(),
    club("family_originalOwner", { ownerId: "newOwner", type: "family", privacy: "inviteOnly" })] }));
  assert.equal(find(plan, "clubs/club_a").serverId, "club_a");
  assert.equal(find(plan, "clubs/club_a").entitlementPolicyId, "legacyCommunityPremiumV1");
  const family = find(plan, "clubs/family_originalOwner");
  assert.equal(family.serverId, "family_originalOwner");
  assert.equal(family.ownerId, "newOwner");
  assert.equal(family.serverType, "family");
  assert.equal(family.entitlementPolicyId, "familyFreeV1");
  assert.equal(family.disposition, "planned");
});

test("family identity, missing owner and unresolved privacy are reported, never repaired by inference", () => {
  const sources = [club("family_bad"), club("bad_id", { type: "family", privacy: "inviteOnly" }),
    club("owner_missing", { ownerId: null }), club("private_unknown", { privacy: null })];
  const plan = planLegacyServerMappings(inventory({ clubs: sources }));
  assert.ok(plan.mappings.every((mapping) => mapping.disposition === "blocked"));
});

test("owner override selects type but never alters existing privacy, roles or paid entitlement", () => {
  const plan = planLegacyServerMappings(inventory({ clubs: [club("club_a", { privacy: "private" })],
    ownerOverrides: [{ sourceKind: "club", sourceId: "club_a", ownerId: "owner_a", serverType: "company" }] }));
  const mapping = find(plan, "clubs/club_a");
  assert.equal(mapping.serverType, "company");
  assert.equal(mapping.privacy, "private");
  assert.equal(mapping.entitlementPolicyId, "legacyCommunityPremiumV1");
  assert.equal(mapping.disposition, "planned");
  for (const override of [
    { ownerId: "other", serverType: "podcast" },
    { ownerId: "owner_a", serverType: "company" },
    { ownerId: "owner_a", serverType: "family" },
  ]) {
    const denied = planLegacyServerMappings(inventory({ clubs: [club()], ownerOverrides: [
      { sourceKind: "club", sourceId: "club_a", ...override },
    ] }));
    assert.equal(find(denied, "clubs/club_a").disposition, "blocked");
  }
});

test("all explicit schema versions are excluded from the legacy planner, including malformed selectors", () => {
  for (const serverSchemaVersion of [1, 2, null, "1", false]) {
    const result = planLegacyServerMappings(inventory({ clubs: [club("club_a", { serverSchemaVersion })],
      rooms: [room("room_a", { serverSchemaVersion })] }));
    for (const mapping of result.mappings) {
      assert.equal(mapping.disposition, serverSchemaVersion === 1 ? "already-versioned" : "blocked");
      assert.equal(mapping.serverId, undefined);
      assert.equal(mapping.provenance, undefined);
    }
  }
});

test("partial boundary markers including null and undefined never select the legacy mapper", () => {
  for (const value of [null, undefined, false, "future-value"]) {
    for (const marker of ["serverType", "serverActivationState"]) {
      const result = planLegacyServerMappings(inventory({ clubs: [club("club_a", { [marker]: value })] }));
      const mapped = find(result, "clubs/club_a");
      assert.equal(mapped.disposition, "blocked");
      assert.equal(mapped.serverId, undefined);
    }
    const result = planLegacyServerMappings(inventory({ rooms: [room("room_a", { serverId: value })] }));
    assert.equal(find(result, "rooms/room_a").disposition, "blocked");
    assert.equal(find(result, "rooms/room_a").serverId, undefined);
  }
});

test("conflicting bound room ownership cannot be silently reassigned by the mapping", () => {
  const result = planLegacyServerMappings(inventory({ clubs: [club()],
    rooms: [room("room_a", { clubId: "club_a", hostId: "different_owner" })], channels: [channel()] }));
  assert.equal(find(result, "rooms/room_a").disposition, "blocked");
  assert.ok(find(result, "rooms/room_a").reasons.includes("bound-room-owner-conflict"));
});

test("reciprocal bound room retains root/channel IDs without creating a second allocation", () => {
  const plan = planLegacyServerMappings(inventory({ clubs: [club()],
    rooms: [room("room_a", { clubId: "club_a" })], channels: [channel()] }));
  const mapping = find(plan, "rooms/room_a");
  assert.equal(mapping.disposition, "planned");
  assert.equal(mapping.serverId, "club_a");
  assert.equal(mapping.channelId, "voice_a");
  assert.equal(mapping.bindingAction, "retain-reciprocal-link");
  assert.equal(mapping.entitlementPolicyId, undefined);
  assert.equal(mapping.reciprocalSourceVersion.path, "clubs/club_a/channels/voice_a");
});

test("missing bound channel yields deterministic review proposal, never overwrites a colliding channel", () => {
  const input = inventory({ clubs: [club()], rooms: [room("room_a", { clubId: "club_a" })] });
  const mapping = find(planLegacyServerMappings(input), "rooms/room_a");
  assert.equal(mapping.channelId, canonicalChannelId("club_a", "legacy-room:room_a"));
  assert.equal(mapping.bindingAction, "review-deterministic-link-repair");
  input.channels.push(channel(mapping.channelId, { roomId: null, type: "chat" }));
  const collided = find(planLegacyServerMappings(input), "rooms/room_a");
  assert.equal(collided.disposition, "blocked");
  assert.ok(collided.reasons.includes("deterministic-channel-id-collision"));
});

test("ambiguous, cross-parent and unbound reverse references fail closed", () => {
  for (const [roomData, channelRows] of [
    [{ clubId: "club_a" }, [channel(), channel("voice_b")]],
    [{ clubId: "club_a" }, [channel("voice_a", {}, "club_b")]],
    [{}, [channel()]],
    [{ clubId: "" }, []],
    [{ channelId: "voice_a" }, []],
  ]) {
    const plan = planLegacyServerMappings(inventory({ clubs: [club()],
      rooms: [room("room_a", roomData)], channels: channelRows }));
    assert.equal(find(plan, "rooms/room_a").disposition, "blocked");
  }
});

test("restricted, malformed and versioned channels require reviewed access conversion", () => {
  for (const patch of [{ isPrivate: true }, { isPrivate: null }, { type: "chat" }, { serverSchemaVersion: 1 }]) {
    const plan = planLegacyServerMappings(inventory({ clubs: [club()],
      rooms: [room("room_a", { clubId: "club_a" })], channels: [channel("voice_a", patch)] }));
    assert.ok(find(plan, "rooms/room_a").reasons.includes("channel-access-mapping-requires-review"));
  }
});

test("existing target roots block even matching migration provenance until full graph reconciliation", () => {
  const id = standaloneServerId("room_a");
  for (const patch of [{}, { serverSchemaVersion: 1,
    migration: { version: 1, sourceKind: "room", sourceId: "room_a", state: "complete" } }]) {
    const plan = planLegacyServerMappings(inventory({ clubs: [club(id, patch)], rooms: [room()] }));
    assert.ok(find(plan, "rooms/room_a").reasons.includes("target-already-exists-reconcile-provenance-and-graph"));
  }
});

test("active sessions defer without a teardown operation; malformed liveness cannot be guessed idle", () => {
  for (const patch of [{ isLive: true }, { participantCount: 1 }]) {
    const result = planLegacyServerMappings(inventory({ rooms: [room("room_a", patch)] }));
    assert.equal(find(result, "rooms/room_a").disposition, "deferred");
    assert.equal(result.writeCount, 0);
  }
  for (const patch of [{ isLive: undefined }, { participantCount: -1 }, { participantCount: "0" }, { voiceSessionId: "../bad" }]) {
    const mapping = find(planLegacyServerMappings(inventory({ rooms: [room("room_a", patch)] })), "rooms/room_a");
    assert.ok(mapping.reasons.includes("unresolved-session-state"));
    assert.equal(mapping.disposition, "blocked");
  }
});

test("report excludes names, URLs, message bodies and transient roster roles; input stays unchanged", () => {
  const input = inventory({ rooms: [room("room_a", { name: "PRIVATE_NAME", imageUrl: "https://invalid.test/?token=SECRET",
    messages: [{ text: "PRIVATE_MESSAGE" }], participants: { visitor: { role: "admin", displayName: "TRANSIENT" } } })] });
  const before = structuredClone(input);
  const result = planLegacyServerMappings(input);
  const serialized = JSON.stringify(result);
  for (const text of ["PRIVATE_NAME", "SECRET", "PRIVATE_MESSAGE", "TRANSIENT", "visitor", "https://"]) {
    assert.equal(serialized.includes(text), false);
  }
  assert.deepEqual(input, before);
  assert.equal(find(result, "rooms/room_a").memberships, "owner-and-verified-durable-roomMembers-only");
});

test("digest is input-order independent and binds source nanoseconds exactly", () => {
  const input = inventory({ clubs: [club("club_b"), club()], rooms: [room("room_b"), room()],
    channels: [channel("chat_b", { roomId: null, type: "chat" }), channel("chat_a", { roomId: null, type: "chat" })] });
  const first = planLegacyServerMappings(input);
  for (const list of Object.values(input)) list.reverse();
  assert.deepEqual(planLegacyServerMappings(input), first);
  input.rooms[0].updateTime.nanoseconds += 1;
  assert.notEqual(planLegacyServerMappings(input).reportDigest, first.reportDigest);
});

test("dangling root/channel/default pointers are reported rather than silently repaired", () => {
  const plan = planLegacyServerMappings(inventory({ clubs: [club("club_a", {
    defaultVoiceChannelId: "missing", loungeRoomId: "missing",
  })], channels: [channel("orphan", {}, "no_root"), channel("bad_ref", { roomId: "../private" })] }));
  assert.equal(find(plan, "clubs/club_a").disposition, "blocked");
  assert.deepEqual(plan.bindingIssues.map((issue) => issue.reason).sort(),
    ["malformed-room-reference", "missing-parent-server", "missing-referenced-room"]);
});

test("bounded strict envelope refuses duplicates, traversal, imprecise timestamps and unexpected writes", () => {
  const cases = [
    { ...inventory(), apply: true },
    inventory({ rooms: [room(), room()] }),
    inventory({ rooms: [room("../bad")] }),
    inventory({ rooms: [{ ...room(), updateTime: { seconds: 1, nanoseconds: 1e9 } }] }),
    inventory({ rooms: [{ ...room(), updateTime: { seconds: 1.2, nanoseconds: 0 } }] }),
    inventory({ rooms: [{ ...room(), updateTime: null }] }),
    inventory({ rooms: [room()], ownerOverrides: [
      { sourceKind: "room", sourceId: "room_a", ownerId: "owner_a", serverType: "friends", privacy: "public" },
    ] }),
    inventory({ rooms: Array(MAX_MAPPING_RECORDS + 1).fill(room()) }),
  ];
  for (const input of cases) {
    assert.throws(() => planLegacyServerMappings(input), { name: "TypeError", message: "Invalid server migration mapping inventory." });
  }
});
