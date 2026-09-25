// In-app bug reports: the reporter callables (validation, account state,
// idempotency, rate limits, the kill switch), the screenshot upload
// reservation and its attach step, the owner callables, the retention sweep,
// the source-gated delivery channels and account-deletion coverage.
//
// Firestore is the explicitly selected localhost emulator; a deterministic
// private-object adapter models Storage generations, headers, token hardening,
// signing and deletion. The rules half (clients can never read or write any of
// this) is firestore-tests/bug_report_rules.test.js.
const assert = require("node:assert/strict");
const { execFileSync } = require("node:child_process");
const path = require("node:path");
const { randomUUID } = require("node:crypto");
const { after, test } = require("node:test");

const enabled = /^(127\.0\.0\.1|localhost):[0-9]+$/u.test(process.env.FIRESTORE_EMULATOR_HOST ?? "");
let app;
let db;
let Timestamp;
let FieldValue;
let FieldPath;
if (enabled) {
  const adminApp = require("firebase-admin/app");
  const firestore = require("firebase-admin/firestore");
  Timestamp = firestore.Timestamp;
  FieldValue = firestore.FieldValue;
  FieldPath = firestore.FieldPath;
  app = adminApp.initializeApp({ projectId: "demo-yovoice-bug-reports" }, `bug-reports-${randomUUID()}`);
  db = firestore.getFirestore(app);
}
after(async () => { if (app) await require("firebase-admin/app").deleteApp(app); });

const { rateLimitReference } = require("../integrity/guards");
const {
  BUG_REPORTS,
  BUG_REPORT_RESERVATIONS,
  GLOBAL_RATE_LIMIT_SENTINEL,
  RATE_LIMITS,
  REPORT_RETENTION_MS,
  RESERVATION_TTL_MS,
  SCREENSHOT_RETENTION_MS,
  bugReportId,
  bugReportStoragePath,
} = require("../bug_reports/contract");
const { createBugReportService, isJpegHeader } = require("../bug_reports/service");
const {
  MAX_ATTEMPTS,
  buildBugReportEmail,
  buildBugReportIssue,
  createBugReportDelivery,
} = require("../bug_reports/delivery");
const {
  BUG_REPORT_BASE_EXPORT_NAMES,
  createBugReportFunctions,
} = require("../bug_reports/registration");
const { createAccountDeletionStages, uidStoragePrefixes } = require("../account/stages");

const NOW = 1_900_000_000_000;
const OWNER = "br-owner";
const JPEG = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0, 0x10, 0x4a, 0x46, 0x49, 0x46, 0, 1, 1, 0, 0, 1]);
const PNG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 0, 0, 0, 0, 0]);

const emulatorTest = (name, fn) => test(`Bug reports: ${name}`, {
  skip: enabled ? false : "Requires explicit localhost Firestore emulator; no cloud fallback.",
  timeout: 90_000,
}, fn);
const unitTest = (name, fn) => test(`Bug reports: ${name}`, fn);
const request = (uid, data, verified = true) => ({ auth: { uid, token: { email_verified: verified } }, data });
const rejects = (promise, code) => assert.rejects(promise, (error) => {
  assert.equal(error.code, code, `${error.code}: ${error.message}`);
  return true;
});

function uniqueUid(label) {
  return `br-${label}-${randomUUID().slice(0, 8)}`;
}

function context(overrides = {}) {
  return {
    appVersion: "3.0.0",
    buildNumber: "36",
    platform: "ios",
    osVersion: "Version 18.6 (Build 22G86)",
    locale: "pl-PL",
    theme: "dark",
    brightness: "dark",
    route: "ChatScreen",
    routeDepth: 2,
    viewportWidth: 390,
    viewportHeight: 844,
    textScale: 1,
    ...overrides,
  };
}

function submitData(overrides = {}) {
  return {
    requestId: `req-${randomUUID()}`,
    description: "The send button stays grey after I pick a photo.",
    context: context(),
    screenshot: null,
    ...overrides,
  };
}

class FakeStorage {
  constructor() {
    this.objects = new Map();
    this.deleted = [];
    this.signed = [];
  }

  put(path, { generation = "1700000000000001", size, contentType = "image/jpeg", metadata = {}, header = JPEG, token = "token-1" } = {}) {
    this.objects.set(path, {
      generation, size, contentType, header,
      metadata: { ...metadata, ...(token ? { firebaseStorageDownloadTokens: token } : {}) },
    });
  }

  async getMetadata(objectPath) {
    const object = this.objects.get(objectPath);
    if (!object) {
      const error = new Error("No such object");
      error.code = 404;
      throw error;
    }
    return {
      generation: object.generation,
      size: String(object.size),
      contentType: object.contentType,
      metadata: { ...object.metadata },
    };
  }

  async readHeader(objectPath, generation) {
    const object = this.objects.get(objectPath);
    assert.equal(object.generation, generation, "the header read is generation-bound");
    return object.header;
  }

