// setServerChannelMessageReactionV1: emoji reactions on Servers V1 channel
// messages, direct-message style (one reaction per person, fixed six). The
// authorization refusals come first; every case runs against the explicitly
// selected localhost Firestore emulator and never a cloud project.
const assert = require("node:assert/strict");
const { randomUUID } = require("node:crypto");
const { after, test } = require("node:test");

const { HttpsError } = require("firebase-functions/v2/https");
const { ALLOWED_DIRECT_REACTIONS } = require("../messaging/direct_integrity");
const { rateLimitReference } = require("../integrity/guards");
const {
  MAX_SERVER_MESSAGE_REACTORS,
  SERVER_MESSAGE_REACTION_LIMIT,
  SERVER_MESSAGE_REACTION_SCOPE,
  canonicalServerMessageReactions,
  createServerMessageReactionService,
} = require("../servers/message_reactions");
const {
  SERVER_MESSAGE_CALLABLE_METHODS,
  SERVER_MESSAGE_EXPORT_NAMES,
  createServerMessageFunctions,
} = require("../servers/registration");
const { seedServerMessaging } = require("./helpers/server_message_fixture");

const enabled = /^(127\.0\.0\.1|localhost):[0-9]+$/u.test(process.env.FIRESTORE_EMULATOR_HOST ?? "");
let app;
let db;
let Timestamp;
if (enabled) {
  const adminApp = require("firebase-admin/app");
  const firestore = require("firebase-admin/firestore");
  Timestamp = firestore.Timestamp;
  app = adminApp.initializeApp({ projectId: "demo-yovoice-server-message-reactions" },
    `server-message-reactions-${randomUUID()}`);
  db = firestore.getFirestore(app);
}
after(async () => { if (app) await require("firebase-admin/app").deleteApp(app); });

const NOW = 1_900_000_000_000;
const emulatorTest = (name, fn) => test(`Server message reactions: ${name}`, {
  skip: enabled ? false : "Requires explicit localhost Firestore emulator; no cloud fallback.",
  timeout: 60_000,
}, fn);
const request = (uid, data, verified = true) => ({ auth: { uid, token: { email_verified: verified } }, data });
const rejects = (promise, code) => assert.rejects(promise, (error) => {
  assert.equal(error.code, code, `${error.code}: ${error.message}`);
  return true;
});

async function fixture() {
  const seeded = await seedServerMessaging(db, Timestamp, { label: "react", nowMs: NOW });
  const service = createServerMessageReactionService({ db, Timestamp, clock: () => NOW });
  const react = (userKey, target, emoji, overrides = {}) => service.setServerChannelMessageReactionV1(
    request(seeded.users[userKey] ?? userKey, {
      serverId: seeded.serverId,
      channelId: target.channelId,
      messageId: target.id,
      emoji,
      requestId: randomUUID(),
      ...overrides,
    }),
  );
  const reactions = async (target) => (await db.doc(target.path).get()).data().reactions;
  return { ...seeded, service, react, reactions };
}

test("Server message reactions: the stored map is validated exactly", () => {
  assert.deepEqual(canonicalServerMessageReactions(undefined), {});
  assert.deepEqual(canonicalServerMessageReactions({ a: "❤️" }), { a: "❤️" });
  for (const bad of [null, [], "x", { a: "🙂" }, { a: 1 }, { "a/b": "❤️" }]) {
    assert.throws(() => canonicalServerMessageReactions(bad), (error) => error.code === "data-loss");
  }
  const oversized = Object.fromEntries(Array.from({ length: MAX_SERVER_MESSAGE_REACTORS + 1 },
    (_, index) => [`u${index}`, "👍"]));
  assert.throws(() => canonicalServerMessageReactions(oversized), (error) => error.code === "data-loss");
  // Imported from the direct-message path, never copied.
  assert.deepEqual([...ALLOWED_DIRECT_REACTIONS], ["❤️", "😂", "🔥", "😮", "😢", "👍"]);
});

