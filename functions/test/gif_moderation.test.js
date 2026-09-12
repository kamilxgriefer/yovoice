const assert = require("node:assert/strict");
const { after, before, beforeEach, test } = require("node:test");

// Reporting and blocking a third-party GIF, against the real emulator.
//
// The property under test is that a GIF report is an ORDINARY REPORT: same
// `reports` collection, same status machine, same triage callable, plus the
// two things that make it different — no YO Voice account is blamed, and the
// evidence travels inside the report because staff cannot read `gifAssets`.

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "demo-yovoice";
process.env.NODE_ENV = "test";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");

// The DEFAULT app, not a named one: functions/utils/firestore.js resolves
// `getFirestore()` off the default app at module load, and moderation/reports.js
// requires it. A named app here would make the triage tests below fail with
// "The default Firebase app does not exist" rather than exercising anything.
if (getApps().length === 0) initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = getFirestore();

const { createGifCache } = require("../media/gif/cache");
const {
  AUTO_SUPPRESS_THRESHOLD,
  createGifModeration,
  evidenceSnapshot,
  gifReportId,
} = require("../media/gif/moderation");
const { createGifFunctions, createGifRuntime } = require("../media/gif/catalog");
const { createFakeGifProvider } = require("../media/gif/fake_provider");
const { resolveGifAsset } = require("../media/gif");
const { gifCdnUrl } = require("../media/gif/gif_ref");

const PROVIDER = "fake";
const GIF_ID = "fakeCat01";
const DOCUMENT_ID = `${PROVIDER}_${GIF_ID}`;
const REPORTERS = ["reporter-0", "reporter-1", "reporter-2", "reporter-x", "gif-reporter-uid"];

const silentLog = { info() {}, warn() {}, error() {} };

async function wipe(...collections) {
  for (const name of collections) {
    const snapshot = await db.collection(name).get();
    await Promise.all(snapshot.docs.map((document) => document.ref.delete()));
  }
}

async function reset() {
  await wipe("reports", "gifAssets", "gifBlocklist", "gifQueryCache", "privateRateLimits");
  await Promise.all(REPORTERS.map((uid) => db.doc(`users/${uid}`).delete()));
}

async function seedAsset(overrides = {}) {
  await db.doc(`gifAssets/${DOCUMENT_ID}`).set({
    schemaVersion: 1,
    provider: PROVIDER,
    gifId: GIF_ID,
    title: "Happy cat",
    rating: "g",
    url: gifCdnUrl(PROVIDER, GIF_ID),
    previewUrl: gifCdnUrl(PROVIDER, GIF_ID),
    width: 200,
    height: 200,
    blocked: false,
    reportCount: 0,
    ...overrides,
  });
}

function moderation() {
  return createGifModeration({
    db,
    cache: createGifCache({ db }),
  });
}

before(reset);
beforeEach(async () => {
  await reset();
  await Promise.all(REPORTERS.map((uid) => db.doc(`users/${uid}`).set({ uid, banned: false })));
});
after(reset);

test("a report lands in the existing queue with no account blamed", async () => {
  await seedAsset();
  const outcome = await moderation().reportAsset({
    reporterId: "reporter-1",
    provider: PROVIDER,
    gifId: GIF_ID,
    reason: "sexual",
    note: "Not appropriate for a G rating.",
    contextPath: "rooms/room-1/messages/m-1",
  });

  assert.equal(outcome.created, true);
  const report = (await db.doc(`reports/${outcome.reportId}`).get()).data();

  assert.equal(report.targetType, "gifAsset");
  assert.equal(report.targetId, `${PROVIDER}:${GIF_ID}`);
  assert.equal(report.status, "open");
  assert.equal(report.schemaVersion, 2);
  assert.equal(report.reason, "sexual");
  // No YO Voice account is at fault for a third party's asset that our own
  // filtered proxy surfaced, so nobody is put into a sanction workflow.
  assert.equal(report.reportedUserId, "");
  // Staff cannot read gifAssets, so the evidence has to be inside the report.
  assert.equal(report.targetTextSnapshot, evidenceSnapshot({
    provider: PROVIDER,
    id: GIF_ID,
    title: "Happy cat",
  }));
  assert.equal(report.targetMediaUrl, gifCdnUrl(PROVIDER, GIF_ID));
  assert.equal(report.contextPath, "rooms/room-1/messages/m-1");
});

