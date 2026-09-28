// The normative "See who liked" page (ADR-230): exact input, the scan loop,
// candidate fetchers and the exact response.
//
// Fixed page size 20 (no client `limit`: sending one is invalid-argument),
// scan cap 60, cursor after the last CONSUMED candidate:
//
//   PAGE = 20; CHUNK = PAGE + 1; SCAN_CAP = 60
//   while visible < PAGE and consumed < SCAN_CAP and not exhausted:
//     want  = min(CHUNK, SCAN_CAP - consumed + 1)     // +1 = MAX+1 sentinel
//     batch = next `want` candidates strictly after lastFetched
//     exhausted = batch.length < want
//     take  = exhausted ? batch : batch.slice(0, want - 1)
//     resolve take (phased liker contexts), then consume IN ORDER, stopping
//     at PAGE visible or SCAN_CAP consumed
//   hasMore    = a candidate exists strictly after lastConsumed
//   nextCursor = hasMore ? store(lastConsumed) : null
//
// So no visible liker is ever skipped, hidden rows cannot pin pagination (the
// cap advances the cursor), and a short page with hasMore happens only when
// 60 consecutive candidates held >= 41 hidden likers (a recorded residual
// disclosure, ADR-230). A malformed edge is skipped but still consumed.
// A position the cursor cannot store (a createdAt that is a map, array,
// bytes, geopoint or reference: malformed server data only) never ends a
// page: the page is cut back to the last storable consumed position, so the
// next page re-consumes the malformed run and moves past it. Only a page
// that consumed no storable position at all ends with hasMore: false.
//
// No read-write transaction: candidates come from plain queries (or an
// in-memory list for Server messages), contexts from plain getAll, and the
// cursor document from a separate create() after the scan and after the
// caller's fresh parent re-check.

const {
  fail,
  requireExactInput,
  requireId,
} = require("../integrity/guards");
const { ALLOWED_DIRECT_REACTIONS } = require("../messaging/direct_reactions");
const {
  cursorKindOf,
  requireLikersCursorToken,
  resolveLikersCursor,
  storableLikersPosition,
  storeLikersCursor,
} = require("./liker_cursors");

const LIKERS_PAGE_SIZE = 20;
const LIKERS_SCAN_CAP = 60;
const LIKERS_CHUNK = LIKERS_PAGE_SIZE + 1;
// Most candidates one page may FETCH: three chunks of 21 (60 consumed + the
// sentinel of each chunk).
const LIKERS_MAX_FETCHED = 3 * LIKERS_CHUNK;
const LIKERS_RESPONSE_KEYS = Object.freeze([
  "hasMore",
  "likers",
  "nextCursor",
  "schemaVersion",
]);
const LIKER_ROW_KEYS = Object.freeze([
  "displayName",
  "photoUrl",
  "reaction",
  "userId",
]);

const LIKERS_INPUT = Object.freeze({
  voiceMoment: Object.freeze({
    allowed: Object.freeze(["commentId", "cursor", "momentId"]),
    required: Object.freeze(["momentId"]),
  }),
  reel: Object.freeze({
    allowed: Object.freeze(["commentId", "cursor", "reelId"]),
    required: Object.freeze(["reelId"]),
  }),
  serverMessage: Object.freeze({
    allowed: Object.freeze([
      "channelId",
      "cursor",
      "emoji",
      "messageId",
      "serverId",
    ]),
    required: Object.freeze(["serverId", "channelId", "messageId"]),
  }),
});

function optionalId(value, label) {
  return value === undefined || value === null ? null : requireId(value, label);
}

// Exact input of one list callable family. Returns the normalized request:
// {targetType, ids, emoji, cursor, ...family ids}. Any `limit` (or other
// unknown key) is invalid-argument; the page size is a server constant.
function requireLikersListInput(family, data) {
  const shape = LIKERS_INPUT[family];
  if (!shape) throw new TypeError(`Unknown likers family: ${family}`);
  requireExactInput(data, shape.allowed, shape.required);
  const cursor = requireLikersCursorToken(data.cursor);
  if (family === "voiceMoment") {
    const momentId = requireId(data.momentId, "momentId");
    const commentId = optionalId(data.commentId, "commentId");
    return {
      targetType: commentId === null ? "voiceMoment" : "voiceMomentComment",
      ids: commentId === null ? [momentId] : [momentId, commentId],
      emoji: null,
      cursor,
      momentId,
      commentId,
    };
  }
  if (family === "reel") {
    const reelId = requireId(data.reelId, "reelId");
    const commentId = optionalId(data.commentId, "commentId");
    return {
      targetType: commentId === null ? "reel" : "reelComment",
      ids: commentId === null ? [reelId] : [reelId, commentId],
      emoji: null,
      cursor,
      reelId,
      commentId,
    };
  }
  const serverId = requireId(data.serverId, "serverId");
  const channelId = requireId(data.channelId, "channelId");
  const messageId = requireId(data.messageId, "messageId");
  let emoji = null;
  if (data.emoji !== undefined && data.emoji !== null) {
    if (
      typeof data.emoji !== "string" ||
      !ALLOWED_DIRECT_REACTIONS.includes(data.emoji)
    ) {
      fail("invalid-argument", "emoji is invalid.");
    }
    emoji = data.emoji;
  }
  return {
    targetType: "serverMessage",
    ids: [serverId, channelId, messageId],
    emoji,
    cursor,
    serverId,
    channelId,
    messageId,
  };
}

