// Page posts (ADR-233 §2.4): reservePagePostMediaV1, publishPagePostV1 and
// managePagePostV1. europe-west1, enforceAppCheck:false, like every Pages
// callable. Nothing here is warm or a keep-warm target.
//
//   reserve -> the server allocates the postId and one mediaId per item,
//              charges the Page's daily budget (reservations + bytes) and
//              opens ONE lease per owner; storage.rules admits exactly the
//              reserved objects for 15 minutes
//   upload  -> the client writes page_posts/{pageId}/{postId}/{mediaId}.{jpg|m4a}
//   publish -> per object: exact metadata, the trusted probe (bytes, tracks,
//              measured duration), assertNoImageMetadata for photos (Exif,
//              XMP, ICC, COM refused), a metadata re-read and the download
//              token revoked; then ONE transaction re-derives the gate and
//              the Page state, checks the budget and the lease, creates the
//              post, deletes the reservations and the lease, and moves
//              postCount / lastPostAt / listed, budget posts + 1 and the ledger
//   manage  -> delete (a SAFETY action: no activation, no gate, allowed while
//              muted and unverified), pin, unpin, setCommentsEnabled
//
// Order in every call (§2.1): auth -> exact input -> activation (non-safety
// only) -> rate budget -> gate (writes) -> content.
//
// Common write preconditions (§2.2) on reserve, publish, pin, unpin and
// setCommentsEnabled, inside the transaction: users/{uid} active, no
// communication mute, verified e-mail. Every gated write that finds the
// capability live also RESTORES a lapsed Page (§2.8 "every write path").
//
// Counter invariant (§1.7): pages.postCount is the number of the Page's
// posts whose status is "published". Publish adds one; deleting (or
// tombstoning) a published post removes one; held / removed posts are not
// counted, so the moderation package moves it when it holds, removes or
// restores a post.
//
// Delete (§2.4, S-B1): a published post with no open report is HARD
// deleted (the post, then its likes and comments in batches of 400 through a
// durable pagePostCleanupJobs row, and one media deletion job per object). A
// held or removed post, or one with evidenceHold / an open report, becomes a
// TOMBSTONE (status "deleted", moderationEvidence fingerprint, text and
// media refs kept, readers never see it). Its media jobs are HELD (heldBy
// set) only while a report is open (evidenceHold or an open-report count),
// so the bytes survive until the report resolves; a held or removed post
// with no open report gets unheld jobs. Every tombstone also gets a
// pageEvidenceRetention row (reason "ownerDelete", purgeAt now + 90 days):
// pagesMaintenance purges the tombstone, its likes, comments and media when
// the last open report resolves (moderation sets purgeAt to now) or after 90
// days, whichever comes first (audit 2026-09-28).

const { Timestamp } = require("firebase-admin/firestore");
const { onCall } = require("firebase-functions/v2/https");
const defaultLogger = require("firebase-functions/logger");

const {
  assertLedgerReplay,
  assertNotRestricted,
  consumeRateLimit,
  fail,
  ledgerData,
  operationIdentity,
  rateLimitReference,
  requireActor,
  requireExactInput,
  requireObject,
  requireRequestId,
  transactionGetAll,
} = require("../integrity/guards");
const { likersAccountIsActive } = require("../utils/likers_access");
const {
  derivePagesCapability,
  pageAccessRequiredError,
  pagesCapabilityReferences,
} = require("./access");
const { assertPagesWriteEnabled } = require("./activation");
const { pageUnavailableError } = require("./audience");
const {
  PAGE_ERRORS,
  PAGE_MEDIA_ID_PATTERN,
  PAGE_POST_ID_PATTERN,
  canonicalPage,
  canonicalPageOrNull,
  derivePageListed,
} = require("./contract");
const { restoredPageFields } = require("./lapse");
const {
  PAGE_DAILY_BUDGET,
  PAGE_MEDIA_HEAD_BYTES,
  PAGE_MEDIA_POST_KINDS,
  PAGE_MEDIA_RESERVATION_TTL_MS,
  PAGE_MEDIA_TYPES,
  PAGE_MEDIA_UPLOAD_METADATA_KEYS,
  PAGE_MODERATION_HOLD,
  PAGE_POST_ERRORS,
  PAGE_VOICE_DURATION_TOLERANCE_MS,
  canonicalPageBudget,
  canonicalPageMediaLease,
  canonicalPageMediaReservation,
  newReservation,
  normalizePostText,
  pageBudgetDay,
  pageBudgetDocument,
  pageMediaDeletionJob,
  pageMediaIdFor,
  pageMediaUploadMetadata,
  pagePostCleanupJob,
  pagePostIdFor,
  pagePostEvidenceFingerprint,
  pagePostOpenReports,
  requireReserveItems,
} = require("./media_contract");
const { assertNoImageMetadata } = require("./media_probe");
const {
  PAGE_EVIDENCE_RETENTION_MS,
  pageEvidenceRetentionDocument,
} = require("./report_contract");
const { customMetadataOf, hasDownloadToken, isMissingObject } = require("./media_storage");
const {
  PAGE_POST_MAX_PHOTOS,
  PAGE_POST_VOICE_MAX_MS,
  canonicalPagePostData,
  pagePostMalformedReason,
} = require("./post_contract");
const { postView } = require("./views");
const {
  applyPageVisibilityInTransaction,
  pageVisibilityReference,
} = require("./visibility");