test("Server message reactions: the extension table registers behind the activation gate with base options", async () => {
  const registrations = [];
  const register = (kind) => (options, handler) => {
    const entry = { kind, options, handler };
    registrations.push(entry);
    return entry;
  };
  const calls = [];
  const runtime = {
    db: {},
    clock: () => NOW,
    messageReactions: {
      setServerChannelMessageReactionV1: async (bound) => { calls.push(bound); return { ok: true }; },
    },
    messageMedia: Object.fromEntries([
      ...Object.entries(SERVER_MESSAGE_CALLABLE_METHODS)
        .filter(([, service]) => service === "messageMedia")
        .map(([name]) => [name, async () => ({ name })]),
      ["expireServerChannelMessageMediaReservations", async () => ({ expired: [], processed: 0, hasMore: false })],
      ["processServerChannelMessageMediaDeletionJobs", async () => ({ completed: [], processed: 0, hasMore: false })],
    ]),
  };
  let admitted = false;
  const gate = {
    requireCallable: async () => {
      if (!admitted) throw new HttpsError("failed-precondition", "Servers are not enabled for this account.");
      return {};
    },
    workersEnabled: async () => true,
  };
  const functions = createServerMessageFunctions({
    runtime,
    registrars: { onCall: register("callable"), onSchedule: register("schedule") },
    activationGate: gate,
    log: { info() {}, warn() {}, error() {} },
  });
  assert.equal(SERVER_MESSAGE_CALLABLE_METHODS.setServerChannelMessageReactionV1, "messageReactions");
  assert.ok(SERVER_MESSAGE_EXPORT_NAMES.includes("setServerChannelMessageReactionV1"));
  const entry = functions.setServerChannelMessageReactionV1;
  assert.equal(entry.kind, "callable");
  assert.equal(entry.options.region, "europe-west1");
  assert.equal(entry.options.minInstances, 0);
  assert.equal(entry.options.enforceAppCheck, false);
  assert.equal("secrets" in entry.options, false);
  await rejects(entry.handler({ data: {} }), "unauthenticated");
  await rejects(entry.handler(request("gate-user", { any: true })), "failed-precondition");
  assert.equal(calls.length, 0, "a disabled activation gate never reaches the factory");
  admitted = true;
  const data = { serverId: "s" };
  assert.deepEqual(await entry.handler({ ...request("gate-user", data), rawRequest: { headers: { x: "y" } } }),
    { ok: true });
  assert.deepEqual(Object.keys(calls[0]).sort(), ["auth", "data"]);
  assert.equal(calls[0].auth.uid, "gate-user");
});

emulatorTest("unauthenticated, unverified and malformed requests are refused before any write", async () => {
  const f = await fixture();
  const target = await f.message("text");
  await rejects(f.service.setServerChannelMessageReactionV1({ data: {
    serverId: f.serverId, channelId: target.channelId, messageId: target.id, emoji: "❤️", requestId: randomUUID(),
  } }), "unauthenticated");
  await rejects(f.service.setServerChannelMessageReactionV1(request(f.users.member, {
    serverId: f.serverId, channelId: target.channelId, messageId: target.id, emoji: "❤️", requestId: randomUUID(),
  }, false)), "failed-precondition");
  await rejects(f.react("member", target, "🙂"), "invalid-argument");
  await rejects(f.react("member", target, "❤️", { extra: true }), "invalid-argument");
  await rejects(f.react("member", target, "❤️", { requestId: "short" }), "invalid-argument");
  assert.equal(await f.reactions(target), undefined);
});

emulatorTest("non-members, banned members, departed members and guests are refused", async () => {
  const f = await fixture();
  const target = await f.message("text");
  await rejects(f.react("outsider", target, "❤️"), "permission-denied");
  await rejects(f.react("banned", target, "❤️"), "permission-denied");
  await rejects(f.react("guest", target, "❤️"), "permission-denied");
  // A member who left: the membership row is gone.
  await db.doc(`clubs/${f.serverId}/members/${f.users.second}`).delete();
  await rejects(f.react("second", target, "❤️"), "permission-denied");
  // A banned account profile is refused before any channel read.
  await db.doc(`users/${f.users.member}`).set({ banned: true }, { merge: true });
  await rejects(f.react("member", target, "❤️"), "permission-denied");
  assert.equal(await f.reactions(target), undefined);
});

