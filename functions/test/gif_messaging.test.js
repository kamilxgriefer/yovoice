const assert = require("node:assert/strict");
const { after, beforeEach, test } = require("node:test");

// Real Firestore transactions are essential: GIF moderation and the kill
// switch must conflict with publication, and retries must preserve the
// existing message ledger and unread/slow-mode quotas. No provider/key or
// production project is contacted by this suite.
process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.NODE_ENV = "test";
const { deleteApp, initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");
const app = initializeApp({ projectId: "demo-yovoice-gif-messaging" }, "gif-messaging");
const db = getFirestore(app);
const {
  DEFAULT_LIMITS,
  createDirectMessagingService,
  validateMessage,
} = require("../messaging/direct_integrity");
const {
  DEFAULT_COMMUNITY_LIMITS,
  createCommunityMessagingService,
} = require("../messaging/community_integrity");
const { createGifCache } = require("../media/gif/cache");
const { createGifModeration } = require("../media/gif/moderation");
const { createGifFunctions, createGifRuntime } = require("../media/gif/catalog");
const { createFakeGifProvider } = require("../media/gif/fake_provider");
const { buildGifAsset } = require("../media/gif/normalize");
const { gifCdnUrl } = require("../media/gif/gif_ref");

const A = "gif-alice";
const B = "gif-bob";
const OTHER = "gif-outsider";
const ROOM = "gif-room";
const CLUB = "gif-club";
const CHANNEL = "chat";
const GIF = { provider: "giphy", id: "canonicalCat" };
const ASSET_PATH = `gifAssets/${GIF.provider}_${GIF.id}`;
const SURFACES = ["direct", "room", "club"];
const silentLog = { info() {}, warn() {}, error() {} };
let nowMs;
let conversationId;
let direct;
let community;
let serial;

function request(uid, data, verified = true) {
  return { auth: { uid, token: { email_verified: verified } }, data };
}

function services({ database = db, providerName = "giphy", directLimits, communityLimits } = {}) {
  return {
    direct: createDirectMessagingService({
      db: database,
      Timestamp,
      clock: () => nowMs,
      gifProviderName: providerName,
      ...(directLimits ? { limits: directLimits } : {}),
    }),
    community: createCommunityMessagingService({
      db: database,
      Timestamp,
      clock: () => nowMs,
      gifProviderName: providerName,
      ...(communityLimits ? { limits: communityLimits } : {}),
    }),
  };
}

function payload(surface, override = {}) {
  const target = surface === "direct" ? { conversationId }
    : surface === "room" ? { roomId: ROOM } : { clubId: CLUB, channelId: CHANNEL };
  return { ...target, requestId: `gif-request-${++serial}`, gif: GIF, ...override };
}

function send(surface, data = payload(surface), uid = B, writers = { direct, community }, verified = true) {
  const invoke = surface === "direct" ? writers.direct.sendDirectMessage
    : surface === "room" ? writers.community.sendRoomMessage : writers.community.sendClubMessage;
  return invoke(request(uid, data, verified));
}

function messages(surface) {
  return db.collection(surface === "direct" ? `conversations/${conversationId}/messages`
    : surface === "room" ? `rooms/${ROOM}/messages`
      : `clubs/${CLUB}/channels/${CHANNEL}/messages`);
}

async function seedUser(uid) {
  await db.doc(`users/${uid}`).set({ uid, displayName: uid, banned: false, disabled: false });
  await db.doc(`publicProfiles/${uid}`).set({
    uid, displayName: uid, username: uid, displayNameSearch: uid, usernameSearch: uid,
    photoUrl: null, bannerUrl: null, bio: "", country: "", nativeLanguage: "",
    spokenLanguages: [], learningLanguages: [], website: null, statusMessage: "",
    accountType: "personal", premiumIdentity: false, friendCount: 0, followerCount: 0,
    followingCount: 0, schemaVersion: 1, updatedAt: Timestamp.fromMillis(nowMs),
  });
}

async function seedAsset(overrides = {}) {
  await db.doc(ASSET_PATH).set({
    schemaVersion: 1, provider: GIF.provider, gifId: GIF.id, title: "Happy cat",
    rating: "g", url: gifCdnUrl(GIF.provider, GIF.id),
    previewUrl: gifCdnUrl(GIF.provider, GIF.id), width: 280, height: 200,
    blocked: false, reportCount: 0, ...overrides,
  });
}

async function clear() {
  const collections = await db.listCollections();
  for (const collection of collections) await db.recursiveDelete(collection);
}

beforeEach(async () => {
  await clear();
  nowMs = 1_900_000_000_000;
  serial = 0;
  ({ direct, community } = services());
  await Promise.all([seedUser(A), seedUser(B), seedUser(OTHER), seedAsset()]);
  ({ conversationId } = await direct.openDirectConversation(request(A, {
    targetUserId: B, requestId: "gif-open-conversation",
  })));
  await db.doc(`rooms/${ROOM}`).set({
    hostId: A, visibility: "public", status: "active", slowModeSeconds: 0,
    updatedAt: Timestamp.fromMillis(nowMs - 1000),
  });
  await db.doc(`rooms/${ROOM}/roomMembers/${B}`).set({ userId: B, role: "member" });
  await db.doc(`clubs/${CLUB}`).set({ ownerId: A, status: "active" });
  await db.doc(`clubs/${CLUB}/members/${B}`).set({ userId: B, role: "member" });
  await db.doc(`clubs/${CLUB}/channels/${CHANNEL}`).set({ type: "chat" });
});

after(async () => { await clear(); await db.terminate(); await deleteApp(app); });

for (const surface of SURFACES) {
  test(`${surface}: authorized GIF send derives the snapshot and a readable legacy fallback`, async () => {
    await seedAsset({ title: "\u202eHappy cat GIF by GIPHY", url: "https://attacker.invalid" });
    const result = await send(surface);
    const stored = (await messages(surface).doc(result.messageId).get()).data();
    assert.equal(stored.senderId, B);
    assert.equal(stored.type, "gif");
    assert.equal(stored[surface === "room" ? "text" : "content"], "GIF: Happy cat");
    assert.deepEqual(stored.gif, {
      ...GIF, title: "Happy cat", url: gifCdnUrl(GIF.provider, GIF.id), width: 280, height: 200,
    });
    if (surface === "direct") {
      assert.equal(stored.mediaUrl, null);
      assert.equal(stored.durationSeconds, null);
      assert.equal(stored.sequence, 1);
      const root = (await db.doc(`conversations/${conversationId}`).get()).data();
      assert.equal(root.lastMessage, "GIF: Happy cat");
      assert.equal(root.lastMessageType, "gif");
      assert.equal(root.unreadCounts[A], 1);
      validateMessage({ exists: true, data: () => stored }, conversationId);
    }
    assert.equal((await db.collection("gifProviderBudget").get()).size, 0);
  });

  test(`${surface}: duplicate retry commits once and changed asset ids cannot reuse the request`, async () => {
    const data = payload(surface);
    const first = await send(surface, data);
    const limits = (await db.collection("privateRateLimits").get()).docs
      .map((row) => [row.id, row.data()]);
    await db.doc(ASSET_PATH).update({ blocked: true });
    await db.doc("appConfig/gif").set({ enabled: false });
    // This acknowledges the already committed message; it never publishes
    // again, reopens a blocked asset or consumes another quota event.
    assert.deepEqual(await send(surface, data), first);
    assert.deepEqual((await db.collection("privateRateLimits").get()).docs
      .map((row) => [row.id, row.data()]), limits);
    await assert.rejects(send(surface, { ...data, gif: { ...GIF, id: "changed" } }),
      (error) => error.code === "already-exists");
    assert.equal((await messages(surface).get()).size, 1);
  });

  test(`${surface}: concurrent duplicate GIF requests produce one message`, async () => {
    const data = payload(surface);
    const results = await Promise.all(Array.from({ length: 4 }, () => send(surface, data)));
    assert.equal(new Set(results.map((result) => result.messageId)).size, 1);
    assert.equal((await messages(surface).get()).size, 1);
    if (surface === "direct") {
      const root = (await db.doc(`conversations/${conversationId}`).get()).data();
      assert.equal(root.lastMessageSequence, 1);
      assert.equal(root.unreadCounts[A], 1);
    }
  });

  test(`${surface}: disabled provider and the live kill switch refuse cached GIFs`, async () => {
    await assert.rejects(send(surface, payload(surface), B, services({ providerName: "none" })),
      (error) => error.code === "failed-precondition");
    await db.doc("appConfig/gif").set({ enabled: false });
    await assert.rejects(send(surface), (error) => error.code === "failed-precondition");
    assert.equal((await messages(surface).get()).size, 0);
  });

  test(`${surface}: blocked, non-g, unknown and mismatched assets are refused`, async () => {
    for (const overrides of [
      { blocked: true }, { rating: "pg" }, { rating: "unrated" },
      { provider: "fake" }, { gifId: "other" }, { blocked: "false" },
    ]) {
      await seedAsset(overrides);
      await assert.rejects(send(surface), (error) => error.code === "failed-precondition");
    }
    await db.doc(ASSET_PATH).delete();
    await assert.rejects(send(surface), (error) => error.code === "failed-precondition");
    assert.equal((await messages(surface).get()).size, 0);
  });

  test(`${surface}: auth, account status, communication sanctions and audience remain enforced`, async () => {
    await assert.rejects(send(surface, payload(surface), null),
      (error) => error.code === "unauthenticated");
    await assert.rejects(send(surface, payload(surface), B, undefined, false),
      (error) => error.code === "failed-precondition");
    await assert.rejects(send(surface, payload(surface), OTHER),
      (error) => error.code === "permission-denied");
    await db.doc(`users/${B}`).update({ banned: true });
    await assert.rejects(send(surface), (error) => error.code === "permission-denied");
    await db.doc(`users/${B}`).update({ banned: false });
    await db.doc(`restrictions/${B}`).set({ type: "communicationMute", expiresAt: null });
    await assert.rejects(send(surface), (error) => error.code === "permission-denied");
    assert.equal((await messages(surface).get()).size, 0);
  });

  test(`${surface}: rejects client URLs, titles, ratings and mixed text/GIF content`, async () => {
    for (const override of [
      { gif: { ...GIF, url: "https://attacker.invalid" } },
      { gif: { ...GIF, title: "Forged title" } },
      { gif: { ...GIF, rating: "g" } },
      { text: "caption" },
      { text: "" },
      { type: "gif" },
    ]) await assert.rejects(send(surface, payload(surface, override)),
      (error) => error.code === "invalid-argument");
    assert.equal((await messages(surface).get()).size, 0);
  });

  test(`${surface}: text requests keep their old stored shape and replay identity`, async () => {
    const data = payload(surface, { text: " unchanged text " });
    delete data.gif;
    const first = await send(surface, data);
    assert.deepEqual(await send(surface, data), first);
    const stored = (await messages(surface).doc(first.messageId).get()).data();
    assert.equal(Object.hasOwn(stored, "gif"), false);
    assert.equal(stored.type, surface === "direct" ? "text" : undefined);
    assert.equal(stored[surface === "room" ? "text" : "content"], "unchanged text");
  });

  test(`${surface}: GIF and text sends share the existing success quota`, async () => {
    const writers = services({
      directLimits: { ...DEFAULT_LIMITS, send: { maxEvents: 2, windowMs: 60_000 } },
      communityLimits: {
        ...DEFAULT_COMMUNITY_LIMITS,
        roomScope: { maxEvents: 2, windowMs: 60_000 },
        clubScope: { maxEvents: 2, windowMs: 60_000 },
      },
    });
    await send(surface, payload(surface), B, writers);
    const text = payload(surface, { text: "The same quota" });
    delete text.gif;
    await send(surface, text, B, writers);
    await assert.rejects(send(surface, payload(surface), B, writers),
      (error) => error.code === "resource-exhausted");
    assert.equal((await messages(surface).get()).size, 2);
  });

  test(`${surface}: refused GIFs still consume the independent attempt quota`, async () => {
    const writers = services({
      directLimits: { ...DEFAULT_LIMITS, send: { maxEvents: 2, windowMs: 60_000 } },
      communityLimits: {
        ...DEFAULT_COMMUNITY_LIMITS,
        roomAttempt: { maxEvents: 2, windowMs: 60_000 },
        clubAttempt: { maxEvents: 2, windowMs: 60_000 },
      },
    });
    await db.doc(ASSET_PATH).update({ blocked: true });
    for (let index = 0; index < 2; index += 1) {
      await assert.rejects(send(surface, payload(surface), B, writers),
        (error) => error.code === "failed-precondition");
    }
    await assert.rejects(send(surface, payload(surface), B, writers),
      (error) => error.code === "resource-exhausted");
    assert.equal((await messages(surface).get()).size, 0);
  });
}

test("direct: both block directions and changed recipient privacy refuse new GIFs", async () => {
  for (const path of [`users/${A}/blocked/${B}`, `users/${B}/blocked/${A}`]) {
    await db.doc(path).set({ uid: path.endsWith(A) ? A : B });
    await assert.rejects(send("direct"), (error) => error.code === "failed-precondition");
    await db.doc(path).delete();
  }
  await db.doc(`users/${A}`).update({ messagePrivacy: "nobody" });
  await assert.rejects(send("direct"), (error) => error.code === "permission-denied");
  assert.equal((await messages("direct").get()).size, 0);
});

test("direct: GIFs can be replied to, reacted to, read and deleted without schema errors", async () => {
  const sent = await send("direct");
  await direct.setDirectMessageReaction(request(A, {
    conversationId, messageId: sent.messageId, requestId: "gif-reaction-001", emoji: "❤️",
  }));
  await direct.sendDirectMessage(request(A, {
    conversationId, requestId: "gif-reply-0001", text: "Nice cat", replyToMessageId: sent.messageId,
  }));
  await direct.markDirectConversationRead(request(A, { conversationId, requestId: "gif-read-00001" }));
  await assert.rejects(direct.editDirectMessage(request(B, {
    conversationId, messageId: sent.messageId, requestId: "gif-edit-00001", text: "Changed",
  })), (error) => error.code === "failed-precondition");
  const removed = await direct.deleteDirectMessage(request(B, {
    conversationId, messageId: sent.messageId, requestId: "gif-delete-001",
  }));
  assert.equal(removed.changed, true);
  const tombstone = await messages("direct").doc(sent.messageId).get();
  assert.equal(tombstone.data().gif, null);
  validateMessage(tombstone, conversationId);
  const afterDeletion = await direct.sendDirectMessage(request(A, {
    conversationId, requestId: "gif-reply-after", text: "After removal", replyToMessageId: sent.messageId,
  }));
  assert.equal((await messages("direct").doc(afterDeletion.messageId).get()).data().replyToContent,
    "Message deleted");
  assert.equal((await db.collection("contentCleanupOutbox").get()).size, 0);
});

test("room: GIFs respect slow mode and private participant admission", async () => {
  await db.doc(`rooms/${ROOM}`).update({ slowModeSeconds: 30 });
  await send("room");
  await assert.rejects(send("room"), (error) => error.code === "resource-exhausted");
  await db.doc(`rooms/${ROOM}/roomMembers/${B}`).delete();
  await db.doc(`rooms/${ROOM}`).update({ visibility: "private", slowModeSeconds: 0 });
  await db.doc(`rooms/${ROOM}/participants/${B}`).set({ userId: B, role: "listener" });
  await assert.rejects(send("room"), (error) => error.code === "permission-denied");
  await db.doc(`rooms/${ROOM}/participants/${B}`).update({ admittedBy: A });
  await send("room");
  assert.equal((await messages("room").get()).size, 2);
});

test("club: announcement roles, banned memberships and inactive roots also gate GIFs", async () => {
  await db.doc(`clubs/${CLUB}/channels/${CHANNEL}`).update({ type: "announcement" });
  await assert.rejects(send("club"), (error) => error.code === "permission-denied");
  await db.doc(`clubs/${CLUB}/members/${B}`).update({ role: "moderator" });
  await send("club");
  await db.doc(`clubs/${CLUB}/members/${B}`).update({ banned: true });
  await assert.rejects(send("club"), (error) => error.code === "permission-denied");
  await db.doc(`clubs/${CLUB}/members/${B}`).update({ banned: false });
  await db.doc(`clubs/${CLUB}`).update({ status: "suspended" });
  await assert.rejects(send("club"), (error) => error.code === "failed-precondition");
});

test("catalog-to-message: a picker result sends on all surfaces without resolving the provider again", async () => {
  let resolveCalls = 0;
  const provider = createFakeGifProvider();
  const runtime = createGifRuntime({
    db, now: () => nowMs, log: silentLog,
    provider: { ...provider, resolve: async () => { resolveCalls += 1; throw new Error("Unexpected resolve"); } },
  });
  const catalog = createGifFunctions({
    runtime, providerName: "fake", registrars: { onCall: (_options, handler) => handler },
  });
  const page = await catalog.searchGifs(request(B, { query: "cat" }));
  assert.ok(page.items.length > 0);
  const selected = page.items[0];
  const writers = services({ providerName: "fake" });
  for (const surface of SURFACES) {
    await send(surface, payload(surface, { gif: { provider: selected.provider, id: selected.id } }), B, writers);
  }
  assert.equal(resolveCalls, 0);
});

test("cache re-observation preserves the durable moderation block and report count", async () => {
  const cache = createGifCache({ db, now: () => nowMs });
  const moderation = createGifModeration({ db, now: () => nowMs, cache });
  await db.doc(ASSET_PATH).update({ reportCount: 5 });
  await moderation.blockAsset({ provider: GIF.provider, gifId: GIF.id, blockedBy: "staff" });
  const item = buildGifAsset({ ...GIF, title: "A refreshed title", rating: "g", width: 200, height: 200 });
  const refreshed = await cache.writeAssets([item]);
  assert.equal(refreshed.blocked.has(`${GIF.provider}_${GIF.id}`), true);
  const stored = (await db.doc(ASSET_PATH).get()).data();
  assert.equal(stored.blocked, true);
  assert.equal(stored.reportCount, 5);
  for (const surface of SURFACES) {
    await assert.rejects(send(surface), (error) => error.code === "failed-precondition");
  }
});

test("discovery suppression remains distinct from a moderator block", async () => {
  await seedAsset({ suppressed: true, reportCount: 3 });
  for (const surface of SURFACES) await send(surface);
});

test("publication rechecks a block or kill switch that changes after authorization", async () => {
  for (const surface of SURFACES) {
    for (const changedPath of [ASSET_PATH, "appConfig/gif"]) {
      await seedAsset();
      await db.doc("appConfig/gif").set({ enabled: true });
      let changed = false;
      const database = {
        doc: db.doc.bind(db),
        runTransaction: (callback) => db.runTransaction((transaction) => {
          const current = new Proxy(transaction, {
            get(target, property) {
              if (property === "get") return async (reference) => {
                if (reference.path === changedPath && !changed) {
                  changed = true;
                  await db.doc(changedPath).update(changedPath === ASSET_PATH
                    ? { blocked: true } : { enabled: false });
                }
                return target.get(reference);
              };
              const value = target[property];
              return typeof value === "function" ? value.bind(target) : value;
            },
          });
          return callback(current);
        }),
      };
      await assert.rejects(send(surface, payload(surface), B, services({ database })),
        (error) => error.code === "failed-precondition");
      assert.equal(changed, true, `${surface} never rechecked ${changedPath}`);
      assert.equal((await messages(surface).get()).size, 0);
    }
  }
});