const REGION = "europe-west1";
const MINUTE_MS = 60_000;

const PAGES_POST_RATE_LIMITS = Object.freeze({
  "pages.reserve": Object.freeze({ maxEvents: 20, windowMs: MINUTE_MS }),
  "pages.publish": Object.freeze({ maxEvents: 3, windowMs: 10 * MINUTE_MS }),
  "pages.manage": Object.freeze({ maxEvents: 30, windowMs: MINUTE_MS }),
});
const LEDGER_KINDS = Object.freeze({
  reserve: "pages.post.reserve.v1",
  publish: "pages.post.publish.v1",
  manage: "pages.post.manage.v1",
});
const MANAGE_POST_OPS = Object.freeze(["delete", "pin", "unpin", "setCommentsEnabled"]);
const PAGE_POST_KINDS_INPUT = Object.freeze(["text", "photo", "voice"]);
const MANAGE_RESPONSE_KEYS = Object.freeze([
  "commentsEnabled",
  "deleted",
  "op",
  "pinned",
  "postId",
  "schemaVersion",
]);

// ------------------------------------------------------------------ inputs

function reserveInput(data) {
  const fields = ["requestId", "kind", "items"];
  requireExactInput(data, fields, fields);
  const requestId = requireRequestId(data.requestId);
  if (!PAGE_MEDIA_POST_KINDS.includes(data.kind)) {
    fail("invalid-argument", "kind must be photo or voice.");
  }
  return { requestId, kind: data.kind, items: requireReserveItems(data.kind, data.items) };
}

function publishInput(data) {
  const fields = ["requestId", "postId", "kind", "text", "mediaIds", "commentsEnabled"];
  requireExactInput(data, fields, fields);
  const requestId = requireRequestId(data.requestId);
  if (!PAGE_POST_KINDS_INPUT.includes(data.kind)) {
    fail("invalid-argument", "kind must be text, photo or voice.");
  }
  if (typeof data.commentsEnabled !== "boolean") {
    fail("invalid-argument", "commentsEnabled must be a boolean.");
  }
  if (!Array.isArray(data.mediaIds)) fail("invalid-argument", "mediaIds must be a list.");
  const text = normalizePostText(data.text, data.kind);
  if (data.kind === "text") {
    // Text posts: the server allocates the id; the client sends none.
    if (data.postId !== null) fail("invalid-argument", "A text post has no client postId.");
    if (data.mediaIds.length !== 0) fail("invalid-argument", "A text post has no media.");
    return { requestId, kind: "text", postId: null, text, mediaIds: [], commentsEnabled: data.commentsEnabled };
  }
  if (typeof data.postId !== "string" || !PAGE_POST_ID_PATTERN.test(data.postId)) {
    fail("invalid-argument", "postId is invalid.");
  }
  const max = data.kind === "photo" ? PAGE_POST_MAX_PHOTOS : 1;
  if (data.mediaIds.length < 1 || data.mediaIds.length > max ||
      data.mediaIds.some((id) => typeof id !== "string" || !PAGE_MEDIA_ID_PATTERN.test(id)) ||
      new Set(data.mediaIds).size !== data.mediaIds.length) {
    fail("invalid-argument", data.kind === "photo"
      ? "mediaIds must list 1-10 distinct photos."
      : "mediaIds must list exactly one clip.");
  }
  return {
    requestId,
    kind: data.kind,
    postId: data.postId,
    text,
    mediaIds: [...data.mediaIds],
    commentsEnabled: data.commentsEnabled,
  };
}

/// The postId format is checked FIRST (§2.4), then the op and the exact keys.
function manageInput(data) {
  requireObject(data);
  if (typeof data.postId !== "string" || !PAGE_POST_ID_PATTERN.test(data.postId)) {
    fail("invalid-argument", "postId is invalid.");
  }
  if (typeof data.op !== "string" || !MANAGE_POST_OPS.includes(data.op)) {
    fail("invalid-argument", "op is invalid.");
  }
  const fields = data.op === "setCommentsEnabled"
    ? ["requestId", "postId", "op", "commentsEnabled"]
    : ["requestId", "postId", "op"];
  requireExactInput(data, fields, fields);
  const requestId = requireRequestId(data.requestId);
  if (data.op === "setCommentsEnabled" && typeof data.commentsEnabled !== "boolean") {
    fail("invalid-argument", "commentsEnabled must be a boolean.");
  }
  return {
    requestId,
    postId: data.postId,
    op: data.op,
    commentsEnabled: data.op === "setCommentsEnabled" ? data.commentsEnabled : null,
  };
}

// ------------------------------------------------------- stored objects

/// The uploaded object's metadata against its reservation, exactly.
/// The object's HTTP headers are the plain ones storage.rules admits (audit
/// 2026-09-28): no Content-Encoding (a gzip body would inflate past the cap
/// on download), no Cache-Control (no shared caching of a photo that may be
/// removed later) and at most an inline Content-Disposition.
function plainObjectHeaders(metadata) {
  const blank = (value) => value === undefined || value === null || value === "";
  return (blank(metadata.contentEncoding) || metadata.contentEncoding === "identity") &&
    blank(metadata.cacheControl) &&
    (blank(metadata.contentDisposition) ||
      (typeof metadata.contentDisposition === "string" &&
        /^inline(;.*)?$/u.test(metadata.contentDisposition)));
}

