// Integration at the real service boundary with controlled Firestore/Storage
// adapters. No provider credential, production request or real signing key.
const assert = require("node:assert/strict");
const { test } = require("node:test");

const {
  DEFAULT_LIMITS,
  INLINE_REEL_MEDIA_GRANT_BUDGET_MS,
  MAX_INLINE_REEL_MEDIA_GRANTS,
  MEDIA_GRANT_TTL_MS,
  createReelService,
} = require("../reels/service");
const { InMemoryFirestore } = require("./helpers/in_memory_firestore");

const NOW_MS = 1_778_000_000_000;
const DAY_MS = 24 * 60 * 60 * 1000;
const VIEWER = "inline-viewer";
const AUTHOR = "inline-author";

function request(data = {}, uid = VIEWER) {
  return {
    auth: { uid, token: { email_verified: false } },
    data: { limit: 10, mediaGrants: true, ...data },
  };
}

function fixture({ limits = DEFAULT_LIMITS } = {}) {
  const db = new InMemoryFirestore();
  const state = { nowMs: NOW_MS };
  const calls = { metadata: [], header: [], revoke: [], sign: [], batches: [], logs: [] };
  const objects = new Map();
  const storage = {
    async getMetadata(path) {
      calls.metadata.push(path);
      return structuredClone(objects.get(path));
    },
    async readHeader(path, length) {
      calls.header.push({ path, length });
      return Buffer.from([0xff, 0xd8, 0xff, 0xe0]);
    },
    async revokeDownloadTokens(path) { calls.revoke.push(path); },
    async getSignedReadUrl(path, options) {
      calls.sign.push({ path, ...options });
      return `https://storage.googleapis.com/test-bucket/${path}` +
        `?generation=${options.generation}&X-Goog-Signature=fixture-signature`;
    },
    async deleteObject() {},
  };
  const originalGetAll = db.getAll.bind(db);
  db.getAll = async (...references) => {
    calls.batches.push(references.map(({ path }) => path));
    return originalGetAll(...references);
  };
  const service = createReelService({
    db,
    FieldPath: { documentId: () => "__name__" },
    Timestamp: { fromMillis: (value) => new Date(value) },
    storage,
    clock: () => state.nowMs,
    randomSeed: () => "1111111111111111",
    limits,
    log: { info: (...args) => calls.logs.push(args) },
  });
  db.seed(`users/${VIEWER}`, {
    uid: VIEWER, email: "private-viewer@example.invalid", phone: "private-phone",
  });
  function seed(id = "inline-reel", { authorId = AUTHOR, rank = 0, expiresAtMs } = {}) {
    if (!db.data(`users/${authorId}`)) {
      db.seed(`users/${authorId}`, {
        uid: authorId, email: "private-author@example.invalid", privateNote: "private-note",
      });
    }
    const publishedAt = new Date(NOW_MS - DAY_MS);
    const reel = {
      schemaVersion: 1,
      status: "published",
      moderationStatus: "visible",
      authorId,
      authorName: "Public creator name",
      media: {
        kind: "image", contentType: "image/jpeg", size: 1024, generation: "123",
        durationMs: 0, storagePath: `reels/${authorId}/${id}/media.jpg`,
      },
      backingAudio: null,
      composition: {
        caption: "Published caption",
        crop: { scalePermille: 1000, offsetXPermille: 0, offsetYPermille: 0 },
        filter: "original", trimStartMs: 0, trimEndMs: 0,
        textOverlays: [], linkOverlays: [], originalAudioVolume: 0,
        backingAudioVolume: 0, audioTrimStartMs: 0,
        audioRightsAttested: false, audioAttribution: "",
      },
      sortKey: `${String(NOW_MS - rank).padStart(13, "0")}_${id}`,
      publishedAt,
      updatedAt: publishedAt,
    };
    db.seed(`reels/${id}`, reel);
    objects.set(reel.media.storagePath, {
      generation: "123", contentType: "image/jpeg", size: "1024",
      metadata: {
        ownerId: authorId, reelId: id, assetKind: "media",
        firebaseStorageDownloadTokens: "private-durable-token",
      },
    });
    if (expiresAtMs !== undefined) {
      db.seed(`reelAvailability/${id}`, {
        schemaVersion: 2, status: "published", ownerId: authorId, reelId: id,
        availabilityHours: 24,
        createdAt: new Date(expiresAtMs - DAY_MS),
        publishedAt: new Date(expiresAtMs - DAY_MS),
        expiresAt: new Date(expiresAtMs),
        updatedAt: new Date(expiresAtMs - DAY_MS),
      });
      // The sidecar and root must describe the same publication.
      reel.publishedAt = new Date(expiresAtMs - DAY_MS);
      reel.updatedAt = reel.publishedAt;
      db.seed(`reels/${id}`, reel);
    }
    return reel;
  }
  return { db, service, state, calls, objects, storage, seed };
}