emulatorTest("a communication mute blocks reacting", async () => {
  const f = await fixture();
  const target = await f.message("text");
  await rejects(f.react("muted", target, "👍"), "permission-denied");
  assert.equal(await f.reactions(target), undefined);
});

emulatorTest("restricted channels require a current grant; a stale or missing grant is refused", async () => {
  const f = await fixture();
  const target = await f.message("restricted", { senderKey: "owner" });
  await rejects(f.react("stranger", target, "❤️"), "permission-denied");
  await rejects(f.react("second", target, "❤️"), "permission-denied");
  assert.deepEqual(await f.react("member", target, "🔥"), {
    serverId: f.serverId, channelId: target.channelId, messageId: target.id, emoji: "🔥", changed: true,
  });
  await db.doc(`clubs/${f.serverId}/channels/${target.channelId}`).update({ aclRevision: 2 });
  await rejects(f.react("member", target, "❤️"), "permission-denied");
  assert.deepEqual(await f.reactions(target), { [f.users.member]: "🔥" });
});

emulatorTest("members react in announcements and rules channels where only moderators post; voice channels have no thread", async () => {
  const f = await fixture();
  const announcement = await f.message("announcements", { senderKey: "owner" });
  const rules = await f.message("rules", { senderKey: "moderator" });
  assert.equal((await f.react("member", announcement, "👍")).changed, true);
  assert.equal((await f.react("second", rules, "😮")).changed, true);
  assert.deepEqual(await f.reactions(announcement), { [f.users.member]: "👍" });
  await rejects(f.react("guest", announcement, "👍"), "permission-denied");
  const voice = await f.message("voice");
  await rejects(f.react("member", voice, "👍"), "permission-denied");
});

emulatorTest("add, replace and remove keep one reaction per person", async () => {
  const f = await fixture();
  const target = await f.message("text");
  assert.equal((await f.react("member", target, "❤️")).changed, true);
  assert.equal((await f.react("owner", target, "😂")).changed, true);
  assert.deepEqual(await f.reactions(target), { [f.users.member]: "❤️", [f.users.owner]: "😂" });
  assert.equal((await f.react("member", target, "🔥")).changed, true);
  assert.deepEqual(await f.reactions(target), { [f.users.member]: "🔥", [f.users.owner]: "😂" });
  assert.equal((await f.react("member", target, "🔥")).changed, false);
  assert.equal((await f.react("member", target, null)).changed, true);
  assert.deepEqual(await f.reactions(target), { [f.users.owner]: "😂" });
  assert.equal((await f.react("member", target, null)).changed, false);
  // Nothing else on the message moved.
  const data = (await db.doc(target.path).get()).data();
  assert.equal(data.content, "hello");
  assert.equal(data.isDeleted, false);
  assert.equal(data.senderId, f.users.second);
});

emulatorTest("a replay under the same requestId is idempotent and a different input is refused", async () => {
  const f = await fixture();
  const target = await f.message("text");
  const requestId = randomUUID();
  const first = await f.react("member", target, "❤️", { requestId });
  // Another person changes the map in between; the replay must not reapply.
  await f.react("owner", target, "👍");
  const replay = await f.react("member", target, "❤️", { requestId });
  assert.deepEqual(replay, first);
  assert.deepEqual(await f.reactions(target), { [f.users.member]: "❤️", [f.users.owner]: "👍" });
  await rejects(f.react("member", target, "😂", { requestId }), "already-exists");
  // A receipt never outlives access: after a ban the replay is refused too.
  await db.doc(`clubs/${f.serverId}/members/${f.users.member}`).update({ banned: true });
  await rejects(f.react("member", target, "❤️", { requestId }), "permission-denied");
});