test("the same reporter reporting twice is idempotent, not a second queue entry", async () => {
  await seedAsset();
  const first = await moderation().reportAsset({
    reporterId: "reporter-1",
    provider: PROVIDER,
    gifId: GIF_ID,
    reason: "spam",
  });
  const second = await moderation().reportAsset({
    reporterId: "reporter-1",
    provider: PROVIDER,
    gifId: GIF_ID,
    reason: "hate",
  });

  assert.equal(first.created, true);
  assert.equal(second.created, false);
  assert.equal(second.reportId, first.reportId);
  assert.equal(first.reportId, gifReportId("reporter-1", PROVIDER, GIF_ID));
  assert.equal((await db.collection("reports").get()).size, 1);
  // The counter moved once, not twice.
  assert.equal((await db.doc(`gifAssets/${DOCUMENT_ID}`).get()).data().reportCount, 1);
});

test("an asset the proxy never surfaced cannot be reported", async () => {
  const outcome = await moderation().reportAsset({
    reporterId: "reporter-1",
    provider: PROVIDER,
    gifId: "fakeNeverSeen",
    reason: "spam",
  });
  assert.equal(outcome.error, "unknown_asset");
  assert.equal((await db.collection("reports").get()).size, 0);
});

test("crossing the threshold auto-suppresses the asset before a human looks", async () => {
  await seedAsset();
  const service = moderation();
  for (let index = 0; index < AUTO_SUPPRESS_THRESHOLD; index += 1) {
    await service.reportAsset({
      reporterId: `reporter-${index}`,
      provider: PROVIDER,
      gifId: GIF_ID,
      reason: "sexual",
    });
  }

  const asset = (await db.doc(`gifAssets/${DOCUMENT_ID}`).get()).data();
  assert.equal(asset.reportCount, AUTO_SUPPRESS_THRESHOLD);
  assert.equal(asset.suppressed, true);
  // Suppression is NOT blocking: it is reversible and only affects discovery.
  assert.notEqual(asset.blocked, true);

  const index = (await db.doc("gifBlocklist/current").get()).data();
  assert.ok(index.assetIds.includes(DOCUMENT_ID));
});

test("staff blocking an asset is durable and refuses it at send time", async () => {
  await seedAsset();
  const service = moderation();
  const blocked = await service.blockAsset({
    provider: PROVIDER,
    gifId: GIF_ID,
    blockedBy: "moderator-9",
  });
  assert.equal(blocked.blocked, true);

  const asset = (await db.doc(`gifAssets/${DOCUMENT_ID}`).get()).data();
  assert.equal(asset.blocked, true);
  assert.equal(asset.blockedBy, "moderator-9");

  // The single authority every send path must go through now refuses it.
  const resolved = await resolveGifAsset({ db, provider: PROVIDER, gifId: GIF_ID });
  assert.equal(resolved.ok, false);
  assert.equal(resolved.reason, "blocked");

  // Re-blocking is idempotent and reports that nothing changed.
  const again = await service.blockAsset({ provider: PROVIDER, gifId: GIF_ID });
  assert.equal(again.blocked, false);
});

test("resolveGifAsset refuses an unknown asset and a non-g rating", async () => {
  const missing = await resolveGifAsset({
    db,
    provider: PROVIDER,
    gifId: "fakeCat01",
  });
  assert.equal(missing.ok, false);
  assert.equal(missing.reason, "unknown_asset");

  await seedAsset({ rating: "pg" });
  const rated = await resolveGifAsset({ db, provider: PROVIDER, gifId: GIF_ID });
  assert.equal(rated.ok, false);
  assert.equal(rated.reason, "rating");
});