function withoutGrants(page) {
  return {
    ...page,
    items: page.items.map(({ mediaGrant, ...item }) => item),
  };
}

test("only an explicit v2 opt-in adds the exact primary-media grant", async () => {
  const f = fixture();
  const root = f.seed();
  const legacy = await f.service.listReelsV2(request({ mediaGrants: undefined }));
  assert.deepEqual(await f.service.listReelsV2(request({ mediaGrants: false })), legacy);
  assert.equal(f.calls.metadata.length, 0);
  const flagged = await f.service.listReelsV2(request());
  assert.deepEqual(withoutGrants(flagged), legacy);
  const grant = flagged.items[0].mediaGrant;
  assert.deepEqual(Object.keys(grant).sort(), ["expiresAtMillis", "generation", "url"]);
  assert.equal(grant.generation, root.media.generation);
  assert.equal(grant.expiresAtMillis, NOW_MS + MEDIA_GRANT_TTL_MS);
  assert.equal(f.calls.sign[0].path, root.media.storagePath);
  assert.deepEqual(f.calls.header, [{ path: root.media.storagePath, length: 64 }]);
  assert.deepEqual(f.calls.revoke, [root.media.storagePath]);
  const direct = await f.service.getReelMediaAccessV2({
    auth: request().auth, data: { reelId: "inline-reel", asset: "media" },
  });
  assert.deepEqual(grant, {
    url: direct.url, generation: direct.generation, expiresAtMillis: direct.expiresAtMillis,
  });
});

test("malformed opt-ins and v1 opt-ins fail before rate or Storage work", async () => {
  const f = fixture();
  f.seed();
  for (const mediaGrants of [null, "true", 1, [], {}, "media"]) {
    await assert.rejects(f.service.listReelsV2(request({ mediaGrants })),
      (error) => error.code === "invalid-argument");
  }
  await assert.rejects(f.service.listReels(request()),
    (error) => error.code === "invalid-argument");
  assert.deepEqual(f.db.paths("privateRateLimits/"), []);
  assert.equal(f.calls.sign.length, 0);
  const v1 = await f.service.listReels({ auth: request().auth, data: { limit: 1 } });
  assert.deepEqual(Object.keys(v1).sort(), ["items", "nextCursor"]);
  assert.equal(Object.hasOwn(v1.items[0], "mediaGrant"), false);
  assert.equal(f.calls.metadata.length, 0);
});

test("a photo Reel with backing audio still inlines only its primary image", async () => {
  const f = fixture();
  const reel = f.seed();
  reel.backingAudio = {
    contentType: "audio/mpeg", size: 1024, generation: "456", durationMs: 12_000,
    storagePath: `reels/${AUTHOR}/inline-reel/backing-audio.mp3`,
  };
  reel.composition = {
    ...reel.composition, backingAudioVolume: 70, audioRightsAttested: true,
    audioAttribution: "Original licensed audio",
  };
  f.db.seed("reels/inline-reel", reel);
  const page = await f.service.listReelsV2(request());
  assert.equal(page.items[0].backingAudio.generation, "456");
  assert.equal(page.items[0].mediaGrant.generation, "123");
  assert.deepEqual(f.calls.metadata, [reel.media.storagePath]);
  assert.equal(Object.hasOwn(page.items[0], "backingAudioGrant"), false);
});