function validateStoredMedia(metadata, reservation) {
  if (!metadata || typeof metadata !== "object" || Array.isArray(metadata)) {
    throw PAGE_POST_ERRORS.mediaInvalid();
  }
  const generation = String(metadata.generation ?? "");
  const size = Number(metadata.size);
  const custom = customMetadataOf(metadata);
  const required = pageMediaUploadMetadata(reservation);
  const allowed = new Set(["firebaseStorageDownloadTokens", ...PAGE_MEDIA_UPLOAD_METADATA_KEYS]);
  if (!/^[0-9]{1,30}$/u.test(generation) || !Number.isSafeInteger(size) ||
      size !== reservation.size || metadata.contentType !== reservation.contentType ||
      !plainObjectHeaders(metadata) ||
      Object.keys(custom).some((key) => !allowed.has(key)) ||
      Object.entries(required).some(([key, value]) => custom[key] !== value)) {
    throw PAGE_POST_ERRORS.mediaInvalid();
  }
  return { generation, size, contentType: metadata.contentType };
}

function sameStored(first, second) {
  return first.generation === second.generation && first.size === second.size &&
    first.contentType === second.contentType;
}

/// The trusted probe's result against the reservation (§2.4 step 2).
function validateProbe(probe, reservation, stored) {
  if (!probe || typeof probe !== "object" || probe.generation !== stored.generation ||
      probe.size !== stored.size || probe.detectedContentType !== reservation.contentType ||
      typeof probe.hasAudio !== "boolean" || typeof probe.hasVideo !== "boolean") {
    throw PAGE_POST_ERRORS.mediaInvalid();
  }
  if (reservation.type === "image") {
    if (probe.durationMs !== null || probe.hasAudio || probe.hasVideo) {
      throw PAGE_POST_ERRORS.mediaInvalid();
    }
    return null;
  }
  if (!probe.hasAudio || probe.hasVideo || !Number.isSafeInteger(probe.durationMs) ||
      probe.durationMs < 1 || probe.durationMs > PAGE_POST_VOICE_MAX_MS ||
      Math.abs(probe.durationMs - reservation.durationMs) > PAGE_VOICE_DURATION_TOLERANCE_MS) {
    throw PAGE_POST_ERRORS.mediaInvalid();
  }
  return probe.durationMs;
}

function mediaEntry(reservation, verified) {
  if (reservation.type === "image") {
    return {
      mediaId: reservation.mediaId,
      type: "image",
      contentType: reservation.contentType,
      size: verified.size,
      width: reservation.width,
      height: reservation.height,
      storagePath: reservation.storagePath,
      generation: verified.generation,
    };
  }
  return {
    mediaId: reservation.mediaId,
    type: "audio",
    contentType: reservation.contentType,
    size: verified.size,
    durationMs: verified.durationMs,
    storagePath: reservation.storagePath,
    generation: verified.generation,
  };
}

function evidenceFingerprint(post) {
  return pagePostEvidenceFingerprint(post);
}

function manageResponse({ op, postId, deleted, pinned, commentsEnabled }) {
  return { schemaVersion: 1, op, postId, deleted, pinned, commentsEnabled };
}

// ---------------------------------------------------------------- service

