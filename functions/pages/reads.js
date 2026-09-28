// The Premium Pages read callables (ADR-233 §2.5, §2.7): getPagesFeedV1,
// getPageV1, getPagePostV1 and findPagesV1. europe-west1,
// enforceAppCheck:false, like every profile callable.
//
// Order in every call: auth (an unverified e-mail may read, as the views) ->
// exact input, cursors decoded and validated (a malformed cursor fails with
// invalid-argument BEFORE any read) -> activation (readAccess for the caller,
// one uncached read) -> rate budget (one small transaction over the caller's
// own privateRateLimits rows) -> content, all plain reads (no read-write
// transaction touches content). The wire shapes live in views.js.
//
// Visibility is decided per Page by audience.js (canViewPage) from documents
// read in THIS call. The feed and Find additionally drop Pages that
// pageVisibility/v1 already hides BEFORE querying, so a hidden Page costs no
// query read. Every content refusal is the uniform `pageUnavailable`.
//
// Paging reuses the ADR-230 scan loop (engagement/likers_paging.js
// scanLikersPage): a fixed page size, a hard scan cap, a cursor after the
// last CONSUMED item, so hidden items can never pin pagination and no loop is
// unbounded. A malformed item is skipped but consumed.
//
// Read budget of getPagesFeedV1 (pinned in pages_feed.test.js):
//   activation 1 + rate 2 + viewer/index/visibility 3
//   + chunks x 21 (<= 10 chunks of 30 ids from the newest 300 follows)
//   + refills <= 3 x 21 (the scan cap bounds them)
//   + 5 per distinct Page in the scanned window (<= 20 Pages resolved per
//     batch, at most 60 posts scanned)
//   + likes <= 20
//   + first page only: suggestions, 1 query <= 41 + 3 per resolved card
//     candidate (<= 40).

const { FieldPath, FieldValue, Timestamp } = require("firebase-admin/firestore");
const { onCall } = require("firebase-functions/v2/https");
const defaultLogger = require("firebase-functions/logger");

const {
  canonicalPublicProfile,
  consumeRateLimit,
  fail,
  rateLimitReference,
  requireActor,
  requireExactInput,
  requireUid,
  restrictionIsActive,
  timestampMillis,
  transactionGetAll,
} = require("../integrity/guards");
const { likersAccountIsActive } = require("../utils/likers_access");
const { scanLikersPage } = require("../engagement/likers_paging");
const { directMessagePrivacyAllows } = require("../messaging/direct_integrity");
const { admitsPublicJoin, canonicalServer } = require("../servers/authority");
const { assertPagesReadEnabled } = require("./activation");
const {
  PAGE_CONTEXT_READS,
  followingEdgeExists,
  livePageStatus,
  pageAcceptsFollowers,
  pageContextReferences,
  pageUnavailableError,
  pageViewDecision,
  visibilityHides,
} = require("./audience");
const {
  PAGE_NAME_CHANGE_FIND_DELAY_MS,
  PAGE_POST_ID_PATTERN,
  canonicalPageOrNull,
  pageNameSearch,
} = require("./contract");
const {
  canonicalPageFollowIndex,
  pageFollowIndexReference,
} = require("./follows");
const {
  canonicalPageCommentData,
  canonicalPagePostData,
} = require("./post_contract");
const {
  FIND_PAGES_MODES,
  commentView,
  decodeFindCursor,
  decodeItemCursor,
  encodeFindCursor,
  encodeItemCursor,
  feedResponse,
  findResponse,
  pageCard,
  pageHeader,
  pageResponse,
  postResponse,
  postView,
  storableFindPosition,
  storableItemPosition,
  viewerView,
} = require("./views");
const {
  canonicalPageVisibility,
  pageVisibilityReference,
} = require("./visibility");

const REGION = "europe-west1";
const MINUTE_MS = 60_000;
const HOUR_MS = 60 * MINUTE_MS;

const PAGES_READ_RATE_LIMITS = Object.freeze({
  "pages.read": Object.freeze({ maxEvents: 60, windowMs: MINUTE_MS }),
  "pages.readHourly": Object.freeze({ maxEvents: 1200, windowMs: HOUR_MS }),
  "pages.find": Object.freeze({ maxEvents: 30, windowMs: MINUTE_MS }),
  "pages.findHourly": Object.freeze({ maxEvents: 300, windowMs: HOUR_MS }),
});
const READ_SCOPES = Object.freeze(["pages.read", "pages.readHourly"]);
const FIND_SCOPES = Object.freeze(["pages.find", "pages.findHourly"]);

const PAGES_FEED_PAGE_SIZE = 20;
const PAGES_FEED_SCAN_CAP = 60;
const PAGES_FEED_INDEX_WINDOW = 300;
const PAGES_FEED_IN_CHUNK = 30;
const PAGES_FEED_QUERY_LIMIT = PAGES_FEED_PAGE_SIZE + 1;
const PAGES_FEED_MAX_CHUNKS = PAGES_FEED_INDEX_WINDOW / PAGES_FEED_IN_CHUNK;
const PAGES_FEED_SUGGESTIONS = 10;
const PAGES_WALL_PAGE_SIZE = 20;
const PAGES_WALL_SCAN_CAP = 60;
const PAGES_COMMENT_PAGE_SIZE = 20;
const PAGES_COMMENT_SCAN_CAP = 60;
const PAGES_FIND_PAGE_SIZE = 20;
const PAGES_FIND_SCAN_CAP = 40;
const PAGES_FIND_QUERY_MIN = 2;
const PAGES_FIND_QUERY_MAX = 60;
// Reads per resolved Find candidate: users/{P} + both blocks (+ the follow
// edge in `search`, where followed Pages are not excluded).
const PAGES_FIND_CONTEXT_READS = 3;