test("anonymous, missing, inactive and restricted viewers receive no inline grants", async () => {
  for (const kind of ["anonymous", "missing", "banned", "disabled", "deleted", "restricted"]) {
    const f = fixture();
    f.seed();
    const input = request();
    if (kind === "anonymous") input.auth = undefined;
    else if (kind === "missing") input.auth.uid = "missing-viewer";
    else if (kind === "restricted") {
      f.db.seed(`restrictions/${VIEWER}`, { type: "communicationMute", expiresAt: null });
    } else f.db.seed(`users/${VIEWER}`, { uid: VIEWER, [kind]: true });
    await assert.rejects(f.service.listReelsV2(input),
      (error) => ["unauthenticated", "not-found", "permission-denied"].includes(error.code));
    assert.equal(f.calls.metadata.length, 0, kind);
    assert.equal(f.calls.sign.length, 0, kind);
  }
});

test("hidden, expired, malformed, blocked and restricted candidates are never signed", async () => {
  for (const kind of ["hidden", "deleted", "malformed", "expired", "outbound-block",
    "inbound-block", "author-missing", "author-banned", "author-restricted"]) {
    const f = fixture();
    const root = f.seed("ineligible", kind === "expired" ? { expiresAtMs: NOW_MS } : {});
    if (kind === "hidden") f.db.seed("reels/ineligible", { ...root, moderationStatus: "hidden" });
    if (kind === "deleted") f.db.seed("reels/ineligible", { ...root, status: "deleted" });
    if (kind === "malformed") f.db.seed("reels/ineligible", { ...root, arbitrary: true });
    if (kind === "outbound-block") f.db.seed(`users/${VIEWER}/blocked/${AUTHOR}`, {});
    if (kind === "inbound-block") f.db.seed(`users/${AUTHOR}/blocked/${VIEWER}`, {});
    if (kind === "author-missing") {
      await f.db.runTransaction(async (tx) => tx.delete(f.db.doc(`users/${AUTHOR}`)));
    }
    if (kind === "author-banned") f.db.seed(`users/${AUTHOR}`, { uid: AUTHOR, banned: true });
    if (kind === "author-restricted") {
      f.db.seed(`restrictions/${AUTHOR}`, { type: "communicationMute", expiresAt: null });
    }
    const page = await f.service.listReelsV2(request());
    assert.deepEqual(page.items, [], kind);
    assert.deepEqual(f.calls.sign, [], kind);
    assert.deepEqual(f.calls.metadata, [], kind);
  }
});

test("the leading ranked items alone receive concurrent grants, with one final auth batch", async () => {
  const f = fixture();
  for (let index = 0; index < 8; index += 1) {
    f.seed(`ranked-${index}`, { authorId: `ranked-author-${index}`, rank: index });
  }
  let release;
  const barrier = new Promise((resolve) => { release = resolve; });
  const original = f.storage.getSignedReadUrl;
  f.storage.getSignedReadUrl = async (...args) => {
    const result = await original(...args);
    if (f.calls.sign.length === MAX_INLINE_REEL_MEDIA_GRANTS) release();
    await barrier;
    return result;
  };
  const page = await f.service.listReelsV2(request({ limit: 8 }));
  assert.equal(f.calls.sign.length, MAX_INLINE_REEL_MEDIA_GRANTS);
  assert.deepEqual(page.items.filter((item) => item.mediaGrant).map(({ id }) => id),
    page.items.slice(0, MAX_INLINE_REEL_MEDIA_GRANTS).map(({ id }) => id));
  assert.deepEqual(f.calls.sign.map(({ path }) => path),
    page.items.slice(0, MAX_INLINE_REEL_MEDIA_GRANTS).map(({ id, authorId }) =>
      `reels/${authorId}/${id}/media.jpg`));
  const finalBatches = f.calls.batches.filter((paths) => paths.some((path) => /^reels\/[^/]+$/u.test(path)));
  assert.equal(finalBatches.length, 1);
  assert.equal(finalBatches[0].length, 26);
  assert.equal(new Set(finalBatches[0]).size, finalBatches[0].length);
  assert.ok(finalBatches[0].includes(`users/${VIEWER}`));
  assert.ok(finalBatches[0].includes(`restrictions/${VIEWER}`));
});