  async hardenObject(objectPath, metadata, required) {
    const object = this.objects.get(objectPath);
    assert.equal(object.generation, String(metadata.generation));
    const next = { ...object.metadata, ...required };
    delete next.firebaseStorageDownloadTokens;
    object.metadata = next;
    return this.getMetadata(objectPath);
  }

  async getSignedReadUrl(objectPath, { expiresAtMs, generation }) {
    this.signed.push({ objectPath, expiresAtMs, generation });
    return `https://storage.googleapis.com/demo/${objectPath}?generation=${generation}&sig=x`;
  }

  async deleteObject(objectPath, { generation = null } = {}) {
    this.deleted.push({ objectPath, generation });
    this.objects.delete(objectPath);
  }
}

function ownerGate() {
  const calls = [];
  return {
    calls,
    authorizeOwner: async (req) => {
      calls.push(req.auth?.uid ?? null);
      if (req.auth?.uid !== OWNER) {
        const error = new Error("This action is reserved for the application owner.");
        error.code = "permission-denied";
        throw error;
      }
      return req.auth;
    },
  };
}

function serviceWith({ storage = new FakeStorage(), clock = () => NOW, gate = ownerGate() } = {}) {
  return {
    storage,
    gate,
    service: createBugReportService({
      db, Timestamp, storage, clock, authorizeOwner: gate.authorizeOwner,
      logger: { info() {}, warn() {} },
    }),
  };
}

async function seedUser(uid, profile = {}) {
  await db.collection("users").doc(uid).set({ uid, displayName: uid, status: "active", ...profile });
}

async function clearRate(scope, uid) {
  await rateLimitReference(db, scope, uid).delete();
}

// ------------------------------------------------------------------ submit

emulatorTest("an unauthenticated caller is refused", async () => {
  const { service } = serviceWith();
  await rejects(service.submitBugReportV1({ data: submitData() }), "unauthenticated");
});

emulatorTest("the input is an exact allowlist with bounded values", async () => {
  const uid = uniqueUid("validation");
  await seedUser(uid);
  const { service } = serviceWith();
  const cases = [
    submitData({ extra: true }),
    { ...submitData(), requestId: undefined },
    submitData({ requestId: "short" }),
    submitData({ description: "too short" }),
    submitData({ description: "x".repeat(2001) }),
    submitData({ description: 42 }),
    submitData({ context: { ...context(), email: "someone@example.com" } }),
    submitData({ context: { ...context(), fcmToken: "abc" } }),
    submitData({ context: context({ platform: "blackberry" }) }),
    submitData({ context: context({ route: "chat/conversation-123 with Anna" }) }),
    submitData({ context: context({ locale: "pl PL" }) }),
    submitData({ context: context({ buildNumber: "36a" }) }),
    submitData({ context: context({ textScale: 9 }) }),
    submitData({ context: context({ routeDepth: -1 }) }),
    submitData({ screenshot: { contentType: "image/png", size: 4096 } }),
    submitData({ screenshot: { contentType: "image/jpeg", size: 64 } }),
    submitData({ screenshot: { contentType: "image/jpeg", size: 1_500_001 } }),
    submitData({ screenshot: { contentType: "image/jpeg", size: 4096, url: "x" } }),
  ];
  for (const data of cases) {
    if (data.requestId === undefined) delete data.requestId;
    await rejects(service.submitBugReportV1(request(uid, data)), "invalid-argument");
  }
  const reports = await db.collection(BUG_REPORTS).where("reporterId", "==", uid).get();
  assert.equal(reports.size, 0, "a refused submit writes nothing");
});

emulatorTest("an unverified account may report; a disabled or deleted one may not; a banned one may", async () => {
  const unverified = uniqueUid("unverified");
  const disabled = uniqueUid("disabled");
  const deleted = uniqueUid("deleted");
  const banned = uniqueUid("banned");
  const missing = uniqueUid("missing");
  await Promise.all([
    seedUser(unverified),
    seedUser(disabled, { disabled: true }),
    seedUser(deleted, { status: "deleted" }),
    seedUser(banned, { banned: true }),
  ]);
  const { service } = serviceWith();
  const accepted = await service.submitBugReportV1(request(unverified, submitData(), false));
  assert.match(accepted.reportId, /^br_[a-f0-9]{40}$/u);
  await rejects(service.submitBugReportV1(request(disabled, submitData())), "permission-denied");
  await rejects(service.submitBugReportV1(request(deleted, submitData())), "permission-denied");
  await rejects(service.submitBugReportV1(request(missing, submitData())), "permission-denied");
  const ban = await service.submitBugReportV1(request(banned, submitData()));
  assert.match(ban.reportId, /^br_/u);
});