function requireCandidates(batch, want) {
  if (!Array.isArray(batch) || batch.length > want) {
    throw new TypeError("fetchCandidates must return at most `want` candidates.");
  }
  for (const candidate of batch) {
    if (
      !candidate ||
      candidate.position === undefined ||
      (candidate.likerId !== null && typeof candidate.likerId !== "string")
    ) {
      throw new TypeError("A candidate needs a position and a likerId (or null).");
    }
  }
  return batch;
}

// The §3.0 loop. `fetchCandidates(afterPosition | null, want)` returns up to
// `want` candidates {position, likerId | null, reaction?} strictly after the
// position, in list order. `resolveVisible(candidates)` returns, in the same
// order, the projected row or null (hidden / malformed) per candidate.
// `isStorable(position)` says whether the cursor could store a position; a
// page never ends on one it cannot (see the header).
async function scanLikersPage({
  after = null,
  fetchCandidates,
  resolveVisible,
  isStorable = () => true,
  pageSize = LIKERS_PAGE_SIZE,
  scanCap = LIKERS_SCAN_CAP,
}) {
  if (typeof fetchCandidates !== "function" ||
      typeof resolveVisible !== "function" ||
      typeof isStorable !== "function") {
    throw new TypeError("fetchCandidates, resolveVisible and isStorable are required.");
  }
  if (!Number.isSafeInteger(pageSize) || pageSize < 1 ||
      !Number.isSafeInteger(scanCap) || scanCap < pageSize) {
    throw new TypeError("pageSize and scanCap are invalid.");
  }
  const chunk = pageSize + 1;
  const likers = [];
  let consumed = 0;
  let fetched = 0;
  let lastConsumed = after;
  let lastFetched = after;
  let exhausted = false;
  // true while a fetched candidate (or a sentinel) lies after lastConsumed.
  let remainder = false;
  // The last consumed position the cursor can store, and how many rows were
  // listed when it was consumed.
  let lastStorable = null;
  let likersAtLastStorable = 0;

  while (likers.length < pageSize && consumed < scanCap && !exhausted) {
    const want = Math.min(chunk, scanCap - consumed + 1);
    const batch = requireCandidates(await fetchCandidates(lastFetched, want), want);
    fetched += batch.length;
    exhausted = batch.length < want;
    const take = exhausted ? batch : batch.slice(0, want - 1);
    if (take.length === 0) {
      remainder = false;
      break;
    }
    const rows = await resolveVisible(take);
    if (!Array.isArray(rows) || rows.length !== take.length) {
      throw new TypeError("resolveVisible must return one entry per candidate.");
    }
    let index = 0;
    for (; index < take.length; index += 1) {
      consumed += 1;
      lastConsumed = take[index].position;
      if (rows[index] !== null && rows[index] !== undefined) {
        likers.push(rows[index]);
      }
      if (isStorable(lastConsumed)) {
        lastStorable = lastConsumed;
        likersAtLastStorable = likers.length;
      }
      if (likers.length === pageSize || consumed === scanCap) {
        index += 1;
        break;
      }
    }
    // Unconsumed candidates of this chunk, or the chunk's sentinel.
    remainder = index < take.length || !exhausted;
    lastFetched = take[take.length - 1].position;
  }
  // `unstorable`: null, "rewound" (the page was cut back to lastStorable)
  // or "stranded" (nothing storable was consumed; the list ends here).
  let unstorable = null;
  if (remainder && consumed > 0 && !isStorable(lastConsumed)) {
    if (lastStorable !== null) {
      unstorable = "rewound";
      lastConsumed = lastStorable;
      likers.length = likersAtLastStorable;
    } else {
      unstorable = "stranded";
      remainder = false;
    }
  }
  return {
    likers,
    hasMore: remainder,
    lastConsumed,
    consumed,
    fetched,
    unstorable,
  };
}