test("Storage/header/generation/token/signing failures omit only the hint and keep fallback usable", async () => {
  for (const kind of ["metadata", "header", "generation", "owner", "reel", "kind", "size",
    "content-type", "revocation", "signing", "unsafe-url", "port"]) {
    const f = fixture();
    const root = f.seed("broken");
    f.seed("healthy", { rank: 1 });
    const restore = [];
    function replace(method, replacement) {
      const original = f.storage[method];
      f.storage[method] = async (path, ...args) => path === root.media.storagePath
        ? replacement(path, ...args) : original(path, ...args);
      restore.push(() => { f.storage[method] = original; });
    }
    if (kind === "metadata") replace("getMetadata", async () => { throw new Error("private failure"); });
    else if (kind === "header") replace("readHeader", async () => Buffer.alloc(64));
    else if (kind === "revocation") replace("revokeDownloadTokens", async () => { throw new Error("token failed"); });
    else if (kind === "signing") replace("getSignedReadUrl", async () => { throw new Error("signing failed"); });
    else if (kind === "unsafe-url") replace("getSignedReadUrl", async () => "https://attacker.invalid/leak");
    else if (kind === "port") replace("getSignedReadUrl", async () => "https://storage.googleapis.com:9443/leak");
    else {
      const metadata = structuredClone(f.objects.get(root.media.storagePath));
      if (kind === "generation") metadata.generation = "124";
      if (kind === "owner") metadata.metadata.ownerId = "other-author";
      if (kind === "reel") metadata.metadata.reelId = "other-reel";
      if (kind === "kind") metadata.metadata.assetKind = "backingAudio";
      if (kind === "size") metadata.size = "1025";
      if (kind === "content-type") metadata.contentType = "image/png";
      replace("getMetadata", async () => metadata);
    }
    const page = await f.service.listReelsV2(request());
    assert.equal(page.items.length, 2, kind);
    assert.equal(page.items.find(({ id }) => id === "broken").mediaGrant, undefined, kind);
    assert.ok(page.items.find(({ id }) => id === "healthy").mediaGrant, kind);
    restore.forEach((reset) => reset());
    assert.ok((await f.service.getReelMediaAccessV2({
      auth: request().auth, data: { reelId: "broken", asset: "media" },
    })).url, kind);
  }
});