/// The most document reads one getPagesFeedV1 call may make for `chunks`
/// query chunks (1..10), first page included. Pinned by pages_feed.test.js.
function pagesFeedReadBudget(chunks) {
  const fixed = 1 + READ_SCOPES.length + 3;
  const queries = chunks * PAGES_FEED_QUERY_LIMIT +
    Math.ceil((PAGES_FEED_SCAN_CAP + PAGES_FEED_QUERY_LIMIT) / PAGES_FEED_QUERY_LIMIT) *
      PAGES_FEED_QUERY_LIMIT;
  const contexts = PAGE_CONTEXT_READS * PAGES_FEED_SCAN_CAP;
  const likes = PAGES_FEED_PAGE_SIZE;
  const suggestions = (PAGES_FIND_SCAN_CAP + 1) +
    PAGES_FIND_CONTEXT_READS * PAGES_FIND_SCAN_CAP;
  return fixed + queries + contexts + likes + suggestions;
}

// The EXACT query shapes of the read callables. The index smoke
// (scripts/smoke_pages_indexes.js) and pages_index_emulator.test.js run these
// same builders, so a shape and its firestore.indexes.json entry cannot
// drift apart.
const PAGES_READ_QUERIES = Object.freeze({
  // pagePosts (pageId ASC, status ASC, createdAt DESC, __name__ DESC)
  feedChunk: (db, documentIdField, pageIds) => db.collection("pagePosts")
    .where("pageId", "in", pageIds)
    .where("status", "==", "published")
    .orderBy("createdAt", "desc")
    .orderBy(documentIdField, "desc"),
  // Same index; the owner reads published + held. "photos" adds kind:
  // pagePosts (pageId ASC, status ASC, kind ASC, createdAt DESC, __name__ DESC)
  wall: (db, documentIdField, pageId, statuses, tab) => {
    let query = db.collection("pagePosts").where("pageId", "==", pageId);
    query = statuses.length === 1
      ? query.where("status", "==", statuses[0])
      : query.where("status", "in", statuses);
    if (tab === "photos") query = query.where("kind", "==", "photo");
    return query.orderBy("createdAt", "desc").orderBy(documentIdField, "desc");
  },
  // pagePostComments (postId ASC, createdAt DESC, __name__ DESC)
  comments: (db, documentIdField, postId) => db.collection("pagePostComments")
    .where("postId", "==", postId)
    .orderBy("createdAt", "desc")
    .orderBy(documentIdField, "desc"),
  // pages (listed ASC, lastPostAt DESC, __name__ DESC)
  suggest: (db, documentIdField) => db.collection("pages")
    .where("listed", "==", true)
    .orderBy("lastPostAt", "desc")
    .orderBy(documentIdField, "desc"),
  // pages (listed ASC, nameSearch ASC, __name__ ASC); prefix match.
  search: (db, documentIdField, prefix) => db.collection("pages")
    .where("listed", "==", true)
    .where("nameSearch", ">=", prefix)
    .where("nameSearch", "<", `${prefix}\uf8ff`)
    .orderBy("nameSearch", "asc")
    .orderBy(documentIdField, "asc"),
});