emulatorTest("the stored report carries exactly the allowlisted fields and the server uid", async () => {
  const uid = uniqueUid("shape");
  await seedUser(uid);
  const { service } = serviceWith();
  const data = submitData({ description: "  Line one\r\nline two\u0007 with a bell  " });
  const result = await service.submitBugReportV1(request(uid, data));
  assert.equal(result.reportId, bugReportId(uid, data.requestId));
  assert.equal(result.screenshotUpload, null);
  const stored = (await db.collection(BUG_REPORTS).doc(result.reportId).get()).data();
  assert.deepEqual(Object.keys(stored).sort(), [
    "context", "createdAt", "description", "expiresAt", "inputHash", "reportId",
    "reporterId", "schemaVersion", "screenshot", "screenshotExpiresAt", "status", "updatedAt",
  ]);
  assert.equal(stored.reporterId, uid);
  assert.equal(stored.description, "Line one\nline two with a bell");
  assert.deepEqual(stored.context, context());
  assert.equal(stored.status, "new");
  assert.equal(stored.screenshot, null);
  assert.equal(stored.expiresAt.toMillis(), NOW + REPORT_RETENTION_MS);
  const serialized = JSON.stringify(stored);
  for (const forbidden of ["email", "token", "ip", "Token"]) {
    assert.ok(!Object.keys(stored.context).some((key) => key.includes(forbidden)), forbidden);
  }
  assert.ok(!serialized.includes("firebaseStorageDownloadTokens"));
});

emulatorTest("a replayed requestId returns the same report without spending the rate limit", async () => {
  const uid = uniqueUid("replay");
  await seedUser(uid);
  const { service } = serviceWith();
  const data = submitData();
  const first = await service.submitBugReportV1(request(uid, data));
  const burstRef = rateLimitReference(db, RATE_LIMITS.burst.scope, uid);
  const countAfterFirst = (await burstRef.get()).data().count;
  const second = await service.submitBugReportV1(request(uid, data));
  assert.equal(second.reportId, first.reportId);
  assert.equal((await burstRef.get()).data().count, countAfterFirst);
  // The same requestId with a different payload is a conflict, not a replay.
  await rejects(service.submitBugReportV1(request(uid, { ...data, description: "Something else entirely." })),
    "already-exists");
  const reports = await db.collection(BUG_REPORTS).where("reporterId", "==", uid).get();
  assert.equal(reports.size, 1);
});

emulatorTest("five reports per ten minutes per account, then resource-exhausted", async () => {
  const uid = uniqueUid("burst");
  await seedUser(uid);
  const { service } = serviceWith();
  for (let index = 0; index < RATE_LIMITS.burst.maxEvents; index += 1) {
    await service.submitBugReportV1(request(uid, submitData()));
  }
  await rejects(service.submitBugReportV1(request(uid, submitData())), "resource-exhausted");
  // Another account is unaffected: the limit is per reporter.
  const other = uniqueUid("burst-other");
  await seedUser(other);
  await service.submitBugReportV1(request(other, submitData()));
  // A new window reopens.
  const later = serviceWith({ clock: () => NOW + RATE_LIMITS.burst.windowMs + 1 }).service;
  await later.submitBugReportV1(request(uid, submitData()));
});

emulatorTest("the daily per-account and the project-wide ceilings both refuse", async () => {
  const uid = uniqueUid("daily");
  await seedUser(uid);
  const { service } = serviceWith();
  await rateLimitReference(db, RATE_LIMITS.daily.scope, uid).set({
    schemaVersion: 1, ownerId: uid, scope: RATE_LIMITS.daily.scope,
    windowStartedAt: Timestamp.fromMillis(NOW - 1000), count: RATE_LIMITS.daily.maxEvents,
    updatedAt: Timestamp.fromMillis(NOW - 1000),
  });
  await rejects(service.submitBugReportV1(request(uid, submitData())), "resource-exhausted");

  const fresh = uniqueUid("global");
  await seedUser(fresh);
  const globalRef = rateLimitReference(db, RATE_LIMITS.global.scope, GLOBAL_RATE_LIMIT_SENTINEL);
  await globalRef.set({
    schemaVersion: 1, ownerId: GLOBAL_RATE_LIMIT_SENTINEL, scope: RATE_LIMITS.global.scope,
    windowStartedAt: Timestamp.fromMillis(NOW - 1000), count: RATE_LIMITS.global.maxEvents,
    updatedAt: Timestamp.fromMillis(NOW - 1000),
  });
  try {
    await rejects(service.submitBugReportV1(request(fresh, submitData())), "resource-exhausted");
  } finally {
    await clearRate(RATE_LIMITS.global.scope, GLOBAL_RATE_LIMIT_SENTINEL);
  }
});

emulatorTest("appConfig/bugReports.enabled=false pauses submission; a missing document does not", async () => {
  const uid = uniqueUid("switch");
  await seedUser(uid);
  const { service } = serviceWith();
  const config = db.collection("appConfig").doc("bugReports");
  await config.set({ enabled: false });
  try {
    await rejects(service.submitBugReportV1(request(uid, submitData())), "failed-precondition");
  } finally {
    await config.delete();
  }
  await service.submitBugReportV1(request(uid, submitData()));
});

// ----------------------------------------------------- upload reservation

async function reserve(service, uid, size = 4096) {
  const data = submitData({ screenshot: { contentType: "image/jpeg", size } });
  const result = await service.submitBugReportV1(request(uid, data));
  return { ...result, data };
}

