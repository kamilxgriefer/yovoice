const assert = require("node:assert/strict");
const { test } = require("node:test");
const crypto = require("node:crypto");
const { canonicalChannelId } = require("../servers/contract");
const { MAX_MAPPING_RECORDS, planLegacyServerMappings, standaloneServerId } = require("../servers/migration_plan");

// Independent offline QA. No Admin SDK, emulator, network or production
// inventory is needed. This verifies a mapping report, never an apply plan.
const stamp = (nanoseconds = 765432100) => ({ seconds: 1_800_000_000, nanoseconds });
const room = (id = "r1", patch = {}) => ({ id, updateTime: stamp(), data: {
  hostId: "owner", status: "active", visibility: "private", experience: "community",
  isLive: false, participantCount: 0, voiceSessionId: null, ...patch,
} });
const club = (id = "c1", patch = {}) => ({ id, updateTime: stamp(), data: {
  ownerId: "owner", status: "active", privacy: "private", type: "community", ...patch,
} });
const channel = (id = "voice", patch = {}, serverId = "c1") => ({ id, serverId,
  updateTime: stamp(), data: { roomId: "r1", type: "voice", isPrivate: false, ...patch } });
const inventory = (patch = {}) => ({ clubs: [], rooms: [], channels: [], ownerOverrides: [], ...patch });
const row = (report, path) => report.mappings.find((value) => value.sourcePath === path);
const invalid = (input) => assert.throws(() => planLegacyServerMappings(input), {
  name: "TypeError", message: "Invalid server migration mapping inventory.",
});
const freeze = (value) => {
  if (value && typeof value === "object") {
    Object.values(value).forEach(freeze);
    Object.freeze(value);
  }
  return value;
};

test("independent planner: frozen input is not mutated and invocation performs no filesystem/network/console work", async (t) => {
  const input = freeze(inventory({ clubs: [club()], rooms: [room("r1", { clubId: "c1" })], channels: [channel()] }));
  const before = structuredClone(input);
  const calls = [];
  const forbidden = (name) => () => { calls.push(name); throw new Error("Unexpected offline planner I/O"); };
  for (const [moduleName, methods] of [
    ["node:fs", ["readFileSync", "writeFileSync", "writeFile", "appendFileSync"]],
    ["node:http", ["request", "get"]], ["node:https", ["request", "get"]],
    ["node:net", ["connect", "createConnection"]],
  ]) {
    const module = require(moduleName);
    for (const method of methods) t.mock.method(module, method, forbidden(`${moduleName}.${method}`));
  }
  t.mock.method(globalThis, "fetch", forbidden("fetch"));
  for (const method of ["log", "warn", "error"]) t.mock.method(console, method, forbidden(`console.${method}`));
  const output = planLegacyServerMappings(input);
  await Promise.resolve();
  assert.equal(typeof output.then, "undefined");
  assert.deepEqual(input, before);
  assert.deepEqual(calls, []);
  assert.equal(output.applyReady, false);
  assert.equal(output.writeCount, 0);
});

test("independent planner: combined inventory bound includes overrides and accepts the exact record limit", () => {
  const rooms = Array.from({ length: MAX_MAPPING_RECORDS }, (_, index) => room(`limit_${index}`, { serverSchemaVersion: 1 }));
  const output = planLegacyServerMappings(inventory({ rooms }));
  assert.equal(output.mappings.length, MAX_MAPPING_RECORDS);
  assert.equal(output.applyReady, false);
  invalid(inventory({ rooms, ownerOverrides: [
    { sourceKind: "room", sourceId: "limit_0", ownerId: "owner", serverType: "community" },
  ] }));
});

test("independent planner: opaque UIDs preserve case, whitespace, Unicode and punctuation without aliasing", () => {
  for (const ownerId of ["Owner", "owner", " owner ", " ", "a:b@c.d", "é", "e\u0301", "osoba🛰", "x".repeat(128)]) {
    const input = inventory({ rooms: [room("r1", { hostId: ownerId })], ownerOverrides: [
      { sourceKind: "room", sourceId: "r1", ownerId, serverType: "company" },
    ] });
    const mapped = row(planLegacyServerMappings(input), "rooms/r1");
    assert.equal(mapped.ownerId, ownerId);
    assert.equal(mapped.disposition, "planned");
    assert.equal(mapped.privacy, "private");
  }
  const mismatched = row(planLegacyServerMappings(inventory({ rooms: [room("r1", { hostId: "é" })], ownerOverrides: [
    { sourceKind: "room", sourceId: "r1", ownerId: "e\u0301", serverType: "community" },
  ] })), "rooms/r1");
  assert.equal(mismatched.disposition, "blocked");
  assert.ok(mismatched.reasons.includes("owner-override-mismatch"));
});

