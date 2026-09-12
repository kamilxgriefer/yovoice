const assert = require("node:assert/strict");
const { test } = require("node:test");
const {
  CHANNEL_KINDS, SERVER_TYPES, accessPolicy, canonicalChannelId,
  canonicalLiveKitRoomName, canonicalServerId, channelCreationInput, creationInput,
} = require("../servers/contract");
const { canonicalChannel, canonicalServer, grantDocument, grantMatches } = require("../servers/authority");
const { templateChannels } = require("../servers/templates");
const { channelDocument } = require("../servers/documents");

const create = (overrides = {}) => ({
  requestId: "request-0001", serverType: "friends", templateVersion: 1,
  name: "Friends", description: "", privacy: "inviteOnly", defaultLanguage: "English", ...overrides,
});
const snapshot = (data) => ({ exists: true, data: () => data });
const throws = (fn, code) => assert.throws(fn, (error) => error.code === code);

test("V1 exact creation contract normalizes once and rejects forged authority", () => {
  assert.equal(creationInput(create({ name: "  Friends  " })).name, "Friends");
  for (const change of [
    { ownerId: "attacker" }, { memberCount: 99 }, { serverId: "chosen" },
    { templateVersion: 2 }, { serverType: "unknown" }, { name: "aa" },
    { description: "x".repeat(221) }, { privacy: "public" },
  ]) throws(() => creationInput(create(change)), "invalid-argument");
  throws(() => creationInput(create({ serverType: "family", privacy: "private" })), "invalid-argument");
  assert.equal(creationInput(create({ serverType: "podcast", privacy: "public" })).privacy, "public");
});

test("templates have stable navigation only and company HR defaults owner-restricted", () => {
  for (const type of SERVER_TYPES) {
    const english = templateChannels(type, "English");
    const polish = templateChannels(type, "Polish");
    assert.deepEqual(english.map((channel) => channel.seedKey), polish.map((channel) => channel.seedKey));
    assert.equal(new Set(english.map((channel) => channel.seedKey)).size, english.length);
    assert.ok(english.every((channel) => CHANNEL_KINDS.includes(channel.kind)));
    assert.ok(english.every((channel) => !Object.hasOwn(channel, "members") && !Object.hasOwn(channel, "messages")));
  }
  const privateSeeds = templateChannels("company", "Polish").filter((channel) => channel.accessMode === "restricted");
  assert.deepEqual(privateSeeds.map((channel) => channel.name), ["HR", "Zarząd"]);
});

test("identities are operation-stable, family-preserving and session-generation-bound", () => {
  const id = canonicalServerId("owner", "request-0001", "friends");
  assert.equal(id, canonicalServerId("owner", "request-0001", "friends"));
  assert.notEqual(id, canonicalServerId("other", "request-0001", "friends"));
  assert.equal(canonicalServerId("owner", "request-0001", "family"), "family_owner");
  assert.equal(canonicalChannelId(id, "general"), canonicalChannelId(id, "general"));
  assert.notEqual(canonicalLiveKitRoomName(id, "channel", "session1"), canonicalLiveKitRoomName(id, "channel", "session2"));
});

test("ACL contract rejects wildcard bypasses and client-derived capability maps", () => {
  throws(() => accessPolicy({ accessMode: "restricted", roleIds: ["admin"], userIds: [] }), "invalid-argument");
  throws(() => accessPolicy({ accessMode: "restricted", roleIds: ["owner", "staff"], userIds: [] }), "invalid-argument");
  throws(() => accessPolicy({ accessMode: "members", roleIds: ["owner"], userIds: [] }), "invalid-argument");
  throws(() => accessPolicy({ accessMode: "restricted", roleIds: ["owner"], userIds: [], capabilities: { read: true } }), "invalid-argument");
});

test("channel kinds cannot silently alter participation experience", () => {
  const base = { serverId: "server", requestId: "request-0001", name: "Channel", categoryId: null, accessMode: "members" };
  const voice = channelCreationInput({ ...base, kind: "voice", experience: "community", mediaMode: "audio" });
  assert.equal(voice.experience, "community");
  throws(() => channelCreationInput({ ...base, kind: "meeting", experience: "broadcast", mediaMode: "meeting" }), "invalid-argument");
  throws(() => channelCreationInput({ ...base, kind: "text", experience: "community" }), "invalid-argument");
});

test("explicit unknown versions and invalid held/active pairs deny instead of falling back", () => {
  const root = { serverSchemaVersion: 1, serverType: "friends", templateVersion: 1,
    type: "community", serverActivationState: "held", status: "preparing", revision: 1 };
  assert.equal(canonicalServer(snapshot(root), { allowHeld: true }), root);
  throws(() => canonicalServer(snapshot(root)), "permission-denied");
  throws(() => canonicalServer(snapshot({ ...root, status: "active" }), { allowHeld: true }), "permission-denied");
  throws(() => canonicalServer(snapshot({ ...root, serverSchemaVersion: 2 }), { allowHeld: true }), "permission-denied");
});

test("restricted grants match canonical member and ACL revisions and every capability", () => {
  const channel = channelDocument({ serverId: "server", channelId: "hr", uid: "owner", position: 0,
    now: 1, input: { kind: "text", name: "HR", categoryId: null, accessMode: "restricted", experience: null, mediaMode: null } });
  canonicalChannel(snapshot(channel), "server");
  const member = { userId: "owner", role: "owner", authorizationRevision: 1 };
  const context = { uid: "owner", serverId: "server", channelId: "hr", member, channel };
  const grant = grantDocument({ ...context, now: 1 });
  assert.equal(grantMatches(grant, context), true);
  assert.equal(grantMatches(grant, { ...context, member: { ...member, authorizationRevision: 2 } }), false);
  assert.equal(grantMatches(grant, { ...context, channel: { ...channel, aclRevision: 2 } }), false);
  assert.equal(grantMatches({ ...grant, capabilities: { ...grant.capabilities, write: false } }, context), false);
  assert.equal(grantMatches({ ...grant, capabilities: { ...grant.capabilities, platformAdmin: true } }, context), false);
});
