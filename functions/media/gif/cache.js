// The cache that makes a beta key survivable, plus the suppression list that
// makes the local blocklist effective on a cached page.
//
// Three layers, cheapest first:
//   1. a per-instance LRU memo, so the trending first page — by far the
//      hottest path, because every panel open starts there — costs nothing at
//      all on a warm instance;
//   2. `gifQueryCache/{sha256(...)}`, SHARED ACROSS ALL USERS, so a popular
//      query costs the provider approximately zero. This is the layer the
//      whole rate-limit budget depends on;
//   3. the provider itself, guarded by the hourly budget in rate_limit.js.
//
// `gifAssets/{provider}_{id}` is written on a miss and is NEVER expired. It is
// three things at once and none of them are optional: the send-time authority
// that messaging reads transactionally before publishing a GIF, the
// moderation record that carries `blocked` and `reportCount`, and the
// per-asset blocklist. Deleting it would break sending — so a future cleanup
// task must replace the send-time authority first.

"use strict";

const { FieldValue, Timestamp } = require("firebase-admin/firestore");

const { gifAssetDocumentId } = require("./gif_ref");

/// Trending changes through the day; a search result for a given phrase does
/// not. The two TTLs differ for that reason alone.
const TRENDING_TTL_MS = 10 * 60 * 1000;
const SEARCH_TTL_MS = 6 * 60 * 60 * 1000;

/// One instance holds roughly one warm working set. 200 entries at ~24 assets
/// each is small enough to be irrelevant against a 512MiB function and large
/// enough to cover trending plus the day's popular searches.
const MEMO_CAPACITY = 200;
const MEMO_TTL_MS = 60 * 1000;

/// Firestore rejects a write over 1 MiB. A page of 30 normalized assets is a
/// few kilobytes, so this is a guard against a pathological provider response
/// rather than an expected limit — but an unguarded cache write would fail the
/// whole request instead of just skipping the cache.
const MAX_CACHED_ITEMS = 60;

/// THE SUPPRESSION LIST IS ONE DOCUMENT ON PURPOSE.
///
/// The query cache is shared and lives for up to six hours, so filtering
/// blocked assets only where they are written would leave a blocked GIF
/// visible in every cached page until its TTL lapsed. Re-reading
/// `gifAssets` for all 24 items on every hit would cost 24 reads and defeat
/// the cache outright. One capped document read once per call makes the block
/// effective immediately on cached and fresh pages alike, for the price of a
/// single read. The cap is what keeps that document small and its read cheap;
/// `gifAssets.blocked` remains the durable per-asset truth and the send-time
/// authority, and this is its hot-path index.
const SUPPRESSION_DOCUMENT = Object.freeze({
  collection: "gifBlocklist",
  id: "current",
  capacity: 500,
});
const SUPPRESSION_TTL_MS = 60 * 1000;

function ttlFor(kind) {
  return kind === "trending" ? TRENDING_TTL_MS : SEARCH_TTL_MS;
}

/// Insertion-ordered Map used as an LRU: re-reading moves the key to the back,
/// and the oldest key is the first one `keys()` yields.
function createMemo({ capacity = MEMO_CAPACITY, ttlMs = MEMO_TTL_MS } = {}) {
  const entries = new Map();
  return {
    read(key, nowMs) {
      const hit = entries.get(key);
      if (!hit) return null;
      if (hit.expiresAtMs <= nowMs) {
        entries.delete(key);
        return null;
      }
      entries.delete(key);
      entries.set(key, hit);
      return hit.value;
    },
    write(key, value, nowMs) {
      entries.delete(key);
      entries.set(key, { value, expiresAtMs: nowMs + ttlMs });
      while (entries.size > capacity) {
        const oldest = entries.keys().next();
        if (oldest.done) break;
        entries.delete(oldest.value);
      }
    },
    get size() {
      return entries.size;
    },
    clear() {
      entries.clear();
    },
  };
}