emulatorTest("a declared screenshot issues one exact, 15-minute reservation for one private path", async () => {
  const uid = uniqueUid("reserve");
  await seedUser(uid);
  const { service } = serviceWith();
  const { reportId, screenshotUpload, data } = await reserve(service, uid);
  assert.deepEqual(screenshotUpload, {
    storagePath: `bug_reports/${uid}/${reportId}.jpg`,
    contentType: "image/jpeg",
    size: 4096,
    uploadMetadata: { yovoiceOwnerUid: uid, yovoiceReportId: reportId },
    expiresAtMillis: NOW + RESERVATION_TTL_MS,
  });
  const reservation = (await db.collection(BUG_REPORT_RESERVATIONS).doc(reportId).get()).data();
  assert.deepEqual(Object.keys(reservation).sort(), [
    "contentType", "createdAt", "expiresAt", "kind", "ownerId", "reportId",
    "schemaVersion", "size", "status", "storagePath",
  ]);
  assert.equal(reservation.kind, "bugReportScreenshot");
  assert.equal(reservation.status, "uploading");
  assert.equal(reservation.storagePath, bugReportStoragePath(uid, reportId));
  const report = (await db.collection(BUG_REPORTS).doc(reportId).get()).data();
  assert.equal(report.screenshot.status, "reserved");
  // A replay hands back the same live reservation.
  const again = await service.submitBugReportV1(request(uid, data));
  assert.deepEqual(again.screenshotUpload, screenshotUpload);
});

emulatorTest("attach binds exactly the reserved JPEG, strips its download token and consumes the reservation", async () => {
  const uid = uniqueUid("attach");
  await seedUser(uid);
  const { service, storage } = serviceWith();
  const { reportId, screenshotUpload } = await reserve(service, uid);
  storage.put(screenshotUpload.storagePath, {
    size: 4096, metadata: screenshotUpload.uploadMetadata, generation: "1700000000000042",
  });
  const result = await service.attachBugReportScreenshotV1(request(uid, {
    reportId, objectGeneration: "1700000000000042",
  }));
  assert.deepEqual(result, { reportId, attached: true });
  const stored = storage.objects.get(screenshotUpload.storagePath);
  assert.equal(stored.metadata.firebaseStorageDownloadTokens, undefined);
  const report = (await db.collection(BUG_REPORTS).doc(reportId).get()).data();
  assert.equal(report.screenshot.status, "attached");
  assert.equal(report.screenshot.generation, "1700000000000042");
  assert.equal(report.screenshotExpiresAt.toMillis(), NOW + SCREENSHOT_RETENTION_MS);
  assert.equal((await db.collection(BUG_REPORT_RESERVATIONS).doc(reportId).get()).exists, false);
  // Idempotent replay of the same attach.
  assert.deepEqual(await service.attachBugReportScreenshotV1(request(uid, {
    reportId, objectGeneration: "1700000000000042",
  })), { reportId, attached: true });
});

emulatorTest("attach refuses a foreign report, a missing object, a size or metadata mismatch, a non-JPEG and an expired window", async () => {
  const uid = uniqueUid("attach-refuse");
  const stranger = uniqueUid("stranger");
  await Promise.all([seedUser(uid), seedUser(stranger)]);
  const { service, storage } = serviceWith();
  const { reportId, screenshotUpload } = await reserve(service, uid);
  const attach = (caller, generation = "1700000000000001") => service.attachBugReportScreenshotV1(
    request(caller, { reportId, objectGeneration: generation }));

  await rejects(attach(stranger), "not-found");
  await rejects(attach(uid), "failed-precondition"); // nothing uploaded
  await rejects(service.attachBugReportScreenshotV1(request(uid, {
    reportId, objectGeneration: "1", extra: 1,
  })), "invalid-argument");

  storage.put(screenshotUpload.storagePath, { size: 4095, metadata: screenshotUpload.uploadMetadata });
  await rejects(attach(uid), "failed-precondition");
  storage.put(screenshotUpload.storagePath, {
    size: 4096, metadata: { ...screenshotUpload.uploadMetadata, extra: "x" },
  });
  await rejects(attach(uid), "failed-precondition");
  storage.put(screenshotUpload.storagePath, { size: 4096, metadata: screenshotUpload.uploadMetadata });
  await rejects(attach(uid, "1700000000000999"), "failed-precondition"); // wrong generation

  storage.put(screenshotUpload.storagePath, {
    size: 4096, metadata: screenshotUpload.uploadMetadata, header: PNG,
  });
  await rejects(attach(uid), "failed-precondition");
  assert.equal(storage.objects.has(screenshotUpload.storagePath), false, "a non-JPEG object is deleted");

  storage.put(screenshotUpload.storagePath, { size: 4096, metadata: screenshotUpload.uploadMetadata });
  const late = serviceWith({ storage, clock: () => NOW + RESERVATION_TTL_MS + 1 }).service;
  await rejects(late.attachBugReportScreenshotV1(request(uid, {
    reportId, objectGeneration: "1700000000000001",
  })), "deadline-exceeded");
  const report = (await db.collection(BUG_REPORTS).doc(reportId).get()).data();
  assert.equal(report.screenshot.status, "reserved", "no refusal binds anything");
});