function createPagesPostService({
  firestore,
  storage,
  probeMedia,
  maintenance = null,
  TimestampImpl = Timestamp,
  clock = () => Date.now(),
  logger = defaultLogger,
  rateLimits = PAGES_POST_RATE_LIMITS,
}) {
  if (!firestore?.doc || !storage?.getMetadata || !storage?.hardenObject ||
      !storage?.readHead || typeof probeMedia !== "function" ||
      typeof TimestampImpl?.fromMillis !== "function" || typeof clock !== "function") {
    throw new TypeError("firestore, storage, probeMedia, Timestamp and clock are required.");
  }

  function timing() {
    const nowMs = clock();
    if (!Number.isSafeInteger(nowMs) || nowMs < 0) {
      throw new TypeError("clock must return epoch milliseconds.");
    }
    return { nowMs, now: TimestampImpl.fromMillis(nowMs) };
  }

  async function chargeRate(scope, uid, { nowMs, now }) {
    const reference = rateLimitReference(firestore, scope, uid);
    await firestore.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(reference);
      consumeRateLimit(transaction, snapshot, {
        reference, scope, uid, nowMs, now, ...rateLimits[scope],
      });
    });
  }

  function gate([userSnapshot, entitlementSnapshot, grantSnapshot], auth, nowMs) {
    const capability = derivePagesCapability(
      { userSnapshot, entitlementSnapshot, grantSnapshot },
      { tokenRole: typeof auth.token?.role === "string" ? auth.token.role : null, now: nowMs },
    );
    if (!capability.allowed) throw pageAccessRequiredError();
  }

  // Active account + no communication mute; the verified e-mail was
  // required by requireActor.
  function assertWritePreconditions(userSnapshot, restrictionSnapshot, nowMs) {
    const user = userSnapshot?.exists ? (userSnapshot.data() ?? null) : null;
    if (!likersAccountIsActive(user)) fail("permission-denied", "Your account is not active.");
    assertNotRestricted(restrictionSnapshot, "Your", nowMs);
  }

  // The ops signal for the spec's "pages budget exhausted" alert: which
  // limit, never who.
  function budgetExhausted(limit) {
    logger.warn("pages budget exhausted", { limit });
    throw PAGE_POST_ERRORS.budget();
  }

  /// A Page the owner may publish to: exists, not suspended, not paused.
  function publishablePage(pageSnapshot, uid) {
    const page = canonicalPage(pageSnapshot, uid);
    if (page === null) throw PAGE_ERRORS.notFound();
    if (page.suspended) throw PAGE_ERRORS.suspended();
    if (page.ownerPaused) throw PAGE_POST_ERRORS.paused();
    return page;
  }

  // The Page after this write: `changes`, plus a restore when the Page had
  // lapsed (the gate just proved the capability live), `listed` re-derived.
  // Queues the pages update and the visibility index entry; returns the Page.
  function writePage(transaction, { uid, page, changes, visibilitySnapshot, now }) {
    const restore = restoredPageFields(page);
    const next = { ...page, ...changes, ...restore, updatedAt: now };
    next.listed = derivePageListed(next);
    transaction.update(firestore.doc(`pages/${uid}`), {
      ...changes, ...restore, listed: next.listed, updatedAt: now,
    });
    applyPageVisibilityInTransaction(transaction, {
      db: firestore, snapshot: visibilitySnapshot, pageId: uid, page: next, now, logger,
    });
    return next;
  }

  // ------------------------------------------------------------ reserve

  async function reservePagePostMediaV1(request) {
    const auth = requireActor(request);
    const input = reserveInput(request.data);
    const uid = auth.uid;
    const timed = timing();
    await assertPagesWriteEnabled({ db: firestore, uid, logger });
    await chargeRate("pages.reserve", uid, timed);
    const postId = pagePostIdFor(uid, input.requestId, "media");
    const mediaIds = input.items.map((item) => pageMediaIdFor(uid, input.requestId, item.index));
    const identity = operationIdentity(LEDGER_KINDS.reserve, uid, input.requestId, {
      kind: input.kind, items: input.items,
    });
    const day = pageBudgetDay(timed.nowMs);
    const budgetRef = firestore.doc(`pagePostBudgets/${uid}_${day}`);
    const ledgerRef = firestore.doc(`integrityOperationLedgers/${identity.id}`);
    const leaseRef = firestore.doc(`pagePostMediaLeases/${uid}`);
    const reservationRefs = mediaIds.map((id) => firestore.doc(`pagePostMediaReservations/${id}`));
    return firestore.runTransaction(async (transaction) => {
      const [user, entitlement, grant, restriction, pageSnapshot, ledgerSnapshot,
        leaseSnapshot, budgetSnapshot, ...reservationSnapshots] = await transactionGetAll(
        transaction,
        ...pagesCapabilityReferences(firestore, uid),
        firestore.doc(`restrictions/${uid}`),
        firestore.doc(`pages/${uid}`),
        ledgerRef,
        leaseRef,
        budgetRef,
        ...reservationRefs,
      );
      assertWritePreconditions(user, restriction, timed.nowMs);
      const prior = assertLedgerReplay(ledgerSnapshot, {
        kind: LEDGER_KINDS.reserve, uid, inputHash: identity.inputHash,
      });
      if (prior) {
        // A retry of the same request returns the same set while it is live.
        const live = reservationSnapshots.every((snapshot) => {
          const reservation = canonicalPageMediaReservation(snapshot);
          return reservation !== null && reservation.status === "uploading" &&
            reservation.expiresAtMs > timed.nowMs && reservation.postId === prior.postId;
        });
        if (!live) throw PAGE_POST_ERRORS.uploadExpired();
        return prior;
      }
      gate([user, entitlement, grant], auth, timed.nowMs);
      publishablePage(pageSnapshot, uid);
      if (reservationSnapshots.some((snapshot) => snapshot.exists)) {
        fail("data-loss", "A Page upload reservation exists without its receipt.");
      }
      const lease = canonicalPageMediaLease(leaseSnapshot, uid);
      if (lease !== null && lease.expiresAtMs > timed.nowMs) {
        throw PAGE_POST_ERRORS.uploadInProgress();
      }
      const budget = canonicalPageBudget(budgetSnapshot, uid, day);
      const bytes = input.items.reduce((sum, item) => sum + item.size, 0);
      const exhausted = budget.posts >= PAGE_DAILY_BUDGET.posts
        ? "posts"
        : budget.reservations + input.items.length > PAGE_DAILY_BUDGET.reservations
          ? "reservations"
          : budget.bytes + bytes > PAGE_DAILY_BUDGET.bytes ? "bytes" : null;
      if (exhausted !== null) budgetExhausted(exhausted);
      const expiresAtMs = timed.nowMs + PAGE_MEDIA_RESERVATION_TTL_MS;
      const expiresAt = TimestampImpl.fromMillis(expiresAtMs);
      const items = [];
      input.items.forEach((item, position) => {
        const reservation = newReservation({
          pageId: uid, postId, mediaId: mediaIds[position], item, kind: input.kind,
          requestId: input.requestId, now: timed.now, expiresAt,
        });
        transaction.create(reservationRefs[position], reservation);
        items.push({
          mediaId: reservation.mediaId,
          storagePath: reservation.storagePath,
          metadata: pageMediaUploadMetadata(reservation),
          expiresAt: expiresAtMs,
        });
      });
      transaction.set(leaseRef, {
        schemaVersion: 1,
        ownerId: uid,
        postId,
        requestId: input.requestId,
        mediaIds,
        status: "uploading",
        expiresAt,
      });
      // Charged here, never refunded (§1.9): an abandoned upload still costs.
      transaction.set(budgetRef, pageBudgetDocument({
        pageId: uid,
        day,
        posts: budget.posts,
        reservations: budget.reservations + input.items.length,
        bytes: budget.bytes + bytes,
        now: timed.now,
      }));
      const result = { postId, items };
      transaction.create(ledgerRef, ledgerData({
        kind: LEDGER_KINDS.reserve, uid, requestId: input.requestId,
        inputHash: identity.inputHash, result, now: timed.now,
      }));
      return result;
    });
  }

  // ------------------------------------------------------------ publish

  // Plain reads before the (slow) object verification, so a refused publish
  // never probes. The transaction re-checks every one of them.
  async function readPublishPlan(auth, input, nowMs) {
    const uid = auth.uid;
    const [user, entitlement, grant, restriction, pageSnapshot, leaseSnapshot] =
      await firestore.getAll(
        ...pagesCapabilityReferences(firestore, uid),
        firestore.doc(`restrictions/${uid}`),
        firestore.doc(`pages/${uid}`),
        firestore.doc(`pagePostMediaLeases/${uid}`),
      );
    assertWritePreconditions(user, restriction, nowMs);
    gate([user, entitlement, grant], auth, nowMs);
    publishablePage(pageSnapshot, uid);
    const lease = canonicalPageMediaLease(leaseSnapshot, uid);
    if (lease === null || lease.postId !== input.postId) {
      fail("failed-precondition", "There is no upload for this post.");
    }
    if (lease.expiresAtMs <= nowMs) throw PAGE_POST_ERRORS.uploadExpired();
    if (input.mediaIds.some((id) => !lease.mediaIds.includes(id))) {
      fail("invalid-argument", "mediaIds must belong to this upload.");
    }
    const snapshots = await firestore.getAll(...input.mediaIds
      .map((id) => firestore.doc(`pagePostMediaReservations/${id}`)));
    const reservations = snapshots.map((snapshot) =>
      liveReservation(snapshot, { uid, postId: input.postId, kind: input.kind, nowMs }));
    return { leaseMediaIds: lease.mediaIds, reservations };
  }

  function liveReservation(snapshot, { uid, postId, kind, nowMs }) {
    const reservation = canonicalPageMediaReservation(snapshot);
    if (reservation === null) {
      if (snapshot?.exists) fail("data-loss", "A Page upload reservation is malformed.");
      throw PAGE_POST_ERRORS.uploadExpired();
    }
    if (reservation.ownerId !== uid || reservation.postId !== postId) {
      fail("invalid-argument", "mediaIds must belong to this upload.");
    }
    if (reservation.postKind !== kind) fail("invalid-argument", "mediaIds do not match kind.");
    if (reservation.status !== "uploading" || reservation.expiresAtMs <= nowMs) {
      throw PAGE_POST_ERRORS.uploadExpired();
    }
    return reservation;
  }

  async function metadataOf(path) {
    try {
      return await storage.getMetadata(path);
    } catch (error) {
      if (isMissingObject(error)) throw PAGE_POST_ERRORS.mediaInvalid();
      throw error;
    }
  }

  async function verifyUploadedMedia(reservation) {
    const stored = validateStoredMedia(await metadataOf(reservation.storagePath), reservation);
    let probe;
    try {
      probe = await probeMedia({
        storagePath: reservation.storagePath,
        generation: stored.generation,
        contentType: stored.contentType,
        size: stored.size,
        kind: reservation.type,
      });
    } catch (error) {
      if (error?.code === "failed-precondition") throw PAGE_POST_ERRORS.mediaInvalid();
      throw error;
    }
    const durationMs = validateProbe(probe, reservation, stored);
    if (reservation.type === "image") {
      const head = await storage.readHead(reservation.storagePath, {
        generation: stored.generation,
        byteCount: Math.min(stored.size, PAGE_MEDIA_HEAD_BYTES),
      });
      if (head === null) throw PAGE_POST_ERRORS.mediaInvalid();
      // No metadata, one frame header, and its size is the declared size.
      assertNoImageMetadata(head, { width: reservation.width, height: reservation.height });
    }
    // The probe may take seconds: re-read so a replaced object cannot publish.
    const finalMetadata = await metadataOf(reservation.storagePath);
    const final = validateStoredMedia(finalMetadata, reservation);
    if (!sameStored(stored, final)) fail("aborted", "The upload changed. Try again.");
    const secured = await storage.hardenObject(reservation.storagePath, finalMetadata,
      pageMediaUploadMetadata(reservation));
    if (hasDownloadToken(secured)) fail("aborted", "The upload could not be secured.");
    if (!sameStored(stored, validateStoredMedia(secured, reservation))) {
      fail("aborted", "The upload could not be secured.");
    }
    return { ...stored, durationMs };
  }

  async function publishPagePostV1(request) {
    const auth = requireActor(request);
    const input = publishInput(request.data);
    const uid = auth.uid;
    const timed = timing();
    await assertPagesWriteEnabled({ db: firestore, uid, logger });
    const identity = operationIdentity(LEDGER_KINDS.publish, uid, input.requestId, {
      kind: input.kind,
      postId: input.postId,
      text: input.text,
      mediaIds: input.mediaIds,
      commentsEnabled: input.commentsEnabled,
    });
    const ledgerRef = firestore.doc(`integrityOperationLedgers/${identity.id}`);
    // A replay is free: the rate below is for new work only.
    const replay = assertLedgerReplay(await ledgerRef.get(), {
      kind: LEDGER_KINDS.publish, uid, inputHash: identity.inputHash,
    });
    if (replay) return replay;
    await chargeRate("pages.publish", uid, timed);

    const media = input.kind !== "text";
    const postId = media ? input.postId : pagePostIdFor(uid, input.requestId, "text");
    let plan = null;
    const verified = new Map();
    if (media) {
      plan = await readPublishPlan(auth, input, timed.nowMs);
      for (const reservation of plan.reservations) {
        verified.set(reservation.mediaId, await verifyUploadedMedia(reservation));
      }
    }
    const day = pageBudgetDay(timed.nowMs);
    const budgetRef = firestore.doc(`pagePostBudgets/${uid}_${day}`);
    const postRef = firestore.doc(`pagePosts/${postId}`);
    const leaseRef = firestore.doc(`pagePostMediaLeases/${uid}`);
    const leaseReservationRefs = media
      ? plan.leaseMediaIds.map((id) => firestore.doc(`pagePostMediaReservations/${id}`))
      : [];

    return firestore.runTransaction(async (transaction) => {
      const [user, entitlement, grant, restriction, pageSnapshot, visibilitySnapshot,
        ledgerSnapshot, budgetSnapshot, postSnapshot, ...rest] = await transactionGetAll(
        transaction,
        ...pagesCapabilityReferences(firestore, uid),
        firestore.doc(`restrictions/${uid}`),
        firestore.doc(`pages/${uid}`),
        pageVisibilityReference(firestore),
        ledgerRef,
        budgetRef,
        postRef,
        ...(media ? [leaseRef, ...leaseReservationRefs] : []),
      );
      assertWritePreconditions(user, restriction, timed.nowMs);
      const prior = assertLedgerReplay(ledgerSnapshot, {
        kind: LEDGER_KINDS.publish, uid, inputHash: identity.inputHash,
      });
      if (prior) return prior;
      gate([user, entitlement, grant], auth, timed.nowMs);
      const page = publishablePage(pageSnapshot, uid);
      if (postSnapshot.exists) fail("data-loss", "A Page post exists without its receipt.");
      const budget = canonicalPageBudget(budgetSnapshot, uid, day);
      if (budget.posts + 1 > PAGE_DAILY_BUDGET.posts) budgetExhausted("posts");

      let entries = [];
      if (media) {
        const [leaseSnapshot, ...reservationSnapshots] = rest;
        const lease = canonicalPageMediaLease(leaseSnapshot, uid);
        if (lease === null || lease.postId !== postId ||
            lease.mediaIds.length !== plan.leaseMediaIds.length ||
            lease.mediaIds.some((id, index) => id !== plan.leaseMediaIds[index])) {
          fail("aborted", "The upload changed. Try again.");
        }
        if (lease.expiresAtMs <= timed.nowMs) throw PAGE_POST_ERRORS.uploadExpired();
        const byId = new Map();
        reservationSnapshots.forEach((snapshot, index) => {
          if (snapshot.exists) byId.set(lease.mediaIds[index], snapshot);
        });
        entries = input.mediaIds.map((mediaId) => {
          const reservation = liveReservation(byId.get(mediaId), {
            uid, postId, kind: input.kind, nowMs: timed.nowMs,
          });
          const object = verified.get(mediaId);
          if (!object || object.size !== reservation.size ||
              object.contentType !== reservation.contentType) {
            fail("aborted", "The upload changed. Try again.");
          }
          return mediaEntry(reservation, object);
        });
        // Every reservation of the set goes (unused ones included: an object
        // uploaded for one is unreferenced and the orphan sweep removes it).
        reservationSnapshots.forEach((snapshot) => {
          if (snapshot.exists) transaction.delete(snapshot.ref);
        });
        transaction.delete(leaseRef);
      }

      const post = {
        schemaVersion: 1,
        postId,
        pageId: uid,
        authorId: uid,
        pageKind: page.kind,
        kind: input.kind,
        text: input.text,
        media: entries,
        status: "published",
        evidenceHold: false,
        commentsEnabled: input.commentsEnabled,
        likeCount: 0,
        commentCount: 0,
        heldAt: null,
        removedAt: null,
        removedReason: null,
        deletedAt: null,
        moderationEvidence: null,
        createdAt: timed.now,
      };
      if (pagePostMalformedReason(post, postId) !== null) {
        fail("data-loss", "The Page post could not be composed.");
      }
      transaction.create(postRef, post);
      const next = writePage(transaction, {
        uid,
        page,
        changes: { postCount: page.postCount + 1, lastPostAt: timed.now },
        visibilitySnapshot,
        now: timed.now,
      });
      transaction.set(budgetRef, pageBudgetDocument({
        pageId: uid,
        day,
        posts: budget.posts + 1,
        reservations: budget.reservations,
        bytes: budget.bytes,
        now: timed.now,
      }));
      const result = postView(post, next, { callerLiked: false });
      transaction.create(ledgerRef, ledgerData({
        kind: LEDGER_KINDS.publish, uid, requestId: input.requestId,
        inputHash: identity.inputHash, result, now: timed.now,
      }));
      return result;
    });
  }

  // ------------------------------------------------------------- manage

  function ownPostOrUnavailable(postSnapshot, uid) {
    const raw = postSnapshot?.exists ? (postSnapshot.data() ?? {}) : null;
    // One uniform refusal for "no such post" and "not your post".
    if (raw === null || raw.pageId !== uid || raw.authorId !== uid) throw pageUnavailableError();
    const post = canonicalPagePostData(postSnapshot);
    if (post === null) fail("data-loss", "The Page post record is malformed.");
    return post;
  }

  async function deletePost(auth, input, timed) {
    const uid = auth.uid;
    const identity = operationIdentity(LEDGER_KINDS.manage, uid, input.requestId, {
      op: "delete", postId: input.postId,
    });
    const ledgerRef = firestore.doc(`integrityOperationLedgers/${identity.id}`);
    const postRef = firestore.doc(`pagePosts/${input.postId}`);
    const outcome = await firestore.runTransaction(async (transaction) => {
      const [ledgerSnapshot, postSnapshot, pageSnapshot, reportsSnapshot, visibilitySnapshot] =
        await transactionGetAll(
          transaction,
          ledgerRef,
          postRef,
          firestore.doc(`pages/${uid}`),
          firestore.doc(`pagePostOpenReports/${input.postId}`),
          pageVisibilityReference(firestore),
        );
      const prior = assertLedgerReplay(ledgerSnapshot, {
        kind: LEDGER_KINDS.manage, uid, inputHash: identity.inputHash,
      });
      if (prior) return { result: prior, hard: false, jobs: [] };
      const post = ownPostOrUnavailable(postSnapshot, uid);
      const done = (result, extra = {}) => {
        transaction.create(ledgerRef, ledgerData({
          kind: LEDGER_KINDS.manage, uid, requestId: input.requestId,
          inputHash: identity.inputHash, result, now: timed.now,
        }));
        return { result, hard: false, jobs: [], ...extra };
      };
      const response = manageResponse({
        op: "delete", postId: post.postId, deleted: true, pinned: false,
        commentsEnabled: post.commentsEnabled,
      });
      if (post.status === "deleted") return done(response);

      // A safety action: a malformed Page is logged and left alone, never a
      // reason to refuse the delete.
      const page = canonicalPageOrNull(pageSnapshot, uid);
      if (pageSnapshot.exists && page === null) {
        logger.error("pages malformed page on a safety action", { reason: "postDelete" });
      }
      const reports = pagePostOpenReports(reportsSnapshot, post.postId);
      // Only an OPEN report holds the bytes: a held post whose reports all
      // closed would otherwise keep jobs nothing can ever release.
      const underReview = post.evidenceHold === true || reports.count > 0;
      const tombstone = post.status !== "published" || underReview;
      const heldBy = underReview ? (reports.lastReportId ?? PAGE_MODERATION_HOLD) : null;

      if (tombstone) {
        transaction.update(postRef, {
          status: "deleted",
          deletedAt: timed.now,
          moderationEvidence: { evidenceVersion: 1, metadataFingerprint: evidenceFingerprint(post) },
        });
        transaction.set(firestore.doc(`pageEvidenceRetention/${post.postId}`),
          pageEvidenceRetentionDocument({
            postId: post.postId,
            pageId: uid,
            reason: "ownerDelete",
            now: timed.now,
            purgeAt: TimestampImpl.fromMillis(timed.nowMs + PAGE_EVIDENCE_RETENTION_MS),
          }));
      } else {
        transaction.delete(postRef);
        transaction.set(firestore.doc(`pagePostCleanupJobs/${post.postId}`), pagePostCleanupJob({
          postId: post.postId, pageId: uid, reason: "ownerDelete", now: timed.now,
        }));
      }
      const jobs = post.media.map((entry) => ({ mediaId: entry.mediaId, held: heldBy !== null }));
      post.media.forEach((entry) => {
        transaction.set(firestore.doc(`pagePostMediaDeletionJobs/${entry.mediaId}`),
          pageMediaDeletionJob({
            storagePath: entry.storagePath,
            generation: entry.generation,
            reason: "ownerDelete",
            heldBy,
            now: timed.now,
          }));
      });
      if (page !== null) {
        const counted = post.status === "published";
        if (counted && page.postCount < 1) {
          logger.error("pages post count underflow", {});
        }
        const changes = {};
        if (counted) changes.postCount = Math.max(0, page.postCount - 1);
        if (page.pinnedPostId === post.postId) changes.pinnedPostId = null;
        if (Object.keys(changes).length > 0) {
          const next = { ...page, ...changes, updatedAt: timed.now };
          next.listed = derivePageListed(next);
          transaction.update(firestore.doc(`pages/${uid}`), {
            ...changes, listed: next.listed, updatedAt: timed.now,
          });
          applyPageVisibilityInTransaction(transaction, {
            db: firestore, snapshot: visibilitySnapshot, pageId: uid, page: next,
            now: timed.now, logger, safetyAction: true,
          });
        }
      }
      return done(response, { hard: !tombstone, jobs });
    });

    // Best effort: the durable jobs survive any failure here and
    // pagesMaintenance finishes them.
    if (maintenance !== null) {
      try {
        for (const job of outcome.jobs) {
          if (!job.held) await maintenance.processMediaDeletionJob(job.mediaId);
        }
        if (outcome.hard) await maintenance.processPostCleanupJob(input.postId);
      } catch (error) {
        logger.warn("pages post cleanup deferred", {
          code: typeof error?.code === "string" || Number.isSafeInteger(error?.code)
            ? error.code
            : null,
        });
      }
    }
    return outcome.result;
  }

  async function arrangePost(auth, input, timed) {
    const uid = auth.uid;
    const identity = operationIdentity(LEDGER_KINDS.manage, uid, input.requestId, {
      op: input.op, postId: input.postId, commentsEnabled: input.commentsEnabled,
    });
    const ledgerRef = firestore.doc(`integrityOperationLedgers/${identity.id}`);
    const postRef = firestore.doc(`pagePosts/${input.postId}`);
    return firestore.runTransaction(async (transaction) => {
      const [user, entitlement, grant, restriction, pageSnapshot, visibilitySnapshot,
        ledgerSnapshot, postSnapshot] = await transactionGetAll(
        transaction,
        ...pagesCapabilityReferences(firestore, uid),
        firestore.doc(`restrictions/${uid}`),
        firestore.doc(`pages/${uid}`),
        pageVisibilityReference(firestore),
        ledgerRef,
        postRef,
      );
      assertWritePreconditions(user, restriction, timed.nowMs);
      const prior = assertLedgerReplay(ledgerSnapshot, {
        kind: LEDGER_KINDS.manage, uid, inputHash: identity.inputHash,
      });
      if (prior) return prior;
      gate([user, entitlement, grant], auth, timed.nowMs);
      const page = canonicalPage(pageSnapshot, uid);
      if (page === null) throw PAGE_ERRORS.notFound();
      if (page.suspended) throw PAGE_ERRORS.suspended();
      const post = ownPostOrUnavailable(postSnapshot, uid);

      const changes = {};
      let commentsEnabled = post.commentsEnabled;
      if (input.op === "pin") {
        if (post.status !== "published") {
          fail("failed-precondition", "Only a published post can be pinned.");
        }
        if (page.pinnedPostId !== post.postId) changes.pinnedPostId = post.postId;
      } else if (input.op === "unpin") {
        if (page.pinnedPostId === post.postId) changes.pinnedPostId = null;
      } else {
        if (post.status !== "published" && post.status !== "held") throw pageUnavailableError();
        if (post.commentsEnabled !== input.commentsEnabled) {
          transaction.update(postRef, { commentsEnabled: input.commentsEnabled });
        }
        commentsEnabled = input.commentsEnabled;
      }
      let next = page;
      if (Object.keys(changes).length > 0 || Object.keys(restoredPageFields(page)).length > 0) {
        next = writePage(transaction, { uid, page, changes, visibilitySnapshot, now: timed.now });
      }
      const result = manageResponse({
        op: input.op,
        postId: post.postId,
        deleted: false,
        pinned: next.pinnedPostId === post.postId,
        commentsEnabled,
      });
      transaction.create(ledgerRef, ledgerData({
        kind: LEDGER_KINDS.manage, uid, requestId: input.requestId,
        inputHash: identity.inputHash, result, now: timed.now,
      }));
      return result;
    });
  }

  async function managePagePostV1(request) {
    // Delete is a safety action: it runs unverified and while muted. Every
    // other op needs the verified e-mail of the common preconditions.
    const auth = requireActor(request, { verified: request?.data?.op !== "delete" });
    const input = manageInput(request.data);
    const timed = timing();
    if (input.op !== "delete") {
      await assertPagesWriteEnabled({ db: firestore, uid: auth.uid, logger });
    }
    await chargeRate("pages.manage", auth.uid, timed);
    return input.op === "delete"
      ? deletePost(auth, input, timed)
      : arrangePost(auth, input, timed);
  }

  return Object.freeze({
    managePagePostV1,
    publishPagePostV1,
    reservePagePostMediaV1,
  });
}