test("resolveGifAsset recomputes the pinned URL rather than trusting the record", async () => {
  await seedAsset({ url: "https://evil.example.com/beacon.gif" });
  const resolved = await resolveGifAsset({ db, provider: PROVIDER, gifId: GIF_ID });
  assert.equal(resolved.ok, true);
  assert.equal(resolved.asset.url, gifCdnUrl(PROVIDER, GIF_ID));
  assert.equal(resolved.asset.title, "Happy cat");
});

test("resolveGifAsset refuses a malformed target without touching Firestore", async () => {
  for (const bad of ["../../etc", "a/b", "", "x".repeat(200)]) {
    const resolved = await resolveGifAsset({ db, provider: PROVIDER, gifId: bad });
    assert.equal(resolved.ok, false);
    assert.equal(resolved.reason, "invalid_target");
  }
  const wrongProvider = await resolveGifAsset({
    db,
    provider: "tenor",
    gifId: GIF_ID,
  });
  assert.equal(wrongProvider.ok, false);
});

test("reportGifAsset validates its input and files through the callable", async () => {
  await seedAsset();
  const exportsMap = createGifFunctions({
    runtime: createGifRuntime({
      db,
      provider: createFakeGifProvider(),
      log: silentLog,
    }),
    registrars: { onCall: (_options, handler) => handler },
    providerName: "fake",
  });
  const call = (data) =>
    exportsMap.reportGifAsset({
      auth: { uid: "reporter-x", token: {} },
      data,
    });

  const filed = await call({
    provider: PROVIDER,
    gifId: GIF_ID,
    reason: "violence",
    requestId: "req-000000001",
  });
  assert.equal(filed.created, true);

  await assert.rejects(
    () =>
      call({
        provider: PROVIDER,
        gifId: GIF_ID,
        reason: "not-a-reason",
        requestId: "req-000000002",
      }),
    (error) => error.code === "invalid-argument",
  );

  await assert.rejects(
    () =>
      call({
        provider: "tenor",
        gifId: GIF_ID,
        reason: "spam",
        requestId: "req-000000003",
      }),
    (error) => error.code === "invalid-argument",
  );

  await assert.rejects(
    () =>
      call({
        provider: PROVIDER,
        gifId: "fakeMissing",
        reason: "spam",
        requestId: "req-000000004",
      }),
    (error) => error.code === "not-found",
  );
});

test("a GIF earns no chat-message achievement, and that is deliberate", () => {
  // functions/achievements/sources.js matches room and club messages with
  // hasExactKeys, so the additive `gif` map drops credit automatically. That
  // is consistent with the direct-message adapter, which already requires
  // `type === "text"` so image, voice and video messages earn nothing either;
  // it removes a GIF-spam farming vector; and it needs NO CHANGE to sources.js.
  //
  // It is still a decision, so it is pinned here rather than left as a quirk
  // somebody later "fixes" by loosening the key match.
  const {
    adaptClubMessageCreated,
    adaptRoomMessageCreated,
  } = require("../achievements/sources");

  const at = new Date("2026-09-09T10:00:00.000Z");
  const gif = {
    provider: "giphy",
    id: "abc",
    url: "https://media.giphy.com/media/abc/200h.gif",
  };

  const roomInput = {
    roomId: "room-1",
    messageId: "message-1",
    message: {
      senderId: "speaker-1",
      senderName: "Speaker One",
      senderPhotoUrl: null,
      text: "look at this",
      createdAt: at,
      reactions: {},
    },
    room: { status: "active" },
    senderAuthorized: true,
    sourceCreatedAt: at,
  };
  assert.equal(
    adaptRoomMessageCreated(roomInput).metric,
    "messages",
    "a plain room message must still earn credit",
  );
  assert.equal(
    adaptRoomMessageCreated({
      ...roomInput,
      message: { ...roomInput.message, gif },
    }),
    null,
    "a room GIF must not earn a messages achievement",
  );

  const clubInput = {
    clubId: "club-1",
    channelId: "channel-1",
    messageId: "message-1",
    message: {
      clubId: "club-1",
      channelId: "channel-1",
      senderId: "member-1",
      senderName: "Member One",
      senderPhotoUrl: null,
      content: "look at this",
      sentAt: at,
      editedAt: null,
      isDeleted: false,
    },
    club: { status: "active" },
    channel: { type: "chat" },
    member: { userId: "member-1", role: "member", banned: false },
    sourceCreatedAt: at,
  };
  assert.equal(
    adaptClubMessageCreated(clubInput).metric,
    "messages",
    "a plain club message must still earn credit",
  );
  assert.equal(
    adaptClubMessageCreated({
      ...clubInput,
      message: { ...clubInput.message, gif },
    }),
    null,
    "a club GIF must not earn a messages achievement",
  );
});