unitTest("the JPEG sniff accepts only FF D8 FF", () => {
  assert.equal(isJpegHeader(JPEG), true);
  assert.equal(isJpegHeader(PNG), false);
  assert.equal(isJpegHeader(Buffer.from([0xff, 0xd8])), false);
});

// ------------------------------------------------------------------ owner

emulatorTest("the owner callables refuse everybody but the protected owner", async () => {
  const uid = uniqueUid("not-owner");
  await seedUser(uid);
  const { service, gate } = serviceWith();
  const { reportId } = await service.submitBugReportV1(request(uid, submitData()));
  await rejects(service.listBugReportsV1(request(uid, {})), "permission-denied");
  await rejects(service.getBugReportV1(request(uid, { reportId })), "permission-denied");
  await rejects(service.updateBugReportStatusV1(request(uid, { reportId, status: "resolved" })),
    "permission-denied");
  // Even the reporter cannot read their own report back.
  assert.deepEqual(gate.calls, [uid, uid, uid]);
});

emulatorTest("the owner lists newest first, filters by status, pages, reads detail with a signed screenshot URL and triages", async () => {
  const uid = uniqueUid("owner-flow");
  await seedUser(uid);
  const storage = new FakeStorage();
  const early = serviceWith({ storage, clock: () => NOW - 60_000 }).service;
  const { service } = serviceWith({ storage });
  const older = await early.submitBugReportV1(request(uid, submitData({ description: "An older bug report text." })));
  const { reportId, screenshotUpload } = await reserve(service, uid);
  storage.put(screenshotUpload.storagePath, { size: 4096, metadata: screenshotUpload.uploadMetadata });
  await service.attachBugReportScreenshotV1(request(uid, { reportId, objectGeneration: "1700000000000001" }));

  const page = await service.listBugReportsV1(request(OWNER, { limit: 50 }));
  const mine = page.reports.filter((row) => row.reporterId === uid);
  assert.deepEqual(mine.map((row) => row.reportId), [reportId, older.reportId]);
  assert.equal(mine[0].screenshotStatus, "attached");
  assert.equal(mine[0].platform, "ios");
  assert.equal(mine[0].route, "ChatScreen");

  const first = await service.listBugReportsV1(request(OWNER, { limit: 1 }));
  assert.equal(first.reports.length, 1);
  assert.equal(typeof first.nextCursor, "string");
  const second = await service.listBugReportsV1(request(OWNER, { limit: 1, cursor: first.nextCursor }));
  assert.notEqual(second.reports[0].reportId, first.reports[0].reportId);

  const detail = await service.getBugReportV1(request(OWNER, { reportId }));
  assert.equal(detail.reporterId, uid);
  assert.equal(detail.description, "The send button stays grey after I pick a photo.");
  assert.equal(detail.screenshot.status, "attached");
  assert.match(detail.screenshot.url, /^https:\/\/storage\.googleapis\.com\//u);
  assert.equal(detail.screenshot.expiresAtMillis, NOW + 5 * 60 * 1000);
  assert.deepEqual(storage.signed.at(-1), {
    objectPath: screenshotUpload.storagePath, expiresAtMs: NOW + 5 * 60 * 1000, generation: "1700000000000001",
  });

  await service.updateBugReportStatusV1(request(OWNER, { reportId, status: "triaged" }));
  const triaged = await service.listBugReportsV1(request(OWNER, { status: "triaged", limit: 50 }));
  assert.ok(triaged.reports.some((row) => row.reportId === reportId));
  assert.ok(!triaged.reports.some((row) => row.reportId === older.reportId));
  await rejects(service.updateBugReportStatusV1(request(OWNER, { reportId, status: "deleted" })),
    "invalid-argument");
  await rejects(service.listBugReportsV1(request(OWNER, { limit: 500 })), "invalid-argument");
});

// ------------------------------------------------------------------ sweep

emulatorTest("the retention sweep removes abandoned uploads, 90-day screenshots and 180-day reports", async () => {
  const uid = uniqueUid("sweep");
  await seedUser(uid);
  const storage = new FakeStorage();
  const { service } = serviceWith({ storage });
  const abandoned = await reserve(service, uid);
  storage.put(abandoned.screenshotUpload.storagePath, { size: 4096, metadata: abandoned.screenshotUpload.uploadMetadata });
  const kept = await reserve(service, uid);
  storage.put(kept.screenshotUpload.storagePath, { size: 4096, metadata: kept.screenshotUpload.uploadMetadata });
  await service.attachBugReportScreenshotV1(request(uid, { reportId: kept.reportId, objectGeneration: "1700000000000001" }));

  // An hour later: only the abandoned reservation is swept.
  const hour = serviceWith({ storage, clock: () => NOW + 60 * 60 * 1000 }).service;
  const firstSweep = await hour.sweepBugReportRetention();
  assert.ok(firstSweep.reservations >= 1);
  assert.equal(storage.objects.has(abandoned.screenshotUpload.storagePath), false);
  assert.equal((await db.collection(BUG_REPORT_RESERVATIONS).doc(abandoned.reportId).get()).exists, false);
  assert.equal((await db.collection(BUG_REPORTS).doc(abandoned.reportId).get()).data().screenshot.status, "expired");
  assert.equal(storage.objects.has(kept.screenshotUpload.storagePath), true);

  // After 90 days the attached screenshot goes; the report stays.
  const ninety = serviceWith({ storage, clock: () => NOW + SCREENSHOT_RETENTION_MS + 1 }).service;
  await ninety.sweepBugReportRetention();
  assert.equal(storage.objects.has(kept.screenshotUpload.storagePath), false);
  const keptReport = (await db.collection(BUG_REPORTS).doc(kept.reportId).get()).data();
  assert.equal(keptReport.screenshot.status, "deleted");
  assert.equal(keptReport.screenshotExpiresAt, null);

  // After 180 days the reports themselves go.
  const later = serviceWith({ storage, clock: () => NOW + REPORT_RETENTION_MS + 1 }).service;
  for (let round = 0; round < 10; round += 1) {
    const swept = await later.sweepBugReportRetention();
    if (swept.reports === 0) break;
  }
  assert.equal((await db.collection(BUG_REPORTS).doc(kept.reportId).get()).exists, false);
  assert.equal((await db.collection(BUG_REPORTS).doc(abandoned.reportId).get()).exists, false);
});

// --------------------------------------------------------------- delivery

function fakeFetch(responses) {
  const calls = [];
  const queue = [...responses];
  const fetchImpl = async (url, init = {}) => {
    calls.push({ url, init, body: init.body ? JSON.parse(init.body) : null });
    const next = queue.shift() ?? { status: 200, body: {} };
    if (next.throws) throw new Error("socket hang up");
    return {
      ok: next.status >= 200 && next.status < 300,
      status: next.status,
      json: async () => next.body ?? {},
    };
  };
  return { calls, fetchImpl };
}

async function seededReport(uid, description = "Crash <script>alert(1)</script> when @someone opens #12 ```") {
  await seedUser(uid);
  const { service } = serviceWith();
  const { reportId } = await service.submitBugReportV1(request(uid, submitData({ description })));
  return reportId;
}

function deliveryWith({ fetchImpl, channels, clock = () => NOW }) {
  return createBugReportDelivery({
    db, Timestamp, fetchImpl, clock, channels, logger: { info() {}, warn() {} },
  });
}

const EMAIL_CHANNEL = { apiKey: () => "re_test_key" };
const GITHUB_CHANNEL = { token: () => "ghp_test_token" };

async function withConfig(value, fn) {
  const config = db.collection("appConfig").doc("bugReports");
  await config.set(value);
  try {
    return await fn();
  } finally {
    await config.delete();
  }
}

emulatorTest("a channel whose runtime switch is off is recorded as disabled and makes no request", async () => {
  const uid = uniqueUid("disabled-channel");
  const reportId = await seededReport(uid);
  const { calls, fetchImpl } = fakeFetch([]);
  const outcome = await deliveryWith({ fetchImpl, channels: { email: EMAIL_CHANNEL, github: GITHUB_CHANNEL } })
    .deliverBugReport(reportId);
  assert.deepEqual(outcome, { email: "disabled", github: "disabled" });
  assert.equal(calls.length, 0);
  const report = (await db.collection(BUG_REPORTS).doc(reportId).get()).data();
  assert.equal(report.delivery.email.status, "disabled");
});

emulatorTest("e-mail goes once through Resend, escaped, without the uid or the screenshot", async () => {
  const uid = uniqueUid("email");
  const reportId = await seededReport(uid);
  const { calls, fetchImpl } = fakeFetch([{ status: 200, body: { id: "resend-1" } }]);
  const delivery = deliveryWith({ fetchImpl, channels: { email: EMAIL_CHANNEL } });
  await withConfig({ emailEnabled: true, emailTo: "owner@example.com", emailFrom: "YO Voice Bugs <bugs@yovoice.app>" },
    async () => {
      assert.deepEqual(await delivery.deliverBugReport(reportId), { email: "sent" });
      // A redelivered event never sends twice.
      assert.deepEqual(await delivery.deliverBugReport(reportId), { email: "skipped" });
    });
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, "https://api.resend.com/emails");
  assert.equal(calls[0].init.headers.Authorization, "Bearer re_test_key");
  assert.deepEqual(calls[0].body.to, ["owner@example.com"]);
  assert.ok(calls[0].body.html.includes("&lt;script&gt;"));
  assert.ok(!calls[0].body.html.includes("<script>"));
  assert.ok(!JSON.stringify(calls[0].body).includes(uid), "the uid is never e-mailed");
  assert.ok(calls[0].body.subject.includes(reportId));
  const report = (await db.collection(BUG_REPORTS).doc(reportId).get()).data();
  assert.equal(report.delivery.email.status, "sent");
  assert.equal(report.delivery.email.externalId, "resend-1");
});