emulatorTest("deleted, missing and mis-bound messages are refused", async () => {
  const f = await fixture();
  const deleted = await f.message("text", { isDeleted: true, content: "" });
  await rejects(f.react("member", deleted, "❤️"), "failed-precondition");
  await rejects(f.react("member", { channelId: f.channels.text, id: "cm_missing" }, "❤️"), "not-found");
  // A document stored under channel `text` that claims another channel.
  const misbound = await f.message("text", { channelId: f.channels.announcements });
  await rejects(f.react("member", misbound, "❤️"), "data-loss");
  const foreign = await f.message("text", { clubId: "another-server" });
  await rejects(f.react("member", foreign, "❤️"), "data-loss");
  const unknownType = await f.message("text", { type: "poll" });
  await rejects(f.react("member", unknownType, "❤️"), "failed-precondition");
  // gif, image and video messages are reactable.
  for (const type of ["gif", "image", "video"]) {
    const media = await f.message("text", { type });
    assert.equal((await f.react("member", media, "😢")).changed, true, type);
  }
});

emulatorTest("a malformed stored map fails closed with data-loss and is not repaired", async () => {
  const f = await fixture();
  const target = await f.message("text", { reactions: { [f.users.owner]: "🙂" } });
  await rejects(f.react("member", target, "❤️"), "data-loss");
  assert.deepEqual(await f.reactions(target), { [f.users.owner]: "🙂" });
});

emulatorTest("the 501st reactor is refused while existing reactors may still change", async () => {
  const f = await fixture();
  const full = { [f.users.second]: "❤️" };
  for (let index = 0; Object.keys(full).length < MAX_SERVER_MESSAGE_REACTORS; index += 1) {
    full[`filler-${index}`] = "👍";
  }
  const target = await f.message("text", { reactions: full });
  await rejects(f.react("member", target, "❤️"), "resource-exhausted");
  assert.equal((await f.react("second", target, "😂")).changed, true);
  assert.equal((await f.react("second", target, null)).changed, true);
  // One slot is free again.
  assert.equal((await f.react("member", target, "❤️")).changed, true);
  assert.equal(Object.keys(await f.reactions(target)).length, MAX_SERVER_MESSAGE_REACTORS);
});

emulatorTest("the per-user reaction rate limit is enforced", async () => {
  const f = await fixture();
  const target = await f.message("text");
  const now = Timestamp.fromMillis(NOW);
  await rateLimitReference(db, SERVER_MESSAGE_REACTION_SCOPE, f.users.member).set({
    schemaVersion: 1,
    ownerId: f.users.member,
    scope: SERVER_MESSAGE_REACTION_SCOPE,
    windowStartedAt: now,
    count: SERVER_MESSAGE_REACTION_LIMIT.maxEvents,
    updatedAt: now,
  });
  await rejects(f.react("member", target, "❤️"), "resource-exhausted");
  assert.equal(await f.reactions(target), undefined);
  assert.equal((await f.react("second", target, "❤️")).changed, true);
});

emulatorTest("legacy clubs and held servers are refused with the same shape as a missing server", async () => {
  const f = await fixture();
  const legacyId = `legacy-${randomUUID().slice(0, 8)}`;
  await db.doc(`clubs/${legacyId}`).set({ ownerId: f.users.owner, status: "active", name: "Legacy" });
  await db.doc(`clubs/${legacyId}/members/${f.users.member}`).set({ userId: f.users.member, role: "member" });
  await db.doc(`clubs/${legacyId}/channels/general`).set({ type: "chat" });
  await db.doc(`clubs/${legacyId}/channels/general/messages/m1`).set({
    clubId: legacyId, channelId: "general", senderId: f.users.owner, content: "x", isDeleted: false,
  });
  const legacyRequest = request(f.users.member, {
    serverId: legacyId, channelId: "general", messageId: "m1", emoji: "❤️", requestId: randomUUID(),
  });
  await rejects(f.service.setServerChannelMessageReactionV1(legacyRequest), "permission-denied");
  await rejects(f.service.setServerChannelMessageReactionV1(request(f.users.member, {
    serverId: "missing-server", channelId: "general", messageId: "m1", emoji: "❤️", requestId: randomUUID(),
  })), "permission-denied");
  assert.equal((await db.doc(`clubs/${legacyId}/channels/general/messages/m1`).get()).data().reactions, undefined);
  const target = await f.message("text");
  await db.doc(`clubs/${f.serverId}`).update({ serverActivationState: "held", status: "preparing" });
  await rejects(f.react("member", target, "❤️"), "permission-denied");
});
