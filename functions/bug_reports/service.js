// In-app bug reports: the reporter's two callables, the owner's three, and the
// retention sweep.
//
//   submit  -> validate, rate-limit and write bugReports/{reportId} in ONE
//              transaction; when a screenshot is declared, also issue ONE
//              15-minute upload reservation for one exact private object
//   upload  -> the client writes exactly that object; storage.rules checks the
//              live reservation, the exact metadata, JPEG and the size bound
//   attach  -> metadata, JPEG magic bytes, download token revoked, then ONE
//              transaction binds the object's generation to the report and
//              consumes the reservation
//   owner   -> list (optionally by reporter, for access and erasure
//              requests) / get (with a 5-minute generation-bound signed URL) /
//              status / delete a report / remove its screenshot, every call
//              gated by requireProtectedOwner, i.e. by the existing
//              YOVOICE_PROTECTED_OWNER_UID secret; both deletions write an
//              adminAuditLogs entry in the same transaction
//   sweep   -> expired reservations, 90-day screenshots, 180-day reports,
//              page after page until each query drains or the time budget ends
//
// The report is written BEFORE the screenshot is uploaded on purpose: the
// words are the report, and a failed or abandoned upload must never lose them.
//
// Clients never read or write bugReports or its reservations (firestore.rules
// denies both outright) and never read bug_reports/ objects except their own
// object while its reservation is live (upload recovery).

const {
  consumeRateLimit,
  digest,
  fail,
  isValidOpaqueUid,
  rateLimitReference,
  requireActor,
  requireExactInput,
  requireRequestId,
  timestampMillis,
  transactionGetAll,
} = require("../integrity/guards");
const {
  BUG_REPORTS,
  BUG_REPORT_CONFIG,
  BUG_REPORT_RESERVATIONS,
  BUG_REPORT_SCHEMA_VERSION,
  GENERATION_PATTERN,
  RATE_LIMITS,
  REPORT_RETENTION_MS,
  RESERVATION_TTL_MS,
  SCREENSHOT_ACCESS_TTL_MS,
  SCREENSHOT_CONTENT_TYPE,
  SCREENSHOT_RETENTION_MS,
  STATUSES,
  bugReportId,
  bugReportStoragePath,
  bugReportUploadMetadata,
  normalizeContext,
  normalizeDescription,
  normalizeScreenshotDeclaration,
  parseBugReportStoragePath,
  requireReportId,
} = require("./contract");

const RESERVATION_KEYS = Object.freeze([
  "schemaVersion", "kind", "reportId", "ownerId", "contentType", "size",
  "storagePath", "status", "createdAt", "expiresAt",
].sort());
const LIST_MAX = 50;
const SWEEP_PAGE = 50;
// The schedule's timeout is 300 s; stop starting new pages well before it.
const SWEEP_BUDGET_MS = 240 * 1000;
// A hard stop independent of the clock, so a page that never shrinks (a write
// that silently does not take) can never spin until the timeout.
const SWEEP_MAX_PAGES = 200;
// A reservation is swept a little after it expires so an upload racing the
// deadline is never deleted underneath a finalize that is still in flight.
const RESERVATION_SWEEP_GRACE_MS = 10 * 60 * 1000;

function customMetadataOf(metadata) {
  const custom = metadata?.metadata ?? metadata?.customMetadata ?? {};
  return custom && typeof custom === "object" && !Array.isArray(custom) ? custom : {};
}

function hasDownloadToken(metadata) {
  const token = customMetadataOf(metadata).firebaseStorageDownloadTokens;
  return typeof token === "string" && token.length > 0;
}

function isMissingObject(error) {
  return error?.code === 404 || error?.code === "404" || error?.code === "storage/object-not-found";
}

function isJpegHeader(bytes) {
  const buffer = Buffer.isBuffer(bytes) ? bytes : Buffer.from(bytes ?? []);
  return buffer.length >= 3 && buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff;
}

