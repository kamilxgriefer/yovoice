const assert = require("node:assert/strict");
const { test } = require("node:test");
const {
  gifMessageFallback,
  isCanonicalMessageGif,
  messageInput,
  resolveMessageGif,
} = require("../messaging/gif_message");
const { validateMessage } = require("../messaging/direct_integrity");
const { gifCdnUrl } = require("../media/gif/gif_ref");
const { resolveGifAsset } = require("../media/gif");
const { createGifCache } = require("../media/gif/cache");
const { createGifFunctions, createGifRuntime } = require("../media/gif/catalog");

const gif = {
  provider: "giphy",
  id: "cat123",
  title: "Happy cat",
  url: gifCdnUrl("giphy", "cat123"),
  width: 280,
  height: 200,
};
const invalid = (error) => error.code === "invalid-argument";

test("GIF message requests accept identity only, preserving normalized text inputs", () => {
  assert.deepEqual(messageInput({ text: " hello " }, 500), { text: "hello" });
  assert.deepEqual(messageInput({ gif: { provider: "giphy", id: "cat123" } }, 500), {
    gif: { provider: "giphy", id: "cat123" },
  });
  for (const data of [
    {},
    { text: "", gif: { provider: "giphy", id: "cat123" } },
    { text: null, gif: { provider: "giphy", id: "cat123" } },
    { gif: null },
    { gif },
    { gif: { provider: "giphy", id: "cat123", url: "https://attacker.invalid" } },
    { gif: { provider: "giphy", id: "cat123", title: "Forged title" } },
    { gif: { provider: "giphy", id: "cat123", rating: "g" } },
    { gif: { provider: "none", id: "cat123" } },
  ]) assert.throws(() => messageInput(data, 500), invalid);
});

test("GIF message ids cannot escape the canonical CDN or Firestore path", () => {
  for (const id of ["", ".", "..", "__name__", "a/b", "a\\b", "a?b", "a#b",
    "a@b", "a%2Fb", "https://attacker.invalid", "a".repeat(129)]) {
    assert.throws(() => messageInput({ gif: { provider: "giphy", id } }, 500), invalid);
  }
});

test("legacy-client fallback is bounded, readable and strips control/bidi characters", () => {
  assert.equal(gifMessageFallback(gif), "GIF: Happy cat");
  assert.equal(gifMessageFallback({ title: "\u202e\u0000" }), "GIF");
  assert.equal(gifMessageFallback({ title: "\u202e hello \ncat " }),
    "GIF: hello cat");
  assert.equal(gifMessageFallback({ title: "x".repeat(500) }).length, 105);
});

test("stored GIF validation refuses arbitrary URLs and malformed metadata", () => {
  assert.equal(isCanonicalMessageGif(gif), true);
  assert.equal(isCanonicalMessageGif({ ...gif, title: "Cat GIF" }), true);
  assert.equal(gifMessageFallback({ ...gif, title: "Cat GIF" }), "GIF: Cat GIF");
  for (const changed of [
    { url: "https://attacker.invalid/cat.gif" },
    { url: `${gif.url}?tracker=1` },
    { id: "other" },
    { width: -1 },
    { height: 0 },
    { width: 4097 },
    { height: 2.5 },
    { title: "" },
    { title: "forged\u202e" },
    { rating: "g" },
  ]) assert.equal(isCanonicalMessageGif({ ...gif, ...changed }), false);
});

function message(overrides = {}) {
  return {
    schemaVersion: 2,
    sequence: 1,
    conversationId: "conversation1",
    senderId: "alice",
    type: "gif",
    content: "GIF: Happy cat",
    gif,
    mediaUrl: null,
    durationSeconds: null,
    sentAt: new Date("2026-09-10T12:00:00Z"),
    readBy: ["alice"],
    reactions: {},
    isDeleted: false,
    editedAt: null,
    replyToMessageId: null,
    replyToSenderId: null,
    replyToContent: null,
    ...overrides,
  };
}