function createPagesReadService({
  firestore,
  TimestampImpl = Timestamp,
  documentIdField = FieldPath.documentId(),
  fieldValue = FieldValue,
  clock = () => Date.now(),
  logger = defaultLogger,
  rateLimits = PAGES_READ_RATE_LIMITS,
}) {
  if (!firestore?.doc || typeof TimestampImpl?.fromMillis !== "function" ||
      typeof clock !== "function") {
    throw new TypeError("firestore, Timestamp and clock are required.");
  }
  function plainGetAll(references) {
    if (references.length === 0) return Promise.resolve([]);
    return firestore.getAll(...references);
  }

  // No ids: the kind and a count are enough to find the writer that broke.
  function logSkipped(kind, count = 1) {
    if (count > 0) logger.warn("pages malformed record skipped", { kind, count });
  }

  function timing() {
    const nowMs = clock();
    if (!Number.isSafeInteger(nowMs) || nowMs < 0) {
      throw new TypeError("clock must return epoch milliseconds.");
    }
    return { nowMs, now: TimestampImpl.fromMillis(nowMs) };
  }

  async function chargeRates(scopes, uid, timed) {
    await firestore.runTransaction(async (transaction) => {
      const references = scopes.map((scope) => rateLimitReference(firestore, scope, uid));
      const snapshots = await transactionGetAll(transaction, ...references);
      scopes.forEach((scope, index) => {
        consumeRateLimit(transaction, snapshots[index], {
          reference: references[index],
          scope,
          uid,
          nowMs: timed.nowMs,
          now: timed.now,
          ...rateLimits[scope],
        });
      });
    });
  }

  async function admit(auth, scopes, timed) {
    const activation = await assertPagesReadEnabled({ db: firestore, uid: auth.uid, logger });
    await chargeRates(scopes, auth.uid, timed);
    return activation;
  }

  function assertViewerActive(viewerSnapshot) {
    const viewer = viewerSnapshot?.exists ? (viewerSnapshot.data() ?? null) : null;
    if (!likersAccountIsActive(viewer)) {
      fail("permission-denied", "Your account is not active.");
    }
    return viewer;
  }

  // A broken top-level index is logged and read as empty: every item is
  // still checked against its own pages/{P} document, so this costs reads,
  // never visibility.
  function visibilityOf(snapshot) {
    try {
      return canonicalPageVisibility(snapshot);
    } catch {
      logger.error("pages visibility index malformed on read", {});
      return Object.freeze({ notViewable: new Map(), readOnlySince: new Map(), exists: true });
    }
  }

  function dataOf(snapshot) {
    return snapshot?.exists ? (snapshot.data() ?? null) : null;
  }

  function pageOf(snapshot, pageId) {
    if (!snapshot?.exists) return null;
    const page = canonicalPageOrNull(snapshot, pageId);
    if (page === null) logSkipped("page");
    return page;
  }

  function startAfterPosition(query, position) {
    if (position === null) return query;
    if (position.snapshot) return query.startAfter(position.snapshot);
    return query.startAfter(TimestampImpl.fromMillis(position.t), position.id);
  }

  function itemPosition(doc, field = "createdAt") {
    return { t: timestampMillis(doc.data()?.[field]), id: doc.id, snapshot: doc };
  }

  // A stateless fetcher over one ordered query (wall, comments, suggest).
  function queryFetcher(orderedQuery, toPosition = itemPosition) {
    return async (after, want) => {
      const snapshot = await startAfterPosition(orderedQuery, after).limit(want).get();
      return snapshot.docs.map((doc) => ({ position: toPosition(doc), likerId: null, doc }));
    };
  }

  async function likedSet(viewerId, postIds) {
    const unique = [...new Set(postIds)];
    const snapshots = await plainGetAll(unique.map((postId) =>
      firestore.doc(`pagePosts/${postId}/likes/${viewerId}`)));
    const liked = new Set();
    snapshots.forEach((snapshot, index) => {
      if (snapshot.exists && dataOf(snapshot)?.userId === viewerId) liked.add(unique[index]);
    });
    return liked;
  }

  function withLikes(views, liked) {
    return views.map((view) => ({ ...view, callerLiked: liked.has(view.postId) }));
  }

  // --------------------------------------------------------------- feed

  // The k-way merge of the per-chunk queries, newest first, id descending as
  // the tiebreak (the same order every chunk query uses). Each chunk is
  // fetched 21 at a time and refilled only when its buffer empties.
  function mergedFeedStream(chunkQueries, cursor) {
    const chunks = chunkQueries.map((query) => ({
      query,
      buffer: [],
      exhausted: false,
      after: cursor,
    }));
    const compare = (left, right) => {
      const leftT = timestampMillis(left.data()?.createdAt) ?? Number.MAX_SAFE_INTEGER;
      const rightT = timestampMillis(right.data()?.createdAt) ?? Number.MAX_SAFE_INTEGER;
      if (leftT !== rightT) return rightT - leftT;
      return left.id < right.id ? 1 : left.id > right.id ? -1 : 0;
    };
    async function refill(chunk) {
      if (chunk.exhausted || chunk.buffer.length > 0) return;
      const snapshot = await startAfterPosition(chunk.query, chunk.after)
        .limit(PAGES_FEED_QUERY_LIMIT)
        .get();
      chunk.buffer = [...snapshot.docs];
      chunk.exhausted = snapshot.docs.length < PAGES_FEED_QUERY_LIMIT;
      if (snapshot.docs.length > 0) {
        chunk.after = { snapshot: snapshot.docs[snapshot.docs.length - 1] };
      }
    }
    return async function next() {
      await Promise.all(chunks.map(refill));
      let best = null;
      for (const chunk of chunks) {
        if (chunk.buffer.length === 0) continue;
        if (best === null || compare(chunk.buffer[0], best.buffer[0]) < 0) best = chunk;
      }
      return best === null ? null : best.buffer.shift();
    };
  }

  // scanLikersPage's fetcher contract ("up to `want` candidates strictly
  // after `after`") over a stateful stream: candidates handed out but not
  // consumed (the scan's sentinel) stay in the lookahead for the next call.
  function lookaheadFetcher(next) {
    const lookahead = [];
    return async (after, want) => {
      if (after !== null) {
        const index = lookahead.findIndex((candidate) => candidate.position === after);
        if (index >= 0) lookahead.splice(0, index + 1);
      }
      while (lookahead.length < want) {
        const doc = await next();
        if (doc === null) break;
        lookahead.push({ position: itemPosition(doc), likerId: null, doc });
      }
      return lookahead.slice(0, want);
    };
  }

  async function prunePageFollowIndex(viewerId, staleIds) {
    if (staleIds.size === 0) return;
    try {
      await pageFollowIndexReference(firestore, viewerId).update({
        pageIds: fieldValue.arrayRemove(...staleIds),
        updatedAt: fieldValue.serverTimestamp(),
      });
    } catch (error) {
      logger.warn("pages follow index prune failed", {
        code: typeof error?.code === "string" || Number.isSafeInteger(error?.code)
          ? error.code
          : null,
      });
    }
  }

  async function getPagesFeedV1(request) {
    const auth = requireActor(request, { verified: false });
    const data = requireExactInput(request.data, ["cursor"], ["cursor"]);
    const cursor = decodeItemCursor(data.cursor, "post");
    const timed = timing();
    const activation = await admit(auth, READ_SCOPES, timed);
    const viewerId = auth.uid;

    const [viewerSnapshot, indexSnapshot, visibilitySnapshot] = await plainGetAll([
      firestore.doc(`users/${viewerId}`),
      pageFollowIndexReference(firestore, viewerId),
      pageVisibilityReference(firestore),
    ]);
    const viewerUser = assertViewerActive(viewerSnapshot);
    const index = canonicalPageFollowIndex(indexSnapshot, viewerId);
    const visibility = visibilityOf(visibilitySnapshot);
    const lapseEnabled = activation.lapseEnabled;

    const window = index.pageIds.slice(-PAGES_FEED_INDEX_WINDOW);
    const queried = window.filter((pageId) =>
      !visibilityHides(visibility, pageId, timed.nowMs, lapseEnabled));
    const chunkQueries = [];
    for (let start = 0; start < queried.length; start += PAGES_FEED_IN_CHUNK) {
      chunkQueries.push(PAGES_READ_QUERIES.feedChunk(
        firestore,
        documentIdField,
        queried.slice(start, start + PAGES_FEED_IN_CHUNK),
      ));
    }

    const contexts = new Map();
    const stale = new Set();
    let skipped = 0;
    const resolveVisible = async (candidates) => {
      const posts = candidates.map((candidate) => canonicalPagePostData(candidate.doc));
      const missing = [...new Set(posts
        .filter((post) => post !== null && !contexts.has(post.pageId))
        .map((post) => post.pageId))];
      const snapshots = await plainGetAll(missing.flatMap((pageId) =>
        pageContextReferences(firestore, viewerId, pageId)));
      missing.forEach((pageId, slot) => {
        const [pageSnapshot, pageUserSnapshot, viewerBlock, pageBlock, edge] =
          snapshots.slice(slot * PAGE_CONTEXT_READS, (slot + 1) * PAGE_CONTEXT_READS);
        const page = pageOf(pageSnapshot, pageId);
        const following = followingEdgeExists(edge, pageId);
        if (!pageSnapshot.exists || !following) stale.add(pageId);
        const decision = pageViewDecision({
          viewerId,
          pageId,
          page,
          pageUser: dataOf(pageUserSnapshot),
          viewerUser,
          viewerBlocksPage: viewerBlock.exists,
          pageBlocksViewer: pageBlock.exists,
          visibility,
          nowMs: timed.nowMs,
          lapseEnabled,
        });
        contexts.set(pageId, decision.viewable && following ? page : null);
      });
      return posts.map((post) => {
        if (post === null) {
          skipped += 1;
          return null;
        }
        const page = contexts.get(post.pageId);
        if (!page || post.status !== "published") return null;
        return postView(post, page);
      });
    };

    const scan = await scanLikersPage({
      after: cursor,
      fetchCandidates: lookaheadFetcher(mergedFeedStream(chunkQueries, cursor)),
      resolveVisible,
      isStorable: (position) => storableItemPosition(position, "post"),
      pageSize: PAGES_FEED_PAGE_SIZE,
      scanCap: PAGES_FEED_SCAN_CAP,
    });
    logSkipped("pagePost", skipped);
    const liked = await likedSet(viewerId, scan.likers.map((view) => view.postId));
    await prunePageFollowIndex(viewerId, stale);

    let suggestions = null;
    if (cursor === null) {
      const found = await suggestPages({
        viewerId,
        visibility,
        followed: new Set(index.pageIds),
        timed,
        lapseEnabled,
        pageSize: PAGES_FEED_SUGGESTIONS,
        after: null,
      });
      suggestions = found.cards;
    }
    return feedResponse({
      posts: withLikes(scan.likers, liked),
      nextCursor: scan.hasMore ? encodeItemCursor(scan.lastConsumed) : null,
      suggestions,
    });
  }

  // --------------------------------------------------------------- find

  function findPosition(mode) {
    return (doc) => {
      const data = doc.data() ?? {};
      return mode === "suggest"
        ? { t: timestampMillis(data.lastPostAt), id: doc.id, snapshot: doc }
        : { s: typeof data.nameSearch === "string" ? data.nameSearch : null, id: doc.id, snapshot: doc };
    };
  }

  // The in-memory exclusions shared by suggest and search (§2.7).
  function findCandidatePage({ doc, viewerId, visibility, followed, timed, lapseEnabled }) {
    const page = pageOf(doc, doc.id);
    if (page === null || page.listed !== true || page.pageId === viewerId) return null;
    if (followed !== null && followed.has(page.pageId)) return null;
    if (visibilityHides(visibility, page.pageId, timed.nowMs, lapseEnabled)) return null;
    if (page.ownerPaused || page.suspended || page.status !== "active") return null;
    const renamedAtMs = timestampMillis(page.nameChangedAt);
    if (renamedAtMs !== null && timed.nowMs - renamedAtMs < PAGE_NAME_CHANGE_FIND_DELAY_MS) {
      return null;
    }
    return page;
  }

  function findResolver({ viewerId, visibility, followed, timed, lapseEnabled, withEdge }) {
    return async (candidates) => {
      const pages = candidates.map((candidate) => findCandidatePage({
        doc: candidate.doc,
        viewerId,
        visibility,
        followed,
        timed,
        lapseEnabled,
      }));
      const survivors = pages.filter((page) => page !== null);
      const perPage = withEdge ? PAGES_FIND_CONTEXT_READS + 1 : PAGES_FIND_CONTEXT_READS;
      const snapshots = await plainGetAll(survivors.flatMap((page) => {
        const references = [
          firestore.doc(`users/${page.pageId}`),
          firestore.doc(`users/${viewerId}/blocked/${page.pageId}`),
          firestore.doc(`users/${page.pageId}/blocked/${viewerId}`),
        ];
        if (withEdge) references.push(firestore.doc(`users/${viewerId}/following/${page.pageId}`));
        return references;
      }));
      const cards = new Map();
      survivors.forEach((page, slot) => {
        const [userSnapshot, viewerBlock, pageBlock, edge] =
          snapshots.slice(slot * perPage, (slot + 1) * perPage);
        const pageUser = dataOf(userSnapshot);
        if (!likersAccountIsActive(pageUser) || viewerBlock.exists || pageBlock.exists) return;
        cards.set(page.pageId, pageCard(page, pageUser, {
          viewerFollows: withEdge ? followingEdgeExists(edge, page.pageId) : false,
        }));
      });
      return pages.map((page) => (page === null ? null : (cards.get(page.pageId) ?? null)));
    };
  }

  async function suggestPages({ viewerId, visibility, followed, timed, lapseEnabled, pageSize, after }) {
    const ordered = PAGES_READ_QUERIES.suggest(firestore, documentIdField);
    const scan = await scanLikersPage({
      after,
      fetchCandidates: queryFetcher(ordered, findPosition("suggest")),
      resolveVisible: findResolver({
        viewerId,
        visibility,
        followed,
        timed,
        lapseEnabled,
        withEdge: false,
      }),
      isStorable: (position) => storableFindPosition("suggest", position),
      pageSize,
      scanCap: PAGES_FIND_SCAN_CAP,
    });
    return {
      cards: scan.likers,
      nextCursor: scan.hasMore ? encodeFindCursor("suggest", scan.lastConsumed) : null,
    };
  }

  async function searchPages({ viewerId, visibility, timed, lapseEnabled, query, after }) {
    const ordered = PAGES_READ_QUERIES.search(firestore, documentIdField, query);
    const fetch = async (position, want) => {
      const base = position === null
        ? ordered
        : position.snapshot
          ? ordered.startAfter(position.snapshot)
          : ordered.startAfter(position.s, position.id);
      const snapshot = await base.limit(want).get();
      return snapshot.docs.map((doc) => ({
        position: findPosition("search")(doc),
        likerId: null,
        doc,
      }));
    };
    const scan = await scanLikersPage({
      after,
      fetchCandidates: fetch,
      resolveVisible: findResolver({
        viewerId,
        visibility,
        followed: null,
        timed,
        lapseEnabled,
        withEdge: true,
      }),
      isStorable: (position) => storableFindPosition("search", position),
      pageSize: PAGES_FIND_PAGE_SIZE,
      scanCap: PAGES_FIND_SCAN_CAP,
    });
    return {
      cards: scan.likers,
      nextCursor: scan.hasMore ? encodeFindCursor("search", scan.lastConsumed) : null,
    };
  }

  // The desktop panel: the follow index newest first, PAGES_FIND_PAGE_SIZE
  // ids consumed per call, each verified against its edge and its Page.
  async function followingPages({ viewerId, viewerUser, index, visibility, timed, lapseEnabled, after }) {
    const newestFirst = [...index.pageIds].reverse();
    let start = 0;
    if (after !== null) {
      start = newestFirst[after.n - 1] === after.id
        ? after.n
        : newestFirst.indexOf(after.id) >= 0
          ? newestFirst.indexOf(after.id) + 1
          : Math.min(after.n, newestFirst.length);
    }
    const ids = newestFirst.slice(start, start + PAGES_FIND_PAGE_SIZE);
    const snapshots = await plainGetAll(ids.flatMap((pageId) =>
      pageContextReferences(firestore, viewerId, pageId)));
    const stale = new Set();
    const cards = [];
    ids.forEach((pageId, slot) => {
      const [pageSnapshot, pageUserSnapshot, viewerBlock, pageBlock, edge] =
        snapshots.slice(slot * PAGE_CONTEXT_READS, (slot + 1) * PAGE_CONTEXT_READS);
      const page = pageOf(pageSnapshot, pageId);
      const following = followingEdgeExists(edge, pageId);
      if (!pageSnapshot.exists || !following) stale.add(pageId);
      const pageUser = dataOf(pageUserSnapshot);
      const decision = pageViewDecision({
        viewerId,
        pageId,
        page,
        pageUser,
        viewerUser,
        viewerBlocksPage: viewerBlock.exists,
        pageBlocksViewer: pageBlock.exists,
        visibility,
        nowMs: timed.nowMs,
        lapseEnabled,
      });
      if (decision.viewable && following) {
        cards.push(pageCard(page, pageUser, { viewerFollows: true }));
      }
    });
    await prunePageFollowIndex(viewerId, stale);
    const consumed = start + ids.length;
    const hasMore = consumed < newestFirst.length && ids.length > 0;
    return {
      cards,
      nextCursor: hasMore
        ? encodeFindCursor("following", { n: consumed, id: ids[ids.length - 1] })
        : null,
    };
  }

  function requireFindInput(data) {
    requireExactInput(data, ["cursor", "mode", "query"], ["cursor", "mode", "query"]);
    if (!FIND_PAGES_MODES.includes(data.mode)) fail("invalid-argument", "mode is invalid.");
    let query = null;
    if (data.mode === "search") {
      if (typeof data.query !== "string") fail("invalid-argument", "query must be text.");
      query = pageNameSearch(data.query);
      if (query.length < PAGES_FIND_QUERY_MIN || query.length > PAGES_FIND_QUERY_MAX) {
        fail("invalid-argument", "query must be 2-60 characters.");
      }
    } else if (data.query !== null) {
      fail("invalid-argument", "query must be null.");
    }
    return { mode: data.mode, query, cursor: decodeFindCursor(data.cursor, data.mode) };
  }

  async function findPagesV1(request) {
    const auth = requireActor(request, { verified: false });
    const input = requireFindInput(request.data);
    const timed = timing();
    const activation = await admit(auth, FIND_SCOPES, timed);
    const viewerId = auth.uid;
    const [viewerSnapshot, indexSnapshot, visibilitySnapshot] = await plainGetAll([
      firestore.doc(`users/${viewerId}`),
      pageFollowIndexReference(firestore, viewerId),
      pageVisibilityReference(firestore),
    ]);
    const viewerUser = assertViewerActive(viewerSnapshot);
    const index = canonicalPageFollowIndex(indexSnapshot, viewerId);
    const visibility = visibilityOf(visibilitySnapshot);
    const lapseEnabled = activation.lapseEnabled;
    let found;
    if (input.mode === "suggest") {
      found = await suggestPages({
        viewerId,
        visibility,
        followed: new Set(index.pageIds),
        timed,
        lapseEnabled,
        pageSize: PAGES_FIND_PAGE_SIZE,
        after: input.cursor,
      });
    } else if (input.mode === "search") {
      found = await searchPages({
        viewerId,
        visibility,
        timed,
        lapseEnabled,
        query: input.query,
        after: input.cursor,
      });
    } else {
      found = await followingPages({
        viewerId,
        viewerUser,
        index,
        visibility,
        timed,
        lapseEnabled,
        after: input.cursor,
      });
    }
    return findResponse({ pages: found.cards, nextCursor: found.nextCursor });
  }

  // --------------------------------------------------------------- profile

  function requirePageInput(data) {
    requireExactInput(data, ["cursor", "pageId", "tab"], ["cursor", "pageId", "tab"]);
    const pageId = requireUid(data.pageId, "pageId");
    if (data.tab !== "wall" && data.tab !== "photos") fail("invalid-argument", "tab is invalid.");
    return { pageId, tab: data.tab, cursor: decodeItemCursor(data.cursor, "post") };
  }

  function linkedServerOf(page, snapshot) {
    if (page.kind !== "community" || page.community?.linkedServerId == null) return null;
    try {
      const server = canonicalServer(snapshot);
      return admitsPublicJoin(server) && server.ownerId === page.pageId ? server : null;
    } catch {
      return null;
    }
  }

  async function getPageV1(request) {
    const auth = requireActor(request, { verified: false });
    const input = requirePageInput(request.data);
    const timed = timing();
    const activation = await admit(auth, READ_SCOPES, timed);
    const viewerId = auth.uid;
    const pageId = input.pageId;
    const lapseEnabled = activation.lapseEnabled;

    const [pageSnapshot, pageUserSnapshot, viewerBlock, pageBlock, edge, viewerSnapshot] =
      await plainGetAll([
        ...pageContextReferences(firestore, viewerId, pageId),
        firestore.doc(`users/${viewerId}`),
      ]);
    const viewerUser = assertViewerActive(viewerSnapshot);
    const page = pageOf(pageSnapshot, pageId);
    const pageUser = dataOf(pageUserSnapshot);
    const decision = pageViewDecision({
      viewerId,
      pageId,
      page,
      pageUser,
      viewerUser,
      viewerBlocksPage: viewerBlock.exists,
      pageBlocksViewer: pageBlock.exists,
      nowMs: timed.nowMs,
      lapseEnabled,
    });
    if (!decision.viewable) throw pageUnavailableError();
    const isOwner = decision.isOwner;
    const following = !isOwner && followingEdgeExists(edge, pageId);
    const statuses = isOwner ? ["published", "held"] : ["published"];

    let header = null;
    let viewer = null;
    let pinned = null;
    if (input.cursor === null) {
      const linkedServerId = page.kind === "community"
        ? (page.community?.linkedServerId ?? null)
        : null;
      const references = [
        firestore.doc(`entitlements/${pageId}`),
        firestore.doc(`vipGrants/${pageId}`),
      ];
      const pinnedSlot = input.tab === "wall" && page.pinnedPostId !== null
        ? references.push(firestore.doc(`pagePosts/${page.pinnedPostId}`)) - 1
        : -1;
      const serverSlot = linkedServerId !== null
        ? references.push(firestore.doc(`clubs/${linkedServerId}`)) - 1
        : -1;
      const dmSlot = !isOwner
        ? references.push(
            firestore.doc(`users/${pageId}/following/${viewerId}`),
            firestore.doc(`friendshipGuards/${viewerId}/friends/${pageId}`),
            firestore.doc(`friendshipGuards/${pageId}/friends/${viewerId}`),
            firestore.doc(`pages/${viewerId}`),
            firestore.doc(`restrictions/${viewerId}`),
            firestore.doc(`restrictions/${pageId}`),
          ) - 6
        : -1;
      const extra = await plainGetAll(references);
      const pageEntitlement = dataOf(extra[0]);
      const pageGrant = dataOf(extra[1]);
      const liveStatus = livePageStatus({
        page,
        pageUser,
        pageEntitlement,
        pageGrant,
        nowMs: timed.nowMs,
        lapseEnabled,
      });
      header = pageHeader(page, pageUser, {
        effectiveStatus: liveStatus,
        linkedServer: serverSlot >= 0 ? linkedServerOf(page, extra[serverSlot]) : null,
      });
      let canMessage = false;
      if (dmSlot >= 0) {
        const [recipientFollowsActor, actorFriendGuard, recipientFriendGuard, actorPage,
          viewerRestriction, pageRestriction] = extra.slice(dmSlot, dmSlot + 6);
        canMessage = auth.token?.email_verified === true &&
          !restrictionIsActive(dataOf(viewerRestriction), timed.nowMs) &&
          !restrictionIsActive(dataOf(pageRestriction), timed.nowMs) &&
          directMessagePrivacyAllows({
            actorId: viewerId,
            recipientId: pageId,
            recipientProfile: pageUserSnapshot,
            recipientFollowsActor,
            actorFriendGuard,
            recipientFriendGuard,
            actorPage,
          });
      }
      viewer = viewerView({
        isOwner,
        following,
        canFollow: !isOwner && !following && auth.token?.email_verified === true &&
          pageAcceptsFollowers({
            callerId: viewerId,
            activation,
            page,
            pageUser,
            pageEntitlement,
            pageGrant,
            nowMs: timed.nowMs,
          }),
        canMessage,
      });
      if (pinnedSlot >= 0) {
        const post = canonicalPagePostData(extra[pinnedSlot]);
        if (post !== null && post.pageId === pageId && statuses.includes(post.status)) {
          pinned = postView(post, page);
        }
      }
    }

    const ordered =
      PAGES_READ_QUERIES.wall(firestore, documentIdField, pageId, statuses, input.tab);
    let skipped = 0;
    const scan = await scanLikersPage({
      after: input.cursor,
      fetchCandidates: queryFetcher(ordered),
      resolveVisible: async (candidates) => candidates.map((candidate) => {
        const post = canonicalPagePostData(candidate.doc);
        if (post === null) {
          skipped += 1;
          return null;
        }
        if (post.pageId !== pageId || !statuses.includes(post.status)) return null;
        // The pinned post heads the wall once; it is not repeated below it.
        if (input.tab === "wall" && post.postId === page.pinnedPostId) return null;
        if (input.tab === "photos" && post.kind !== "photo") return null;
        return postView(post, page);
      }),
      isStorable: (position) => storableItemPosition(position, "post"),
      pageSize: PAGES_WALL_PAGE_SIZE,
      scanCap: PAGES_WALL_SCAN_CAP,
    });
    logSkipped("pagePost", skipped);
    const liked = await likedSet(viewerId, [
      ...scan.likers.map((view) => view.postId),
      ...(pinned ? [pinned.postId] : []),
    ]);
    return pageResponse({
      page: header,
      viewer,
      pinned: pinned ? withLikes([pinned], liked)[0] : null,
      posts: withLikes(scan.likers, liked),
      nextCursor: scan.hasMore ? encodeItemCursor(scan.lastConsumed) : null,
    });
  }

  // --------------------------------------------------------------- post

  function requirePostInput(data) {
    requireExactInput(data, ["commentCursor", "postId"], ["commentCursor", "postId"]);
    if (typeof data.postId !== "string" || !PAGE_POST_ID_PATTERN.test(data.postId)) {
      fail("invalid-argument", "postId is invalid.");
    }
    return { postId: data.postId, commentCursor: decodeItemCursor(data.commentCursor, "comment") };
  }

  // Comment authors: users/{A}, publicProfiles/{A}, both blocks. The viewer
  // always sees their own comments (name from their own projection).
  const COMMENT_AUTHOR_READS = 4;

  async function getPagePostV1(request) {
    const auth = requireActor(request, { verified: false });
    const input = requirePostInput(request.data);
    const timed = timing();
    const activation = await admit(auth, READ_SCOPES, timed);
    const viewerId = auth.uid;
    const lapseEnabled = activation.lapseEnabled;

    const [postSnapshot, viewerSnapshot] = await plainGetAll([
      firestore.doc(`pagePosts/${input.postId}`),
      firestore.doc(`users/${viewerId}`),
    ]);
    const viewerUser = assertViewerActive(viewerSnapshot);
    const post = canonicalPagePostData(postSnapshot);
    if (post === null) {
      if (postSnapshot.exists) logSkipped("pagePost");
      throw pageUnavailableError();
    }
    const pageId = post.pageId;
    const [pageSnapshot, pageUserSnapshot, viewerBlock, pageBlock, likeSnapshot] =
      await plainGetAll([
        firestore.doc(`pages/${pageId}`),
        firestore.doc(`users/${pageId}`),
        firestore.doc(`users/${viewerId}/blocked/${pageId}`),
        firestore.doc(`users/${pageId}/blocked/${viewerId}`),
        firestore.doc(`pagePosts/${post.postId}/likes/${viewerId}`),
      ]);
    const page = pageOf(pageSnapshot, pageId);
    const decision = pageViewDecision({
      viewerId,
      pageId,
      page,
      pageUser: dataOf(pageUserSnapshot),
      viewerUser,
      viewerBlocksPage: viewerBlock.exists,
      pageBlocksViewer: pageBlock.exists,
      nowMs: timed.nowMs,
      lapseEnabled,
    });
    const statuses = decision.isOwner ? ["published", "held"] : ["published"];
    if (!decision.viewable || !statuses.includes(post.status)) throw pageUnavailableError();

    const ordered = PAGES_READ_QUERIES.comments(firestore, documentIdField, post.postId);
    const authors = new Map();
    let skipped = 0;
    const resolveVisible = async (candidates) => {
      const comments = candidates.map((candidate) => canonicalPageCommentData(candidate.doc));
      const missing = [...new Set(comments
        .filter((comment) => comment !== null && !authors.has(comment.authorId))
        .map((comment) => comment.authorId))];
      const snapshots = await plainGetAll(missing.flatMap((authorId) => [
        firestore.doc(`users/${authorId}`),
        firestore.doc(`publicProfiles/${authorId}`),
        firestore.doc(`users/${viewerId}/blocked/${authorId}`),
        firestore.doc(`users/${authorId}/blocked/${viewerId}`),
      ]));
      missing.forEach((authorId, slot) => {
        const [userSnapshot, publicSnapshot, viewerBlocksAuthor, authorBlocksViewer] =
          snapshots.slice(slot * COMMENT_AUTHOR_READS, (slot + 1) * COMMENT_AUTHOR_READS);
        let name = null;
        try {
          name = canonicalPublicProfile(publicSnapshot, authorId).displayName;
        } catch {
          name = null;
        }
        const visible = name !== null && (authorId === viewerId ||
          (likersAccountIsActive(dataOf(userSnapshot)) &&
            !viewerBlocksAuthor.exists && !authorBlocksViewer.exists));
        authors.set(authorId, visible ? name : null);
      });
      return comments.map((comment) => {
        if (comment === null) {
          skipped += 1;
          return null;
        }
        if (comment.postId !== post.postId || comment.pageId !== pageId) return null;
        const authorName = authors.get(comment.authorId) ?? null;
        return authorName === null ? null : commentView(comment, { authorName, pageId });
      });
    };
    const scan = await scanLikersPage({
      after: input.commentCursor,
      fetchCandidates: queryFetcher(ordered),
      resolveVisible,
      isStorable: (position) => storableItemPosition(position, "comment"),
      pageSize: PAGES_COMMENT_PAGE_SIZE,
      scanCap: PAGES_COMMENT_SCAN_CAP,
    });
    logSkipped("pagePostComment", skipped);
    return postResponse({
      post: {
        ...postView(post, page),
        callerLiked: likeSnapshot.exists && dataOf(likeSnapshot)?.userId === viewerId,
      },
      comments: scan.likers,
      nextCommentCursor: scan.hasMore ? encodeItemCursor(scan.lastConsumed) : null,
    });
  }

  return Object.freeze({ findPagesV1, getPagePostV1, getPageV1, getPagesFeedV1 });
}