emulatorTest("a public repository gets a minimal issue: no description, no uid, no locale", async () => {
  const uid = uniqueUid("github-public");
  const reportId = await seededReport(uid);
  const { calls, fetchImpl } = fakeFetch([
    { status: 200, body: { private: false } },
    { status: 201, body: { number: 77 } },
  ]);
  const delivery = deliveryWith({ fetchImpl, channels: { github: GITHUB_CHANNEL } });
  await withConfig({ githubEnabled: true, githubRepo: "kamilxgriefer/yovoice", githubIncludeDescription: true },
    () => delivery.deliverBugReport(reportId));
  assert.equal(calls[0].url, "https://api.github.com/repos/kamilxgriefer/yovoice");
  assert.equal(calls[1].url, "https://api.github.com/repos/kamilxgriefer/yovoice/issues");
  const issue = JSON.stringify(calls[1].body);
  assert.ok(issue.includes(reportId));
  assert.ok(!issue.includes("Crash"), "the description never reaches a public repository");
  assert.ok(!issue.includes(uid));
  assert.ok(!issue.includes("pl-PL"));
  assert.ok(!issue.includes("storage"));
  const report = (await db.collection(BUG_REPORTS).doc(reportId).get()).data();
  assert.equal(report.delivery.github.externalId, "77");
});