test("post-signing changes to viewer, author, blocks, root and availability withhold grants", async () => {
  for (const kind of ["viewer-disabled", "viewer-missing", "viewer-restricted", "author-disabled", "author-restricted",
    "viewer-block", "author-block", "hidden", "deleted", "owner", "generation", "availability", "expired"]) {
    const f = fixture();
    const root = f.seed("racing", { expiresAtMs: NOW_MS + 60_000 });
    const original = f.storage.getSignedReadUrl;
    f.storage.getSignedReadUrl = async (...args) => {
      const url = await original(...args);
      if (kind === "viewer-disabled") f.db.seed(`users/${VIEWER}`, { disabled: true });
      if (kind === "viewer-missing") {
        await f.db.runTransaction(async (tx) => tx.delete(f.db.doc(`users/${VIEWER}`)));
      }
      if (kind === "viewer-restricted") f.db.seed(`restrictions/${VIEWER}`, { type: "communicationMute" });
      if (kind === "author-disabled") f.db.seed(`users/${AUTHOR}`, { disabled: true });
      if (kind === "author-restricted") f.db.seed(`restrictions/${AUTHOR}`, { type: "communicationMute" });
      if (kind === "viewer-block") f.db.seed(`users/${VIEWER}/blocked/${AUTHOR}`, {});
      if (kind === "author-block") f.db.seed(`users/${AUTHOR}/blocked/${VIEWER}`, {});
      if (kind === "hidden") f.db.seed("reels/racing", { ...root, moderationStatus: "hidden" });
      if (kind === "deleted") f.db.seed("reels/racing", { ...root, status: "deleted" });
      if (kind === "generation") f.db.seed("reels/racing", { ...root, media: { ...root.media, generation: "124" } });
      if (kind === "owner") {
        f.db.seed("users/new-owner", { uid: "new-owner" });
        f.db.seed("reels/racing", {
          ...root, authorId: "new-owner",
          media: { ...root.media, storagePath: "reels/new-owner/racing/media.jpg" },
        });
      }
      if (kind === "availability") {
        const previous = f.db.data("reelAvailability/racing");
        f.db.seed("reelAvailability/racing", {
          ...previous, availabilityHours: 25, expiresAt: new Date(NOW_MS + 3_660_000),
        });
      }
      if (kind === "expired") f.state.nowMs += 60_000;
      return url;
    };
    const page = await f.service.listReelsV2(request());
    assert.equal(f.calls.sign.length, 1, kind);
    assert.ok(page.items.every((item) => item.mediaGrant === undefined), kind);
    if (kind === "expired") assert.deepEqual(page.items, []);
  }
});

test("inline grants retain the 90-second ceiling and clamp to content expiry", async () => {
  const f = fixture();
  f.seed("near-expiry", { expiresAtMs: NOW_MS + 20_000 });
  f.seed("permanent", { rank: 1 });
  const page = await f.service.listReelsV2(request());
  assert.equal(page.items.find(({ id }) => id === "near-expiry").mediaGrant.expiresAtMillis, NOW_MS + 20_000);
  assert.equal(page.items.find(({ id }) => id === "permanent").mediaGrant.expiresAtMillis, NOW_MS + 90_000);
  assert.equal(MEDIA_GRANT_TTL_MS, 90_000);
});

test("final authorization read failure returns the legacy page without private error text", async () => {
  const f = fixture();
  f.seed();
  const original = f.db.getAll.bind(f.db);
  f.db.getAll = async (...refs) => {
    if (refs.some(({ path }) => path === "reels/inline-reel")) {
      throw new Error("private-author@example.invalid fixture-signature private-note");
    }
    return original(...refs);
  };
  const page = await f.service.listReelsV2(request());
  assert.equal(page.items.length, 1);
  assert.equal(page.items[0].mediaGrant, undefined);
  assert.doesNotMatch(JSON.stringify([page, f.calls.logs]), /private-|fixture-signature/u);
});

test("slow signing is bounded and a late completion cannot publish a hint or start final reads", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const f = fixture();
  f.seed();
  let signing;
  const started = new Promise((resolve) => { signing = resolve; });
  let release;
  f.storage.getSignedReadUrl = async () => {
    signing();
    return new Promise((resolve) => { release = resolve; });
  };
  const pending = f.service.listReelsV2(request());
  await started;
  t.mock.timers.tick(INLINE_REEL_MEDIA_GRANT_BUDGET_MS);
  const page = await pending;
  assert.equal(page.items.length, 1);
  assert.equal(page.items[0].mediaGrant, undefined);
  const reads = f.calls.batches.length;
  release("https://storage.googleapis.com/test-bucket/late?X-Goog-Signature=late");
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(page.items[0].mediaGrant, undefined);
  assert.equal(f.calls.batches.length, reads);
});