let defaultService = null;
function service() {
  if (defaultService === null) {
    const { db } = require("../utils/firestore");
    defaultService = createPagesReadService({ firestore: db });
  }
  return defaultService;
}

const callableOptions = { region: REGION, enforceAppCheck: false };
const getPagesFeedV1 = onCall(callableOptions, (request) => service().getPagesFeedV1(request));
const getPageV1 = onCall(callableOptions, (request) => service().getPageV1(request));
const getPagePostV1 = onCall(callableOptions, (request) => service().getPagePostV1(request));
const findPagesV1 = onCall(callableOptions, (request) => service().findPagesV1(request));

module.exports = {
  FIND_SCOPES,
  PAGES_COMMENT_PAGE_SIZE,
  PAGES_COMMENT_SCAN_CAP,
  PAGES_FEED_INDEX_WINDOW,
  PAGES_FEED_IN_CHUNK,
  PAGES_FEED_MAX_CHUNKS,
  PAGES_FEED_PAGE_SIZE,
  PAGES_FEED_QUERY_LIMIT,
  PAGES_FEED_SCAN_CAP,
  PAGES_FEED_SUGGESTIONS,
  PAGES_FIND_CONTEXT_READS,
  PAGES_FIND_PAGE_SIZE,
  PAGES_FIND_QUERY_MAX,
  PAGES_FIND_QUERY_MIN,
  PAGES_FIND_SCAN_CAP,
  PAGES_READ_QUERIES,
  PAGES_READ_RATE_LIMITS,
  PAGES_WALL_PAGE_SIZE,
  PAGES_WALL_SCAN_CAP,
  READ_SCOPES,
  createPagesReadService,
  findPagesV1,
  getPagePostV1,
  getPageV1,
  getPagesFeedV1,
  pagesFeedReadBudget,
};
