// ADR-213 against the REAL Firestore emulator: one send allow-set serves YO
// Voice Originals and GIPHY on the direct, room and club paths, and a GIPHY
// id resolved by `resolveGif` is exactly what those transactions accept.
// Start the emulator first:  firebase emulators:start --only firestore
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
const app = initializeApp({ projectId: "demo-yovoice-gif-dual" }, "gif-dual-provider");
const db = getFirestore(app);
const { createDirectMessagingService } = require("../messaging/direct_integrity");
const { createCommunityMessagingService } = require("../messaging/community_integrity");
const { createGifFunctions, createGifRuntime } = require("../media/gif/catalog");
const { gifCdnUrl } = require("../media/gif/gif_ref");
const { createGiphyProvider } = require("../media/gif/giphy_provider");

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

// The production wiring (functions/index.js): the catalog provider stays
// `yovoice` and the send allow-set carries both providers (ADR-213).
function services({ database = db, providerNames = ["yovoice", "giphy"] } = {}) {
  return {
    direct: createDirectMessagingService({
      db: database,
      Timestamp,
      clock: () => nowMs,
      gifProviderName: "yovoice",
      gifProviderNames: providerNames,
    }),
    community: createCommunityMessagingService({
      db: database,
      Timestamp,
      clock: () => nowMs,
      gifProviderName: "yovoice",
      gifProviderNames: providerNames,
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


const ORIGINAL = { provider: "yovoice", id: "yoFire01" };

async function seedOriginal() {
  await db.doc(`gifAssets/${ORIGINAL.provider}_${ORIGINAL.id}`).set({
    schemaVersion: 1, provider: ORIGINAL.provider, gifId: ORIGINAL.id,
    title: "That is fire", rating: "g", url: gifCdnUrl(ORIGINAL.provider, ORIGINAL.id),
    previewUrl: gifCdnUrl(ORIGINAL.provider, ORIGINAL.id), width: 320, height: 200,
    blocked: false, reportCount: 0,
  });
}

for (const surface of SURFACES) {
  test(`${surface}: an Original and a GIPHY GIF both send through one allow-set`, async () => {
    await seedOriginal();
    for (const gif of [ORIGINAL, GIF]) {
      const result = await send(surface, payload(surface, { gif }));
      const stored = (await messages(surface).doc(result.messageId).get()).data();
      assert.equal(stored.type, "gif");
      assert.equal(stored.gif.provider, gif.provider);
      assert.equal(stored.gif.url, gifCdnUrl(gif.provider, gif.id));
    }
    assert.equal((await messages(surface).get()).size, 2);
  });

  test(`${surface}: an Originals-only allow-set still refuses GIPHY`, async () => {
    const writers = services({ providerNames: ["yovoice"] });
    await assert.rejects(send(surface, payload(surface), B, writers),
      (error) => error.code === "failed-precondition" &&
        error.details.code === "not_configured");
    assert.equal((await messages(surface).get()).size, 0);
  });

  test(`${surface}: a blocked GIPHY asset is refused while Originals keep sending`, async () => {
    await seedOriginal();
    await db.doc(ASSET_PATH).update({ blocked: true });
    await assert.rejects(send(surface), (error) => error.details?.code === "blocked");
    await send(surface, payload(surface, { gif: ORIGINAL }));
    assert.equal((await messages(surface).get()).size, 1);
  });
}

test("resolveGif writes the record that direct, room and club sends accept", async () => {
  await db.doc(ASSET_PATH).delete();
  const fetchCalls = [];
  const giphy = createGiphyProvider({
    apiKey: "test-only-not-a-key",
    fetchImpl: async (url) => {
      fetchCalls.push(url);
      return {
        ok: true,
        status: 200,
        json: async () => ({ data: {
          id: GIF.id, title: "canonical cat GIF", rating: "g",
          images: { fixed_height: {
            url: `https://media2.giphy.com/media/${GIF.id}/200h.gif`, width: "300", height: "200",
          } },
        } }),
      };
    },
  });
  const runtime = createGifRuntime({ db, provider: giphy, log: silentLog, now: () => nowMs });
  const callables = createGifFunctions({
    runtime,
    resolveRuntime: runtime,
    providerName: "yovoice",
    resolveProviders: ["giphy"],
    registrars: { onCall: (_options, handler) => handler },
  });
  const resolved = await callables.resolveGif(request(B, { ...GIF }));
  assert.equal(resolved.asset.url, gifCdnUrl(GIF.provider, GIF.id));
  assert.equal(fetchCalls.length, 1);
  const budget = await db.collection("gifProviderBudget").get();
  assert.equal(budget.size, 1);
  assert.equal(budget.docs[0].data().calls, 1);

  for (const surface of SURFACES) {
    const result = await send(surface, payload(surface));
    const stored = (await messages(surface).doc(result.messageId).get()).data();
    assert.deepEqual(stored.gif, {
      ...GIF, title: "canonical cat", url: gifCdnUrl(GIF.provider, GIF.id), width: 300, height: 200,
    });
  }
  // Every later send and re-resolve reads the record; GIPHY is asked once.
  await callables.resolveGif(request(B, { ...GIF }));
  assert.equal(fetchCalls.length, 1);
});
