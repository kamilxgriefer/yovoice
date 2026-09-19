// functions/scripts/repair_stale_server_channel_liveness.js against the local
// emulator only: a dry run writes nothing and classifies every seeded shape,
// --apply repairs only the provably stale projections, a second --apply is a
// no-op, and a projection backed by a live generation is never touched.
const assert = require("node:assert/strict");
const { randomUUID } = require("node:crypto");
const { after, test } = require("node:test");

const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
const enabled = typeof emulatorHost === "string" && /^(127\.0\.0\.1|localhost):[0-9]+$/u.test(emulatorHost);
const apps = [];
const {
  EXIT_REFUSED, EXIT_SUCCESS, accessDecision, parseArguments, run,
} = require("../scripts/repair_stale_server_channel_liveness");
const { createServerCreationService } = require("../servers/creation");
const { createServerSessionService } = require("../servers/sessions");
const { canonicalLiveKitRoomName, channelLiveness } = require("../servers/contract");

const emulatorTest = (name, fn) => test(name, {
  skip: enabled ? false : "Requires explicit localhost demo Firestore emulator.", timeout: 60_000,
}, fn);
const request = (uid, data) => ({ auth: { uid, token: { email_verified: true } }, data });
after(async () => { for (const app of apps) await require("firebase-admin/app").deleteApp(app); });

async function seeded() {
  const { initializeApp } = require("firebase-admin/app");
  const { getFirestore, Timestamp } = require("firebase-admin/firestore");
  const projectId = `demo-yovoice-repair-${randomUUID().slice(0, 8)}`;
  const app = initializeApp({ projectId }, `repair-${randomUUID()}`);
  apps.push(app);
  const db = getFirestore(app);
  const uid = `repair-owner-${randomUUID()}`;
  let nowMs = Date.now();
  const clock = () => nowMs;
  await db.doc(`users/${uid}`).set({ displayName: "Repair owner", status: "active" });
  const dependencies = { db, Timestamp, clock };
  const livekit = {
    assertSupported() { return "wss://test-fixture.livekit.cloud"; },
    async mintToken() { throw new Error("no token in this fixture"); },
    async revokeParticipant() { return { alreadyAbsent: false, revokedBeforeMillis: (Math.floor(nowMs / 1000) + 1) * 1000 }; },
    async endRoom() { return {}; },
    async roomOccupancy() { throw new Error("the repair script never reads the provider"); },
  };
  const sessions = createServerSessionService({ ...dependencies, livekit });
  const created = await createServerCreationService(dependencies).createServerV1(request(uid, {
    requestId: randomUUID(), serverType: "friends", templateVersion: 1,
    name: "Repair fixture", description: "", privacy: "inviteOnly", defaultLanguage: "English",
  }));
  const serverId = created.serverId;
  await db.doc(`clubs/${serverId}`).update({ status: "active", serverActivationState: "active" });
  const voices = (await db.collection(`clubs/${serverId}/channels`).where("kind", "==", "voice").get()).docs;
  for (const voice of voices) {
    await db.doc(`rooms/${voice.data().roomId}`).update({ status: "active", serverActivationState: "active", hostId: uid });
  }
  const [liveChannel, staleChannel] = voices;
  const start = (channel) => sessions.startServerChannelSessionV1(request(uid, { serverId, channelId: channel.id,
    requestId: randomUUID() }));
  // 1. A real live generation: never touched.
  const live = await start(liveChannel);
  // 2. A generation that ended, then a stranded badge with no pointer.
  const ended = await start(staleChannel);
  const receipt = await sessions.endServerChannelSessionV1(request(uid, { serverId, channelId: staleChannel.id,
    sessionId: ended.sessionId, requestId: randomUUID() }));
  assert.equal(receipt.status, "ended");
  const startedAt = Timestamp.fromMillis(nowMs - 2 * 60 * 60_000);
  const liveProjection = { schemaVersion: 1, isLive: true, startedAt };
  await staleChannel.ref.update({ liveness: liveProjection });
  // 3. A second server whose channels carry a pointer at the ended-and-gone
  // generation of another shape, and an unprovable live-looking generation.
  const other = await createServerCreationService(dependencies).createServerV1(request(uid, {
    requestId: randomUUID(), serverType: "friends", templateVersion: 1,
    name: "Repair fixture two", description: "", privacy: "inviteOnly", defaultLanguage: "English",
  }));
  await db.doc(`clubs/${other.serverId}`).update({ status: "active", serverActivationState: "active" });
  const [terminalChannel, ghostChannel] = (await db.collection(`clubs/${other.serverId}/channels`)
    .where("kind", "==", "voice").get()).docs;
  await terminalChannel.ref.update({ activeSessionId: `ss_${"3".repeat(40)}`, liveness: liveProjection });
  const ghostId = `ss_${"4".repeat(40)}`;
  await ghostChannel.ref.collection("channelSessions").doc(ghostId).set({ serverSchemaVersion: 1,
    serverId: other.serverId, channelId: ghostChannel.id, roomId: ghostChannel.data().roomId, sessionId: ghostId,
    status: "live", livekitRoomName: canonicalLiveKitRoomName(other.serverId, ghostChannel.id, ghostId),
    maxTokenExpiresAtMillis: 0 });
  await ghostChannel.ref.update({ activeSessionId: ghostId,
    liveness: { schemaVersion: 1, isLive: true, startedAt: Timestamp.fromMillis(nowMs - 48 * 60 * 60_000) } });
  const references = { live: liveChannel.ref, stale: staleChannel.ref, terminal: terminalChannel.ref, ghost: ghostChannel.ref };
  const snapshot = async () => Object.fromEntries(await Promise.all(Object.entries(references)
    .map(async ([key, reference]) => [key, (await reference.get()).data()])));
  return { projectId, db, serverId, otherServerId: other.serverId, live, references, snapshot, ids: {
    live: `${serverId}/${liveChannel.id}`, stale: `${serverId}/${staleChannel.id}`,
    terminal: `${other.serverId}/${terminalChannel.id}`, ghost: `${other.serverId}/${ghostChannel.id}`,
  } };
}

