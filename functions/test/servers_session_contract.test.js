const assert = require("node:assert/strict");
const { test } = require("node:test");
const {
  canonicalSessionId, deriveSessionGrant, sessionInput, tokenRecipientId,
} = require("../servers/session_contract");
const { cloudUrl, createServerLiveKitAdapter } = require("../servers/session_livekit");
const { mirrorBelongsTo, reconnectAfterMillis } = require("../servers/session_control");
const { canonicalLiveKitRoomName } = require("../servers/contract");

const base = { serverId: "server", channelId: "channel", sessionId: "session", requestId: "request-0001" };
const denied = (action) => assert.throws(action, (error) => error.code === "invalid-argument");

test("runtime payloads reject chosen owner/room/role/source authority and require retry identity", () => {
  assert.deepEqual(sessionInput(base), base);
  for (const extra of [{ roomId: "foreign" }, { uid: "victim" }, { role: "host" },
    { sources: ["camera"] }, { serverActivationState: "active" }, { sessionId: "../x" }, { requestId: "a" }]) {
    denied(() => sessionInput({ ...base, ...extra }));
  }
  denied(() => sessionInput(base, { session: false }));
  const { sessionId, ...start } = base;
  assert.deepEqual(sessionInput(start, { session: false }), start);
});

test("session/recipient IDs are deterministic, unambiguous and scoped to the canonical identity", () => {
  const id = canonicalSessionId("server", "channel", "owner", "request-0001");
  assert.equal(id, canonicalSessionId("server", "channel", "owner", "request-0001"));
  assert.notEqual(id, canonicalSessionId("server", "other", "owner", "request-0001"));
  assert.notEqual(id, canonicalSessionId("server", "channel", "other", "request-0001"));
  assert.notEqual(tokenRecipientId("a_b"), tokenRecipientId("a-b"));
});

test("source policy separates listener, microphone, camera, screen and screen audio; local mute retains role", () => {
  const access = (mediaMode) => ({ channel: { mediaMode } });
  const participant = (role, extra = {}) => ({ role, hostMuted: false, serverMuted: false, isMuted: true, ...extra });
  for (const mode of ["audio", "video", "meeting"]) {
    const listener = deriveSessionGrant(access(mode), participant("listener"));
    assert.equal(listener.canPublish, false);
    assert.deepEqual(listener.permittedTrackSources, []);
  }
  assert.deepEqual(deriveSessionGrant(access("audio"), participant("host")).permittedTrackSources, ["microphone"]);
  assert.deepEqual(deriveSessionGrant(access("video"), participant("guest")).permittedTrackSources, ["microphone", "camera"]);
  assert.deepEqual(deriveSessionGrant(access("meeting"), participant("guest")).permittedTrackSources, ["microphone", "camera"]);
  assert.deepEqual(deriveSessionGrant(access("meeting"), participant("host")).permittedTrackSources,
    ["microphone", "camera", "screen_share", "screen_share_audio"]);
  assert.equal(deriveSessionGrant(access("audio"), participant("guest")).canPublish, true);
  assert.equal(deriveSessionGrant(access("audio"), participant("host", { hostMuted: true })).canPublish, false);
  assert.throws(() => deriveSessionGrant(access("audio"), participant("unknown")), (error) => error.code === "permission-denied");
  assert.throws(() => deriveSessionGrant(access("unknown"), participant("host")), (error) => error.code === "permission-denied");
});

test("provider URL fails closed for self-hosted, credentials, paths and unreviewed origins", () => {
  assert.equal(cloudUrl("wss://test-fixture.livekit.cloud"), "wss://test-fixture.livekit.cloud");
  for (const url of ["https://test.livekit.cloud", "wss://localhost", "wss://test.livekit.cloud.attacker.test",
    "wss://user:test@test.livekit.cloud", "wss://test.livekit.cloud/room", "wss://test.livekit.cloud?q=x"]) {
    assert.throws(() => cloudUrl(url), (error) => error.code === "failed-precondition");
  }
});