emulatorTest("a repository the API confirms private may carry the fenced description, still without the uid", async () => {
  const uid = uniqueUid("github-private");
  const reportId = await seededReport(uid);
  const { calls, fetchImpl } = fakeFetch([
    { status: 200, body: { private: true } },
    { status: 201, body: { number: 5 } },
  ]);
  const delivery = deliveryWith({ fetchImpl, channels: { github: GITHUB_CHANNEL } });
  await withConfig({ githubEnabled: true, githubRepo: "kamilxgriefer/yovoice-bug-inbox", githubIncludeDescription: true },
    () => delivery.deliverBugReport(reportId));
  const body = calls[1].body.body;
  assert.ok(body.includes("````text\nCrash <script>"), "a fence longer than any backtick run in the text");
  assert.ok(!body.includes(uid));
  // Without the explicit opt-in, even a private repository gets the minimal form.
  const quiet = await seededReport(uniqueUid("github-quiet"));
  const second = fakeFetch([{ status: 201, body: { number: 6 } }]);
  await withConfig({ githubEnabled: true, githubRepo: "kamilxgriefer/yovoice-bug-inbox" },
    () => deliveryWith({ fetchImpl: second.fetchImpl, channels: { github: GITHUB_CHANNEL } }).deliverBugReport(quiet));
  assert.equal(second.calls.length, 1, "no visibility probe without the opt-in");
  assert.ok(!second.calls[0].body.body.includes("Crash"));
});

emulatorTest("a transient failure is recorded and retried; a permanent one is recorded once; attempts are bounded", async () => {
  const uid = uniqueUid("retry");
  const reportId = await seededReport(uid);
  const config = { emailEnabled: true, emailTo: "owner@example.com", emailFrom: "bugs@yovoice.app" };
  await withConfig(config, async () => {
    const flaky = fakeFetch([{ status: 503 }, { status: 200, body: { id: "r2" } }]);
    const delivery = deliveryWith({ fetchImpl: flaky.fetchImpl, channels: { email: EMAIL_CHANNEL } });
    await assert.rejects(delivery.deliverBugReport(reportId));
    let report = (await db.collection(BUG_REPORTS).doc(reportId).get()).data();
    assert.equal(report.delivery.email.status, "retrying");
    assert.equal(report.delivery.email.lastErrorCode, "http-503");
    assert.deepEqual(await delivery.deliverBugReport(reportId), { email: "sent" });
    report = (await db.collection(BUG_REPORTS).doc(reportId).get()).data();
    assert.equal(report.delivery.email.attempts, 2);

    const permanentId = await seededReport(uniqueUid("permanent"));
    const refused = fakeFetch([{ status: 401 }]);
    const outcome = await deliveryWith({ fetchImpl: refused.fetchImpl, channels: { email: EMAIL_CHANNEL } })
      .deliverBugReport(permanentId);
    assert.deepEqual(outcome, { email: "failed" });

    const boundedId = await seededReport(uniqueUid("bounded"));
    await db.collection(BUG_REPORTS).doc(boundedId).update({
      "delivery.email": { status: "retrying", attempts: MAX_ATTEMPTS, lastErrorCode: "http-503" },
    });
    const never = fakeFetch([]);
    assert.deepEqual(await deliveryWith({ fetchImpl: never.fetchImpl, channels: { email: EMAIL_CHANNEL } })
      .deliverBugReport(boundedId), { email: "skipped" });
    assert.equal(never.calls.length, 0);
    assert.equal((await db.collection(BUG_REPORTS).doc(boundedId).get()).data().delivery.email.status, "failed");
  });
});