// ---------------------------------------------------------------------------
// Staff triage. No new staff endpoint: a GIF report is resolved through the
// same `moderateReport` callable, with the same role checks and audit trail.
// ---------------------------------------------------------------------------

test("moderateReport blocks the asset when staff resolve with contentRemoved", async () => {
  const { moderateReport } = require("../moderation/reports");
  const run = moderateReport.run ?? moderateReport;
  const MODERATOR = "gif-moderator-uid";
  const REPORTER = "gif-reporter-uid";

  await db.doc(`users/${MODERATOR}`).set({
    uid: MODERATOR,
    displayName: "Mod",
    role: "moderator",
  });
  await seedAsset();
  const filed = await moderation().reportAsset({
    reporterId: REPORTER,
    provider: PROVIDER,
    gifId: GIF_ID,
    reason: "sexual",
    note: "",
  });

  const outcome = await run({
    auth: {
      uid: MODERATOR,
      token: { role: "moderator", auth_time: Math.floor(Date.now() / 1000) },
    },
    data: {
      reportId: filed.reportId,
      action: "removeAndResolve",
      resolution: "contentRemoved",
      requestId: "gif-triage-000001",
    },
  });

  assert.equal(outcome.status, "resolved");
  assert.equal(outcome.contentRemoved, true);

  const asset = (await db.doc(`gifAssets/${DOCUMENT_ID}`).get()).data();
  assert.equal(asset.blocked, true);
  assert.equal(asset.blockedBy, MODERATOR);

  const report = (await db.doc(`reports/${filed.reportId}`).get()).data();
  assert.equal(report.status, "resolved");
  assert.equal(report.resolution, "contentRemoved");
  // Reporter evidence is untouched, exactly as for every other target type.
  assert.equal(report.reporterId, REPORTER);
  assert.equal(report.targetType, "gifAsset");

  await db.doc(`users/${MODERATOR}`).delete();
  await wipe("adminAuditLogs");
});

test("moderateReport refuses a GIF report whose evidence is missing", async () => {
  const { moderateReport } = require("../moderation/reports");
  const run = moderateReport.run ?? moderateReport;
  const MODERATOR = "gif-moderator-uid-2";

  await db.doc(`users/${MODERATOR}`).set({
    uid: MODERATOR,
    displayName: "Mod",
    role: "moderator",
  });
  // A report shaped like a GIF report but carrying no snapshot: a moderator
  // could not have judged it honestly, so it is refused rather than acted on.
  await db.doc("reports/forged-gif-report").set({
    schemaVersion: 2,
    reporterId: "gif-reporter-uid",
    targetType: "gifAsset",
    targetId: `${PROVIDER}:${GIF_ID}`,
    reportedUserId: "someone-innocent",
    gifProvider: PROVIDER,
    gifId: GIF_ID,
    reason: "spam",
    note: "",
    status: "open",
    createdAt: new Date(),
  });

  await assert.rejects(
    () =>
      run({
        auth: {
          uid: MODERATOR,
          token: {
            role: "moderator",
            auth_time: Math.floor(Date.now() / 1000),
          },
        },
        data: {
          reportId: "forged-gif-report",
          action: "removeAndResolve",
          resolution: "contentRemoved",
          requestId: "gif-triage-000002",
        },
      }),
    (error) => {
      assert.equal(error.code, "failed-precondition");
      assert.match(error.message, /GIF reference is invalid/u);
      return true;
    },
  );

  await db.doc(`users/${MODERATOR}`).delete();
  await db.doc("reports/forged-gif-report").delete();
});