/** The private-object adapter over a (lazy) Cloud Storage bucket. */
function createBugReportStorageAdapter(bucket) {
  if (!bucket?.file) throw new TypeError("A Storage bucket is required.");
  return Object.freeze({
    async getMetadata(path) {
      const [metadata] = await bucket.file(path).getMetadata();
      return metadata;
    },
    async readHeader(path, generation) {
      const [bytes] = await bucket.file(path, { generation }).download({ start: 0, end: 15 });
      return bytes;
    },
    async hardenObject(path, metadata, requiredMetadata) {
      const generation = String(metadata?.generation ?? "");
      if (!GENERATION_PATTERN.test(generation)) {
        fail("data-loss", "The bug report screenshot generation is malformed.");
      }
      const custom = customMetadataOf(metadata);
      const [updated] = await bucket.file(path).setMetadata({
        metadata: { ...custom, ...requiredMetadata, firebaseStorageDownloadTokens: null },
      }, { ifGenerationMatch: generation });
      return updated;
    },
    async getSignedReadUrl(path, { expiresAtMs, generation }) {
      const [url] = await bucket.file(path).getSignedUrl({
        version: "v4", action: "read", expires: expiresAtMs, queryParams: { generation },
      });
      return url;
    },
    async deleteObject(path, { generation = null } = {}) {
      await bucket.file(path, generation === null ? undefined : { generation }).delete({
        ignoreNotFound: true,
        ...(generation === null ? {} : { ifGenerationMatch: generation }),
      });
    },
  });
}

/**
 * Authoritative account state: refuses deleted and disabled accounts, and
 * returns whether the account is banned.
 *
 * A banned account MAY report in words: a bug in the ban flow is still a bug,
 * and the rate limits bound what a banned account can send. It may NOT attach
 * a screenshot: storage.rules' isActiveUser refuses a banned uploader, so a
 * reservation would only ever be left unused. The server therefore issues
 * none, and records the screenshot as "refused" (ADR, "In-app bug reports").
 */
function assertReporterAccount(snapshot) {
  if (!snapshot?.exists) fail("permission-denied", "Your account is not active.");
  const profile = snapshot.data() ?? {};
  if (profile.disabled === true || profile.deleted === true || profile.status === "deleted" ||
      (profile.authDeletedAt !== null && profile.authDeletedAt !== undefined)) {
    fail("permission-denied", "Your account is not active.");
  }
  return { banned: profile.banned === true };
}

function canonicalReservation(snapshot, { uid, reportId }) {
  if (!snapshot?.exists) return null;
  const value = snapshot.data() ?? {};
  const keys = Object.keys(value).sort();
  if (keys.length !== RESERVATION_KEYS.length ||
      keys.some((key, index) => key !== RESERVATION_KEYS[index]) ||
      value.schemaVersion !== BUG_REPORT_SCHEMA_VERSION ||
      value.kind !== "bugReportScreenshot" ||
      value.reportId !== snapshot.id || value.reportId !== reportId ||
      value.ownerId !== uid ||
      value.storagePath !== bugReportStoragePath(uid, reportId) ||
      value.contentType !== SCREENSHOT_CONTENT_TYPE ||
      !Number.isSafeInteger(value.size) ||
      value.status !== "uploading" ||
      timestampMillis(value.expiresAt) === null) {
    fail("failed-precondition", "The screenshot upload reservation is invalid.");
  }
  return { ...value, expiresAtMillis: timestampMillis(value.expiresAt) };
}

function uploadDescriptor(reservation) {
  return {
    storagePath: reservation.storagePath,
    contentType: reservation.contentType,
    size: reservation.size,
    uploadMetadata: bugReportUploadMetadata(reservation.ownerId, reservation.reportId),
    expiresAtMillis: reservation.expiresAtMillis,
  };
}

function validateStoredScreenshot(metadata, reservation, generation) {
  if (!metadata || typeof metadata !== "object") {
    fail("failed-precondition", "The uploaded screenshot is missing.");
  }
  const storedGeneration = String(metadata.generation ?? "");
  const size = Number(metadata.size);
  const custom = customMetadataOf(metadata);
  const required = bugReportUploadMetadata(reservation.ownerId, reservation.reportId);
  const allowed = new Set(["firebaseStorageDownloadTokens", ...Object.keys(required)]);
  if (!GENERATION_PATTERN.test(storedGeneration) || storedGeneration !== generation ||
      !Number.isSafeInteger(size) || size !== reservation.size ||
      metadata.contentType !== SCREENSHOT_CONTENT_TYPE ||
      Object.keys(custom).some((key) => !allowed.has(key)) ||
      Object.entries(required).some(([key, value]) => custom[key] !== value)) {
    fail("failed-precondition", "The uploaded screenshot is invalid.");
  }
  return { generation: storedGeneration, size };
}