let defaultService = null;
function service() {
  if (defaultService === null) {
    const { db } = require("../utils/firestore");
    const { defaultPagesMediaDependencies } = require("./media_runtime");
    const { createPagesMaintenanceService } = require("./maintenance");
    const { storage, probeMedia } = defaultPagesMediaDependencies();
    defaultService = createPagesPostService({
      firestore: db,
      storage,
      probeMedia,
      maintenance: createPagesMaintenanceService({ firestore: db, storage }),
    });
  }
  return defaultService;
}

const callableOptions = { region: REGION, enforceAppCheck: false };
// Publish reads and probes up to ten objects before its transaction.
const mediaOptions = { ...callableOptions, memory: "512MiB", timeoutSeconds: 120 };

const reservePagePostMediaV1 = onCall(
  callableOptions,
  (request) => service().reservePagePostMediaV1(request),
);
const publishPagePostV1 = onCall(
  mediaOptions,
  (request) => service().publishPagePostV1(request),
);
const managePagePostV1 = onCall(
  callableOptions,
  (request) => service().managePagePostV1(request),
);

module.exports = {
  LEDGER_KINDS,
  MANAGE_POST_OPS,
  MANAGE_RESPONSE_KEYS,
  PAGES_POST_RATE_LIMITS,
  createPagesPostService,
  managePagePostV1,
  publishPagePostV1,
  reservePagePostMediaV1,
};