async function runScript(argv) {
  const out = [];
  const err = [];
  const code = await run({ argv, env: { ...process.env }, stdout: (text) => out.push(text), stderr: (text) => err.push(text) });
  return { code, out, err };
}

emulatorTest("a dry run classifies every shape and writes nothing; --apply repairs only the stale projections; a second --apply is a no-op", async () => {
  const f = await seeded();
  const before = await f.snapshot();
  const dry = await runScript(["--project", f.projectId]);
  assert.equal(dry.code, EXIT_SUCCESS, dry.err.join("\n"));
  assert.equal(dry.out[0], "server channel liveness repair: DRY RUN (no writes)");
  assert.ok(dry.out.includes(`ok-live ${f.ids.live}`), dry.out.join("\n"));
  assert.ok(dry.out.includes(`reset-null-session ${f.ids.stale} (dry run: would repair)`), dry.out.join("\n"));
  assert.ok(dry.out.includes(`reset-terminal-session ${f.ids.terminal} (dry run: would repair)`), dry.out.join("\n"));
  assert.ok(dry.out.some((line) => line.startsWith(`unresolved ${f.ids.ghost} (live-looking for over 24 h`)), dry.out.join("\n"));
  assert.ok(dry.out.includes("writes: 0"));
  assert.ok(dry.out.includes("live projections examined: 4"));
  assert.deepEqual(await f.snapshot(), before, "a dry run writes nothing");

  const applied = await runScript(["--project", f.projectId, "--apply"]);
  assert.equal(applied.code, EXIT_SUCCESS, applied.err.join("\n"));
  assert.equal(applied.out[0], "server channel liveness repair: APPLY (writes)");
  assert.ok(applied.out.includes(`reset-null-session ${f.ids.stale} (repaired)`), applied.out.join("\n"));
  assert.ok(applied.out.includes(`reset-terminal-session ${f.ids.terminal} (repaired)`), applied.out.join("\n"));
  assert.ok(applied.out.includes("writes: 2"));
  const after = await f.snapshot();
  assert.deepEqual(after.live, before.live, "a projection backed by a live generation is never touched");
  assert.deepEqual(after.ghost, before.ghost, "an unresolved shape is never written");
  assert.deepEqual(after.stale.liveness, channelLiveness());
  assert.equal(after.stale.activeSessionId, null);
  assert.equal(after.stale.revision, before.stale.revision, "the terminal fence leaves the revision alone");
  assert.deepEqual(after.terminal.liveness, channelLiveness());
  assert.equal(after.terminal.activeSessionId, null);
  assert.equal(after.terminal.revision, before.terminal.revision + 1);
  assert.equal(after.live.activeSessionId, f.live.sessionId);

  const again = await runScript(["--project", f.projectId, "--apply"]);
  assert.equal(again.code, EXIT_SUCCESS);
  assert.ok(again.out.includes("writes: 0"));
  assert.ok(again.out.includes("live projections examined: 2"));
  assert.deepEqual(await f.snapshot(), after, "a second --apply changes nothing");
});

test("the script refuses without an explicit project, with a non-local emulator host, and on malformed arguments", async () => {
  for (const argv of [[], ["--apply"], ["--project"], ["--project", "Bad_Project"], ["--project", "p", "--project", "q"],
    ["--project", "p", "--max-servers", "0"], ["--project", "p", "--max-servers", "5001"], ["--project", "p", "--force"]]) {
    assert.equal(parseArguments(argv).ok, false, JSON.stringify(argv));
    const { code, err } = await runScript(argv);
    assert.equal(code, EXIT_REFUSED, JSON.stringify(argv));
    assert.ok(err.join("\n").includes("Usage:"), JSON.stringify(argv));
  }
  assert.deepEqual(parseArguments(["--project", "demo-yovoice"]).value, { project: "demo-yovoice", apply: false, maxServers: 5000 });
  assert.equal(parseArguments(["--apply", "--project", "demo-yovoice"]).value.apply, true);
  assert.equal(accessDecision({ env: { FIRESTORE_EMULATOR_HOST: "10.0.0.5:8080" }, project: "demo-yovoice" }).allowed, false);
  assert.deepEqual(accessDecision({ env: { FIRESTORE_EMULATOR_HOST: "127.0.0.1:8080" }, project: "demo-yovoice" }),
    { allowed: true, projectId: "demo-yovoice", emulator: true });
  assert.deepEqual(accessDecision({ env: {}, project: "yovoice-ec54a" }),
    { allowed: true, projectId: "yovoice-ec54a", emulator: false });
  const refused = await run({ argv: ["--project", "demo-yovoice"], env: { FIRESTORE_EMULATOR_HOST: "remote.example:8080" },
    stdout: () => {}, stderr: () => {} });
  assert.equal(refused, EXIT_REFUSED);
});