function millis(value) {
  return timestampMillis(value);
}

/** What the owner's list shows per row: enough to triage, nothing more. */
function summaryOf(snapshot) {
  const value = snapshot.data() ?? {};
  const description = typeof value.description === "string" ? value.description : "";
  const context = value.context ?? {};
  return {
    reportId: snapshot.id,
    reporterId: typeof value.reporterId === "string" ? value.reporterId : null,
    status: typeof value.status === "string" ? value.status : "new",
    createdAtMillis: millis(value.createdAt),
    descriptionPreview: description.length > 160 ? `${description.slice(0, 159)}…` : description,
    platform: typeof context.platform === "string" ? context.platform : null,
    appVersion: typeof context.appVersion === "string" ? context.appVersion : null,
    buildNumber: typeof context.buildNumber === "string" ? context.buildNumber : null,
    route: typeof context.route === "string" ? context.route : null,
    screenshotStatus: typeof value.screenshot?.status === "string" ? value.screenshot.status : "none",
  };
}

function deliveryOf(value) {
  const delivery = value?.delivery ?? {};
  const out = {};
  for (const channel of ["email", "github"]) {
    const entry = delivery[channel];
    if (!entry || typeof entry !== "object") continue;
    out[channel] = {
      status: typeof entry.status === "string" ? entry.status : "unknown",
      attempts: Number.isSafeInteger(entry.attempts) ? entry.attempts : 0,
      lastErrorCode: typeof entry.lastErrorCode === "string" ? entry.lastErrorCode : null,
      sentAtMillis: millis(entry.sentAt),
    };
  }
  return out;
}