function createGifCache({ db, now = () => Date.now(), memo = null } = {}) {
  if (!db) throw new TypeError("A Firestore handle is required.");
  const lru = memo ?? createMemo();
  let suppressionCache = { ids: new Set(), readAtMs: -Infinity };

  const queryDoc = (key) => db.collection("gifQueryCache").doc(key);
  const suppressionDoc = () =>
    db
      .collection(SUPPRESSION_DOCUMENT.collection)
      .doc(SUPPRESSION_DOCUMENT.id);
  const assetDoc = (provider, id) => {
    const documentId = gifAssetDocumentId(provider, id);
    return documentId === null
      ? null
      : db.collection("gifAssets").doc(documentId);
  };

  /// A cached page, or `null`.
  ///
  /// An expired document is treated as a MISS regardless of whether any
  /// sweeper has run, so correctness never depends on cleanup. Cleanup itself
  /// is a native Firestore TTL policy on `gifQueryCache.expiresAt` — a manual
  /// console step recorded in docs/DEPLOYMENT.md, not a scheduled function.
  async function readQuery(key) {
    const nowMs = now();
    const memoized = lru.read(key, nowMs);
    if (memoized) return { ...memoized, source: "memo" };

    let snapshot;
    try {
      snapshot = await queryDoc(key).get();
    } catch (_) {
      // A cache read failing must never fail the search. Falling through is
      // exactly what a miss does.
      return null;
    }
    if (!snapshot.exists) return null;
    const data = snapshot.data() ?? {};
    const expiresAtMs =
      data.expiresAt instanceof Timestamp ? data.expiresAt.toMillis() : 0;
    if (!Number.isFinite(expiresAtMs) || expiresAtMs <= nowMs) return null;
    if (!Array.isArray(data.items)) return null;
    const value = {
      items: data.items,
      nextCursor: typeof data.nextCursor === "string" ? data.nextCursor : null,
      cachedAtMs:
        data.cachedAt instanceof Timestamp ? data.cachedAt.toMillis() : nowMs,
    };
    lru.write(key, value, nowMs);
    return { ...value, source: "firestore" };
  }

  async function writeQuery(key, { kind, items, nextCursor }) {
    const nowMs = now();
    const bounded = items.slice(0, MAX_CACHED_ITEMS);
    const value = {
      items: bounded,
      nextCursor: nextCursor ?? null,
      cachedAtMs: nowMs,
    };
    lru.write(key, value, nowMs);
    try {
      await queryDoc(key).set({
        schemaVersion: 1,
        items: bounded,
        nextCursor: nextCursor ?? null,
        cachedAt: Timestamp.fromMillis(nowMs),
        expiresAt: Timestamp.fromMillis(nowMs + ttlFor(kind)),
      });
    } catch (_) {
      // The page is already being returned to the caller; losing the cache
      // write costs a future provider call, not this request.
    }
  }

  /// Persist the assets a page is made of, and report which ones landed.
  ///
  /// The callable omits from its response any asset whose write failed. That
  /// keeps a picker result backed by a durable `gifAssets/{provider}_{id}`
  /// record. The message callable can then resolve it without another
  /// provider request while rechecking current moderation state.
  ///
  /// `firstSeenAt` is written only for assets that are genuinely new, which is
  /// why the existing documents are read first. That read is also what makes
  /// the miss path honest about `blocked` and `reportCount`: those fields are
  /// returned to the caller so a blocked asset is dropped from the page it
  /// was about to appear in. The read and write share a transaction: a failed
  /// pre-read or concurrent first observation must never reset moderation.
  async function writeAssets(items) {
    if (items.length === 0) {
      return { written: new Set(), blocked: new Set() };
    }
    const nowMs = now();
    const stamp = Timestamp.fromMillis(nowMs);
    const referencesById = new Map();
    for (const item of items) {
      const reference = assetDoc(item.provider, item.id);
      if (reference !== null) referencesById.set(reference.id, { item, reference });
    }
    const references = [...referencesById.values()];
    if (references.length === 0) {
      return { written: new Set(), blocked: new Set() };
    }

    try {
      return await db.runTransaction(async (transaction) => {
        const existing = await transaction.getAll(
          ...references.map((entry) => entry.reference),
        );
        const knownBlocked = new Set();
        const written = new Set();
        for (let index = 0; index < references.length; index += 1) {
          const { item, reference } = references[index];
          const snapshot = existing[index];
          const previous = snapshot.exists ? (snapshot.data() ?? {}) : null;
          if (previous?.blocked === true) knownBlocked.add(reference.id);
          const record = {
            schemaVersion: 1,
            provider: item.provider,
            gifId: item.id,
            title: item.title,
            rating: item.rating,
            url: item.full.url,
            previewUrl: item.preview.url,
            width: item.full.width,
            height: item.full.height,
            lastSeenAt: stamp,
          };
          if (!snapshot.exists) {
            record.firstSeenAt = stamp;
            record.reportCount = 0;
            record.blocked = false;
          }
          transaction.set(reference, record, { merge: true });
          written.add(reference.id);
        }
        return { written, blocked: knownBlocked };
      });
    } catch (_) {
      // No proof of a committed asset means no picker result. In particular,
      // never reinterpret a failed read as absence and write blocked:false.
      return { written: new Set(), blocked: new Set() };
    }
  }

  async function readAsset(provider, id) {
    const reference = assetDoc(provider, id);
    if (reference === null) return null;
    const snapshot = await reference.get();
    if (!snapshot.exists) return null;
    return { id: snapshot.id, ...(snapshot.data() ?? {}) };
  }

  /// The suppression list, memoized for a minute per instance.
  ///
  /// A minute of staleness on an un-block is harmless; a minute on a block is
  /// the price of not paying a read per item per request. A missing or
  /// unreadable document means "nothing suppressed", which is the same answer
  /// as before any moderator has ever blocked anything.
  async function suppressedAssetIds() {
    const nowMs = now();
    if (nowMs - suppressionCache.readAtMs < SUPPRESSION_TTL_MS) {
      return suppressionCache.ids;
    }
    let ids = new Set();
    try {
      const snapshot = await suppressionDoc().get();
      const raw = snapshot.exists ? (snapshot.data() ?? {}).assetIds : null;
      if (Array.isArray(raw)) {
        ids = new Set(raw.filter((value) => typeof value === "string"));
      }
    } catch (_) {
      ids = suppressionCache.ids;
    }
    suppressionCache = { ids, readAtMs: nowMs };
    return ids;
  }

  /// Add one asset id to the capped suppression list.
  ///
  /// `arrayUnion` is idempotent, so repeated reports and a moderator re-block
  /// converge without a transaction. The cap is trimmed opportunistically:
  /// oldest-first, because a recently blocked asset is the one still appearing
  /// in live cache entries.
  async function suppressAsset(documentId) {
    if (typeof documentId !== "string" || documentId.length === 0) return;
    const reference = suppressionDoc();
    try {
      await reference.set(
        {
          schemaVersion: 1,
          assetIds: FieldValue.arrayUnion(documentId),
          updatedAt: Timestamp.fromMillis(now()),
        },
        { merge: true },
      );
      const snapshot = await reference.get();
      const ids = (snapshot.data() ?? {}).assetIds;
      if (Array.isArray(ids) && ids.length > SUPPRESSION_DOCUMENT.capacity) {
        await reference.set(
          { assetIds: ids.slice(ids.length - SUPPRESSION_DOCUMENT.capacity) },
          { merge: true },
        );
      }
    } catch (_) {
      // `gifAssets.blocked` is the durable truth and is written first by every
      // caller; this index failing costs freshness, never correctness.
    }
    suppressionCache = { ids: new Set(), readAtMs: -Infinity };
  }

  return {
    MAX_CACHED_ITEMS,
    SEARCH_TTL_MS,
    SUPPRESSION_DOCUMENT,
    TRENDING_TTL_MS,
    assetDoc,
    memo: lru,
    queryDoc,
    readAsset,
    readQuery,
    suppressAsset,
    suppressedAssetIds,
    suppressionDoc,
    ttlFor,
    writeAssets,
    writeQuery,
  };
}

module.exports = {
  MAX_CACHED_ITEMS,
  MEMO_CAPACITY,
  MEMO_TTL_MS,
  SEARCH_TTL_MS,
  SUPPRESSION_DOCUMENT,
  SUPPRESSION_TTL_MS,
  TRENDING_TTL_MS,
  createGifCache,
  createMemo,
  ttlFor,
};