// Content likes (voiceMoments/{m}/likes, reels/{r}/likes, commentLikes
// filtered by commentKey): newest first, doc id as the tiebreak, resumed
// strictly after (createdAt, id). `documentIdField` is
// FieldPath.documentId() in production. `toLikerId(snapshot)` validates the
// edge and returns the liker uid, or null for a malformed edge (skipped but
// consumed).
function queryCandidateFetcher({ query, documentIdField, toLikerId }) {
  if (!query?.orderBy || documentIdField === undefined ||
      typeof toLikerId !== "function") {
    throw new TypeError("query, documentIdField and toLikerId are required.");
  }
  const ordered = query
    .orderBy("createdAt", "desc")
    .orderBy(documentIdField, "desc");
  return async (after, want) => {
    const page = after === null
      ? ordered
      : ordered.startAfter(after.createdAt, after.id);
    const snapshot = await page.limit(want).get();
    return snapshot.docs.map((doc) => ({
      position: { createdAt: doc.data()?.createdAt, id: doc.id },
      likerId: toLikerId(doc),
      reaction: null,
    }));
  };
}

function compareServerPositions(left, right) {
  if (left.emojiIndex !== right.emojiIndex) {
    return left.emojiIndex - right.emojiIndex;
  }
  // Firebase uids are opaque and case-sensitive: code-unit order, never
  // locale order.
  return left.uid < right.uid ? -1 : left.uid > right.uid ? 1 : 0;
}

// Server message reactors: the canonical {uid: emoji} map has no timestamps
// (ADR-216), so candidates sort by (emoji picker index, uid). An emoji filter
// keeps one emoji. Resuming "strictly after (emojiIndex, uid)" against the
// CURRENT map is robust to reactions added or removed between pages.
function serverReactionCandidates(reactions, { emoji = null } = {}) {
  if (!reactions || typeof reactions !== "object" || Array.isArray(reactions)) {
    throw new TypeError("reactions must be the canonical reaction map.");
  }
  return Object.entries(reactions)
    .filter(([, value]) => emoji === null || value === emoji)
    .map(([uid, value]) => {
      const emojiIndex = ALLOWED_DIRECT_REACTIONS.indexOf(value);
      if (emojiIndex < 0) {
        throw new TypeError("reactions must be the canonical reaction map.");
      }
      return { position: { emojiIndex, uid }, likerId: uid, reaction: value };
    })
    .sort((left, right) => compareServerPositions(left.position, right.position));
}

// Pages an already-sorted candidate list (serverReactionCandidates) with the
// same "strictly after the position" contract as the query fetcher.
function inMemoryCandidateFetcher(candidates, compare = compareServerPositions) {
  return async (after, want) => {
    const start = after === null
      ? 0
      : candidates.findIndex((candidate) =>
        compare(candidate.position, after) > 0);
    return start < 0 ? [] : candidates.slice(start, start + want);
  };
}

function likersPageResponse({ likers, nextCursor }) {
  if (!Array.isArray(likers) || likers.length > LIKERS_PAGE_SIZE) {
    throw new TypeError("likers must hold at most one page.");
  }
  return {
    schemaVersion: 1,
    likers: likers.map((row) => ({
      userId: row.userId,
      displayName: row.displayName,
      photoUrl: null,
      reaction: row.reaction ?? null,
    })),
    nextCursor,
    hasMore: nextCursor !== null,
  };
}

// The content phase of one list call after the target is authorized:
// resolve the cursor, scan, let the caller re-check the parent with a FRESH
// read (`recheck`), then create the cursor document when there is more.
async function runLikersPage({
  db,
  Timestamp,
  viewerId,
  targetType,
  targetKey,
  cursor,
  timing,
  fetchCandidates,
  resolveVisible,
  recheck = async () => {},
  randomBytes = undefined,
}) {
  cursorKindOf(targetType);
  const after = await resolveLikersCursor({
    db,
    token: cursor,
    viewerId,
    targetType,
    targetKey,
    nowMs: timing.nowMs,
  });
  const page = await scanLikersPage({
    after,
    fetchCandidates,
    resolveVisible,
    isStorable: (position) => storableLikersPosition(targetType, position),
  });
  await recheck();
  const nextCursor = page.hasMore
    ? await storeLikersCursor({
      db,
      Timestamp,
      viewerId,
      targetType,
      targetKey,
      position: page.lastConsumed,
      timing,
      ...(randomBytes ? { randomBytes } : {}),
    })
    : null;
  return {
    response: likersPageResponse({ likers: page.likers, nextCursor }),
    scan: page,
  };
}

module.exports = {
  LIKERS_CHUNK,
  LIKERS_INPUT,
  LIKERS_MAX_FETCHED,
  LIKERS_PAGE_SIZE,
  LIKERS_RESPONSE_KEYS,
  LIKERS_SCAN_CAP,
  LIKER_ROW_KEYS,
  compareServerPositions,
  inMemoryCandidateFetcher,
  likersPageResponse,
  queryCandidateFetcher,
  requireLikersListInput,
  runLikersPage,
  scanLikersPage,
  serverReactionCandidates,
};