test("list quota bounds inline work and an exhausted list never touches Storage", async () => {
  const f = fixture({ limits: { ...DEFAULT_LIMITS, list: { maxEvents: 1, windowMs: 60_000 } } });
  f.seed();
  await f.service.listReelsV2(request());
  const reads = f.calls.metadata.length;
  await assert.rejects(f.service.listReelsV2(request()),
    (error) => error.code === "resource-exhausted");
  assert.equal(f.calls.metadata.length, reads);
});

test("responses and logs disclose no private account, graph, ranking, token or object path fields", async () => {
  const f = fixture();
  f.seed();
  f.db.seed(`users/${VIEWER}/friends/${AUTHOR}`, { privateNote: "graph-private-note" });
  f.db.seed(`users/${VIEWER}/reelViews/inline-reel`, {
    viewedAt: new Date(NOW_MS - DAY_MS), expiresAt: new Date(NOW_MS + 89 * DAY_MS),
  });
  const page = await f.service.listReelsV2(request());
  assert.deepEqual(Object.keys(page).sort(), ["items", "nextCursor", "schemaVersion"]);
  assert.doesNotMatch(JSON.stringify(page), /private-|viewedAt|reelViews|rankScore|storagePath|checkedAtMs/u);
  assert.doesNotMatch(JSON.stringify(f.calls.logs),
    /inline-viewer|inline-author|inline-reel|fixture-signature|storage\.googleapis|private-|1111111111111111/u);
  assert.deepEqual(f.db.paths("reelMediaGrants/"), []);
  assert.equal(f.calls.logs[0][1].inlineGrants, 1);
});

test("inline hints preserve f1 modes, legacy cursors, own pagination and the seen policy", async () => {
  const f = fixture();
  const ownIds = [];
  for (let index = 0; index < 7; index += 1) {
    ownIds.push(`own-${index}`);
    f.seed(`own-${index}`, { authorId: VIEWER, rank: index * 2 });
    f.seed(`other-${index}`, { rank: index * 2 + 1 });
  }
  f.db.seed(`users/${VIEWER}/reelViews/own-0`, {
    viewedAt: new Date(NOW_MS - 1000), expiresAt: new Date(NOW_MS + 90 * DAY_MS),
  });
  let cursor = null;
  const found = [];
  for (let pageNumber = 0; pageNumber < 8; pageNumber += 1) {
    const page = await f.service.listReelsV2(request({ limit: 3, scope: "own", cursor }));
    found.push(...page.items.map(({ id }) => id));
    assert.ok(page.items.every((item) => item.authorId === VIEWER && item.mediaGrant));
    cursor = page.nextCursor;
    if (cursor === null) break;
    assert.match(cursor, /^f1\.o\.[0-9a-f]{16}\./u);
  }
  assert.deepEqual(found, ownIds);
  const discover = await f.service.listReelsV2(request({ limit: 3 }));
  assert.match(discover.nextCursor, /^f1\.d\./u);
  assert.ok(discover.items.every(({ id }) => id !== "own-0"));
  const legacyCursor = discover.nextCursor.split(".")[3];
  const resumed = await f.service.listReelsV2(request({ limit: 3, cursor: legacyCursor }));
  assert.ok(resumed.items.every(({ id }) => !discover.items.some((item) => item.id === id)));
  assert.ok(resumed.items.every((item) => item.mediaGrant));
  const allSeen = await f.service.listReelsV2(request({ limit: 3, includeSeen: true }));
  assert.match(allSeen.nextCursor, /^f1\.s\./u);
  assert.ok(allSeen.items.some(({ id }) => id === "own-0"));
  const attempts = f.calls.sign.length;
  for (const data of [
    { cursor: discover.nextCursor, scope: "own" },
    { cursor: allSeen.nextCursor },
    { cursor: "f1.d.invalid.position" },
    { scope: "own", includeSeen: true },
    { authorId: AUTHOR },
    { storagePath: "private/foreign-object" },
  ]) {
    await assert.rejects(f.service.listReelsV2(request(data)),
      (error) => error.code === "invalid-argument");
  }
  assert.equal(f.calls.sign.length, attempts);
});