test("real installed SDK signs generation-bound explicit source grants using test-only keys", async () => {
  const sdk = require("livekit-server-sdk");
  const key = "test-server-runtime-key";
  const secret = "test-server-runtime-secret-not-a-real-credential";
  const adapter = createServerLiveKitAdapter({ apiKey: () => key, apiSecret: () => secret,
    serverUrl: () => "wss://test-fixture.livekit.cloud" });
  const binding = { serverId: "server", channelId: "channel", roomId: "anchor", sessionId: "session", livekitRoomName: "srv_fixture" };
  const grant = deriveSessionGrant({ channel: { mediaMode: "meeting" } }, { role: "host", hostMuted: false, serverMuted: false });
  const mintStartedAt = Math.floor(Date.now() / 1000);
  const result = await adapter.mintToken({ uid: "test-user", participantName: "Test user", binding, sessionRole: "host", grant });
  const mintedAt = Math.floor(Date.now() / 1000);
  const claims = await new sdk.TokenVerifier(key, secret).verify(result.token);
  assert.equal(claims.video.room, "srv_fixture");
  assert.deepEqual(claims.video.canPublishSources, ["microphone", "camera", "screen_share", "screen_share_audio"]);
  assert.equal(claims.video.canUpdateOwnMetadata, false);
  assert.equal(claims.video.roomAdmin, undefined);
  assert.equal(claims.video.roomCreate, undefined);
  assert.equal(result.expiresAtMillis, claims.exp * 1000);
  // The installed SDK sets exp and nbf in separate clock reads; crossing a
  // second boundary legitimately makes their difference 299 rather than 300.
  assert.ok(claims.exp >= mintStartedAt + 300 && claims.exp <= mintedAt + 300);
  assert.ok(claims.nbf >= mintStartedAt && claims.nbf <= mintedAt);
  const { livekitRoomName, ...metadataBinding } = binding;
  assert.deepEqual(JSON.parse(claims.metadata), { uid: "test-user", role: "host", ...metadataBinding });
});

test("offline participant NOT_FOUND is not accepted as a positive Cloud token-revocation receipt", async () => {
  const calls = [];
  let absent = true;
  let nowMs = 10_000;
  const adapter = createServerLiveKitAdapter({ apiKey: () => "test-key", apiSecret: () => "test-secret",
    serverUrl: () => "wss://test-fixture.livekit.cloud", clock: () => nowMs,
    client: { async removeParticipant(room, uid, options) {
      calls.push({ room, uid, options });
      if (absent) throw Object.assign(new Error("not online"), { code: "not_found" });
      return {};
    } } });
  await assert.rejects(adapter.revokeParticipant("srv_fixture", "uid"), (error) => error.code === "unavailable");
  assert.equal(calls[0].options.revokeTokenTs, 11n);
  absent = false;
  nowMs = 100_000;
  const acknowledged = await adapter.revokeParticipant("srv_fixture", "uid");
  assert.equal(acknowledged.alreadyAbsent, false);
  assert.equal(calls[1].options.revokeTokenTs, 101n);
  assert.equal(acknowledged.revokedBeforeMillis, 101_000);
});

test("a generation-bound mirror is never confused with a newer or legacy session", () => {
  const binding = { serverId: "server", channelId: "channel", roomId: "anchor", sessionId: "old",
    livekitRoomName: "rtc_old", userId: "uid", participantIdentity: "uid" };
  const mirror = { serverSchemaVersion: 1, ...binding, tokenEpoch: 1 };
  assert.equal(mirrorBelongsTo(mirror, binding, 2), true);
  assert.equal(mirrorBelongsTo({ ...mirror, sessionId: "new" }, binding, 2), false);
  assert.equal(mirrorBelongsTo({ ...mirror, tokenEpoch: 2 }, binding, 2), false);
  assert.equal(mirrorBelongsTo({ ...mirror, serverSchemaVersion: undefined }, binding, 2), false);
});

test("per-recipient Cloud removal makes exactly one attempt after an ambiguous transport timeout", async () => {
  let calls = 0;
  const adapter = createServerLiveKitAdapter({ apiKey: () => "test-key", apiSecret: () => "test-secret",
    serverUrl: () => "wss://test-fixture.livekit.cloud", clock: () => 10_000,
    client: { async removeParticipant() {
      calls += 1;
      if (calls === 1) throw Object.assign(new Error("test-only ambiguous timeout"), { code: "deadline_exceeded" });
      return {}; // An automatic retry would falsely present this as safe ACK.
    } } });
  await assert.rejects(adapter.revokeParticipant("srv_fixture", "uid"));
  assert.equal(calls, 1);
});