test("independent planner: malformed owners fail closed without copying supplied hostile values", () => {
  for (const ownerId of [null, false, 123, "", "x".repeat(129), "bad/PRIVATE_OWNER", "bad\nPRIVATE_OWNER", "bad\u0000PRIVATE_OWNER"]) {
    const output = planLegacyServerMappings(inventory({ clubs: [club("c1", { ownerId })], rooms: [room("r1", { hostId: ownerId })] }));
    for (const mapped of output.mappings) {
      assert.equal(mapped.disposition, "blocked");
      assert.equal(mapped.ownerId, null);
      assert.ok(mapped.reasons.includes("missing-or-malformed-owner"));
    }
    assert.equal(JSON.stringify(output).includes("PRIVATE_OWNER"), false);
  }
});

test("independent planner: exact timestamp bounds preserve nanoseconds and bind reciprocal channel versions", () => {
  for (const updateTime of [{ seconds: 0, nanoseconds: 0 }, { seconds: 253402300799, nanoseconds: 999999999 }]) {
    const input = inventory({ rooms: [{ ...room(), updateTime }] });
    assert.deepEqual(row(planLegacyServerMappings(input), "rooms/r1").sourceVersion.updateTime, updateTime);
  }
  for (const updateTime of [{ seconds: -1, nanoseconds: 0 }, { seconds: 253402300800, nanoseconds: 0 },
    { seconds: 1, nanoseconds: -1 }, { seconds: 1, nanoseconds: 1.1 },
    { seconds: 1, nanoseconds: "1" }, { seconds: Infinity, nanoseconds: 0 },
    { seconds: 1, nanoseconds: 0, milliseconds: 1000 }]) invalid(inventory({ rooms: [{ ...room(), updateTime }] }));
  const input = inventory({ clubs: [club()], rooms: [room("r1", { clubId: "c1" })], channels: [channel()] });
  const initial = planLegacyServerMappings(input);
  input.channels[0].updateTime.nanoseconds += 1;
  const changed = planLegacyServerMappings(input);
  assert.notEqual(changed.reportDigest, initial.reportDigest);
  assert.notEqual(row(changed, "rooms/r1").reciprocalSourceVersion.versionFingerprint,
    row(initial, "rooms/r1").reciprocalSourceVersion.versionFingerprint);
});

test("independent planner: all inventory permutations retain identical sorted report and digest", () => {
  const source = inventory({ clubs: [club("c2"), club()], rooms: [room("r2"), room("r1", { clubId: "c1" })],
    channels: [channel("voice_b"), channel("voice_a"), channel("orphan", { roomId: "missing" }, "none")],
    ownerOverrides: [{ sourceKind: "club", sourceId: "c1", ownerId: "owner", serverType: "friends" },
      { sourceKind: "room", sourceId: "r2", ownerId: "owner", serverType: "podcast" }] });
  const initial = planLegacyServerMappings(source);
  for (let mask = 0; mask < 16; mask += 1) {
    const input = structuredClone(source);
    Object.values(input).forEach((values, index) => { if (mask & (1 << index)) values.reverse(); });
    assert.deepEqual(planLegacyServerMappings(input), initial);
  }
});

test("independent planner: duplicate paths and malformed envelopes always use the same non-leaking error", () => {
  const input = inventory({ clubs: [club()], rooms: [room()], channels: [channel()] });
  for (const key of ["clubs", "rooms", "channels"]) {
    const duplicate = structuredClone(input); duplicate[key].push(structuredClone(duplicate[key][0])); invalid(duplicate);
  }
  for (const input of [null, [], new Date(), inventory({ rooms: {} }),
    { ...inventory(), db: "SECRET_DB" }, inventory({ rooms: [room("../SECRET_PATH")] }),
    inventory({ clubs: [{ ...club(), updateTime: { seconds: 1, nanoseconds: 0, token: "SECRET_TOKEN" } }] }),
    inventory({ channels: [channel("voice", {}, "x/SECRET_PARENT")] })]) invalid(input);
});

test("independent planner: reserved object-key IDs remain distinct exact hashed paths", () => {
  const ids = ["__proto__", "constructor", "toString", "A", "a", "a-b", "a_b"];
  const output = planLegacyServerMappings(inventory({ rooms: ids.map((id) => room(id)) }));
  assert.equal(new Set(output.mappings.map((mapped) => mapped.serverId)).size, ids.length);
  for (const id of ids) {
    const exactHash = crypto.createHash("sha256").update(`rooms/${id}`).digest("hex").slice(0, 40);
    assert.equal(row(output, `rooms/${id}`).serverId, `legacy_room_${exactHash}`);
  }
});

test("independent planner: deterministic server/channel collisions never become successful repairs", () => {
  const generatedRoot = standaloneServerId("r1");
  const rootCollision = planLegacyServerMappings(inventory({ rooms: [room()], clubs: [club(generatedRoot)] }));
  assert.equal(row(rootCollision, "rooms/r1").disposition, "blocked");
  const generatedChannel = canonicalChannelId("c1", "legacy-room:r1");
  const channelCollision = planLegacyServerMappings(inventory({ clubs: [club()], rooms: [room("r1", { clubId: "c1" })],
    channels: [channel(generatedChannel, { roomId: null, type: "chat", messages: ["PRIVATE_COLLISION"] })] }));
  assert.equal(row(channelCollision, "rooms/r1").disposition, "blocked");
  assert.ok(row(channelCollision, "rooms/r1").reasons.includes("deterministic-channel-id-collision"));
  assert.equal(JSON.stringify(channelCollision).includes("PRIVATE_COLLISION"), false);
});