test("canonical direct GIFs and redacted tombstones stay readable to later operations", () => {
  for (const data of [message(), message({ content: "", gif: null, isDeleted: true })]) {
    assert.deepEqual(validateMessage({ exists: true, data: () => data }, "conversation1"), data);
  }
  for (const data of [
    message({ content: "Forged fallback" }),
    message({ mediaUrl: gif.url }),
    message({ durationSeconds: 1 }),
    message({ type: "text" }),
    message({ content: "", isDeleted: true }),
    message({ gif: { ...gif, url: "https://attacker.invalid" } }),
  ]) {
    assert.throws(() => validateMessage({ exists: true, data: () => data }, "conversation1"),
      (error) => error.code === "data-loss");
  }
});

test("transactional resolution uses current asset state and never calls a provider", async () => {
  const paths = [];
  let providerCalls = 0;
  const result = await resolveGifAsset({
    db: { doc: (path) => ({ path }) },
    provider: gif.provider,
    gifId: gif.id,
    transaction: {
      async get(reference) {
        paths.push(reference.path);
        return { exists: true, data: () => ({
          schemaVersion: 1,
          provider: gif.provider,
          gifId: gif.id,
          blocked: false,
          rating: "g",
          title: "\u202eHappy cat GIF by GIPHY",
          url: "https://attacker.invalid/ignored.gif",
          width: -20,
          height: 5000,
        }) };
      },
    },
    gifProvider: { resolve: async () => { providerCalls += 1; return { items: [] }; } },
  });
  assert.equal(result.ok, true);
  assert.deepEqual(result.asset, { ...gif, width: 200 });
  assert.deepEqual(paths, ["gifAssets/giphy_cat123"]);
  assert.equal(providerCalls, 0);
});

test("transactional cache misses and unreadable authority cannot fall back to provider I/O", async () => {
  const input = {
    db: { doc: (path) => ({ path }) },
    provider: gif.provider,
    gifId: gif.id,
    gifProvider: { resolve: async () => { throw new Error("Provider must not be called"); } },
  };
  const result = await resolveGifAsset({
    ...input,
    transaction: { get: async () => ({ exists: false }) },
  });
  assert.deepEqual(result, { ok: false, reason: "unknown_asset" });
  await assert.rejects(resolveGifAsset({
    ...input,
    transaction: { get: async () => { throw new Error("read unavailable"); } },
  }), /read unavailable/u);
});

test("provider none refuses even a known asset without touching its record", async () => {
  await assert.rejects(resolveMessageGif({
    db: { doc: () => { throw new Error("Unexpected read"); } },
    transaction: { get: async () => { throw new Error("Unexpected read"); } },
    providerName: "none",
    gif: { provider: gif.provider, id: gif.id },
  }), (error) => error.code === "failed-precondition" &&
    error.details.code === "not_configured");
});

test("failed asset-cache reads never reset a moderation block", async () => {
  let writes = 0;
  const cache = createGifCache({ db: {
    collection: (name) => ({ doc: (id) => ({ id, path: `${name}/${id}` }) }),
    runTransaction: (callback) => callback({
      getAll: async () => { throw new Error("unavailable"); },
      set: () => { writes += 1; },
    }),
  } });
  const result = await cache.writeAssets([{
    ...gif,
    rating: "g",
    full: { url: gif.url, width: gif.width, height: gif.height },
    preview: { url: gif.url },
  }]);
  assert.equal(result.written.size, 0);
  assert.equal(writes, 0);
});

test("the secret-free catalog reports configured rollout without reading an unbound key", async () => {
  let keyReads = 0;
  const runtime = createGifRuntime({
    providerName: "giphy",
    apiKey: () => { keyReads += 1; throw new Error("This function binds no key"); },
    db: { collection: () => ({ doc: () => ({ get: async () => ({ exists: false }) }) }) },
    log: { info() {}, warn() {}, error() {} },
  });
  const callables = createGifFunctions({
    runtime,
    providerName: "giphy",
    registrars: { onCall: (_options, handler) => handler },
  });
  const result = await callables.getGifCatalog({
    auth: { uid: "alice", token: { email_verified: true } }, data: {},
  });
  assert.equal(result.available, true);
  assert.equal(result.provider, "giphy");
  assert.equal(keyReads, 0);
});