function createBugReportService(dependencies) {
  const {
    db, Timestamp, storage, authorizeOwner, clock = Date.now, logger = console,
    // Elapsed-time source for the sweep's budget only; `clock` is business
    // time (and is frozen in tests).
    monotonic = Date.now,
  } = dependencies ?? {};
  if (!db?.runTransaction || !Timestamp?.fromMillis || typeof clock !== "function" ||
      !storage?.getMetadata || !storage?.readHeader || !storage?.hardenObject ||
      !storage?.getSignedReadUrl || !storage?.deleteObject ||
      typeof authorizeOwner !== "function") {
    throw new TypeError("db, Timestamp, storage, authorizeOwner and clock are required.");
  }

  const reportRef = (reportId) => db.collection(BUG_REPORTS).doc(reportId);
  const reservationRef = (reportId) => db.collection(BUG_REPORT_RESERVATIONS).doc(reportId);
  const configRef = () => db.collection(BUG_REPORT_CONFIG.collection).doc(BUG_REPORT_CONFIG.id);

  // --------------------------------------------------------------- submit

  function submitInput(data) {
    const fields = ["requestId", "description", "context", "screenshot"];
    requireExactInput(data, fields, fields);
    return {
      requestId: requireRequestId(data.requestId),
      description: normalizeDescription(data.description),
      context: normalizeContext(data.context),
      screenshot: normalizeScreenshotDeclaration(data.screenshot),
    };
  }

  async function submitBugReportV1(request) {
    // Unverified accounts may report: a tester stuck before e-mail
    // verification is exactly who hits sign-up bugs. The rate limits and the
    // active-account check bound the surface.
    const auth = requireActor(request, { verified: false });
    const input = submitInput(request.data);
    const reportId = bugReportId(auth.uid, input.requestId);
    const inputHash = digest("bugReport.input.v1", auth.uid, input.requestId, {
      description: input.description, context: input.context, screenshot: input.screenshot,
    });
    // Per-account limits only: no shared bucket may refuse a report (see
    // RATE_LIMITS in contract.js).
    const limits = [
      { ...RATE_LIMITS.burst, uid: auth.uid },
      { ...RATE_LIMITS.daily, uid: auth.uid },
    ].map((limit) => ({ ...limit, reference: rateLimitReference(db, limit.scope, limit.uid) }));

    const result = await db.runTransaction(async (transaction) => {
      const nowMs = clock();
      const now = Timestamp.fromMillis(nowMs);
      const [config, user, existing, reservation, ...rates] = await transactionGetAll(
        transaction,
        configRef(),
        db.collection("users").doc(auth.uid),
        reportRef(reportId),
        reservationRef(reportId),
        ...limits.map((limit) => limit.reference),
      );
      if (config.exists && (config.data() ?? {}).enabled === false) {
        fail("failed-precondition", "Bug reports are paused right now.");
      }
      const { banned } = assertReporterAccount(user);

      if (existing.exists) {
        const prior = existing.data() ?? {};
        if (prior.reporterId !== auth.uid || prior.inputHash !== inputHash) {
          fail("already-exists", "requestId was already used for another report.");
        }
        // A replay: the same report, and its upload reservation while it is
        // still live. Replays never consume the rate limits.
        const live = canonicalReservation(reservation, { uid: auth.uid, reportId });
        return {
          reportId,
          replayed: true,
          screenshotUpload: live && live.expiresAtMillis > nowMs ? uploadDescriptor(live) : null,
        };
      }
      if (reservation.exists) {
        fail("data-loss", "A bug report reservation exists without its report.");
      }

      limits.forEach((limit, index) => consumeRateLimit(transaction, rates[index], {
        reference: limit.reference,
        scope: limit.scope,
        uid: limit.uid,
        nowMs,
        now,
        maxEvents: limit.maxEvents,
        windowMs: limit.windowMs,
      }));

      const reserveScreenshot = input.screenshot !== null && !banned;
      const storagePath = reserveScreenshot ? bugReportStoragePath(auth.uid, reportId) : null;
      transaction.create(reportRef(reportId), {
        schemaVersion: BUG_REPORT_SCHEMA_VERSION,
        reportId,
        reporterId: auth.uid,
        inputHash,
        description: input.description,
        context: input.context,
        screenshot: input.screenshot
          ? {
            status: reserveScreenshot ? "reserved" : "refused",
            storagePath,
            contentType: input.screenshot.contentType,
            size: input.screenshot.size,
            generation: null,
            attachedAt: null,
          }
          : null,
        screenshotExpiresAt: null,
        status: "new",
        createdAt: now,
        updatedAt: now,
        expiresAt: Timestamp.fromMillis(nowMs + REPORT_RETENTION_MS),
      });
      if (!reserveScreenshot) return { reportId, replayed: false, screenshotUpload: null };

      const expiresAtMillis = nowMs + RESERVATION_TTL_MS;
      const reserved = {
        schemaVersion: BUG_REPORT_SCHEMA_VERSION,
        kind: "bugReportScreenshot",
        reportId,
        ownerId: auth.uid,
        contentType: input.screenshot.contentType,
        size: input.screenshot.size,
        storagePath,
        status: "uploading",
        createdAt: now,
        expiresAt: Timestamp.fromMillis(expiresAtMillis),
      };
      transaction.create(reservationRef(reportId), reserved);
      return {
        reportId,
        replayed: false,
        screenshotUpload: uploadDescriptor({ ...reserved, expiresAtMillis }),
      };
    });
    // Constants only: never the description, never the uid.
    logger.info?.("bug report submitted", {
      reportId, replayed: result.replayed, screenshot: result.screenshotUpload !== null,
    });
    return { reportId: result.reportId, screenshotUpload: result.screenshotUpload };
  }

  // --------------------------------------------------------------- attach

  async function attachBugReportScreenshotV1(request) {
    const auth = requireActor(request, { verified: false });
    const fields = ["reportId", "objectGeneration"];
    requireExactInput(request.data, fields, fields);
    const reportId = requireReportId(request.data.reportId);
    const generation = request.data.objectGeneration;
    if (typeof generation !== "string" || !GENERATION_PATTERN.test(generation)) {
      fail("invalid-argument", "objectGeneration is invalid.");
    }

    const [reportSnapshot, reservationSnapshot] = await Promise.all([
      reportRef(reportId).get(), reservationRef(reportId).get(),
    ]);
    const report = reportSnapshot.exists ? reportSnapshot.data() ?? {} : null;
    // Somebody else's report and a missing one read the same.
    if (!report || report.reporterId !== auth.uid) fail("not-found", "The bug report was not found.");
    if (report.screenshot?.status === "attached") {
      if (report.screenshot.generation === generation) return { reportId, attached: true };
      fail("failed-precondition", "A screenshot is already attached to this report.");
    }
    const reservation = canonicalReservation(reservationSnapshot, { uid: auth.uid, reportId });
    if (!reservation || report.screenshot?.status !== "reserved" ||
        report.screenshot.storagePath !== reservation.storagePath) {
      fail("failed-precondition", "This report has no screenshot upload in progress.");
    }
    if (reservation.expiresAtMillis <= clock()) {
      fail("deadline-exceeded", "The screenshot upload window closed.");
    }

    let metadata;
    try {
      metadata = await storage.getMetadata(reservation.storagePath);
    } catch (error) {
      if (isMissingObject(error)) fail("failed-precondition", "The uploaded screenshot is missing.");
      throw error;
    }
    const stored = validateStoredScreenshot(metadata, reservation, generation);
    const header = await storage.readHeader(reservation.storagePath, stored.generation);
    if (!isJpegHeader(header)) {
      await storage.deleteObject(reservation.storagePath, { generation: stored.generation });
      fail("failed-precondition", "The uploaded screenshot is not a JPEG image.");
    }
    // Firebase clients mint a durable download token on upload. Remove it,
    // generation-guarded, before the object is bound to the report.
    const secured = await storage.hardenObject(reservation.storagePath, metadata,
      bugReportUploadMetadata(auth.uid, reportId));
    if (hasDownloadToken(secured)) fail("aborted", "The screenshot could not be secured.");
    const final = validateStoredScreenshot(secured, reservation, generation);
    if (final.size !== stored.size) fail("aborted", "The uploaded screenshot changed. Try again.");

    await db.runTransaction(async (transaction) => {
      const nowMs = clock();
      const now = Timestamp.fromMillis(nowMs);
      const [currentReport, currentReservation] = await transactionGetAll(
        transaction, reportRef(reportId), reservationRef(reportId),
      );
      const value = currentReport.exists ? currentReport.data() ?? {} : null;
      if (!value || value.reporterId !== auth.uid) fail("not-found", "The bug report was not found.");
      if (value.screenshot?.status === "attached") {
        if (value.screenshot.generation === generation) return;
        fail("failed-precondition", "A screenshot is already attached to this report.");
      }
      const live = canonicalReservation(currentReservation, { uid: auth.uid, reportId });
      if (!live || live.expiresAtMillis <= nowMs || value.screenshot?.status !== "reserved") {
        fail("failed-precondition", "This report has no screenshot upload in progress.");
      }
      transaction.update(reportRef(reportId), {
        screenshot: {
          status: "attached",
          storagePath: live.storagePath,
          contentType: SCREENSHOT_CONTENT_TYPE,
          size: stored.size,
          generation: stored.generation,
          attachedAt: now,
        },
        screenshotExpiresAt: Timestamp.fromMillis(nowMs + SCREENSHOT_RETENTION_MS),
        updatedAt: now,
      });
      transaction.delete(reservationRef(reportId));
    });
    logger.info?.("bug report screenshot attached", { reportId });
    return { reportId, attached: true };
  }

  // ---------------------------------------------------------------- owner

  async function listBugReportsV1(request) {
    await authorizeOwner(request);
    const data = request.data ?? {};
    requireExactInput(data, ["limit", "cursor", "status", "reporterId"]);
    const limit = data.limit === undefined || data.limit === null ? 25 : data.limit;
    if (!Number.isSafeInteger(limit) || limit < 1 || limit > LIST_MAX) {
      fail("invalid-argument", "limit is invalid.");
    }
    const status = data.status === undefined || data.status === null ? null : data.status;
    if (status !== null && !STATUSES.includes(status)) fail("invalid-argument", "status is invalid.");
    const cursor = data.cursor === undefined || data.cursor === null
      ? null
      : requireReportId(data.cursor);
    // One account's reports, for an access or erasure request.
    const reporterId = data.reporterId === undefined || data.reporterId === null
      ? null
      : data.reporterId;
    if (reporterId !== null && !isValidOpaqueUid(reporterId)) {
      fail("invalid-argument", "reporterId is invalid.");
    }

    let query = db.collection(BUG_REPORTS);
    if (reporterId !== null) query = query.where("reporterId", "==", reporterId);
    if (status !== null) query = query.where("status", "==", status);
    query = query.orderBy("createdAt", "desc");
    if (cursor !== null) {
      const cursorSnapshot = await reportRef(cursor).get();
      if (!cursorSnapshot.exists) fail("invalid-argument", "cursor is no longer available.");
      query = query.startAfter(cursorSnapshot);
    }
    const snapshot = await query.limit(limit + 1).get();
    const docs = snapshot.docs.slice(0, limit);
    return {
      reports: docs.map(summaryOf),
      nextCursor: snapshot.docs.length > limit ? docs[docs.length - 1].id : null,
    };
  }

  async function getBugReportV1(request) {
    await authorizeOwner(request);
    const fields = ["reportId"];
    requireExactInput(request.data, fields, fields);
    const reportId = requireReportId(request.data.reportId);
    const snapshot = await reportRef(reportId).get();
    if (!snapshot.exists) fail("not-found", "The bug report was not found.");
    const value = snapshot.data() ?? {};
    let screenshot = null;
    const shot = value.screenshot;
    if (shot && typeof shot === "object") {
      screenshot = { status: typeof shot.status === "string" ? shot.status : "unknown", url: null, expiresAtMillis: null };
      if (shot.status === "attached" && typeof shot.generation === "string" &&
          GENERATION_PATTERN.test(shot.generation) &&
          parseBugReportStoragePath(shot.storagePath)?.reportId === reportId) {
        const expiresAtMillis = clock() + SCREENSHOT_ACCESS_TTL_MS;
        try {
          screenshot.url = await storage.getSignedReadUrl(shot.storagePath, {
            expiresAtMs: expiresAtMillis, generation: shot.generation,
          });
          screenshot.expiresAtMillis = expiresAtMillis;
        } catch (error) {
          if (!isMissingObject(error)) throw error;
          screenshot.status = "missing";
        }
      }
    }
    return {
      ...summaryOf(snapshot),
      description: typeof value.description === "string" ? value.description : "",
      context: value.context ?? {},
      updatedAtMillis: millis(value.updatedAt),
      expiresAtMillis: millis(value.expiresAt),
      screenshot,
      delivery: deliveryOf(value),
    };
  }

  async function updateBugReportStatusV1(request) {
    await authorizeOwner(request);
    const fields = ["reportId", "status"];
    requireExactInput(request.data, fields, fields);
    const reportId = requireReportId(request.data.reportId);
    const status = request.data.status;
    if (!STATUSES.includes(status)) fail("invalid-argument", "status is invalid.");
    await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(reportRef(reportId));
      if (!snapshot.exists) fail("not-found", "The bug report was not found.");
      const now = Timestamp.fromMillis(clock());
      transaction.update(reportRef(reportId), { status, updatedAt: now, statusUpdatedAt: now });
    });
    return { reportId, status };
  }

  /** The canonical object path of a report's screenshot, or null. */
  function screenshotPathOf(reportId, value) {
    const reporterId = typeof value?.reporterId === "string" ? value.reporterId : null;
    const stored = value?.screenshot?.storagePath;
    const parsed = parseBugReportStoragePath(stored);
    if (parsed && parsed.reportId === reportId && parsed.ownerId === reporterId) return stored;
    // A reservation that never became an upload still names one exact path.
    return reporterId !== null && isValidOpaqueUid(reporterId)
      ? bugReportStoragePath(reporterId, reportId)
      : null;
  }

  /**
   * One adminAuditLogs entry, in the caller's transaction, in exactly the flat
   * shape functions/utils/audit.js writeAuditLog writes (the Staff Center
   * audit browser reads that shape). Never the description or the image.
   */
  function auditOwnerAction(transaction, caller, { action, reportId, details, now }) {
    transaction.create(db.collection("adminAuditLogs").doc(), {
      actorId: caller?.uid ?? null,
      actorEmail: caller?.token?.email ?? caller?.email ?? null,
      actorRole: caller?.role ?? caller?.token?.role ?? "owner",
      action,
      targetType: "bugReport",
      targetId: reportId,
      targetLabel: null,
      details,
      createdAt: now,
    });
  }

  /**
   * Deletes one report now: the document, any upload reservation and the
   * screenshot object. For erasure requests (the reporter's, or a third
   * party's shown in a screenshot) and for reports that should not be kept.
   * The object is deleted before AND after the transaction: before, so a
   * failed transaction never leaves a report pointing at a half-deleted
   * image; after, so an upload racing the reservation's deletion cannot
   * leave an orphan.
   */
  async function deleteBugReportV1(request) {
    const caller = await authorizeOwner(request);
    const fields = ["reportId"];
    requireExactInput(request.data, fields, fields);
    const reportId = requireReportId(request.data.reportId);
    const snapshot = await reportRef(reportId).get();
    if (!snapshot.exists) fail("not-found", "The bug report was not found.");
    const objectPath = screenshotPathOf(reportId, snapshot.data());
    if (objectPath !== null) await storage.deleteObject(objectPath);
    await db.runTransaction(async (transaction) => {
      const current = await transaction.get(reportRef(reportId));
      if (!current.exists) fail("not-found", "The bug report was not found.");
      const value = current.data() ?? {};
      const now = Timestamp.fromMillis(clock());
      transaction.delete(reportRef(reportId));
      transaction.delete(reservationRef(reportId));
      auditOwnerAction(transaction, caller, {
        action: "bug_report.deleted",
        reportId,
        now,
        details: {
          reporterId: typeof value.reporterId === "string" ? value.reporterId : null,
          screenshotStatus: typeof value.screenshot?.status === "string" ? value.screenshot.status : "none",
        },
      });
    });
    if (objectPath !== null) await storage.deleteObject(objectPath);
    logger.info?.("bug report deleted by the owner", { reportId });
    return { reportId, deleted: true };
  }

  /**
   * Removes only the screenshot of one report; the words stay. Idempotent: a
   * report without a live screenshot answers removed without an audit entry.
   */
  async function deleteBugReportScreenshotV1(request) {
    const caller = await authorizeOwner(request);
    const fields = ["reportId"];
    requireExactInput(request.data, fields, fields);
    const reportId = requireReportId(request.data.reportId);
    const snapshot = await reportRef(reportId).get();
    if (!snapshot.exists) fail("not-found", "The bug report was not found.");
    const before = snapshot.data() ?? {};
    const status = before.screenshot?.status;
    if (status !== "attached" && status !== "reserved" && status !== "missing") {
      return { reportId, removed: false };
    }
    const objectPath = screenshotPathOf(reportId, before);
    if (objectPath !== null) await storage.deleteObject(objectPath);
    await db.runTransaction(async (transaction) => {
      const current = await transaction.get(reportRef(reportId));
      if (!current.exists) fail("not-found", "The bug report was not found.");
      const value = current.data() ?? {};
      const now = Timestamp.fromMillis(clock());
      transaction.update(reportRef(reportId), {
        "screenshot.status": "removed",
        "screenshot.generation": null,
        screenshotExpiresAt: null,
        updatedAt: now,
      });
      transaction.delete(reservationRef(reportId));
      auditOwnerAction(transaction, caller, {
        action: "bug_report.screenshot_removed",
        reportId,
        now,
        details: {
          reporterId: typeof value.reporterId === "string" ? value.reporterId : null,
          previousStatus: typeof value.screenshot?.status === "string" ? value.screenshot.status : "none",
        },
      });
    });
    if (objectPath !== null) await storage.deleteObject(objectPath);
    logger.info?.("bug report screenshot removed by the owner", { reportId });
    return { reportId, removed: true };
  }

  // ---------------------------------------------------------------- sweep

  async function sweepExpiredReservations(nowMs) {
    const snapshot = await db.collection(BUG_REPORT_RESERVATIONS)
      .where("expiresAt", "<=", Timestamp.fromMillis(nowMs - RESERVATION_SWEEP_GRACE_MS))
      .limit(SWEEP_PAGE).get();
    let removed = 0;
    for (const document of snapshot.docs) {
      const value = document.data() ?? {};
      const parsed = parseBugReportStoragePath(value.storagePath);
      if (parsed && parsed.reportId === document.id && parsed.ownerId === value.ownerId) {
        // The object may or may not exist; an abandoned upload is deleted
        // here, never bound to the report.
        await storage.deleteObject(value.storagePath);
      }
      await db.runTransaction(async (transaction) => {
        const report = await transaction.get(reportRef(document.id));
        if (report.exists && report.data()?.screenshot?.status === "reserved") {
          transaction.update(reportRef(document.id), {
            "screenshot.status": "expired",
            updatedAt: Timestamp.fromMillis(nowMs),
          });
        }
        transaction.delete(document.ref);
      });
      removed += 1;
    }
    return removed;
  }

  async function sweepExpiredScreenshots(nowMs) {
    const snapshot = await db.collection(BUG_REPORTS)
      .where("screenshotExpiresAt", "<=", Timestamp.fromMillis(nowMs))
      .limit(SWEEP_PAGE).get();
    let removed = 0;
    for (const document of snapshot.docs) {
      const shot = document.data()?.screenshot;
      if (shot?.status === "attached" && parseBugReportStoragePath(shot.storagePath)) {
        await storage.deleteObject(shot.storagePath, {
          generation: GENERATION_PATTERN.test(String(shot.generation ?? "")) ? shot.generation : null,
        });
      }
      await document.ref.update({
        "screenshot.status": "deleted",
        screenshotExpiresAt: null,
        updatedAt: Timestamp.fromMillis(nowMs),
      });
      removed += 1;
    }
    return removed;
  }

  async function sweepExpiredReports(nowMs) {
    const snapshot = await db.collection(BUG_REPORTS)
      .where("expiresAt", "<=", Timestamp.fromMillis(nowMs))
      .limit(SWEEP_PAGE).get();
    let removed = 0;
    for (const document of snapshot.docs) {
      const value = document.data() ?? {};
      const shot = value.screenshot;
      if (shot && parseBugReportStoragePath(shot.storagePath)) {
        await storage.deleteObject(shot.storagePath);
      }
      await Promise.all([document.ref.delete(), reservationRef(document.id).delete()]);
      removed += 1;
    }
    return removed;
  }

  /**
   * Runs one sub-sweep page after page until a page comes back short (the
   * query drained), the time budget ends, or the page cap is hit. One page a
   * day could not keep up with the permitted intake.
   */
  async function drain(sweepPage, nowMs, startedAt) {
    let total = 0;
    for (let page = 0; page < SWEEP_MAX_PAGES; page += 1) {
      if (monotonic() - startedAt >= SWEEP_BUDGET_MS) return { total, drained: false };
      const removed = await sweepPage(nowMs);
      total += removed;
      if (removed < SWEEP_PAGE) return { total, drained: true };
    }
    return { total, drained: false };
  }

  async function sweepBugReportRetention() {
    const nowMs = clock();
    const startedAt = monotonic();
    const reservations = await drain(sweepExpiredReservations, nowMs, startedAt);
    const screenshots = await drain(sweepExpiredScreenshots, nowMs, startedAt);
    const reports = await drain(sweepExpiredReports, nowMs, startedAt);
    // Counts only. A backlog means the next run (or an operator) must catch up.
    const backlog = !(reservations.drained && screenshots.drained && reports.drained);
    const outcome = {
      reservations: reservations.total,
      screenshots: screenshots.total,
      reports: reports.total,
      backlog,
    };
    if (backlog) logger.warn?.("bug report retention sweep left a backlog", outcome);
    else logger.info?.("bug report retention sweep", outcome);
    return outcome;
  }

  return Object.freeze({
    attachBugReportScreenshotV1,
    deleteBugReportScreenshotV1,
    deleteBugReportV1,
    getBugReportV1,
    listBugReportsV1,
    submitBugReportV1,
    sweepBugReportRetention,
    updateBugReportStatusV1,
  });
}

module.exports = {
  createBugReportService,
  createBugReportStorageAdapter,
  isJpegHeader,
};