test("independent planner: explicit unknown schemas cannot produce legacy identities, even with owner overrides", () => {
  for (const version of [0, 2, "1", null, false, {}, []]) {
    const output = planLegacyServerMappings(inventory({ rooms: [room("r1", { serverSchemaVersion: version })],
      ownerOverrides: [{ sourceKind: "room", sourceId: "r1", ownerId: "owner", serverType: "company" }] }));
    const mapped = row(output, "rooms/r1");
    assert.equal(mapped.disposition, "blocked");
    assert.equal(mapped.serverId, undefined);
    assert.equal(mapped.ownerId, undefined);
    assert.deepEqual(mapped.reasons, ["unsupported-explicit-schema-version"]);
    assert.equal(output.applyReady, false);
  }
});

test("independent planner: overrides never broaden privacy or convert a transferred Family allocation", () => {
  const family = club("family_original", { type: "family", ownerId: "new:owner", privacy: "inviteOnly" });
  const preserved = row(planLegacyServerMappings(inventory({ clubs: [family] })), "clubs/family_original");
  assert.equal(preserved.ownerId, "new:owner"); assert.equal(preserved.serverId, "family_original");
  assert.equal(preserved.privacy, "inviteOnly"); assert.equal(preserved.entitlementPolicyId, "familyFreeV1");
  for (const serverType of ["friends", "company", "podcast"]) {
    const mapped = row(planLegacyServerMappings(inventory({ clubs: [family], ownerOverrides: [
      { sourceKind: "club", sourceId: family.id, ownerId: "new:owner", serverType },
    ] })), "clubs/family_original");
    assert.equal(mapped.disposition, "blocked"); assert.equal(mapped.privacy, "inviteOnly");
    assert.equal(mapped.entitlementPolicyId, "familyFreeV1");
  }
  for (const serverType of ["friends", "company", "family"]) {
    const mapped = row(planLegacyServerMappings(inventory({ rooms: [room("r1", { visibility: "public" })], ownerOverrides: [
      { sourceKind: "room", sourceId: "r1", ownerId: "owner", serverType },
    ] })), "rooms/r1");
    assert.equal(mapped.disposition, "blocked"); assert.equal(mapped.privacy, "public");
  }
});

test("independent planner: private content and historical session evidence never imply apply readiness", () => {
  const secret = "PRIVATE_PAYLOAD_DO_NOT_EXPORT";
  const input = inventory({ rooms: [room("r1", { voiceSessionId: "historical-session", name: secret,
    audioUrl: `https://example.invalid/?token=${secret}`, participantIds: [secret],
    participants: { [secret]: { role: "host" } }, messages: [{ text: secret }],
    storagePath: secret, token: secret, recording: { secret } })] });
  const output = planLegacyServerMappings(input);
  assert.equal(JSON.stringify(output).includes(secret), false);
  assert.equal(output.writeCount, 0); assert.equal(output.dryRun, true); assert.equal(output.applyReady, false);
  assert.ok(output.requiredNextGates.includes("complete-related-record-and-media-generation-inventory"));
  assert.ok(output.requiredNextGates.includes("compatible-client-and-idle-session-cutover-gate"));
  assert.equal(row(output, "rooms/r1").sessionEvidence.voiceSessionId, "historical-session");
  // The digest is a mapping-report fingerprint, not a content/apply manifest.
  input.rooms[0].data.messages[0].text = "DIFFERENT_PRIVATE_CONTENT";
  assert.equal(planLegacyServerMappings(input).reportDigest, output.reportDigest);
});

test("independent planner: known partial V1 markers cannot be proposed as ordinary legacy mappings", () => {
  const output = planLegacyServerMappings(inventory({
    clubs: [club("c1", { serverType: "company", serverActivationState: "held" })],
    rooms: [room("r1", { serverId: "existing_server" })],
  }));
  const mapped = [row(output, "clubs/c1"), row(output, "rooms/r1")];
  assert.deepEqual(mapped.map((value) => value.disposition), ["blocked", "blocked"]);
  assert.ok(mapped.every((value) => value.reasons.length > 0));
  assert.equal(output.applyReady, false);
  assert.equal(output.writeCount, 0);
});

test("independent planner: conflicting bound room host and server owner require explicit review", () => {
  const output = planLegacyServerMappings(inventory({
    clubs: [club("c1", { ownerId: "owner_a" })],
    rooms: [room("r1", { clubId: "c1", hostId: "owner_b" })],
    channels: [channel()],
  }));
  assert.equal(row(output, "clubs/c1").disposition, "planned");
  const mapped = row(output, "rooms/r1");
  assert.equal(mapped.disposition, "blocked");
  assert.ok(mapped.reasons.length > 0);
  assert.equal(output.applyReady, false);
  assert.equal(output.writeCount, 0);
});