unitTest("the message builders never include the screenshot path or the uid", () => {
  const report = {
    reporterId: "secret-uid",
    description: "Hello",
    context: context(),
    screenshot: { status: "attached", storagePath: "bug_reports/secret-uid/br_x.jpg" },
  };
  const email = buildBugReportEmail("br_" + "a".repeat(40), report);
  const issue = buildBugReportIssue("br_" + "a".repeat(40), report, { includeDescription: true });
  for (const text of [email.text, email.html, issue.body, issue.title]) {
    assert.ok(!text.includes("secret-uid"));
    assert.ok(!text.includes("bug_reports/"));
  }
});

// ------------------------------------------------------------ registration

unitTest("six base exports need no new secret; delivery registers only when a channel is source-enabled", () => {
  const registered = [];
  const registrars = {
    onCall: (options, handler) => { registered.push({ kind: "call", options }); return { options, handler }; },
    onSchedule: (options, handler) => { registered.push({ kind: "schedule", options }); return { options, handler }; },
    onDocumentCreated: (options, handler) => { registered.push({ kind: "trigger", options }); return { options, handler }; },
  };
  const base = createBugReportFunctions({ registrars, runtimeFactory: () => ({}) });
  assert.deepEqual(Object.keys(base).sort(), [...BUG_REPORT_BASE_EXPORT_NAMES]);
  for (const name of ["listBugReportsV1", "getBugReportV1", "updateBugReportStatusV1"]) {
    assert.deepEqual(base[name].options.secrets, ["YOVOICE_PROTECTED_OWNER_UID"], name);
    assert.equal(base[name].options.region, "europe-west1");
  }
  for (const name of ["submitBugReportV1", "attachBugReportScreenshotV1"]) {
    assert.equal(base[name].options.secrets, undefined, name);
  }
  assert.ok(!registered.some((entry) => entry.kind === "trigger"));
});

unitTest("each delivery secret is declared only by its own source gate", () => {
  const FUNCTIONS_DIR = path.resolve(__dirname, "..");
  const inspect = (options) => JSON.parse(execFileSync(process.execPath, ["-e", [
    "const { declaredParams } = require('firebase-functions/params');",
    "const { createBugReportFunctions } = require('./bug_reports/registration');",
    "const r = { onCall: (o, h) => ({ o, h }), onSchedule: (o, h) => ({ o, h }), onDocumentCreated: (o, h) => ({ o, h }) };",
    `const exported = createBugReportFunctions({ ...${JSON.stringify(options)}, registrars: r, runtimeFactory: () => ({}) });`,
    "process.stdout.write(JSON.stringify({ names: declaredParams.map((p) => p.name).sort(), exports: Object.keys(exported).sort() }));",
  ].join(" ")], { cwd: FUNCTIONS_DIR, encoding: "utf8", stdio: ["ignore", "pipe", "inherit"] }));

  const off = inspect({});
  assert.ok(!off.names.includes("RESEND_API_KEY"));
  assert.ok(!off.names.includes("GITHUB_BUG_REPORT_TOKEN"));
  assert.ok(!off.exports.includes("deliverBugReportV1"));

  const email = inspect({ emailDelivery: true });
  assert.ok(email.names.includes("RESEND_API_KEY"));
  assert.ok(!email.names.includes("GITHUB_BUG_REPORT_TOKEN"));
  assert.ok(email.exports.includes("deliverBugReportV1"));

  const github = inspect({ githubDelivery: true });
  assert.ok(github.names.includes("GITHUB_BUG_REPORT_TOKEN"));
  assert.ok(!github.names.includes("RESEND_API_KEY"));
});

// -------------------------------------------------------- account deletion

emulatorTest("account deletion sweeps the screenshot prefix and deletes only the subject's reports", async () => {
  const uid = uniqueUid("deleted-account");
  const bystander = uniqueUid("bystander");
  await Promise.all([seedUser(uid), seedUser(bystander)]);
  const { service } = serviceWith();
  const own = await reserve(service, uid);
  const plain = await service.submitBugReportV1(request(uid, submitData()));
  const theirs = await service.submitBugReportV1(request(bystander, submitData()));

  assert.ok(uidStoragePrefixes(uid).includes(`bug_reports/${uid}/`));

  const stages = createAccountDeletionStages({
    db, FieldValue, FieldPath,
    authAdmin: { async revokeRefreshTokens() {}, async deleteUser() {} },
    resolveBucket: () => ({ name: "demo", file: () => ({ async delete() {} }) }),
    deleteTrustedPrefix: async () => ({ deleted: true }),
    logger: { info() {}, warn() {}, error() {} },
    limits: { reportPage: 1 },
  });
  let cursor = null;
  for (let round = 0; round < 40; round += 1) {
    const outcome = await stages.runStage("records", { uid, cursor, row: {} });
    if (outcome.done) break;
    cursor = outcome.cursor;
  }
  assert.equal((await db.collection(BUG_REPORTS).doc(own.reportId).get()).exists, false);
  assert.equal((await db.collection(BUG_REPORTS).doc(plain.reportId).get()).exists, false);
  assert.equal((await db.collection(BUG_REPORT_RESERVATIONS).doc(own.reportId).get()).exists, false);
  assert.equal((await db.collection(BUG_REPORTS).doc(theirs.reportId).get()).exists, true,
    "another account's report survives");
});
