// The rollback lever, proven end to end.
//
// This file runs in its own process (node --test isolates per file) because
// FEED_RANKING is resolved once at module load. It exists so that "turn
// ranking off with one environment variable, no client release" is a tested
// claim rather than a comment: with the flag off the feed must be pure
// recency again, must read no ranking documents, and must STILL emit and
// accept the new cursor grammar — the codec is a one-way door and reverting
// it would strand every client holding an `f1.` cursor.
process.env.REEL_FEED_RANKING_ENABLED = "false";

const assert = require("node:assert/strict");
const { test } = require("node:test");

const { FEED_CURSOR_PATTERN } = require("../reels/contract");
const { FEED_RANKING } = require("../reels/ranking");
const { createReelService } = require("../reels/service");
const { InMemoryFirestore } = require("./helpers/in_memory_firestore");

const NOW_MS = 1_778_000_000_000;
const HOUR_MS = 60 * 60 * 1000;
const VIEWER = "viewer-1";

function composition() {
  return {
    caption: "A real Reel",
    crop: { scalePermille: 1000, offsetXPermille: 0, offsetYPermille: 0 },
    filter: "original",
    trimStartMs: 0,
    trimEndMs: 0,
    textOverlays: [],
    linkOverlays: [],
    originalAudioVolume: 0,
    backingAudioVolume: 0,
    audioTrimStartMs: 0,
    audioRightsAttested: false,
    audioAttribution: "",
  };
}

function sortKeyFor(rank, id) {
  return `${String(NOW_MS - rank).padStart(13, "0")}_${id}`;
}

function fixture() {
  const db = new InMemoryFirestore();
  db.seed(`users/${VIEWER}`, { uid: VIEWER, displayName: "Viewer" });
  const service = createReelService({
    db,
    FieldPath: { documentId: () => "__name__" },
    Timestamp: { fromMillis: (value) => new Date(value) },
    storage: {
      getMetadata: async () => ({}),
      readHeader: async () => Buffer.alloc(0),
      revokeDownloadTokens: async () => {},
      getSignedReadUrl: async () => "https://example.invalid/file",
      deleteObject: async () => {},
    },
    clock: () => NOW_MS,
    randomSeed: () => "0f0f0f0f0f0f0f0f",
  });
  function seedReel({ id, authorId, rank }) {
    db.seed(`users/${authorId}`, { uid: authorId });
    db.seed(`reels/${id}`, {
      schemaVersion: 1,
      status: "published",
      moderationStatus: "visible",
      authorId,
      authorName: `Creator ${authorId}`,
      media: {
        kind: "image",
        contentType: "image/jpeg",
        size: 1024,
        generation: "123",
        durationMs: 0,
        storagePath: `reels/${authorId}/${id}/media.jpg`,
      },
      backingAudio: null,
      composition: composition(),
      sortKey: sortKeyFor(rank, id),
      publishedAt: new Date(NOW_MS - rank * HOUR_MS),
      updatedAt: new Date(NOW_MS - rank * HOUR_MS),
      likeCount: (10 - rank) * 40,
    });
    return id;
  }
  return { db, service, seedReel };
}

function request({ cursor = null, limit = 20, ...rest } = {}) {
  return {
    auth: { uid: VIEWER, token: { email_verified: false } },
    data: { cursor, limit, ...rest },
  };
}

test("the environment flag actually disables ranking", () => {
  assert.equal(FEED_RANKING.enabled, false);
});

test("with ranking off the v2 feed is pure recency again", async () => {
  const scenario = fixture();
  const chronological = [];
  for (let index = 0; index < 8; index += 1) {
    chronological.push(scenario.seedReel({
      id: `off-${index}`,
      authorId: `off-author-${index % 3}`,
      rank: index,
    }));
  }
  // A seen row that WOULD suppress under ranking must have no effect here.
  scenario.db.seed(`users/${VIEWER}/reelViews/off-0`, {
    viewedAt: new Date(NOW_MS - 60_000),
    expiresAt: new Date(NOW_MS + 90 * 24 * HOUR_MS),
  });
  const before = scenario.db.metrics.getAllDocumentReads;
  const page = await scenario.service.listReelsV2(request({ limit: 8 }));
  assert.deepEqual(page.items.map(({ id }) => id), chronological);
  // Three authors * four authorization documents + eight availability
  // documents + eight callerLiked documents. No reelViews, no social graph.
  assert.equal(
    scenario.db.metrics.getAllDocumentReads - before,
    3 * 4 + 8 + 8,
  );
});

test("the cursor codec keeps working with ranking off — it is a one-way door",
  async () => {
    const scenario = fixture();
    for (let index = 0; index < 6; index += 1) {
      scenario.seedReel({
        id: `door-${index}`,
        authorId: `door-author-${index % 2}`,
        rank: index,
      });
    }
    const first = await scenario.service.listReelsV2(request({ limit: 2 }));
    assert.match(first.nextCursor, FEED_CURSOR_PATTERN);
    const second = await scenario.service.listReelsV2(
      request({ cursor: first.nextCursor, limit: 2 }),
    );
    assert.deepEqual(second.items.map(({ id }) => id), ["door-2", "door-3"]);
    assert.match(second.nextCursor, FEED_CURSOR_PATTERN);
    // scope still narrows server-side; only the ORDERING is rolled back.
    const own = await scenario.service.listReelsV2(
      request({ limit: 5, scope: "own" }),
    );
    assert.deepEqual(own.items, []);
  });