test("reconnect deadline respects post-ACK skew and the whole-second revocation cutoff", () => {
  assert.equal(reconnectAfterMillis(10_000, 11_000), 12_000);
  assert.equal(reconnectAfterMillis(10_999, 11_000), 12_999);
  assert.equal(reconnectAfterMillis(12_500, 11_000), 14_500);
  assert.equal(reconnectAfterMillis(10_000, 15_000), 16_000);
});

const terminalContext = () => ({ version: 1, endOperationId: "terminal-operation",
  serverId: "server", channelId: "channel", roomId: "anchor", sessionId: "session",
  livekitRoomName: canonicalLiveKitRoomName("server", "channel", "session") });

test("terminal DeleteRoom requires its exact internal V1 generation binding before any provider call", async () => {
  let calls = 0;
  const adapter = createServerLiveKitAdapter({ apiKey: () => "test-key", apiSecret: () => "test-secret",
    serverUrl: () => "wss://test-fixture.livekit.cloud", client: {
      async deleteRoom() { calls += 1; },
      async listParticipants() { assert.fail("Terminal delete must not enumerate participants."); },
      async getParticipant() { assert.fail("Terminal delete must not look up participants."); },
      async removeParticipant() { assert.fail("Terminal delete must not perform another revocation pass."); },
    } });
  const context = terminalContext();
  for (const invalid of [undefined, null, {}, { ...context, version: 2 }, { ...context, authorized: true },
    { ...context, roomId: "../legacy" }, { ...context, endOperationId: null },
    { ...context, sessionId: "foreign" }, { ...context, livekitRoomName: "anchor" }]) {
    await assert.rejects(adapter.endRoom(context.livekitRoomName, invalid));
  }
  await assert.rejects(adapter.endRoom("anchor", context));
  assert.equal(calls, 0);
  assert.deepEqual(await adapter.endRoom(context.livekitRoomName, context), { alreadyAbsent: false, attempts: 1 });
  assert.equal(calls, 1);
});

test("installed SDK terminal transport performs exactly one DeleteRoom RPC with four-second timeout and no failover", async (t) => {
  const calls = []; const timeouts = []; let outcome = "success";
  t.mock.method(AbortSignal, "timeout", (milliseconds) => {
    timeouts.push(milliseconds); return new AbortController().signal;
  });
  t.mock.method(globalThis, "fetch", async (url, options) => {
    calls.push({ url: String(url), body: JSON.parse(options.body), signal: options.signal });
    if (outcome === "timeout") throw Object.assign(new Error("test-only ambiguous timeout"), { name: "TimeoutError" });
    const status = outcome === "absent" ? 404 : outcome === "unavailable" ? 503 : 200;
    return new Response(JSON.stringify(status === 200 ? {} : { code: status === 404 ? "not_found" : "unavailable" }),
      { status, headers: { "content-type": "application/json" } });
  });
  const adapter = createServerLiveKitAdapter({ apiKey: () => "test-terminal-key",
    apiSecret: () => "test-terminal-secret-not-a-real-credential",
    serverUrl: () => "wss://test-fixture.livekit.cloud" });
  const context = terminalContext();
  for (outcome of ["success", "absent", "unavailable", "timeout"]) {
    const before = calls.length;
    if (["success", "absent"].includes(outcome)) {
      assert.deepEqual(await adapter.endRoom(context.livekitRoomName, context),
        { alreadyAbsent: outcome === "absent", attempts: 1 });
    } else await assert.rejects(adapter.endRoom(context.livekitRoomName, context));
    assert.equal(calls.length - before, 1, `${outcome} must not trigger an SDK retry, region lookup or roster scan.`);
    assert.equal(calls.at(-1).url, "https://test-fixture.livekit.cloud/twirp/livekit.RoomService/DeleteRoom");
    assert.deepEqual(calls.at(-1).body, { room: context.livekitRoomName });
    assert.ok(calls.at(-1).signal instanceof AbortSignal);
    assert.equal(timeouts.at(-1), 4_000);
  }
  assert.equal(timeouts.length, 4);
});

test("only provider DeleteRoom absence is idempotent; missing configuration never becomes a deletion receipt", async () => {
  const context = terminalContext(); let called = false;
  const adapter = createServerLiveKitAdapter({ apiKey: () => "test-key", apiSecret: () => "test-secret",
    serverUrl: () => { throw Object.assign(new Error("test-only missing config"), { status: 404 }); },
    client: { async deleteRoom() { called = true; } } });
  await assert.rejects(adapter.endRoom(context.livekitRoomName, context));
  assert.equal(called, false);
});
